create table if not exists public.saved_events (
  user_id uuid not null references public.profiles(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id,event_id)
);

alter table public.saved_events enable row level security;

drop policy if exists saved_events_own on public.saved_events;
create policy saved_events_own on public.saved_events
for all to authenticated
using (user_id=(select auth.uid()))
with check (user_id=(select auth.uid()));

create index if not exists saved_events_user_created_idx
  on public.saved_events(user_id,created_at desc);

alter publication supabase_realtime add table public.saved_events;
