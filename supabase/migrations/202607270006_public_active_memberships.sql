drop policy if exists memberships_public_active_read
  on public.club_memberships;

create policy memberships_public_active_read
on public.club_memberships for select to authenticated
using (
  status='active'
  and exists(
    select 1
    from public.clubs c
    where c.id=club_id and c.visibility='public'
  )
);
