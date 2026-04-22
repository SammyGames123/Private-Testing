-- shared_posts_phase7.sql
--
-- Turns DM shares into proper references. Adds `shared_video_id` to
-- `messages` so a message can point at a feed post; the client renders
-- these as post cards instead of plain text.
--
-- When a shared-video message has no body text, the push notification
-- falls back to "Shared a post" so recipients know what they're getting.
--
-- Depends on:
--   * push_notifications_phase4_triggers.sql (enqueue_push, display_name_for)
--   * message_requests_phase5.sql            (message_threads.status)
--   * existing videos, messages tables

-- 1. Column ----------------------------------------------------------------

alter table public.messages
  add column if not exists shared_video_id uuid
    references public.videos(id) on delete set null;

create index if not exists messages_shared_video_id_idx
  on public.messages (shared_video_id)
  where shared_video_id is not null;

-- Allow body to be empty when there's a shared post attached. The
-- existing CHECK (if any) on body_non_empty gets replaced so shares
-- without a note still pass validation. Drop-if-exists stays tolerant
-- of projects that never had the constraint.

do $$
begin
  if exists (
    select 1
      from pg_constraint c
      join pg_class t on t.oid = c.conrelid
     where t.relname = 'messages'
       and c.conname = 'messages_body_not_empty'
  ) then
    alter table public.messages drop constraint messages_body_not_empty;
  end if;
end
$$;

alter table public.messages
  add constraint messages_body_or_share_present
  check (
    (body is not null and length(trim(body)) > 0)
    or shared_video_id is not null
  );

-- 2. Updated push trigger --------------------------------------------------
-- Pending-thread rules carry over from message_requests_phase5. Shared
-- posts with an empty body push as "Shared a post".

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
  v_share_fallback constant text := 'Shared a post';
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
    if new.shared_video_id is not null and (new.body is null or length(trim(new.body)) = 0) then
      v_body := v_actor_name || ' shared a post with you.';
    else
      v_body := v_actor_name || ' wants to message you.';
    end if;
  else
    v_actor_name := public.display_name_for(new.sender_id);
    v_title := v_actor_name;
    if new.shared_video_id is not null and (new.body is null or length(trim(new.body)) = 0) then
      v_body := v_share_fallback;
    else
      v_body := substr(new.body, 1, 160);
    end if;
  end if;

  perform public.enqueue_push(
    v_recipient,
    'direct_messages',
    v_title,
    v_body,
    jsonb_build_object(
      'thread_id', new.thread_id,
      'message_id', new.id,
      'actor_id', new.sender_id,
      'shared_video_id', new.shared_video_id
    )
  );
  return new;
end;
$$;

drop trigger if exists push_on_message on public.messages;
create trigger push_on_message
  after insert on public.messages
  for each row execute function public.tg_push_on_message();
