-- push_notifications_phase3.sql
--
-- Push notification foundation. We don't send pushes from the client —
-- an Edge Function with an APNs key does that — but we have to:
--
--   * Store the APNs device token per user per device.
--   * Store per-user notification preferences (mirrors the local
--     `spilltop.notif.*` toggles so server-side senders can respect them).
--
-- Actually sending the push lands in a follow-up migration + Edge Function
-- once the APNs key is provisioned.

-- 1. Device tokens ----------------------------------------------------------

create table if not exists public.device_push_tokens (
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null,
  platform text not null check (platform in ('ios', 'android')),
  app_version text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, token)
);

create index if not exists device_push_tokens_user_idx
  on public.device_push_tokens (user_id);

alter table public.device_push_tokens enable row level security;

drop policy if exists "device_push_tokens_select_own" on public.device_push_tokens;
create policy "device_push_tokens_select_own"
  on public.device_push_tokens
  for select
  using (auth.uid() = user_id);

drop policy if exists "device_push_tokens_insert_own" on public.device_push_tokens;
create policy "device_push_tokens_insert_own"
  on public.device_push_tokens
  for insert
  with check (auth.uid() = user_id);

drop policy if exists "device_push_tokens_update_own" on public.device_push_tokens;
create policy "device_push_tokens_update_own"
  on public.device_push_tokens
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "device_push_tokens_delete_own" on public.device_push_tokens;
create policy "device_push_tokens_delete_own"
  on public.device_push_tokens
  for delete
  using (auth.uid() = user_id);

-- 2. Notification preferences ----------------------------------------------
--
-- Single row per user. Every toggle defaults to true so a brand-new user
-- gets a useful experience out of the box.

create table if not exists public.notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  likes boolean not null default true,
  comments boolean not null default true,
  follows boolean not null default true,
  direct_messages boolean not null default true,
  live_streams boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.notification_preferences enable row level security;

drop policy if exists "notification_preferences_select_own" on public.notification_preferences;
create policy "notification_preferences_select_own"
  on public.notification_preferences
  for select
  using (auth.uid() = user_id);

drop policy if exists "notification_preferences_insert_own" on public.notification_preferences;
create policy "notification_preferences_insert_own"
  on public.notification_preferences
  for insert
  with check (auth.uid() = user_id);

drop policy if exists "notification_preferences_update_own" on public.notification_preferences;
create policy "notification_preferences_update_own"
  on public.notification_preferences
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
