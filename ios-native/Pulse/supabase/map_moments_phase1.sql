-- map_moments_phase1.sql
--
-- Adds Snapchat-style map moments. Posts keep living on profiles forever,
-- but only posts with coordinates from the last 24 hours are returned here.

alter table public.videos
  add column if not exists latitude double precision,
  add column if not exists longitude double precision,
  add column if not exists map_visibility text not null default 'public'
    check (map_visibility in ('public', 'mutuals', 'hidden'));

create index if not exists videos_map_moments_recent_idx
  on public.videos (created_at desc)
  where latitude is not null
    and longitude is not null
    and map_visibility <> 'hidden'
    and is_archived = false;

create index if not exists videos_map_moments_creator_idx
  on public.videos (creator_id, created_at desc)
  where latitude is not null
    and longitude is not null;

create or replace function public.is_mutual_follow(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.follows
    where follower_id = a and following_id = b
  ) and exists (
    select 1
    from public.follows
    where follower_id = b and following_id = a
  );
$$;

grant execute on function public.is_mutual_follow(uuid, uuid) to authenticated;

create or replace function public.list_map_moments(p_limit integer default 120)
returns table (
  id uuid,
  title text,
  caption text,
  category text,
  playback_url text,
  thumbnail_url text,
  created_at timestamptz,
  creator_id uuid,
  creator_username text,
  creator_display_name text,
  creator_avatar_url text,
  latitude double precision,
  longitude double precision,
  map_visibility text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    v.id,
    v.title,
    v.caption,
    v.category,
    v.playback_url,
    v.thumbnail_url,
    v.created_at,
    v.creator_id,
    p.username as creator_username,
    p.display_name as creator_display_name,
    p.avatar_url as creator_avatar_url,
    v.latitude,
    v.longitude,
    v.map_visibility
  from public.videos v
  join public.profiles p on p.id = v.creator_id
  where auth.uid() is not null
    and v.visibility = 'public'
    and v.is_archived = false
    and v.latitude is not null
    and v.longitude is not null
    and v.map_visibility <> 'hidden'
    and v.created_at >= timezone('utc', now()) - interval '24 hours'
    and (
      v.map_visibility = 'public'
      or v.creator_id = auth.uid()
      or (
        v.map_visibility = 'mutuals'
        and public.is_mutual_follow(auth.uid(), v.creator_id)
      )
    )
  order by v.created_at desc
  limit least(greatest(coalesce(p_limit, 120), 1), 200);
$$;

revoke all on function public.list_map_moments(integer) from public;
grant execute on function public.list_map_moments(integer) to authenticated;
