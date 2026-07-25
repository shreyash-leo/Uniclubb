-- Product navigation/permissions revision.

alter table public.clubs
  add column if not exists club_type text not null default 'Student';

-- Repair accounts created while the auth trigger was unavailable. This is also
-- used by the client before rendering/editing a profile.
create or replace function public.ensure_user_profile()
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  result public.profiles;
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  insert into public.profiles(id,email,full_name,avatar_url,onboarding_complete)
  values(
    current_user_id,
    coalesce(auth.jwt()->>'email',''),
    coalesce(auth.jwt()->'user_metadata'->>'full_name',''),
    auth.jwt()->'user_metadata'->>'avatar_url',
    false
  )
  on conflict(id) do nothing;

  insert into public.notification_preferences(user_id)
  values(current_user_id)
  on conflict(user_id) do nothing;

  select * into result from public.profiles where id=current_user_id;
  return result;
end
$$;

grant execute on function public.ensure_user_profile() to authenticated;

-- Club creation is an atomic, audited operation. Using a security-definer RPC
-- prevents a missing legacy profile or an after-insert role trigger from
-- surfacing as a misleading clubs RLS failure.
create or replace function public.create_club(
  club_name text,
  club_category text,
  club_type_value text,
  club_college_id uuid default null,
  club_location text default null,
  club_description text default '',
  club_logo_url text default null,
  club_banner_url text default null
)
returns public.clubs
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  result public.clubs;
  base_slug text;
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  perform public.ensure_user_profile();
  if not public.is_active_user() then
    raise exception 'Only active accounts can create clubs';
  end if;
  if length(trim(club_name)) < 3 then
    raise exception 'Club name must contain at least 3 characters';
  end if;
  if length(trim(club_description)) < 20 then
    raise exception 'Club description must contain at least 20 characters';
  end if;

  base_slug := trim(both '-' from regexp_replace(
    lower(trim(club_name)), '[^a-z0-9]+', '-', 'g'
  ));

  insert into public.clubs(
    name,slug,category,club_type,college_id,location,description,
    logo_url,banner_url,created_by
  )
  values(
    trim(club_name),
    base_slug||'-'||substr(gen_random_uuid()::text,1,8),
    trim(club_category),
    trim(club_type_value),
    club_college_id,
    nullif(trim(club_location),''),
    trim(club_description),
    club_logo_url,
    club_banner_url,
    current_user_id
  )
  returning * into result;

  update public.club_positions
  set permissions=array_append(permissions,'manage_social')
  where club_id=result.id
    and name in ('Vice President','Faculty Coordinator')
    and not ('manage_social'=any(permissions));

  return result;
end
$$;

grant execute on function public.create_club(
  text,text,text,uuid,text,text,text,text
) to authenticated;

