-- push_notifications_phase4_triggers.sql
--
-- Wires Postgres triggers into the `send-push` Edge Function. Each
-- relevant INSERT fires `public.enqueue_push`, which POSTs a JSON body
-- to the function. The function then fans out to APNs for every device
-- the recipient has registered.
--
-- Depends on:
--   * push_notifications_phase3.sql  (device_push_tokens, notification_preferences)
--   * follow_requests_phase2.sql     (follow_requests)
--   * safety_phase1.sql              (is_blocked_between)
--   * pg_net extension               (http_post)
--
-- Before applying, set these project-level DB settings so the helper
-- knows where to POST and which secret to send:
--
--   alter database postgres set "app.settings.push_webhook_url"
--     = 'https://<PROJECT_REF>.functions.supabase.co/send-push';
--   alter database postgres set "app.settings.push_webhook_secret"
--     = '<PUSH_WEBHOOK_SECRET>';
--
-- Both values must match what you configure in the send-push function's
-- environment (see supabase/functions/send-push/README.md).

create extension if not exists pg_net;

-- 1. Helper ----------------------------------------------------------------

create or replace function public.enqueue_push(
  recipient uuid,
  category text,
  title text,
  body text,
  data jsonb default '{}'::jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  webhook_url text := current_setting('app.settings.push_webhook_url', true);
  webhook_secret text := current_setting('app.settings.push_webhook_secret', true);
begin
  if webhook_url is null or webhook_secret is null then
    -- Not configured yet; silently no-op so triggers don't break writes.
    return;
  end if;

  perform net.http_post(
    url := webhook_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'X-Webhook-Secret', webhook_secret
    ),
    body := jsonb_build_object(
      'user_id', recipient,
      'category', category,
      'title', title,
      'body', body,
      'data', data
    )
  );
exception when others then
  -- Never let a push failure block the originating write. Log and move on.
  raise warning '[enqueue_push] failed: %', sqlerrm;
end;
$$;

revoke all on function public.enqueue_push(uuid, text, text, text, jsonb) from public;

