-- Direct messages are an internal club collaboration feature. Enforce the
-- shared-active-club rule on the server, not only in the Flutter UI.
create or replace function public.get_or_create_direct_conversation(
  target_user uuid
)
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
  if not exists (
    select 1
    from public.club_memberships mine
    join public.club_memberships theirs
      on theirs.club_id=mine.club_id
    where mine.user_id=current_user_id
      and theirs.user_id=target_user
      and mine.status='active'
      and theirs.status='active'
  ) then
    raise exception 'Direct messages are limited to members of your clubs';
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

revoke all on function public.get_or_create_direct_conversation(uuid)
from public,anon;
grant execute on function public.get_or_create_direct_conversation(uuid)
to authenticated;
