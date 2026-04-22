-- message_requests_phase5.sql
--
-- Introduces message requests. A thread between users who don't mutually
-- follow starts in status='pending'. Recipient must accept before it shows
-- in their main inbox. Once accepted (or once both follow each other), it
-- behaves like a normal DM thread.
--
-- Depends on:
--   * safety_phase1.sql                (is_blocked_between)
--   * push_notifications_phase4_triggers.sql (enqueue_push, display_name_for)
--   * existing message_threads, thread_participants, messages tables
--   * existing follows (follower_id, following_id)
--
-- Behaviour
-- ---------
-- - start_or_get_thread(target): returns (thread_id, status). Creates the
--   thread with the right status if it doesn't exist; otherwise returns
--   whatever's already there.
-- - accept_message_request(thread): recipient flips status to accepted.
-- - decline_message_request(thread): recipient wipes the thread entirely
--   (messages, participants, row).
-- - Inserting a mutual follow auto-accepts any pending thread between the
--   two users.
-- - Push on message: pending threads push a request notice on the FIRST
--   message only; subsequent messages in a pending thread are silent.

-- 1. Column ----------------------------------------------------------------

alter table public.message_threads
  add column if not exists status text not null default 'accepted'
    check (status in ('accepted', 'pending'));

create index if not exists message_threads_status_idx
  on public.message_threads (status)
  where status = 'pending';

-- 2. Mutual-follow helper --------------------------------------------------

create or replace function public.is_mutual_follow(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.follows
    where follower_id = a and following_id = b
  ) and exists (
    select 1 from public.follows
    where follower_id = b and following_id = a
  );
$$;

grant execute on function public.is_mutual_follow(uuid, uuid) to authenticated;

-- 3. start_or_get_thread ---------------------------------------------------

