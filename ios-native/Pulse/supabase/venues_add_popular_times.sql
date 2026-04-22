-- Weekly busyness heatmap per venue, scraped from Google Maps via
-- scripts/backfill-popular-times.py. One row per (venue, weekday, hour).
-- weekday follows Postgres extract(dow): 0 = Sunday ... 6 = Saturday.

create table if not exists public.venue_popular_times (
    venue_id uuid not null references public.venues(id) on delete cascade,
    weekday smallint not null check (weekday between 0 and 6),
    hour smallint not null check (hour between 0 and 23),
    busyness smallint not null check (busyness between 0 and 100),
    updated_at timestamptz not null default now(),
    primary key (venue_id, weekday, hour)
);

create index if not exists venue_popular_times_venue_idx
    on public.venue_popular_times (venue_id);

-- Public read; writes only via service role / SQL editor.
alter table public.venue_popular_times enable row level security;

drop policy if exists "venue_popular_times_read" on public.venue_popular_times;
create policy "venue_popular_times_read"
    on public.venue_popular_times
    for select
    using (true);
