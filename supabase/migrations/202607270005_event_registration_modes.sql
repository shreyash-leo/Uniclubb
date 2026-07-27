alter table public.events
  drop constraint if exists events_registration_type_check;

alter table public.events
  add constraint events_registration_type_check
  check (registration_type in ('none','solo','team'));

alter table public.events
  add column if not exists payment_note text not null default '';