-- Helper: best-effort display-name lookup so push bodies read naturally
-- ("Sam liked your moment" instead of "Someone liked your moment").
create or replace function public.display_name_for(user_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(display_name, username, 'Someone')
    from public.profiles
    where id = user_id;
$$;

-- 2. Likes -----------------------------------------------------------------

create or replace function public.tg_push_on_like()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  creator uuid;
  actor_name text;
begin
  select creator_id into creator from public.videos where id = new.video_id;
  if creator is null or creator = new.user_id then
    return new;
  end if;
  if public.is_blocked_between(creator, new.user_id) then
    return new;
  end if;

  actor_name := public.display_name_for(new.user_id);
  perform public.enqueue_push(
    creator,
    'likes',
    'New like',
    actor_name || ' liked your moment.',
    jsonb_build_object('video_id', new.video_id, 'actor_id', new.user_id)
  );
  return new;
end;
$$;

drop trigger if exists push_on_like on public.likes;
create trigger push_on_like
  after insert on public.likes
  for each row execute function public.tg_push_on_like();

-- 3. Comments --------------------------------------------------------------

create or replace function public.tg_push_on_comment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  creator uuid;
  actor_name text;
begin
  select creator_id into creator from public.videos where id = new.video_id;
  if creator is null or creator = new.user_id then
    return new;
  end if;
  if public.is_blocked_between(creator, new.user_id) then
    return new;
  end if;

  actor_name := public.display_name_for(new.user_id);
  perform public.enqueue_push(
    creator,
    'comments',
    'New comment',
    actor_name || ': ' || substr(new.body, 1, 120),
    jsonb_build_object(
      'video_id', new.video_id,
      'comment_id', new.id,
      'actor_id', new.user_id
    )
  );
  return new;
end;
$$;

drop trigger if exists push_on_comment on public.comments;
create trigger push_on_comment
  after insert on public.comments
  for each row execute function public.tg_push_on_comment();

-- 4. Follows ---------------------------------------------------------------

create or replace function public.tg_push_on_follow()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_name text;
begin
  if new.follower_id = new.following_id then
    return new;
  end if;
  if public.is_blocked_between(new.following_id, new.follower_id) then
    return new;
  end if;

  actor_name := public.display_name_for(new.follower_id);
  perform public.enqueue_push(
    new.following_id,
    'follows',
    'New follower',
    actor_name || ' started following you.',
    jsonb_build_object('actor_id', new.follower_id)
  );
  return new;
end;
$$;

drop trigger if exists push_on_follow on public.follows;
create trigger push_on_follow
  after insert on public.follows
  for each row execute function public.tg_push_on_follow();

-- 5. Follow-request approvals ---------------------------------------------
--
-- Notify the requester when their pending follow request becomes
-- approved. (The insert-side notification above also fires when an
-- approval writes to `follows` — this gives the requester an extra
-- "accepted" signal with their own context.)

create or replace function public.tg_push_on_follow_request_approved()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_name text;
begin
  if old.status = 'approved' or new.status <> 'approved' then
    return new;
  end if;

  target_name := public.display_name_for(new.target_id);
  perform public.enqueue_push(
    new.requester_id,
    'follows',
    'Request approved',
    target_name || ' accepted your follow request.',
    jsonb_build_object('actor_id', new.target_id)
  );
  return new;
end;
$$;

drop trigger if exists push_on_follow_request_approved on public.follow_requests;
create trigger push_on_follow_request_approved
  after update on public.follow_requests
  for each row execute function public.tg_push_on_follow_request_approved();

-- 6. Direct messages -------------------------------------------------------

create or replace function public.tg_push_on_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  recipient_id uuid;
  actor_name text;
begin
  -- DM is 1:1 — pick the single other participant.
  select user_id into recipient_id
    from public.thread_participants
    where thread_id = new.thread_id and user_id <> new.sender_id
    limit 1;

  if recipient_id is null then
    return new;
  end if;
  if public.is_blocked_between(recipient_id, new.sender_id) then
    return new;
  end if;

  actor_name := public.display_name_for(new.sender_id);
  perform public.enqueue_push(
    recipient_id,
    'direct_messages',
    actor_name,
    substr(new.body, 1, 160),
    jsonb_build_object(
      'thread_id', new.thread_id,
      'message_id', new.id,
      'actor_id', new.sender_id
    )
  );
  return new;
end;
$$;

drop trigger if exists push_on_message on public.messages;
create trigger push_on_message
  after insert on public.messages
  for each row execute function public.tg_push_on_message();

-- 7. Live streams going live ----------------------------------------------
--
-- Fan out to every follower when a stream transitions to 'live'. We push
-- a single invocation per follower so each respects their own
-- notification_preferences.live_streams flag in the Edge Function.

create or replace function public.tg_push_on_live_started()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  rec record;
  host_name text;
begin
  if new.status <> 'live' then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.status = 'live' then
    return new;
  end if;

  host_name := public.display_name_for(new.creator_id);

  for rec in
    select f.follower_id as uid
      from public.follows f
      where f.following_id = new.creator_id
  loop
    if public.is_blocked_between(rec.uid, new.creator_id) then
      continue;
    end if;
    perform public.enqueue_push(
      rec.uid,
      'live_streams',
      host_name || ' is live',
      'Tap to join the live stream.',
      jsonb_build_object('live_stream_id', new.id, 'creator_id', new.creator_id)
    );
  end loop;
  return new;
end;
$$;

drop trigger if exists push_on_live_started_insert on public.live_streams;
create trigger push_on_live_started_insert
  after insert on public.live_streams
  for each row execute function public.tg_push_on_live_started();

drop trigger if exists push_on_live_started_update on public.live_streams;
create trigger push_on_live_started_update
  after update of status on public.live_streams
  for each row execute function public.tg_push_on_live_started();