create or replace function public.start_or_get_thread(target_user_id uuid)
returns table (thread_id uuid, status text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_thread uuid;
  v_status text;
  v_mutual boolean;
begin
  if v_me is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if target_user_id is null or v_me = target_user_id then
    raise exception 'invalid target' using errcode = '22023';
  end if;
  if public.is_blocked_between(v_me, target_user_id) then
    raise exception 'blocked' using errcode = '42501';
  end if;

  -- Existing 1:1 thread?
  select tp1.thread_id into v_thread
    from public.thread_participants tp1
    join public.thread_participants tp2 on tp2.thread_id = tp1.thread_id
    where tp1.user_id = v_me and tp2.user_id = target_user_id
    limit 1;

  if v_thread is not null then
    select mt.status into v_status
      from public.message_threads mt
      where mt.id = v_thread;
    thread_id := v_thread;
    status := v_status;
    return next;
    return;
  end if;

  -- New thread. Status depends on mutual-follow at creation time.
  v_mutual := public.is_mutual_follow(v_me, target_user_id);
  v_status := case when v_mutual then 'accepted' else 'pending' end;

  insert into public.message_threads (created_by, status)
    values (v_me, v_status)
    returning id into v_thread;

  insert into public.thread_participants (thread_id, user_id)
    values (v_thread, v_me), (v_thread, target_user_id);

  thread_id := v_thread;
  status := v_status;
  return next;
end;
$$;

revoke all on function public.start_or_get_thread(uuid) from public;
grant execute on function public.start_or_get_thread(uuid) to authenticated;

-- 4. accept_message_request ------------------------------------------------

create or replace function public.accept_message_request(p_thread_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_status text;
  v_created_by uuid;
  v_is_participant boolean;
begin
  if v_me is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select mt.status, mt.created_by
    into v_status, v_created_by
    from public.message_threads mt
    where mt.id = p_thread_id;
  if not found then
    raise exception 'thread not found' using errcode = '42P01';
  end if;

  if v_created_by = v_me then
    raise exception 'only the recipient can accept' using errcode = '42501';
  end if;

  select exists (
    select 1 from public.thread_participants tp
    where tp.thread_id = p_thread_id and tp.user_id = v_me
  ) into v_is_participant;
  if not v_is_participant then
    raise exception 'not a participant' using errcode = '42501';
  end if;

  -- Idempotent.
  if v_status <> 'pending' then
    return;
  end if;

  update public.message_threads
    set status = 'accepted'
    where id = p_thread_id;
end;
$$;

revoke all on function public.accept_message_request(uuid) from public;
grant execute on function public.accept_message_request(uuid) to authenticated;

-- 5. decline_message_request -----------------------------------------------
-- Wipes the thread. Silent — the requester gets no notification.

create or replace function public.decline_message_request(p_thread_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_status text;
  v_created_by uuid;
  v_is_participant boolean;
begin
  if v_me is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select mt.status, mt.created_by
    into v_status, v_created_by
    from public.message_threads mt
    where mt.id = p_thread_id;
  if not found then
    raise exception 'thread not found' using errcode = '42P01';
  end if;

  if v_created_by = v_me then
    raise exception 'only the recipient can decline' using errcode = '42501';
  end if;

  select exists (
    select 1 from public.thread_participants tp
    where tp.thread_id = p_thread_id and tp.user_id = v_me
  ) into v_is_participant;
  if not v_is_participant then
    raise exception 'not a participant' using errcode = '42501';
  end if;

  if v_status <> 'pending' then
    raise exception 'only pending threads can be declined' using errcode = '42501';
  end if;

  delete from public.messages where thread_id = p_thread_id;
  delete from public.thread_participants where thread_id = p_thread_id;
  delete from public.message_threads where id = p_thread_id;
end;
$$;

revoke all on function public.decline_message_request(uuid) from public;
grant execute on function public.decline_message_request(uuid) to authenticated;

-- 6. Auto-accept on mutual follow ------------------------------------------
-- When a new follow completes mutual-follow between two users, upgrade any
-- pending thread between them to accepted.

create or replace function public.tg_follow_upgrade_pending_threads()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Does the other side already follow us back? If not, nothing to do.
  if not exists (
    select 1 from public.follows
    where follower_id = new.following_id
      and following_id = new.follower_id
  ) then
    return new;
  end if;

  update public.message_threads mt
    set status = 'accepted'
    where mt.status = 'pending'
      and mt.id in (
        select tp1.thread_id
          from public.thread_participants tp1
          join public.thread_participants tp2
            on tp2.thread_id = tp1.thread_id
          where tp1.user_id = new.follower_id
            and tp2.user_id = new.following_id
      );

  return new;
end;
$$;

drop trigger if exists follow_upgrade_pending_threads on public.follows;
create trigger follow_upgrade_pending_threads
  after insert on public.follows
  for each row execute function public.tg_follow_upgrade_pending_threads();

-- 7. Updated push trigger for messages -------------------------------------
-- Replaces the version from push_notifications_phase4_triggers.sql.
--
-- - Accepted thread: normal DM push.
-- - Pending thread, first message from this sender: "message request" push.
-- - Pending thread, subsequent messages: silent.

create or replace function public.tg_push_on_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_recipient uuid;
  v_status text;
  v_prior_count int;
  v_actor_name text;
  v_title text;
  v_body text;
begin
  select user_id into v_recipient
    from public.thread_participants
    where thread_id = new.thread_id
      and user_id <> new.sender_id
    limit 1;

  if v_recipient is null then
    return new;
  end if;
  if public.is_blocked_between(v_recipient, new.sender_id) then
    return new;
  end if;

  select status into v_status
    from public.message_threads
    where id = new.thread_id;

  if v_status = 'pending' then
    select count(*) into v_prior_count
      from public.messages
      where thread_id = new.thread_id
        and sender_id = new.sender_id
        and id <> new.id;
    if v_prior_count > 0 then
      return new;
    end if;
    v_actor_name := public.display_name_for(new.sender_id);
    v_title := 'Message request';
    v_body := v_actor_name || ' wants to message you.';
  else
    v_actor_name := public.display_name_for(new.sender_id);
    v_title := v_actor_name;
    v_body := substr(new.body, 1, 160);
  end if;

  perform public.enqueue_push(
    v_recipient,
    'direct_messages',
    v_title,
    v_body,
    jsonb_build_object(
      'thread_id', new.thread_id,
      'message_id', new.id,
      'actor_id', new.sender_id
    )
  );
  return new;
end;
$$;

-- Re-bind the trigger (create trigger is idempotent via drop).
drop trigger if exists push_on_message on public.messages;
create trigger push_on_message
  after insert on public.messages
  for each row execute function public.tg_push_on_message();
