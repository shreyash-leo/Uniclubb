-- Function privilege hardening and missing social notification.

revoke all on function public.discover_clubs(integer) from public, anon;
revoke all on function public.club_public_counts(uuid) from public, anon;
revoke all on function public.profile_public_counts(uuid) from public, anon;
revoke all on function public.get_or_create_direct_conversation(uuid)
from public, anon;

grant execute on function public.discover_clubs(integer) to authenticated;
grant execute on function public.club_public_counts(uuid) to authenticated;
grant execute on function public.profile_public_counts(uuid) to authenticated;
grant execute on function public.get_or_create_direct_conversation(uuid)
to authenticated;

create or replace function public.notify_new_user_follow()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  insert into public.notifications(user_id,actor_id,type,title,body,data)
  select
    new.followed_id,
    new.follower_id,
    'new_follower',
    'New follower',
    coalesce(nullif(p.full_name,''),p.username,'Someone')||' started following you',
    jsonb_build_object('user_id',new.follower_id)
  from public.profiles p
  where p.id=new.follower_id;
  return new;
end
$$;

drop trigger if exists notify_new_user_follow on public.user_follows;
create trigger notify_new_user_follow
after insert on public.user_follows
for each row execute function public.notify_new_user_follow();
