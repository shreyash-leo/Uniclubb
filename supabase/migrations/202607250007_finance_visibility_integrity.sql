-- Approvers must be able to inspect expenses before deciding them.

drop policy if exists expenses_read on public.expenses;
create policy expenses_read on public.expenses for select to authenticated
using (
  submitted_by=(select auth.uid())
  or public.has_club_permission(club_id,'manage_finance')
  or public.has_club_permission(club_id,'approve_expenses')
  or public.has_club_permission(club_id,'all')
);

drop policy if exists expenses_submit on public.expenses;
create policy expenses_submit on public.expenses for insert to authenticated
with check (
  submitted_by=(select auth.uid())
  and public.is_club_member(club_id)
  and (
    budget_id is null
    or exists(
      select 1 from public.club_budgets b
      where b.id=budget_id and b.club_id=expenses.club_id
    )
  )
);

update public.profiles set social_links='{}'::jsonb
where social_links<>'{}'::jsonb;
revoke update(social_links) on public.profiles from authenticated;

drop table if exists public.interviews cascade;
drop table if exists public.recruitment_rounds cascade;
drop table if exists public.recruitment_applications cascade;
drop table if exists public.recruitment_positions cascade;
drop table if exists public.recruitment_campaigns cascade;

update public.club_positions
set permissions=array_remove(permissions,'manage_recruitment')
where 'manage_recruitment'=any(permissions);

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
    (new.id,'Vice President',2,array['manage_members','manage_events','manage_announcements','manage_social'],true),
    (new.id,'Supervisor',2,array['manage_members','manage_events','manage_announcements','manage_social','manage_attendance','approve_expenses'],true),
    (new.id,'Secretary',3,array['manage_announcements','manage_members'],true),
    (new.id,'Treasurer',3,array['manage_finance','approve_expenses'],true),
    (new.id,'Event Head',4,array['manage_events','manage_attendance'],true),
    (new.id,'Technical Head',4,array['manage_events'],true),
    (new.id,'Marketing Head',4,array['manage_announcements','manage_social'],true),
    (new.id,'Faculty Coordinator',2,array['manage_members','approve_expenses','manage_events','manage_social'],true),
    (new.id,'Volunteer',20,array['manage_attendance'],true),
    (new.id,'Member',100,array[]::text[],true);

  select id into president_position from public.club_positions
  where club_id=new.id and name='President';
  insert into public.club_memberships(
    club_id,user_id,position_id,status,joined_at
  ) values(new.id,new.created_by,president_position,'active',now());
  insert into public.club_scores(club_id) values(new.id);
  insert into public.conversations(kind,club_id,title,created_by)
  values('club',new.id,new.name||' chat',new.created_by)
  returning id into club_conversation;
  insert into public.conversation_members(conversation_id,user_id,role)
  values(club_conversation,new.created_by,'admin');
  return new;
end
$$;
