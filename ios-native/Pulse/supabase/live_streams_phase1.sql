create extension if not exists "pgcrypto";

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

create table if not exists public.live_streams (
  id uuid primary key default gen_random_uuid(),
  creator_id uuid not null references public.profiles (id) on delete cascade,
  venue_id uuid references public.venues (id) on delete set null,
  title text not null,
  status text not null default 'setup' check (status in ('setup', 'live', 'ended')),
  provider text not null default 'pending',
  provider_stream_id text,
  ingest_url text,
  stream_key text,
  playback_url text,
  thumbnail_url text,
  viewer_count integer not null default 0,
  requires_geo_verification boolean not null default true,
  started_at timestamptz not null default timezone('utc', now()),
  ended_at timestamptz,
  last_heartbeat_at timestamptz not null default timezone('utc', now()),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

with ranked_active_streams as (
  select
    id,
    creator_id,
    row_number() over (
      partition by creator_id
      order by started_at desc, created_at desc, id desc
    ) as recency_rank
  from public.live_streams
  where ended_at is null
)
update public.live_streams as live_streams
set
  status = 'ended',
  ended_at = timezone('utc', now()),
  last_heartbeat_at = timezone('utc', now())
from ranked_active_streams
where live_streams.id = ranked_active_streams.id
  and ranked_active_streams.recency_rank > 1;

create index if not exists live_streams_started_at_idx
on public.live_streams (started_at desc);

create index if not exists live_streams_active_started_idx
on public.live_streams (status, ended_at, started_at desc);

create index if not exists live_streams_creator_active_idx
on public.live_streams (creator_id, started_at desc)
where ended_at is null;

create index if not exists live_streams_venue_active_idx
on public.live_streams (venue_id, started_at desc)
where ended_at is null;

drop trigger if exists live_streams_set_updated_at on public.live_streams;
create trigger live_streams_set_updated_at
before update on public.live_streams
for each row
execute function public.set_updated_at();

alter table public.live_streams enable row level security;

drop policy if exists "authenticated users can see live streams" on public.live_streams;
create policy "authenticated users can see live streams"
on public.live_streams for select
to authenticated
using ((status = 'live' and ended_at is null) or creator_id = auth.uid());

drop policy if exists "creators can insert their own live streams" on public.live_streams;
create policy "creators can insert their own live streams"
on public.live_streams for insert
to authenticated
with check (creator_id = auth.uid());

drop policy if exists "creators can update their own live streams" on public.live_streams;
create policy "creators can update their own live streams"
on public.live_streams for update
to authenticated
using (creator_id = auth.uid())
with check (creator_id = auth.uid());

drop policy if exists "creators can delete their own live streams" on public.live_streams;
create policy "creators can delete their own live streams"
on public.live_streams for delete
to authenticated
using (creator_id = auth.uid());
