-- follow_requests_phase2.sql
--
-- Private accounts: when `profiles.is_private = true`, a would-be follower
-- has to be approved before they start following. This migration adds:
--
--   * `follow_requests` table — pending/approved/rejected requests.
--   * `request_follow(target uuid)` RPC — request-or-follow, branches on
--     whether the target is private.
--   * `approve_follow_request(request_id uuid)` RPC — target approves.
--   * `reject_follow_request(request_id uuid)` RPC — target rejects.
--   * RLS that lets both parties read their own rows and keeps everyone
--     else out.
--
-- We deliberately keep the existing `follows` table unchanged. Approval
-- just inserts into it the same way a direct follow would, so all the
-- existing feed / profile code keeps working.

-- 1. Table ------------------------------------------------------------------

create table if not exists public.follow_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references auth.users(id) on delete cascade,
  target_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  constraint follow_requests_not_self check (requester_id <> target_id),
  constraint follow_requests_unique_pending unique (requester_id, target_id)
);

create index if not exists follow_requests_target_pending_idx
  on public.follow_requests (target_id)
  where status = 'pending';

create index if not exists follow_requests_requester_idx
  on public.follow_requests (requester_id);

alter table public.follow_requests enable row level security;

-- 2. RLS --------------------------------------------------------------------

drop policy if exists "follow_requests_select_own" on public.follow_requests;
create policy "follow_requests_select_own"
  on public.follow_requests
  for select
  using (
    auth.uid() = requester_id
    or auth.uid() = target_id
  );

-- Inserts happen exclusively through `request_follow` (security definer),
-- so direct inserts are disallowed.
drop policy if exists "follow_requests_no_direct_insert" on public.follow_requests;
create policy "follow_requests_no_direct_insert"
  on public.follow_requests
  for insert
  with check (false);

-- Updates happen through `approve_follow_request` / `reject_follow_request`.
drop policy if exists "follow_requests_no_direct_update" on public.follow_requests;
create policy "follow_requests_no_direct_update"
  on public.follow_requests
  for update
  using (false);

-- Requester can cancel their own pending request; target can delete any
-- resolved row on their side for tidy-up.
drop policy if exists "follow_requests_delete_own" on public.follow_requests;
create policy "follow_requests_delete_own"
  on public.follow_requests
  for delete
  using (
    (auth.uid() = requester_id and status = 'pending')
    or auth.uid() = target_id
  );

-- 3. RPC: request_follow ----------------------------------------------------
--
-- Returns one of: 'followed' | 'requested' | 'already_following' | 'already_requested'.

create or replace function public.request_follow(target uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  target_is_private boolean;
begin
  if me is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if target is null or me = target then
    raise exception 'invalid target' using errcode = '22023';
  end if;

  -- Block check — symmetric. If either side has blocked the other, refuse.
  if public.is_blocked_between(me, target) then
    raise exception 'blocked' using errcode = '42501';
  end if;

  select is_private into target_is_private
    from public.profiles
    where id = target;

  if coalesce(target_is_private, false) = false then
    -- Public account: direct follow.
    insert into public.follows (follower_id, following_id)
      values (me, target)
      on conflict do nothing;
    return 'followed';
  end if;

  -- Private account: already following?
  if exists (
    select 1 from public.follows
      where follower_id = me and following_id = target
  ) then
    return 'already_following';
  end if;

  -- Existing pending request?
  if exists (
    select 1 from public.follow_requests
      where requester_id = me and target_id = target and status = 'pending'
  ) then
    return 'already_requested';
  end if;

  -- Fresh request (or resurrect a previously-rejected row).
  insert into public.follow_requests (requester_id, target_id, status)
    values (me, target, 'pending')
    on conflict (requester_id, target_id) do update
      set status = 'pending',
          created_at = now(),
          responded_at = null;

  return 'requested';
end;
$$;

revoke all on function public.request_follow(uuid) from public;
grant execute on function public.request_follow(uuid) to authenticated;

-- 4. RPC: approve_follow_request -------------------------------------------

create or replace function public.approve_follow_request(request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  row_requester uuid;
  row_target uuid;
  row_status text;
begin
  if me is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select requester_id, target_id, status
    into row_requester, row_target, row_status
    from public.follow_requests
    where id = request_id;

  if not found then
    raise exception 'request not found' using errcode = '42P01';
  end if;
  if row_target <> me then
    raise exception 'only the target can approve' using errcode = '42501';
  end if;
  if row_status <> 'pending' then
    -- Idempotent: an already-approved request is fine.
    return;
  end if;

  insert into public.follows (follower_id, following_id)
    values (row_requester, row_target)
    on conflict do nothing;

  update public.follow_requests
    set status = 'approved',
        responded_at = now()
    where id = request_id;
end;
$$;

revoke all on function public.approve_follow_request(uuid) from public;
grant execute on function public.approve_follow_request(uuid) to authenticated;

-- 5. RPC: reject_follow_request --------------------------------------------

create or replace function public.reject_follow_request(request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  row_target uuid;
  row_status text;
begin
  if me is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select target_id, status
    into row_target, row_status
    from public.follow_requests
    where id = request_id;

  if not found then
    raise exception 'request not found' using errcode = '42P01';
  end if;
  if row_target <> me then
    raise exception 'only the target can reject' using errcode = '42501';
  end if;
  if row_status <> 'pending' then
    return;
  end if;

  update public.follow_requests
    set status = 'rejected',
        responded_at = now()
    where id = request_id;
end;
$$;

revoke all on function public.reject_follow_request(uuid) from public;
grant execute on function public.reject_follow_request(uuid) to authenticated;
