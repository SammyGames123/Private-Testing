-- Leaderboard: rolling-window point totals computed live from existing
-- action tables. No ledger, no triggers — the function aggregates on each
-- call.
--
-- Point values (mirrored in iOS/LeaderboardService.swift):
--   post a moment (video)        25
--   check in (deduped per venue
--             per 3-hour bucket) 10
--   comment received             5
--   like received                2
--
-- Live streams intentionally do NOT award points for going live. We'll add
-- engagement-based live points (viewers, chat, reactions) in a follow-up.
--
-- Anti-gaming:
--   - check-ins dedupe by (user, venue, 3-hour bucket)
--   - self-likes and self-comments excluded
--   - rows referencing deleted videos disappear via FK cascade

-- Indexes

create index if not exists videos_creator_created_idx
  on public.videos (creator_id, created_at desc);

create index if not exists check_ins_user_created_idx
  on public.check_ins (user_id, created_at desc);

create index if not exists check_ins_venue_user_created_idx
  on public.check_ins (venue_id, user_id, created_at desc);

create index if not exists comments_video_created_idx
  on public.comments (video_id, created_at desc);

create index if not exists likes_video_created_idx
  on public.likes (video_id, created_at desc);

-- Function

drop function if exists public.get_leaderboard(integer, integer);

create function public.get_leaderboard(
  window_days integer default 7,
  limit_n integer default 100
)
returns table (
  user_id uuid,
  username text,
  display_name text,
  avatar_url text,
  points bigint,
  post_count bigint,
  checkin_count bigint,
  likes_received bigint,
  comments_received bigint
)
language sql
stable
as $$
  with
  params as (
    select
      case when window_days <= 0
        then '1900-01-01'::timestamptz
        else timezone('utc', now()) - make_interval(days => window_days)
      end as since
  ),
  post_stats as (
    select creator_id as uid, count(*)::bigint as n
    from public.videos
    where created_at >= (select since from params)
    group by creator_id
  ),
  checkin_stats as (
    select uid, count(*)::bigint as n
    from (
      select distinct
        user_id as uid,
        venue_id,
        floor(extract(epoch from created_at) / 10800)::bigint as bucket
      from public.check_ins
      where created_at >= (select since from params)
        and venue_id is not null
    ) d
    group by uid
  ),
  likes_stats as (
    select v.creator_id as uid, count(*)::bigint as n
    from public.likes l
    join public.videos v on v.id = l.video_id
    where l.created_at >= (select since from params)
      and l.user_id <> v.creator_id
    group by v.creator_id
  ),
  comment_stats as (
    select v.creator_id as uid, count(*)::bigint as n
    from public.comments c
    join public.videos v on v.id = c.video_id
    where c.created_at >= (select since from params)
      and c.user_id <> v.creator_id
    group by v.creator_id
  ),
  combined as (
    select uid from post_stats
    union select uid from checkin_stats
    union select uid from likes_stats
    union select uid from comment_stats
  ),
  scored as (
    select
      c.uid as user_id,
      coalesce(ps.n, 0) as post_count,
      coalesce(cs.n, 0) as checkin_count,
      coalesce(lks.n, 0) as likes_received,
      coalesce(cmt.n, 0) as comments_received,
      (
        25 * coalesce(ps.n, 0)
        + 10 * coalesce(cs.n, 0)
        +  2 * coalesce(lks.n, 0)
        +  5 * coalesce(cmt.n, 0)
      ) as points
    from combined c
    left join post_stats    ps  on ps.uid  = c.uid
    left join checkin_stats cs  on cs.uid  = c.uid
    left join likes_stats   lks on lks.uid = c.uid
    left join comment_stats cmt on cmt.uid = c.uid
  )
  select
    s.user_id,
    p.username,
    p.display_name,
    p.avatar_url,
    s.points,
    s.post_count,
    s.checkin_count,
    s.likes_received,
    s.comments_received
  from scored s
  join public.profiles p on p.id = s.user_id
  where s.points > 0
  order by s.points desc, p.username asc nulls last
  limit greatest(limit_n, 1);
$$;

grant execute on function public.get_leaderboard(integer, integer) to anon, authenticated;