create table if not exists public.club_tasks (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  title text not null check (length(trim(title)) between 2 and 160),
  description text not null default '',
  assigned_to uuid references public.profiles(id) on delete set null,
  due_at timestamptz,
  status text not null default 'todo'
    check (status in ('todo','in_progress','completed','cancelled')),
  created_by uuid not null references public.profiles(id),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists club_tasks_club_due_idx
  on public.club_tasks(club_id,due_at);
create index if not exists club_tasks_assignee_idx
  on public.club_tasks(assigned_to,status);

alter table public.club_tasks enable row level security;

drop policy if exists club_tasks_member_read on public.club_tasks;
create policy club_tasks_member_read on public.club_tasks for select to authenticated
  using (public.is_club_member(club_id));

drop policy if exists club_tasks_manage_insert on public.club_tasks;
create policy club_tasks_manage_insert on public.club_tasks for insert to authenticated
  with check (
    created_by=(select auth.uid())
    and (
      public.has_club_permission(club_id,'manage_members')
      or public.has_club_permission(club_id,'manage_events')
    )
    and (
      assigned_to is null
      or exists(
        select 1 from public.club_memberships m
        where m.club_id=club_tasks.club_id
          and m.user_id=club_tasks.assigned_to
          and m.status='active'
      )
    )
  );

drop policy if exists club_tasks_update on public.club_tasks;
create policy club_tasks_update on public.club_tasks for update to authenticated
  using (
    assigned_to=(select auth.uid())
    or public.has_club_permission(club_id,'manage_members')
    or public.has_club_permission(club_id,'manage_events')
  )
  with check (
    assigned_to=(select auth.uid())
    or public.has_club_permission(club_id,'manage_members')
    or public.has_club_permission(club_id,'manage_events')
  );

drop policy if exists club_tasks_delete on public.club_tasks;
create policy club_tasks_delete on public.club_tasks for delete to authenticated
  using (
    public.has_club_permission(club_id,'manage_members')
    or public.has_club_permission(club_id,'manage_events')
  );

drop trigger if exists touch_club_tasks on public.club_tasks;
create trigger touch_club_tasks before update on public.club_tasks
for each row execute function public.touch_updated_at();

create or replace function public.notify_task_assignment()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if new.assigned_to is not null and new.assigned_to<>new.created_by then
    insert into public.notifications(user_id,actor_id,type,title,body,data)
    values(
      new.assigned_to,new.created_by,'club_task','New club task',
      new.title,jsonb_build_object('club_id',new.club_id,'task_id',new.id)
    );
  end if;
  return new;
end
$$;

drop trigger if exists notify_task_assignment on public.club_tasks;
create trigger notify_task_assignment after insert on public.club_tasks
for each row execute function public.notify_task_assignment();

-- Publishing stories is a club action, not a personal social-post action.
drop policy if exists stories_owner on public.stories;
drop policy if exists stories_official_insert on public.stories;
create policy stories_official_insert on public.stories for insert to authenticated
  with check (
    author_id=(select auth.uid())
    and club_id is not null
    and public.has_club_permission(club_id,'manage_social')
  );
drop policy if exists stories_official_update on public.stories;
create policy stories_official_update on public.stories for update to authenticated
  using (
    author_id=(select auth.uid())
    and public.has_club_permission(club_id,'manage_social')
  )
  with check (
    author_id=(select auth.uid())
    and public.has_club_permission(club_id,'manage_social')
  );
drop policy if exists stories_official_delete on public.stories;
create policy stories_official_delete on public.stories for delete to authenticated
  using (
    author_id=(select auth.uid())
    and public.has_club_permission(club_id,'manage_social')
  );

-- Senior officials can publish social content while operational permissions
-- remain explicit for events, members, finance and recruitment.
update public.club_positions
set permissions = array_append(permissions,'manage_social')
where name in ('Vice President','Faculty Coordinator')
  and not ('all'=any(permissions))
  and not ('manage_social'=any(permissions));

-- Keep chat membership synchronized when an official removes a club member.
create or replace function public.sync_club_chat_membership()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  club_conversation uuid;
begin
  select id into club_conversation
  from public.conversations
  where club_id=new.club_id and kind='club';

  if new.status='active' then
    insert into public.conversation_members(conversation_id,user_id,role)
    values(club_conversation,new.user_id,'member')
    on conflict(conversation_id,user_id) do nothing;
  elsif old.status='active' and new.status<>'active' then
    delete from public.conversation_members
    where conversation_id=club_conversation and user_id=new.user_id;
  end if;
  return new;
end
$$;

drop trigger if exists sync_club_chat_membership on public.club_memberships;
create trigger sync_club_chat_membership
after update of status on public.club_memberships
for each row execute function public.sync_club_chat_membership();

-- Add all newly live screens to Realtime without failing repeated deployments.
do $$
declare
  target_table text;
begin
  foreach target_table in array array['club_tasks','stories','clubs'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname='supabase_realtime'
        and schemaname='public'
        and tablename=target_table
    ) then
      execute format(
        'alter publication supabase_realtime add table public.%I',
        target_table
      );
    end if;
  end loop;
end
$$;
