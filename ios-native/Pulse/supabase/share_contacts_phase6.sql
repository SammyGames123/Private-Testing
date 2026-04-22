-- share_contacts_phase6.sql
--
-- Returns the viewer's "shareable contacts" — anyone the viewer can DM
-- without going through the message-request flow. That's the union of:
--
--   * mutual follows (you follow them AND they follow you back), and
--   * anyone with an accepted DM thread with the viewer (either side
--     started it, both have consented to messaging).
--
-- The in-app share sheet on a feed post uses this to list recipients.
--
-- Depends on:
--   * follows (follower_id, following_id)
--   * message_threads (status = 'accepted' | 'pending')
--   * thread_participants
--   * profiles (id, username, display_name, bio, avatar_url)
--   * message_requests_phase5.sql  (introduces status on message_threads)

create or replace function public.list_shareable_contacts()
returns table (
  id uuid,
  username text,
  display_name text,
  bio text,
  avatar_url text
)
language sql
stable
security definer
set search_path = public
as $$
  with me as (
    select auth.uid() as uid
  ),
  mutual as (
    -- My followees who also follow me back.
    select f1.following_id as other_id
      from public.follows f1
      join public.follows f2
        on f2.follower_id = f1.following_id
       and f2.following_id = f1.follower_id
      cross join me
     where f1.follower_id = me.uid
  ),
  accepted_thread_partners as (
    -- The other participant of every accepted 1:1 thread I'm in.
    select tp_other.user_id as other_id
      from public.thread_participants tp_me
      join public.message_threads mt
        on mt.id = tp_me.thread_id
       and mt.status = 'accepted'
      join public.thread_participants tp_other
        on tp_other.thread_id = tp_me.thread_id
       and tp_other.user_id <> tp_me.user_id
      cross join me
     where tp_me.user_id = me.uid
  ),
  combined as (
    select other_id from mutual
    union
    select other_id from accepted_thread_partners
  )
  select p.id,
         p.username,
         p.display_name,
         p.bio,
         p.avatar_url
    from combined c
    join public.profiles p on p.id = c.other_id
    cross join me
   where not public.is_blocked_between(me.uid, c.other_id)
   order by coalesce(p.display_name, p.username) asc nulls last;
$$;

revoke all on function public.list_shareable_contacts() from public;
grant execute on function public.list_shareable_contacts() to authenticated;
