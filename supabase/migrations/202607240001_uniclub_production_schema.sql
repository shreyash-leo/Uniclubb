-- UniClub v2 production schema. Apply with `supabase db push`.
create extension if not exists pgcrypto;

create type public.account_state as enum ('active', 'suspended', 'deleted');
create type public.membership_state as enum ('pending', 'active', 'rejected', 'waitlisted', 'left');
create type public.registration_state as enum ('pending', 'approved', 'rejected', 'waitlisted', 'cancelled', 'checked_in', 'completed');
create type public.payment_state as enum ('pending', 'authorized', 'paid', 'failed', 'refunded', 'partially_refunded');
create type public.visibility_state as enum ('public', 'college', 'members', 'private');

create table public.colleges (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  short_name text not null,
  city text,
  state text,
  country text not null default 'India',
  domain text,
  logo_url text,
  verified boolean not null default false,
  created_at timestamptz not null default now(),
  unique (name, city)
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  full_name text not null default '',
  username text unique,
  avatar_url text,
  cover_url text,
  bio text not null default '',
  college_id uuid references public.colleges(id) on delete set null,
  department text,
  academic_year text,
  skills text[] not null default '{}',
  interests text[] not null default '{}',
  social_links jsonb not null default '{}',
  account_state public.account_state not null default 'active',
  suspension_reason text,
  suspended_until timestamptz,
  is_platform_admin boolean not null default false,
  onboarding_complete boolean not null default false,
  last_seen_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.user_blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  reason text,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create table public.user_follows (
  follower_id uuid not null references public.profiles(id) on delete cascade,
  followed_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, followed_id),
  check (follower_id <> followed_id)
);

