-- Social visibility, deterministic discovery and resilient direct chat.

drop policy if exists club_follows_public_read on public.club_follows;
create policy club_follows_public_read
on public.club_follows for select to authenticated
using (public.is_active_user());

drop policy if exists user_follows_public_read on public.user_follows;
create policy user_follows_public_read
on public.user_follows for select to authenticated
using (
  public.is_active_user()
  and public.can_view_profile(follower_id)
  and public.can_view_profile(followed_id)
);

create or replace function public.discover_clubs(result_limit integer default 24)
returns setof public.clubs
language sql
stable
security definer
set search_path=public
as $$
  select c.*
  from public.clubs c
  left join lateral (
    select count(*)::bigint as follower_count
    from public.club_follows f where f.club_id=c.id
  ) followers on true
  left join lateral (
    select count(*)::bigint as member_count
    from public.club_memberships m
    where m.club_id=c.id and m.status='active'
  ) members on true
  left join lateral (
    select count(*)::bigint as upcoming_count
    from public.events e
    where e.club_id=c.id
      and e.status='published'
      and e.ends_at>=now()
  ) events on true
  where c.visibility='public'
  order by
    c.verified desc,
    (
      coalesce(followers.follower_count,0) * 3
      + coalesce(members.member_count,0) * 2
      + coalesce(events.upcoming_count,0) * 4
    ) desc,
    c.created_at desc
  limit greatest(1,least(coalesce(result_limit,24),100))
$$;

grant execute on function public.discover_clubs(integer) to authenticated;

create or replace function public.club_public_counts(target_club uuid)
returns jsonb
language sql
stable
security definer
set search_path=public
as $$
  select jsonb_build_object(
    'followers', (select count(*) from public.club_follows f where f.club_id=target_club),
    'members', (select count(*) from public.club_memberships m where m.club_id=target_club and m.status='active'),
    'events', (select count(*) from public.events e where e.club_id=target_club and e.status='published')
  )
  where exists(
    select 1 from public.clubs c
    where c.id=target_club and c.visibility='public'
  )
$$;

create or replace function public.profile_public_counts(target_user uuid)
returns jsonb
language sql
stable
security definer
set search_path=public
as $$
  select jsonb_build_object(
    'followers', (select count(*) from public.user_follows f where f.followed_id=target_user),
    'following', (select count(*) from public.user_follows f where f.follower_id=target_user)
  )
  where public.can_view_profile(target_user)
$$;

grant execute on function public.club_public_counts(uuid) to authenticated;
grant execute on function public.profile_public_counts(uuid) to authenticated;

create or replace function public.get_or_create_direct_conversation(target_user uuid)
returns public.conversations
language plpgsql
security definer
set search_path=public
as $$
declare
  current_user_id uuid := auth.uid();
  result public.conversations;
  lock_key text;
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if target_user is null or target_user=current_user_id then
    raise exception 'Choose another user';
  end if;
  if not public.can_view_profile(target_user) then
    raise exception 'This profile is unavailable';
  end if;

  lock_key := least(current_user_id::text,target_user::text)
    ||':'||greatest(current_user_id::text,target_user::text);
  perform pg_advisory_xact_lock(hashtextextended(lock_key,0));

  select c.* into result
  from public.conversations c
  where c.kind='direct'
    and exists(
      select 1 from public.conversation_members cm
      where cm.conversation_id=c.id and cm.user_id=current_user_id
    )
    and exists(
      select 1 from public.conversation_members cm
      where cm.conversation_id=c.id and cm.user_id=target_user
    )
    and 2=(
      select count(*) from public.conversation_members cm
      where cm.conversation_id=c.id
    )
  order by c.created_at
  limit 1;

  if result.id is null then
    insert into public.conversations(kind,title,created_by)
    values('direct',null,current_user_id)
    returning * into result;

    insert into public.conversation_members(conversation_id,user_id,role)
    values
      (result.id,current_user_id,'member'),
      (result.id,target_user,'member');
  end if;

  return result;
end
$$;

grant execute on function public.get_or_create_direct_conversation(uuid)
to authenticated;

-- Supervisors are senior club officials with explicit operational permissions.
insert into public.club_positions(
  club_id,name,rank,permissions,is_system
)
select
  c.id,
  'Supervisor',
  2,
  array[
    'manage_members','manage_events','manage_recruitment',
    'manage_announcements','manage_social','manage_attendance',
    'approve_expenses'
  ],
  true
from public.clubs c
on conflict(club_id,name) do update
set permissions=excluded.permissions, rank=excluded.rank, is_system=true;

create or replace function public.seed_club_roles()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  president_position uuid;
  club_conversation uuid;
begin
  insert into public.club_positions(club_id,name,rank,permissions,is_system)
  values
    (new.id,'President',1,array['all'],true),
    (new.id,'Vice President',2,array['manage_members','manage_events','manage_recruitment','manage_announcements','manage_social'],true),
    (new.id,'Supervisor',2,array['manage_members','manage_events','manage_recruitment','manage_announcements','manage_social','manage_attendance','approve_expenses'],true),
    (new.id,'Secretary',3,array['manage_announcements','manage_members'],true),
    (new.id,'Treasurer',3,array['manage_finance','approve_expenses'],true),
    (new.id,'Event Head',4,array['manage_events','manage_attendance'],true),
    (new.id,'Technical Head',4,array['manage_events'],true),
    (new.id,'Marketing Head',4,array['manage_announcements','manage_social'],true),
    (new.id,'Faculty Coordinator',2,array['manage_members','approve_expenses','manage_events','manage_social'],true),
    (new.id,'Volunteer',20,array['manage_attendance'],true),
    (new.id,'Member',100,array[]::text[],true);

  select id into president_position
  from public.club_positions
  where club_id=new.id and name='President';

  insert into public.club_memberships(club_id,user_id,position_id,status,joined_at)
  values(new.id,new.created_by,president_position,'active',now());
  insert into public.club_scores(club_id) values(new.id);
  insert into public.conversations(kind,club_id,title,created_by)
  values('club',new.id,new.name||' chat',new.created_by)
  returning id into club_conversation;
  insert into public.conversation_members(conversation_id,user_id,role)
  values(club_conversation,new.created_by,'admin');
  return new;
end
$$;
