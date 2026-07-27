alter table public.expenses
  add column if not exists event_id uuid
  references public.events(id) on delete set null;

create index if not exists expenses_event_created_idx
  on public.expenses(event_id,created_at desc);

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
  and (
    event_id is null
    or exists(
      select 1 from public.events e
      where e.id=event_id and e.club_id=expenses.club_id
    )
  )
);
