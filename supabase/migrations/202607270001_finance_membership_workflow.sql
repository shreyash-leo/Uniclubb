-- Finance access is limited to the three product roles. Every active member
-- can submit an expense, but can read only their own submission.

create or replace function public.has_finance_role(target_club uuid)
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select exists(
    select 1
    from public.club_memberships m
    join public.club_positions p on p.id=m.position_id
    where m.club_id=target_club
      and m.user_id=(select auth.uid())
      and m.status='active'
      and p.name in ('President','Supervisor','Treasurer')
  )
$$;

revoke all on function public.has_finance_role(uuid) from public,anon;
grant execute on function public.has_finance_role(uuid) to authenticated;

drop policy if exists expenses_read on public.expenses;
create policy expenses_read on public.expenses for select to authenticated
using (
  submitted_by=(select auth.uid())
  or public.has_finance_role(club_id)
);

drop policy if exists budgets_read on public.club_budgets;
create policy budgets_read on public.club_budgets for select to authenticated
using (public.has_finance_role(club_id));

drop policy if exists transactions_read on public.financial_transactions;
create policy transactions_read on public.financial_transactions
for select to authenticated
using (public.has_finance_role(club_id));

drop policy if exists expenses_submit on public.expenses;
create policy expenses_submit on public.expenses for insert to authenticated
with check (
  submitted_by=(select auth.uid())
  and public.is_club_member(club_id)
  and cardinality(receipt_urls)>0
  and (
    budget_id is null
    or (
      public.has_finance_role(club_id)
      and exists(
        select 1 from public.club_budgets b
        where b.id=budget_id and b.club_id=expenses.club_id
      )
    )
  )
);

alter table public.expenses
  drop constraint if exists expenses_receipt_required;
alter table public.expenses
  add constraint expenses_receipt_required
  check (cardinality(receipt_urls)>0) not valid;

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
  remaining numeric;
begin
  if decision not in ('approved','rejected') then
    raise exception 'Invalid expense decision';
  end if;
  select * into target from public.expenses where id=expense_id for update;
  if target.id is null then raise exception 'Expense not found'; end if;
  if not public.has_finance_role(target.club_id) then
    raise exception 'Only the President, Supervisor or Treasurer can approve expenses';
  end if;
  if target.status<>'pending' then
    raise exception 'This expense has already been decided';
  end if;
  if decision='approved' and target.budget_id is not null then
    select allocated-spent into remaining
    from public.club_budgets where id=target.budget_id for update;
    if remaining is null or target.amount>remaining then
      raise exception 'This expense exceeds the remaining budget';
    end if;
  end if;
  update public.expenses
  set status=decision,approved_by=auth.uid(),updated_at=now()
  where id=expense_id returning * into target;
  return target;
end
$$;

revoke all on function public.decide_expense(uuid,text) from public,anon;
grant execute on function public.decide_expense(uuid,text) to authenticated;

create or replace function public.handle_membership_notification()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  club_conversation uuid;
  club_name text;
  role_name text;
begin
  select name into club_name from public.clubs where id=new.club_id;
  select name into role_name from public.club_positions where id=new.position_id;

  if new.status='pending' and
     (tg_op='INSERT' or old.status is distinct from new.status) then
    insert into public.notifications(user_id,actor_id,type,title,body,data)
    select m.user_id,new.user_id,'join_request','New club join request',
      'A student requested to join '||coalesce(club_name,'the club')||'.',
      jsonb_build_object('club_id',new.club_id,'membership_id',new.id)
    from public.club_memberships m
    join public.club_positions p on p.id=m.position_id
    left join public.notification_preferences pref on pref.user_id=m.user_id
    where m.club_id=new.club_id and m.status='active'
      and ('all'=any(p.permissions) or 'manage_members'=any(p.permissions))
      and m.user_id<>new.user_id and coalesce(pref.join_requests,true);
  elsif new.status='active' and
        (tg_op='INSERT' or old.status is distinct from new.status) then
    select id into club_conversation from public.conversations
      where club_id=new.club_id and kind='club';
    if club_conversation is not null then
      insert into public.conversation_members(conversation_id,user_id,role)
      values(club_conversation,new.user_id,'member') on conflict do nothing;
    end if;
    insert into public.notifications(user_id,type,title,body,data)
    values(
      new.user_id,
      'club_membership',
      'Welcome to '||coalesce(club_name,'your new club')||'!',
      'Congratulations! You are now '||coalesce(role_name,'a member')||'.',
      jsonb_build_object('club_id',new.club_id,'membership_id',new.id)
    );
  elsif tg_op='UPDATE' and old.status is distinct from new.status then
    insert into public.notifications(user_id,type,title,body,data)
    values(
      new.user_id,
      'club_membership',
      case
        when new.status='left' then 'Club membership ended'
        when new.status='rejected' then 'Club request update'
        else 'Membership status updated'
      end,
      case
        when new.status='left' then
          'You are no longer a member of '||coalesce(club_name,'this club')||'.'
        when new.status='rejected' then
          'Your request to join '||coalesce(club_name,'this club')||' was not approved.'
        else
          'Your membership status is now '||new.status||'.'
      end,
      jsonb_build_object('club_id',new.club_id,'membership_id',new.id)
    );
  end if;
  return new;
end
$$;