create table public.clubs (
  id uuid primary key default gen_random_uuid(),
  college_id uuid references public.colleges(id) on delete set null,
  name text not null,
  slug text not null unique,
  category text not null,
  description text not null default '',
  logo_url text,
  banner_url text,
  location text,
  social_links jsonb not null default '{}',
  recruitment_open boolean not null default false,
  verified boolean not null default false,
  visibility public.visibility_state not null default 'public',
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.club_positions (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  name text not null,
  rank int not null default 100,
  permissions text[] not null default '{}',
  color text,
  is_system boolean not null default false,
  created_at timestamptz not null default now(),
  unique (club_id, name)
);

create table public.club_memberships (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  position_id uuid references public.club_positions(id) on delete set null,
  status public.membership_state not null default 'pending',
  joined_at timestamptz,
  ended_at timestamptz,
  created_at timestamptz not null default now(),
  unique (club_id, user_id)
);

create table public.club_follows (
  club_id uuid not null references public.clubs(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (club_id, user_id)
);

create table public.recruitment_campaigns (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  title text not null,
  description text not null default '',
  opens_at timestamptz not null,
  closes_at timestamptz not null,
  status text not null default 'draft' check (status in ('draft','open','closed','archived')),
  form_schema jsonb not null default '[]',
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.recruitment_positions (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.recruitment_campaigns(id) on delete cascade,
  title text not null,
  description text not null default '',
  openings int not null default 1 check (openings > 0),
  required_skills text[] not null default '{}'
);

create table public.recruitment_applications (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.recruitment_campaigns(id) on delete cascade,
  position_id uuid references public.recruitment_positions(id) on delete set null,
  applicant_id uuid not null references public.profiles(id) on delete cascade,
  answers jsonb not null default '{}',
  status text not null default 'submitted' check (status in ('submitted','screening','interview','accepted','rejected','waitlisted','withdrawn')),
  current_round int not null default 0,
  reviewer_notes text,
  submitted_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (campaign_id, applicant_id)
);

create table public.recruitment_rounds (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.recruitment_campaigns(id) on delete cascade,
  round_number int not null,
  name text not null,
  kind text not null default 'review',
  instructions text,
  unique (campaign_id, round_number)
);

create table public.interviews (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.recruitment_applications(id) on delete cascade,
  round_id uuid references public.recruitment_rounds(id) on delete set null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  location_or_link text,
  interviewer_ids uuid[] not null default '{}',
  outcome text,
  notes text
);

create table public.events (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  title text not null,
  slug text not null unique,
  description text not null default '',
  category text not null,
  event_type text not null default 'event' check (event_type in ('event','hackathon','competition','workshop','meetup')),
  flyer_url text,
  venue_name text,
  venue_address text,
  latitude double precision,
  longitude double precision,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  registration_deadline timestamptz,
  capacity int check (capacity is null or capacity > 0),
  waitlist_enabled boolean not null default true,
  approval_mode text not null default 'manual' check (approval_mode in ('manual','automatic')),
  registration_schema jsonb not null default '[]',
  feedback_schema jsonb not null default '[]',
  agenda jsonb not null default '[]',
  sponsors jsonb not null default '[]',
  speakers jsonb not null default '[]',
  guests jsonb not null default '[]',
  certificate_template_url text,
  is_paid boolean not null default false,
  currency text not null default 'INR',
  visibility public.visibility_state not null default 'public',
  status text not null default 'draft' check (status in ('draft','published','cancelled','completed')),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at),
  check (registration_deadline is null or registration_deadline <= starts_at)
);

create table public.event_ticket_types (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  name text not null,
  description text,
  price numeric(12,2) not null default 0 check (price >= 0),
  capacity int check (capacity is null or capacity > 0),
  sales_start timestamptz,
  sales_end timestamptz,
  active boolean not null default true
);

create table public.coupons (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  code text not null,
  discount_type text not null check (discount_type in ('flat','percent')),
  discount_value numeric(12,2) not null check (discount_value > 0),
  usage_limit int,
  used_count int not null default 0,
  expires_at timestamptz,
  active boolean not null default true,
  unique (event_id, code)
);

create table public.event_registrations (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  ticket_type_id uuid references public.event_ticket_types(id) on delete set null,
  coupon_id uuid references public.coupons(id) on delete set null,
  answers jsonb not null default '{}',
  team_name text,
  status public.registration_state not null default 'pending',
  amount_due numeric(12,2) not null default 0,
  payment_status public.payment_state not null default 'pending',
  approval_note text,
  qr_token uuid not null default gen_random_uuid() unique,
  registered_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (event_id, user_id)
);

create table public.registration_members (
  id uuid primary key default gen_random_uuid(),
  registration_id uuid not null references public.event_registrations(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete set null,
  name text not null,
  email text,
  phone text,
  role text,
  unique (registration_id, email)
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  registration_id uuid references public.event_registrations(id) on delete set null,
  user_id uuid not null references public.profiles(id),
  provider text not null,
  provider_payment_id text,
  amount numeric(12,2) not null check (amount >= 0),
  currency text not null default 'INR',
  status public.payment_state not null default 'pending',
  invoice_number text unique,
  invoice_url text,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.refunds (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references public.payments(id) on delete cascade,
  amount numeric(12,2) not null check (amount > 0),
  reason text,
  provider_refund_id text,
  status text not null default 'pending',
  created_at timestamptz not null default now()
);

create table public.attendance (
  id uuid primary key default gen_random_uuid(),
  registration_id uuid not null references public.event_registrations(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  checked_in_at timestamptz,
  checked_out_at timestamptz,
  method text not null default 'qr' check (method in ('qr','manual')),
  late boolean not null default false,
  marked_by uuid references public.profiles(id),
  unique (event_id, user_id)
);

create table public.event_feedback (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  rating int check (rating between 1 and 5),
  answers jsonb not null default '{}',
  comment text,
  created_at timestamptz not null default now(),
  unique (event_id, user_id)
);

create table public.certificates (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  registration_id uuid references public.event_registrations(id) on delete set null,
  certificate_url text not null,
  verification_code text not null unique,
  issued_at timestamptz not null default now()
);

create table public.announcements (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  author_id uuid not null references public.profiles(id),
  title text not null,
  body text not null,
  attachments jsonb not null default '[]',
  poll jsonb,
  pinned boolean not null default false,
  scheduled_at timestamptz,
  published_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.announcement_votes (
  announcement_id uuid not null references public.announcements(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  option_index int not null,
  created_at timestamptz not null default now(),
  primary key (announcement_id, user_id)
);

create table public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles(id) on delete cascade,
  club_id uuid references public.clubs(id) on delete cascade,
  event_id uuid references public.events(id) on delete cascade,
  body text not null default '',
  media jsonb not null default '[]',
  visibility public.visibility_state not null default 'public',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.post_likes (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create table public.post_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  parent_id uuid references public.post_comments(id) on delete cascade,
  body text not null,
  mentioned_user_ids uuid[] not null default '{}',
  created_at timestamptz not null default now()
);

create table public.post_shares (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  destination text not null default 'external',
  created_at timestamptz not null default now()
);

create table public.stories (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles(id) on delete cascade,
  club_id uuid references public.clubs(id) on delete cascade,
  event_id uuid references public.events(id) on delete cascade,
  media_url text not null,
  media_type text not null default 'image',
  caption text,
  expires_at timestamptz not null default (now() + interval '24 hours'),
  created_at timestamptz not null default now()
);

create table public.story_views (
  story_id uuid not null references public.stories(id) on delete cascade,
  viewer_id uuid not null references public.profiles(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key (story_id, viewer_id)
);

create table public.story_highlights (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  title text not null,
  cover_url text,
  story_ids uuid[] not null default '{}',
  created_at timestamptz not null default now()
);

create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  kind text not null default 'direct' check (kind in ('direct','group','club','event')),
  club_id uuid references public.clubs(id) on delete cascade,
  event_id uuid references public.events(id) on delete cascade,
  title text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create unique index one_club_conversation on public.conversations(club_id)
  where kind='club' and club_id is not null;
create unique index one_event_conversation on public.conversations(event_id)
  where kind='event' and event_id is not null;

create table public.conversation_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'member',
  muted boolean not null default false,
  last_read_at timestamptz,
  joined_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  body text not null default '',
  attachment jsonb,
  mentioned_user_ids uuid[] not null default '{}',
  reply_to_id uuid references public.messages(id) on delete set null,
  edited_at timestamptz,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.club_budgets (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  name text not null,
  fiscal_year text not null,
  allocated numeric(14,2) not null default 0,
  spent numeric(14,2) not null default 0,
  created_by uuid not null references public.profiles(id),
  unique (club_id, name, fiscal_year)
);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  budget_id uuid references public.club_budgets(id) on delete set null,
  submitted_by uuid not null references public.profiles(id),
  title text not null,
  description text,
  amount numeric(14,2) not null check (amount > 0),
  currency text not null default 'INR',
  receipt_urls text[] not null default '{}',
  status text not null default 'pending' check (status in ('pending','approved','rejected','paid')),
  approved_by uuid references public.profiles(id),
  approval_note text,
  incurred_at date not null default current_date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.financial_transactions (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  expense_id uuid references public.expenses(id) on delete set null,
  kind text not null check (kind in ('income','expense','transfer','refund')),
  amount numeric(14,2) not null check (amount > 0),
  description text,
  reference text,
  occurred_at timestamptz not null default now(),
  recorded_by uuid not null references public.profiles(id)
);

create table public.badges (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text not null,
  icon_url text,
  points int not null default 0,
  criteria jsonb not null default '{}'
);

create table public.user_badges (
  badge_id uuid not null references public.badges(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  club_id uuid references public.clubs(id) on delete set null,
  awarded_by uuid references public.profiles(id),
  awarded_at timestamptz not null default now(),
  primary key (badge_id, user_id)
);

create table public.club_scores (
  club_id uuid primary key references public.clubs(id) on delete cascade,
  engagement_points int not null default 0,
  event_points int not null default 0,
  attendance_points int not null default 0,
  community_points int not null default 0,
  updated_at timestamptz not null default now()
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  type text not null,
  title text not null,
  body text not null,
  data jsonb not null default '{}',
  read_at timestamptz,
  push_sent_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.notification_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  push_enabled boolean not null default true,
  email_enabled boolean not null default true,
  event_reminders boolean not null default true,
  registration_updates boolean not null default true,
  club_announcements boolean not null default true,
  new_messages boolean not null default true,
  new_events boolean not null default true,
  join_requests boolean not null default true,
  expense_updates boolean not null default true,
  mentions boolean not null default true,
  invitations boolean not null default true,
  quiet_hours jsonb not null default '{}'
);

create table public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  provider text not null check (provider in ('apns','fcm','onesignal','webpush')),
  token text not null unique,
  platform text not null,
  enabled boolean not null default true,
  last_seen_at timestamptz not null default now()
);

create table public.event_reminders (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  remind_at timestamptz not null,
  delivered_at timestamptz,
  unique (event_id, user_id, remind_at)
);

create table public.calendar_connections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  provider text not null check (provider in ('google','apple','outlook')),
  provider_account_id text,
  encrypted_credentials jsonb not null default '{}',
  sync_enabled boolean not null default true,
  last_synced_at timestamptz,
  unique (user_id, provider)
);

create table public.invitations (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles(id),
  recipient_id uuid not null references public.profiles(id),
  club_id uuid references public.clubs(id) on delete cascade,
  event_id uuid references public.events(id) on delete cascade,
  kind text not null,
  status text not null default 'pending',
  created_at timestamptz not null default now()
);

create table public.ai_generations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  club_id uuid references public.clubs(id) on delete cascade,
  kind text not null,
  prompt text not null,
  result jsonb not null,
  model text,
  created_at timestamptz not null default now()
);

create table public.app_crashes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete set null,
  platform text not null,
  app_version text,
  error_type text not null,
  message text not null,
  stack_excerpt text,
  context jsonb not null default '{}',
  created_at timestamptz not null default now()
);

create table public.app_config (
  key text primary key,
  value jsonb not null,
  public boolean not null default false,
  updated_at timestamptz not null default now()
);

create table public.app_versions (
  id bigint generated always as identity primary key,
  platform text not null,
  minimum_version text not null,
  latest_version text not null,
  store_url text,
  force_update boolean not null default false,
  release_notes text,
  created_at timestamptz not null default now()
);

-- Fast lookup and feeds.
create index events_feed_idx on public.events(status, starts_at);
create index events_club_idx on public.events(club_id, starts_at);
create index notifications_user_idx on public.notifications(user_id, created_at desc);
create index messages_conversation_idx on public.messages(conversation_id, created_at);
create index posts_feed_idx on public.posts(created_at desc);
create index memberships_user_idx on public.club_memberships(user_id, status);
create index registrations_user_idx on public.event_registrations(user_id, registered_at desc);
create index announcements_club_idx on public.announcements(club_id, published_at desc);

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

do $$ declare t text;
begin
  foreach t in array array['profiles','clubs','events','event_registrations','recruitment_applications','payments','expenses','posts']
  loop execute format('create trigger touch_%I before update on public.%I for each row execute function public.touch_updated_at()', t, t);
  end loop;
end $$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles(id,email,full_name,avatar_url)
  values(new.id,coalesce(new.email,''),coalesce(new.raw_user_meta_data->>'full_name',''),new.raw_user_meta_data->>'avatar_url');
  insert into public.notification_preferences(user_id) values(new.id);
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_user();

create or replace function public.is_active_user()
returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.account_state='active'
    and (p.suspended_until is null or p.suspended_until <= now()))
$$;

create or replace function public.is_platform_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.is_platform_admin and p.account_state='active')
$$;

create or replace function public.is_club_member(target_club uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.club_memberships m
    where m.club_id=target_club and m.user_id=(select auth.uid()) and m.status='active')
$$;

create or replace function public.has_club_permission(target_club uuid, required_permission text)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_platform_admin() or exists(
    select 1 from public.club_memberships m
    join public.club_positions p on p.id=m.position_id
    where m.club_id=target_club and m.user_id=(select auth.uid()) and m.status='active'
      and (required_permission=any(p.permissions) or 'all'=any(p.permissions))
  )
$$;

create or replace function public.is_conversation_member(target_conversation uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.conversation_members cm
    where cm.conversation_id=target_conversation and cm.user_id=(select auth.uid()))
$$;

create or replace function public.can_view_profile(target_user uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select target_user=(select auth.uid()) or (
    public.is_active_user()
    and exists(select 1 from public.profiles p where p.id=target_user and p.account_state='active')
    and not exists(select 1 from public.user_blocks b
      where (b.blocker_id=(select auth.uid()) and b.blocked_id=target_user)
         or (b.blocker_id=target_user and b.blocked_id=(select auth.uid())))
  )
$$;

create or replace function public.seed_club_roles()
returns trigger language plpgsql security definer set search_path=public as $$
declare president_position uuid; club_conversation uuid;
begin
  insert into public.club_positions(club_id,name,rank,permissions,is_system)
  values
    (new.id,'President',1,array['all'],true),
    (new.id,'Vice President',2,array['manage_members','manage_events','manage_recruitment','manage_announcements'],true),
    (new.id,'Secretary',3,array['manage_announcements','manage_members'],true),
    (new.id,'Treasurer',3,array['manage_finance','approve_expenses'],true),
    (new.id,'Event Head',4,array['manage_events','manage_attendance'],true),
    (new.id,'Technical Head',4,array['manage_events'],true),
    (new.id,'Marketing Head',4,array['manage_announcements','manage_social'],true),
    (new.id,'Faculty Coordinator',2,array['manage_members','approve_expenses','manage_events'],true),
    (new.id,'Volunteer',20,array['manage_attendance'],true),
    (new.id,'Member',100,array[]::text[],true);
  select id into president_position from public.club_positions where club_id=new.id and name='President';
  insert into public.club_memberships(club_id,user_id,position_id,status,joined_at)
  values(new.id,new.created_by,president_position,'active',now());
  insert into public.club_scores(club_id) values(new.id);
  insert into public.conversations(kind,club_id,title,created_by)
    values('club',new.id,new.name||' chat',new.created_by) returning id into club_conversation;
  insert into public.conversation_members(conversation_id,user_id,role)
    values(club_conversation,new.created_by,'admin');
  return new;
end $$;
create trigger after_club_created after insert on public.clubs
for each row execute function public.seed_club_roles();

create or replace function public.create_event_conversation()
returns trigger language plpgsql security definer set search_path=public as $$
declare event_conversation uuid;
begin
  insert into public.conversations(kind,event_id,club_id,title,created_by)
    values('event',new.id,new.club_id,new.title||' chat',new.created_by)
    returning id into event_conversation;
  insert into public.conversation_members(conversation_id,user_id,role)
    select event_conversation,m.user_id,
      case when 'manage_events'=any(p.permissions) or 'all'=any(p.permissions) then 'admin' else 'member' end
    from public.club_memberships m left join public.club_positions p on p.id=m.position_id
    where m.club_id=new.club_id and m.status='active'
    on conflict do nothing;
  return new;
end $$;
create trigger after_event_created after insert on public.events
for each row execute function public.create_event_conversation();

create or replace function public.registration_capacity_guard()
returns trigger language plpgsql security definer set search_path=public as $$
declare max_capacity int; approved_count int; mode text;
begin
  select capacity,approval_mode into max_capacity,mode from public.events where id=new.event_id for update;
  select count(*) into approved_count from public.event_registrations
    where event_id=new.event_id and status in ('approved','checked_in','completed');
  if max_capacity is not null and approved_count >= max_capacity then new.status='waitlisted';
  elsif mode='automatic' and new.amount_due=0 then new.status='approved';
  end if;
  return new;
end $$;
create trigger registration_capacity before insert on public.event_registrations
for each row execute function public.registration_capacity_guard();

create or replace function public.notify_registration_change()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if old.status is distinct from new.status then
    insert into public.notifications(user_id,type,title,body,data)
    values(new.user_id,'registration_update','Registration '||replace(new.status::text,'_',' '),
      'Your event registration status was updated.',jsonb_build_object('event_id',new.event_id,'registration_id',new.id));
  end if;
  return new;
end $$;
create trigger notify_registration after update on public.event_registrations
for each row execute function public.notify_registration_change();

create or replace function public.add_registrant_to_event_chat()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.status in ('approved','checked_in','completed') then
    insert into public.conversation_members(conversation_id,user_id,role)
    select c.id,new.user_id,'member' from public.conversations c
    where c.event_id=new.event_id and c.kind='event'
    on conflict do nothing;
  end if;
  return new;
end $$;
create trigger registration_chat_insert after insert on public.event_registrations
for each row execute function public.add_registrant_to_event_chat();
create trigger registration_chat_update after update on public.event_registrations
for each row execute function public.add_registrant_to_event_chat();

-- Database notification fan-out keeps in-app state consistent on every client.
-- A scheduled Edge Function handles provider-specific push delivery.
create or replace function public.notify_new_event()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.status='published' and (tg_op='INSERT' or old.status is distinct from new.status) then
    insert into public.notifications(user_id,actor_id,type,title,body,data)
    select audience.user_id,new.created_by,'new_event','New event: '||new.title,
      coalesce(nullif(new.venue_name,''),'Open UniClub for details.'),
      jsonb_build_object('event_id',new.id,'club_id',new.club_id)
    from (
      select user_id from public.club_follows where club_id=new.club_id
      union
      select user_id from public.club_memberships where club_id=new.club_id and status='active'
    ) audience
    left join public.notification_preferences pref on pref.user_id=audience.user_id
    where audience.user_id<>new.created_by and coalesce(pref.new_events,true);
  end if;
  return new;
end $$;
create trigger notify_event_insert after insert on public.events
for each row execute function public.notify_new_event();
create trigger notify_event_publish after update of status on public.events
for each row execute function public.notify_new_event();

create or replace function public.notify_announcement()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.published_at is not null and new.published_at<=now()
     and (tg_op='INSERT' or old.published_at is distinct from new.published_at) then
    insert into public.notifications(user_id,actor_id,type,title,body,data)
    select audience.user_id,new.author_id,'club_announcement',new.title,left(new.body,180),
      jsonb_build_object('announcement_id',new.id,'club_id',new.club_id)
    from (
      select user_id from public.club_memberships where club_id=new.club_id and status='active'
      union
      select user_id from public.club_follows where club_id=new.club_id
    ) audience
    left join public.notification_preferences pref on pref.user_id=audience.user_id
    where audience.user_id<>new.author_id and coalesce(pref.club_announcements,true);
  end if;
  return new;
end $$;
create trigger notify_announcement_insert after insert on public.announcements
for each row execute function public.notify_announcement();
create trigger notify_announcement_publish after update of published_at on public.announcements
for each row execute function public.notify_announcement();

create or replace function public.handle_membership_notification()
returns trigger language plpgsql security definer set search_path=public as $$
declare club_conversation uuid;
begin
  if new.status='pending' and (tg_op='INSERT' or old.status is distinct from new.status) then
    insert into public.notifications(user_id,actor_id,type,title,body,data)
    select m.user_id,new.user_id,'join_request','New club join request',
      'A student requested to join the club.',
      jsonb_build_object('club_id',new.club_id,'membership_id',new.id)
    from public.club_memberships m
    join public.club_positions p on p.id=m.position_id
    left join public.notification_preferences pref on pref.user_id=m.user_id
    where m.club_id=new.club_id and m.status='active'
      and ('all'=any(p.permissions) or 'manage_members'=any(p.permissions))
      and m.user_id<>new.user_id and coalesce(pref.join_requests,true);
  elsif new.status='active' and (tg_op='INSERT' or old.status is distinct from new.status) then
    select id into club_conversation from public.conversations
      where club_id=new.club_id and kind='club';
    if club_conversation is not null then
      insert into public.conversation_members(conversation_id,user_id,role)
      values(club_conversation,new.user_id,'member') on conflict do nothing;
    end if;
    insert into public.notifications(user_id,type,title,body,data)
    values(new.user_id,'club_membership','Club membership approved',
      'Your club join request was approved.',jsonb_build_object('club_id',new.club_id));
  elsif tg_op='UPDATE' and old.status is distinct from new.status then
    insert into public.notifications(user_id,type,title,body,data)
    values(new.user_id,'club_membership','Club request '||new.status::text,
      'Your club membership request was updated.',jsonb_build_object('club_id',new.club_id));
  end if;
  return new;
end $$;
create trigger notify_membership_insert after insert on public.club_memberships
for each row execute function public.handle_membership_notification();
create trigger notify_membership_update after update of status on public.club_memberships
for each row execute function public.handle_membership_notification();

create or replace function public.notify_expense()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if tg_op='INSERT' then
    insert into public.notifications(user_id,actor_id,type,title,body,data)
    select m.user_id,new.submitted_by,'expense_approval','Expense approval needed',
      new.title||' · ₹'||new.amount::text,jsonb_build_object('club_id',new.club_id,'expense_id',new.id)
    from public.club_memberships m join public.club_positions p on p.id=m.position_id
    left join public.notification_preferences pref on pref.user_id=m.user_id
    where m.club_id=new.club_id and m.status='active'
      and ('all'=any(p.permissions) or 'approve_expenses'=any(p.permissions))
      and m.user_id<>new.submitted_by and coalesce(pref.expense_updates,true);
  elsif old.status is distinct from new.status then
    insert into public.notifications(user_id,actor_id,type,title,body,data)
    values(new.submitted_by,new.approved_by,'expense_update','Expense '||new.status,
      new.title||' · ₹'||new.amount::text,jsonb_build_object('club_id',new.club_id,'expense_id',new.id));
  end if;
  return new;
end $$;
create trigger notify_expense_insert after insert on public.expenses
for each row execute function public.notify_expense();
create trigger notify_expense_update after update of status on public.expenses
for each row execute function public.notify_expense();

create or replace function public.refresh_budget_spend()
returns trigger language plpgsql security definer set search_path=public as $$
declare target_budget uuid;
begin
  target_budget := case when tg_op='DELETE' then old.budget_id else new.budget_id end;
  if target_budget is not null then
    update public.club_budgets set spent=coalesce((
      select sum(amount) from public.expenses
      where budget_id=target_budget and status in ('approved','paid')
    ),0) where id=target_budget;
  end if;
  if tg_op='UPDATE' and old.budget_id is distinct from new.budget_id and old.budget_id is not null then
    update public.club_budgets set spent=coalesce((
      select sum(amount) from public.expenses
      where budget_id=old.budget_id and status in ('approved','paid')
    ),0) where id=old.budget_id;
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end $$;
create trigger refresh_budget_after_expense
after insert or update or delete on public.expenses
for each row execute function public.refresh_budget_spend();

create or replace function public.notify_message()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.notifications(user_id,actor_id,type,title,body,data)
  select cm.user_id,new.sender_id,
    case when cm.user_id=any(new.mentioned_user_ids) then 'mention' else 'new_message' end,
    case when cm.user_id=any(new.mentioned_user_ids) then 'You were mentioned' else 'New message' end,
    left(new.body,180),jsonb_build_object('conversation_id',new.conversation_id,'message_id',new.id)
  from public.conversation_members cm
  left join public.notification_preferences pref on pref.user_id=cm.user_id
  where cm.conversation_id=new.conversation_id and cm.user_id<>new.sender_id and not cm.muted
    and ((cm.user_id=any(new.mentioned_user_ids) and coalesce(pref.mentions,true))
      or (not (cm.user_id=any(new.mentioned_user_ids)) and coalesce(pref.new_messages,true)));
  return new;
end $$;
create trigger notify_message_insert after insert on public.messages
for each row execute function public.notify_message();

create or replace function public.notify_invitation()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.notifications(user_id,actor_id,type,title,body,data)
  select new.recipient_id,new.sender_id,'invitation','New invitation',
    'You received a new '||new.kind||' invitation.',
    jsonb_build_object('invitation_id',new.id,'kind',new.kind,'target_id',new.target_id)
  where coalesce((select invitations from public.notification_preferences where user_id=new.recipient_id),true);
  return new;
end $$;
create trigger notify_invitation_insert after insert on public.invitations
for each row execute function public.notify_invitation();

-- Global search returns normalized result cards while respecting blocked users.
create or replace function public.global_search(search_text text, result_limit int default 30)
returns table(kind text,id uuid,title text,subtitle text,image_url text,metadata jsonb)
language sql stable security invoker as $$
  (select 'club',c.id,c.name,c.category,c.logo_url,jsonb_build_object('college_id',c.college_id,'location',c.location)
   from public.clubs c where c.visibility='public' and (c.name ilike '%'||search_text||'%' or c.description ilike '%'||search_text||'%'))
  union all
  (select 'event',e.id,e.title,e.category,e.flyer_url,jsonb_build_object('starts_at',e.starts_at,'location',e.venue_name)
   from public.events e where e.status='published' and (e.title ilike '%'||search_text||'%' or e.description ilike '%'||search_text||'%'))
  union all
  (select 'user',p.id,p.full_name,coalesce(p.department,''),p.avatar_url,jsonb_build_object('skills',p.skills,'college_id',p.college_id)
   from public.profiles p where p.account_state='active' and p.id<>(select auth.uid())
    and public.can_view_profile(p.id)
    and (p.full_name ilike '%'||search_text||'%' or p.username ilike '%'||search_text||'%'))
  union all
  (select 'college',co.id,co.name,coalesce(co.city,''),co.logo_url,'{}'::jsonb
   from public.colleges co where co.name ilike '%'||search_text||'%' or co.short_name ilike '%'||search_text||'%')
  union all
  (select 'announcement',a.id,a.title,left(a.body,100),null,jsonb_build_object('club_id',a.club_id)
   from public.announcements a where a.published_at<=now() and (a.title ilike '%'||search_text||'%' or a.body ilike '%'||search_text||'%'))
  union all
  (select 'post',po.id,left(po.body,80),'Post',null,jsonb_build_object('club_id',po.club_id,'event_id',po.event_id)
   from public.posts po where po.visibility='public' and po.body ilike '%'||search_text||'%')
  limit result_limit
$$;

-- Enable RLS everywhere exposed to the client.
do $$ declare t text;
begin
  foreach t in array array[
    'colleges','profiles','user_blocks','user_follows','clubs','club_positions','club_memberships','club_follows',
    'recruitment_campaigns','recruitment_positions','recruitment_applications','recruitment_rounds','interviews',
    'events','event_ticket_types','coupons','event_registrations','registration_members','payments','refunds',
    'attendance','event_feedback','certificates','announcements','announcement_votes','posts','post_likes',
    'post_comments','post_shares','stories','story_views','story_highlights','conversations','conversation_members',
    'messages','club_budgets','expenses','financial_transactions','badges','user_badges','club_scores',
    'notifications','notification_preferences','device_tokens','event_reminders','calendar_connections',
    'invitations','ai_generations','app_crashes','app_config','app_versions'
  ] loop execute format('alter table public.%I enable row level security',t); end loop;
end $$;

-- Public/read policies.
create policy colleges_read on public.colleges for select using (true);
create policy profiles_read on public.profiles for select to authenticated
  using (public.can_view_profile(id));
create policy profiles_self_update on public.profiles for update to authenticated
  using (id=(select auth.uid())) with check (id=(select auth.uid()));
revoke update on public.profiles from authenticated;
grant update(full_name,username,avatar_url,cover_url,bio,college_id,department,
  academic_year,skills,interests,social_links,onboarding_complete,last_seen_at)
  on public.profiles to authenticated;
create policy clubs_read on public.clubs for select using (visibility='public' or public.is_club_member(id));
create policy clubs_create on public.clubs for insert to authenticated with check (created_by=(select auth.uid()) and public.is_active_user());
create policy clubs_manage on public.clubs for update to authenticated using (public.has_club_permission(id,'all'));
create policy positions_read on public.club_positions for select to authenticated using (public.is_active_user());
create policy positions_manage on public.club_positions for all to authenticated
  using (public.has_club_permission(club_id,'manage_members'))
  with check (public.has_club_permission(club_id,'manage_members'));
create policy memberships_read on public.club_memberships for select to authenticated
  using (user_id=(select auth.uid()) or public.is_club_member(club_id));
create policy memberships_apply on public.club_memberships for insert to authenticated
  with check (user_id=(select auth.uid()) or public.has_club_permission(club_id,'manage_members'));
create policy memberships_manage on public.club_memberships for update to authenticated
  using (user_id<>(select auth.uid()) and public.has_club_permission(club_id,'manage_members'))
  with check (user_id<>(select auth.uid()) and public.has_club_permission(club_id,'manage_members'));
create policy follows_own_all on public.club_follows for all to authenticated
  using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy blocks_own_all on public.user_blocks for all to authenticated
  using (blocker_id=(select auth.uid())) with check (blocker_id=(select auth.uid()));
create policy user_follows_own_all on public.user_follows for all to authenticated
  using (follower_id=(select auth.uid())) with check (follower_id=(select auth.uid()));
create policy events_read on public.events for select using (status='published' or public.is_club_member(club_id));
create policy events_manage on public.events for all to authenticated
  using (public.has_club_permission(club_id,'manage_events'))
  with check (public.has_club_permission(club_id,'manage_events'));
create policy ticket_read on public.event_ticket_types for select using (true);
create policy ticket_manage on public.event_ticket_types for all to authenticated
  using (public.has_club_permission((select club_id from public.events where id=event_id),'manage_events'))
  with check (public.has_club_permission((select club_id from public.events where id=event_id),'manage_events'));
create policy coupon_read on public.coupons for select to authenticated using (active and (expires_at is null or expires_at>now()));
create policy coupon_manage on public.coupons for all to authenticated
  using (public.has_club_permission((select club_id from public.events where id=event_id),'manage_events'))
  with check (public.has_club_permission((select club_id from public.events where id=event_id),'manage_events'));
create policy registration_own_read on public.event_registrations for select to authenticated
  using (user_id=(select auth.uid()) or public.has_club_permission((select club_id from public.events where id=event_id),'manage_events'));
create policy registration_create on public.event_registrations for insert to authenticated
  with check (user_id=(select auth.uid()) and public.is_active_user());
create policy registration_manage on public.event_registrations for update to authenticated
  using (user_id<>(select auth.uid()) and public.has_club_permission((select club_id from public.events where id=event_id),'manage_events'))
  with check (user_id<>(select auth.uid()) and public.has_club_permission((select club_id from public.events where id=event_id),'manage_events'));
create policy registration_members_read on public.registration_members for select to authenticated
  using (exists(select 1 from public.event_registrations r where r.id=registration_id
    and (r.user_id=(select auth.uid()) or public.has_club_permission((select club_id from public.events where id=r.event_id),'manage_events'))));
create policy registration_members_create on public.registration_members for insert to authenticated
  with check (exists(select 1 from public.event_registrations r where r.id=registration_id and r.user_id=(select auth.uid())));
create policy payments_own_read on public.payments for select to authenticated
  using (user_id=(select auth.uid()) or exists(select 1 from public.event_registrations r
    join public.events e on e.id=r.event_id where r.id=registration_id and public.has_club_permission(e.club_id,'manage_finance')));
create policy refunds_own_read on public.refunds for select to authenticated
  using (exists(select 1 from public.payments p
    left join public.event_registrations r on r.id=p.registration_id
    left join public.events e on e.id=r.event_id
    where p.id=payment_id and (p.user_id=(select auth.uid())
      or public.has_club_permission(e.club_id,'manage_finance'))));
create policy announcements_read on public.announcements for select to authenticated
  using (published_at<=now() or public.is_club_member(club_id));
create policy announcements_manage on public.announcements for all to authenticated
  using (public.has_club_permission(club_id,'manage_announcements'))
  with check (public.has_club_permission(club_id,'manage_announcements'));
create policy announcement_votes_read on public.announcement_votes for select to authenticated using (true);
create policy announcement_votes_own on public.announcement_votes for insert to authenticated
  with check (user_id=(select auth.uid()));
create policy posts_read on public.posts for select to authenticated
  using (visibility='public' or author_id=(select auth.uid()) or (club_id is not null and public.is_club_member(club_id)));
create policy posts_create on public.posts for insert to authenticated with check (author_id=(select auth.uid()));
create policy posts_owner on public.posts for update to authenticated using (author_id=(select auth.uid()));
create policy posts_owner_delete on public.posts for delete to authenticated using (author_id=(select auth.uid()));
create policy social_like_all on public.post_likes for all to authenticated
  using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy comments_read on public.post_comments for select to authenticated using (true);
create policy comments_create on public.post_comments for insert to authenticated with check (author_id=(select auth.uid()));
create policy shares_own on public.post_shares for insert to authenticated with check (user_id=(select auth.uid()));
create policy stories_read on public.stories for select to authenticated using (expires_at>now() or author_id=(select auth.uid()));
create policy stories_owner on public.stories for all to authenticated
  using (author_id=(select auth.uid())) with check (author_id=(select auth.uid()));
create policy story_views_read on public.story_views for select to authenticated
  using (viewer_id=(select auth.uid()) or exists(select 1 from public.stories s where s.id=story_id and s.author_id=(select auth.uid())));
create policy story_views_own on public.story_views for insert to authenticated with check (viewer_id=(select auth.uid()));
create policy highlights_read on public.story_highlights for select to authenticated using (true);
create policy highlights_manage on public.story_highlights for all to authenticated
  using (public.has_club_permission(club_id,'manage_social'))
  with check (public.has_club_permission(club_id,'manage_social'));
create policy conversation_member_read on public.conversations for select to authenticated
  using (created_by=(select auth.uid()) or exists(select 1 from public.conversation_members cm where cm.conversation_id=id and cm.user_id=(select auth.uid())));
create policy conversation_create on public.conversations for insert to authenticated
  with check (created_by=(select auth.uid()) and kind in ('direct','group') and club_id is null and event_id is null);
create policy conversation_members_read on public.conversation_members for select to authenticated
  using (public.is_conversation_member(conversation_id));
create policy conversation_members_manage on public.conversation_members for insert to authenticated
  with check (exists(select 1 from public.conversations c
    where c.id=conversation_id and c.created_by=(select auth.uid())));
create policy messages_read on public.messages for select to authenticated
  using (exists(select 1 from public.conversation_members cm where cm.conversation_id=messages.conversation_id and cm.user_id=(select auth.uid())));
create policy messages_create on public.messages for insert to authenticated
  with check (sender_id=(select auth.uid()) and exists(select 1 from public.conversation_members cm where cm.conversation_id=messages.conversation_id and cm.user_id=(select auth.uid())));
create policy notifications_own on public.notifications for select to authenticated using (user_id=(select auth.uid()));
create policy notifications_update on public.notifications for update to authenticated using (user_id=(select auth.uid()));
revoke update on public.notifications from authenticated;
grant update(read_at) on public.notifications to authenticated;
create policy preferences_own on public.notification_preferences for all to authenticated
  using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy device_tokens_own on public.device_tokens for all to authenticated
  using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy reminders_own on public.event_reminders for all to authenticated
  using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy calendar_own on public.calendar_connections for all to authenticated
  using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy applications_own_read on public.recruitment_applications for select to authenticated
  using (applicant_id=(select auth.uid()) or public.has_club_permission((select club_id from public.recruitment_campaigns where id=campaign_id),'manage_recruitment'));
create policy applications_create on public.recruitment_applications for insert to authenticated with check (applicant_id=(select auth.uid()));
create policy applications_manage on public.recruitment_applications for update to authenticated
  using (applicant_id<>(select auth.uid()) and public.has_club_permission((select club_id from public.recruitment_campaigns where id=campaign_id),'manage_recruitment'))
  with check (applicant_id<>(select auth.uid()) and public.has_club_permission((select club_id from public.recruitment_campaigns where id=campaign_id),'manage_recruitment'));
create policy campaigns_read on public.recruitment_campaigns for select using (status='open' or public.is_club_member(club_id));
create policy campaigns_manage on public.recruitment_campaigns for all to authenticated
  using (public.has_club_permission(club_id,'manage_recruitment')) with check (public.has_club_permission(club_id,'manage_recruitment'));
create policy recruitment_positions_read on public.recruitment_positions for select to authenticated using (true);
create policy recruitment_positions_manage on public.recruitment_positions for all to authenticated
  using (public.has_club_permission((select club_id from public.recruitment_campaigns where id=campaign_id),'manage_recruitment'))
  with check (public.has_club_permission((select club_id from public.recruitment_campaigns where id=campaign_id),'manage_recruitment'));
create policy recruitment_rounds_read on public.recruitment_rounds for select to authenticated using (true);
create policy recruitment_rounds_manage on public.recruitment_rounds for all to authenticated
  using (public.has_club_permission((select club_id from public.recruitment_campaigns where id=campaign_id),'manage_recruitment'))
  with check (public.has_club_permission((select club_id from public.recruitment_campaigns where id=campaign_id),'manage_recruitment'));
create policy interviews_read on public.interviews for select to authenticated
  using (exists(select 1 from public.recruitment_applications a where a.id=application_id
    and (a.applicant_id=(select auth.uid()) or public.has_club_permission((select club_id from public.recruitment_campaigns where id=a.campaign_id),'manage_recruitment'))));
create policy interviews_manage on public.interviews for all to authenticated
  using (exists(select 1 from public.recruitment_applications a where a.id=application_id
    and public.has_club_permission((select club_id from public.recruitment_campaigns where id=a.campaign_id),'manage_recruitment')))
  with check (exists(select 1 from public.recruitment_applications a where a.id=application_id
    and public.has_club_permission((select club_id from public.recruitment_campaigns where id=a.campaign_id),'manage_recruitment')));
create policy expenses_read on public.expenses for select to authenticated
  using (submitted_by=(select auth.uid()) or public.has_club_permission(club_id,'manage_finance'));
create policy expenses_submit on public.expenses for insert to authenticated
  with check (submitted_by=(select auth.uid()) and public.is_club_member(club_id));
create policy expenses_approve on public.expenses for update to authenticated
  using (submitted_by<>(select auth.uid()) and public.has_club_permission(club_id,'approve_expenses'));
create policy budgets_read on public.club_budgets for select to authenticated using (public.is_club_member(club_id));
create policy budgets_manage on public.club_budgets for all to authenticated
  using (public.has_club_permission(club_id,'manage_finance'))
  with check (public.has_club_permission(club_id,'manage_finance'));
create policy transactions_read on public.financial_transactions for select to authenticated using (public.is_club_member(club_id));
create policy transactions_manage on public.financial_transactions for all to authenticated
  using (public.has_club_permission(club_id,'manage_finance'))
  with check (public.has_club_permission(club_id,'manage_finance'));
create policy badges_read on public.badges for select using (true);
create policy user_badges_read on public.user_badges for select using (true);
create policy scores_read on public.club_scores for select using (true);
create policy attendance_read on public.attendance for select to authenticated
  using (user_id=(select auth.uid()) or public.has_club_permission((select club_id from public.events where id=event_id),'manage_attendance'));
create policy attendance_manage on public.attendance for all to authenticated
  using (public.has_club_permission((select club_id from public.events where id=event_id),'manage_attendance'))
  with check (public.has_club_permission((select club_id from public.events where id=event_id),'manage_attendance'));
create policy feedback_read on public.event_feedback for select to authenticated
  using (user_id=(select auth.uid()) or public.has_club_permission((select club_id from public.events where id=event_id),'manage_events'));
create policy feedback_own on public.event_feedback for insert to authenticated with check (user_id=(select auth.uid()));
create policy feedback_update on public.event_feedback for update to authenticated
  using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy certificates_read on public.certificates for select to authenticated
  using (user_id=(select auth.uid()) or public.has_club_permission((select club_id from public.events where id=event_id),'manage_events'));
create policy certificates_manage on public.certificates for all to authenticated
  using (public.has_club_permission((select club_id from public.events where id=event_id),'manage_events'))
  with check (public.has_club_permission((select club_id from public.events where id=event_id),'manage_events'));
create policy invitations_read on public.invitations for select to authenticated
  using (sender_id=(select auth.uid()) or recipient_id=(select auth.uid()));
create policy invitations_create on public.invitations for insert to authenticated with check (sender_id=(select auth.uid()));
create policy ai_own on public.ai_generations for select to authenticated using (user_id=(select auth.uid()));
create policy crashes_insert on public.app_crashes for insert to authenticated
  with check (user_id=(select auth.uid()));
create policy app_config_public on public.app_config for select using (public=true);
create policy versions_read on public.app_versions for select using (true);

-- Public media buckets with authenticated owner writes.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
 ('avatars','avatars',true,5242880,array['image/jpeg','image/png','image/webp']),
 ('club-media','club-media',true,15728640,array['image/jpeg','image/png','image/webp','application/pdf']),
 ('event-media','event-media',true,52428800,array['image/jpeg','image/png','image/webp','application/pdf','audio/mpeg','audio/wav','audio/mp4']),
 ('receipts','receipts',false,10485760,array['image/jpeg','image/png','application/pdf']),
 ('certificates','certificates',false,10485760,array['application/pdf'])
on conflict(id) do nothing;

create policy storage_public_read on storage.objects for select using (bucket_id in ('avatars','club-media','event-media'));
create policy storage_owner_insert on storage.objects for insert to authenticated
  with check (bucket_id in ('avatars','club-media','event-media','receipts','certificates') and owner_id=(select auth.uid()::text));
create policy storage_owner_update on storage.objects for update to authenticated
  using (owner_id=(select auth.uid()::text)) with check (owner_id=(select auth.uid()::text));
create policy storage_owner_delete on storage.objects for delete to authenticated using (owner_id=(select auth.uid()::text));

-- Realtime tables.
alter publication supabase_realtime add table public.notifications;
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.announcements;
alter publication supabase_realtime add table public.event_registrations;

insert into public.badges(name,description,points) values
 ('First Step','Attend your first event',10),
 ('Club Builder','Become an active club member',25),
 ('Event Champion','Attend ten events',100),
 ('Community Voice','Create ten helpful posts or comments',75),
 ('Volunteer Star','Complete five volunteer assignments',100),
 ('Leadership','Hold a leadership position in a club',150)
on conflict(name) do nothing;
