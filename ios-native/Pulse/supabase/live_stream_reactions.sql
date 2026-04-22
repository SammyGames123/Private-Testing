-- Persistence layer for live-stream heart reactions. Reactions already
-- broadcast visually over LiveKit (see live room reaction handling);
-- this table records them so they can power leaderboard points.
--
-- One row per (stream, sender) pair — a single viewer can tap 100 hearts
-- and it's still one row with total_hearts = 100. Points are awarded on
-- unique reacting viewers, not on total hearts, to prevent spam farming.

create table if not exists public.live_stream_reactions (
  stream_id uuid not null references public.live_streams (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  first_sent_at timestamptz not null default timezone('utc', now()),
  last_sent_at timestamptz not null default timezone('utc', now()),
  total_hearts integer not null default 1,
  primary key (stream_id, sender_id)
);

create index if not exists live_stream_reactions_sender_time_idx
  on public.live_stream_reactions (sender_id, last_sent_at desc);

create index if not exists live_stream_reactions_stream_idx
  on public.live_stream_reactions (stream_id);

-- Row level security: anyone authenticated can read; you can only insert
-- reactions as yourself.

alter table public.live_stream_reactions enable row level security;

drop policy if exists "live_reactions_read_all" on public.live_stream_reactions;
create policy "live_reactions_read_all"
  on public.live_stream_reactions for select
  to authenticated, anon
  using (true);

drop policy if exists "live_reactions_insert_self" on public.live_stream_reactions;
create policy "live_reactions_insert_self"
  on public.live_stream_reactions for insert
  to authenticated
  with check (sender_id = auth.uid());

drop policy if exists "live_reactions_update_self" on public.live_stream_reactions;
create policy "live_reactions_update_self"
  on public.live_stream_reactions for update
  to authenticated
  using (sender_id = auth.uid())
  with check (sender_id = auth.uid());

-- RPC: client calls this once per tap. Upserts the row, bumps hearts,
-- stamps last_sent_at. Security-definer so the increment is atomic and
-- RLS doesn't trip on the update half of the upsert.

drop function if exists public.send_live_reaction(uuid);

create function public.send_live_reaction(p_stream_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sender uuid := auth.uid();
begin
  if v_sender is null then
    raise exception 'not authenticated';
  end if;

  insert into public.live_stream_reactions (stream_id, sender_id, total_hearts)
  values (p_stream_id, v_sender, 1)
  on conflict (stream_id, sender_id) do update
    set total_hearts = public.live_stream_reactions.total_hearts + 1,
        last_sent_at = timezone('utc', now());
end;
$$;

grant execute on function public.send_live_reaction(uuid) to authenticated;

-- Rebuild the leaderboard function with a reaction-based points CTE.
-- Points: 3 per unique reacting viewer per stream, received within window.
-- Self-reactions (owner hearting own stream) excluded.

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
  comments_received bigint,
  reactions_received bigint
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
  reaction_stats as (
    -- Count distinct reacting viewers per creator in window. Last-sent
    -- timestamp anchors the window so reactions on an older stream don't
    -- count if the viewer stopped engaging.
    select l.creator_id as uid, count(distinct r.sender_id)::bigint as n
    from public.live_stream_reactions r
    join public.live_streams l on l.id = r.stream_id
    where r.last_sent_at >= (select since from params)
      and r.sender_id <> l.creator_id
    group by l.creator_id
  ),
  combined as (
    select uid from post_stats
    union select uid from checkin_stats
    union select uid from likes_stats
    union select uid from comment_stats
    union select uid from reaction_stats
  ),
  scored as (
    select
      c.uid as user_id,
      coalesce(ps.n, 0) as post_count,
      coalesce(cs.n, 0) as checkin_count,
      coalesce(lks.n, 0) as likes_received,
      coalesce(cmt.n, 0) as comments_received,
      coalesce(rxn.n, 0) as reactions_received,
      (
        25 * coalesce(ps.n, 0)
        + 10 * coalesce(cs.n, 0)
        +  2 * coalesce(lks.n, 0)
        +  5 * coalesce(cmt.n, 0)
        +  3 * coalesce(rxn.n, 0)
      ) as points
    from combined c
    left join post_stats    ps  on ps.uid  = c.uid
    left join checkin_stats cs  on cs.uid  = c.uid
    left join likes_stats   lks on lks.uid = c.uid
    left join comment_stats cmt on cmt.uid = c.uid
    left join reaction_stats rxn on rxn.uid = c.uid
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
    s.comments_received,
    s.reactions_received
  from scored s
  join public.profiles p on p.id = s.user_id
  where s.points > 0
  order by s.points desc, p.username asc nulls last
  limit greatest(limit_n, 1);
$$;

grant execute on function public.get_leaderboard(integer, integer) to anon, authenticated;
