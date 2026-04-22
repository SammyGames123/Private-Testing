-- Safety & privacy foundations.
--
-- Ships three pieces:
--   1. user_blocks   — symmetric hide: blocker won't see blocked's content
--                     and vice versa. RLS keeps the list private to the
--                     owner.
--   2. content_reports — user-submitted abuse reports against other users,
--                     videos, comments, or live streams. Insert-only for
--                     end-users; only the service role can read/resolve.
--   3. profiles.is_private — opt-in private account flag. The feed + venue
--                     pages already only surface `visibility = 'public'`
--                     videos, but this adds a first-class profile-level
--                     gate that client code + follow flows can consult.
--
-- Intentionally scoped: does NOT rewrite existing RLS on videos/check_ins/
-- live_streams to filter blocks at the DB. Client code filters on fetch,
-- and the table is the source of truth for that filter. A follow-up
-- migration can tighten RLS once the app-level filtering is proven.

-- ---------------------------------------------------------------------------
-- user_blocks
-- ---------------------------------------------------------------------------

create table if not exists public.user_blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create index if not exists user_blocks_blocker_idx
  on public.user_blocks (blocker_id);
create index if not exists user_blocks_blocked_idx
  on public.user_blocks (blocked_id);

alter table public.user_blocks enable row level security;

-- Owner-only visibility. You can see who YOU have blocked; you can never
-- learn who has blocked you (that's a deliberate safety choice — harassers
-- shouldn't be able to enumerate "who's afraid of me").
drop policy if exists "user_blocks_owner_read" on public.user_blocks;
create policy "user_blocks_owner_read"
  on public.user_blocks for select
  to authenticated
  using (blocker_id = auth.uid());

drop policy if exists "user_blocks_owner_insert" on public.user_blocks;
create policy "user_blocks_owner_insert"
  on public.user_blocks for insert
  to authenticated
  with check (blocker_id = auth.uid());

drop policy if exists "user_blocks_owner_delete" on public.user_blocks;
create policy "user_blocks_owner_delete"
  on public.user_blocks for delete
  to authenticated
  using (blocker_id = auth.uid());

-- Helper the server and future RLS policies can use. Symmetric: returns
-- true if EITHER user has blocked the other.
create or replace function public.is_blocked_between(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_blocks
    where (blocker_id = a and blocked_id = b)
       or (blocker_id = b and blocked_id = a)
  );
$$;

grant execute on function public.is_blocked_between(uuid, uuid) to authenticated;

-- Convenience RPC so the client can pull "everyone I've blocked" in one
-- call without pagination.
create or replace function public.get_my_blocked_user_ids()
returns table (blocked_id uuid)
language sql
stable
security definer
set search_path = public
as $$
  select blocked_id
  from public.user_blocks
  where blocker_id = auth.uid();
$$;

grant execute on function public.get_my_blocked_user_ids() to authenticated;

-- ---------------------------------------------------------------------------
-- content_reports
-- ---------------------------------------------------------------------------

create table if not exists public.content_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  -- Exactly one of the target_* columns is populated. We don't use a single
  -- polymorphic reference because FK cascades are easier per-type.
  target_user_id uuid references public.profiles (id) on delete cascade,
  target_video_id uuid references public.videos (id) on delete cascade,
  target_comment_id uuid references public.comments (id) on delete cascade,
  target_live_stream_id uuid references public.live_streams (id) on delete cascade,
  category text not null check (category in (
    'spam', 'harassment', 'nudity', 'violence', 'hate',
    'self_harm', 'illegal', 'impersonation', 'other'
  )),
  note text,
  status text not null default 'open' check (status in ('open', 'reviewing', 'dismissed', 'actioned')),
  created_at timestamptz not null default timezone('utc', now()),
  resolved_at timestamptz,
  -- Force exactly one target.
  check (
    (case when target_user_id is not null then 1 else 0 end) +
    (case when target_video_id is not null then 1 else 0 end) +
    (case when target_comment_id is not null then 1 else 0 end) +
    (case when target_live_stream_id is not null then 1 else 0 end)
    = 1
  )
);

create index if not exists content_reports_reporter_idx
  on public.content_reports (reporter_id, created_at desc);

create index if not exists content_reports_status_idx
  on public.content_reports (status, created_at desc);

alter table public.content_reports enable row level security;

-- Users can insert their own reports. They cannot read them back (no
-- "here's your abuse report history" surface for now) — moderation is
-- service-role only.
drop policy if exists "content_reports_insert_self" on public.content_reports;
create policy "content_reports_insert_self"
  on public.content_reports for insert
  to authenticated
  with check (reporter_id = auth.uid());

-- No select policy for `authenticated` — RLS default-denies, which is what
-- we want. Admins query via the service role or dedicated dashboard.

-- ---------------------------------------------------------------------------
-- profiles.is_private
-- ---------------------------------------------------------------------------

alter table public.profiles
  add column if not exists is_private boolean not null default false;

create index if not exists profiles_is_private_idx
  on public.profiles (is_private)
  where is_private;
