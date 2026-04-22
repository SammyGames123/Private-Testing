-- Add persistent coordinates to venues so the map uses real lat/long
-- instead of geocoding the address at runtime.

alter table public.venues
    add column if not exists latitude double precision,
    add column if not exists longitude double precision;

create index if not exists venues_latlong_idx
    on public.venues (latitude, longitude)
    where latitude is not null and longitude is not null;
