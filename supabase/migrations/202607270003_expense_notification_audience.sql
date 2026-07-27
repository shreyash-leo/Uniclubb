create or replace function public.notify_expense()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if tg_op='INSERT' then
    insert into public.notifications(user_id,actor_id,type,title,body,data)
    select
      m.user_id,
      new.submitted_by,
      'expense_approval',
      'Expense approval needed',
      new.title||' · ₹'||new.amount::text,
      jsonb_build_object(
        'club_id',new.club_id,
        'expense_id',new.id
      )
    from public.club_memberships m
    join public.club_positions p on p.id=m.position_id
    left join public.notification_preferences pref on pref.user_id=m.user_id
    where m.club_id=new.club_id
      and m.status='active'
      and p.name in ('President','Supervisor','Treasurer')
      and m.user_id<>new.submitted_by
      and coalesce(pref.expense_updates,true);
  elsif old.status is distinct from new.status then
    insert into public.notifications(user_id,actor_id,type,title,body,data)
    values(
      new.submitted_by,
      new.approved_by,
      'expense_update',
      'Expense '||new.status,
      new.title||' · ₹'||new.amount::text,
      jsonb_build_object(
        'club_id',new.club_id,
        'expense_id',new.id
      )
    );
  end if;
  return new;
end
$$;
