alter table public.clubs
  add column if not exists tagline text not null default '';
