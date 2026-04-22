-- Add canonical Google Places identity so each venue can stay linked
-- to one stable place record over time.

alter table public.venues
    add column if not exists google_place_id text,
    add column if not exists google_place_name text,
    add column if not exists google_last_synced_at timestamp with time zone;

create unique index if not exists venues_google_place_id_idx
    on public.venues (google_place_id)
    where google_place_id is not null;
