-- Requested product simplification and workflow hardening.

drop table if exists public.ai_generations cascade;
drop table if exists public.app_crashes cascade;

alter table public.events
  add column if not exists registration_enabled boolean not null default true,
  add column if not exists registration_type text not null default 'solo'
    check (registration_type in ('solo','team')),
  add column if not exists team_size_min integer not null default 1
    check (team_size_min > 0),
  add column if not exists team_size_max integer not null default 1
    check (team_size_max >= team_size_min);

alter table public.announcements
  add column if not exists event_id uuid references public.events(id)
    on delete cascade;
create index if not exists announcements_event_idx
  on public.announcements(event_id,published_at desc);

drop trigger if exists after_event_created on public.events;
drop trigger if exists registration_chat_insert on public.event_registrations;
drop trigger if exists registration_chat_update on public.event_registrations;
delete from public.conversations where kind='event';

drop policy if exists clubs_delete on public.clubs;
create policy clubs_delete on public.clubs for delete to authenticated
using (public.has_club_permission(id,'all'));

drop policy if exists registration_create on public.event_registrations;
create policy registration_create on public.event_registrations
for insert to authenticated
with check (
  user_id=(select auth.uid())
  and public.is_active_user()
  and exists(
    select 1 from public.events e
    where e.id=event_id
      and e.status='published'
      and e.registration_enabled
      and (e.registration_deadline is null or e.registration_deadline>=now())
  )
);

create or replace function public.recalculate_budget_spent()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  old_budget uuid;
  new_budget uuid;
begin
  old_budget := case when tg_op='INSERT' then null else old.budget_id end;
  new_budget := case when tg_op='DELETE' then null else new.budget_id end;

  update public.club_budgets b
  set spent=coalesce((
    select sum(e.amount) from public.expenses e
    where e.budget_id=b.id and e.status in ('approved','paid')
  ),0)
  where b.id in (old_budget,new_budget);
  return coalesce(new,old);
end
$$;

drop trigger if exists recalculate_budget_spent on public.expenses;
create trigger recalculate_budget_spent
after insert or update or delete on public.expenses
for each row execute function public.recalculate_budget_spent();

create or replace function public.decide_expense(
  expense_id uuid,
  decision text
)
returns public.expenses
language plpgsql
security definer
set search_path=public
as $$
declare
  target public.expenses;
begin
  if decision not in ('approved','rejected') then
    raise exception 'Invalid expense decision';
  end if;
  select * into target from public.expenses where id=expense_id for update;
  if target.id is null then raise exception 'Expense not found'; end if;
  if not public.has_club_permission(target.club_id,'approve_expenses')
     and not public.has_club_permission(target.club_id,'all') then
    raise exception 'You cannot approve expenses for this club';
  end if;
  if target.status<>'pending' then
    raise exception 'This expense has already been decided';
  end if;
  update public.expenses
  set status=decision,approved_by=auth.uid(),updated_at=now()
  where id=expense_id returning * into target;
  return target;
end
$$;
revoke all on function public.decide_expense(uuid,text) from public,anon;
grant execute on function public.decide_expense(uuid,text) to authenticated;

create or replace function public.record_event_attendance(
  target_event uuid,
  qr_value uuid,
  checkout boolean default false
)
returns public.attendance
language plpgsql
security definer
set search_path=public
as $$
declare
  registration public.event_registrations;
  result public.attendance;
  event_start timestamptz;
begin
  if not public.has_club_permission(
    (select club_id from public.events where id=target_event),
    'manage_attendance'
  ) and not public.has_club_permission(
    (select club_id from public.events where id=target_event),
    'manage_events'
  ) then
    raise exception 'Attendance permission required';
  end if;

  select * into registration
  from public.event_registrations
  where event_id=target_event and qr_token=qr_value
  for update;
  if registration.id is null then raise exception 'Invalid QR code'; end if;
  if registration.status in ('rejected','cancelled','waitlisted','pending') then
    raise exception 'Registration is not approved';
  end if;

  if checkout then
    update public.attendance
    set checked_out_at=now(),marked_by=auth.uid()
    where event_id=target_event and user_id=registration.user_id
      and checked_in_at is not null and checked_out_at is null
    returning * into result;
    if result.id is null then raise exception 'Check-in is required first'; end if;
    update public.event_registrations set status='completed'
    where id=registration.id;
  else
    if exists(
      select 1 from public.attendance
      where event_id=target_event and user_id=registration.user_id
        and checked_in_at is not null
    ) then raise exception 'Participant is already checked in'; end if;
    select starts_at into event_start from public.events where id=target_event;
    insert into public.attendance(
      registration_id,event_id,user_id,checked_in_at,method,late,marked_by
    ) values(
      registration.id,target_event,registration.user_id,now(),'qr',
      now()>event_start+interval '15 minutes',auth.uid()
    ) returning * into result;
    update public.event_registrations set status='checked_in'
    where id=registration.id;
  end if;
  return result;
end
$$;
revoke all on function public.record_event_attendance(uuid,uuid,boolean)
from public,anon;
grant execute on function public.record_event_attendance(uuid,uuid,boolean)
to authenticated;

create or replace function public.notify_announcement()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if new.published_at is not null and new.published_at<=now()
     and (tg_op='INSERT' or old.published_at is distinct from new.published_at) then
    insert into public.notifications(user_id,actor_id,type,title,body,data)
    select distinct audience.user_id,new.author_id,'club_announcement',
      new.title,left(new.body,180),
      jsonb_build_object(
        'announcement_id',new.id,'club_id',new.club_id,'event_id',new.event_id
      )
    from (
      select user_id from public.club_memberships
      where club_id=new.club_id and status='active'
      union
      select r.user_id from public.event_registrations r
      where new.event_id is not null and r.event_id=new.event_id
        and r.status not in ('rejected','cancelled')
    ) audience
    left join public.notification_preferences pref
      on pref.user_id=audience.user_id
    where audience.user_id<>new.author_id
      and coalesce(pref.club_announcements,true);
  end if;
  return new;
end
$$;

create or replace function public.sync_club_chat_membership()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  club_conversation uuid;
begin
  select id into club_conversation from public.conversations
  where club_id=new.club_id and kind='club';
  if new.status='active' then
    insert into public.conversation_members(conversation_id,user_id,role)
    values(club_conversation,new.user_id,'member')
    on conflict(conversation_id,user_id) do nothing;
  elsif tg_op='UPDATE' and old.status='active' then
    delete from public.conversation_members
    where conversation_id=club_conversation and user_id=new.user_id;
  end if;
  return new;
end
$$;

drop trigger if exists sync_club_chat_membership on public.club_memberships;
create trigger sync_club_chat_membership
after insert or update of status on public.club_memberships
for each row execute function public.sync_club_chat_membership();

insert into public.conversation_members(conversation_id,user_id,role)
select c.id,m.user_id,
  case when p.name='President' then 'admin' else 'member' end
from public.club_memberships m
join public.conversations c on c.club_id=m.club_id and c.kind='club'
left join public.club_positions p on p.id=m.position_id
where m.status='active'
on conflict(conversation_id,user_id) do nothing;

do $$
declare target_budget uuid;
begin
  for target_budget in select id from public.club_budgets loop
    update public.club_budgets b
    set spent=coalesce((
      select sum(e.amount) from public.expenses e
      where e.budget_id=b.id and e.status in ('approved','paid')
    ),0)
    where b.id=target_budget;
  end loop;
end
$$;
