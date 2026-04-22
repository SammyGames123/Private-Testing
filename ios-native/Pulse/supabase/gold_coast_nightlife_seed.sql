-- Gold Coast nightlife starter seed for Spilltop.
-- This version avoids data-modifying CTEs and conflict handling so it is easy
-- to reason about in the Supabase SQL editor.

create table if not exists public.nightlife_precincts (
    id text primary key,
    name text not null,
    description text not null,
    priority integer not null
);

alter table public.venues
    add column if not exists slug text,
    add column if not exists precinct_id text,
    add column if not exists address text,
    add column if not exists price_level integer,
    add column if not exists nightlife_score integer,
    add column if not exists featured boolean not null default false,
    add column if not exists google_place_id text,
    add column if not exists google_place_name text,
    add column if not exists google_last_synced_at timestamp with time zone;

insert into public.nightlife_precincts (id, name, description, priority)
values
    ('surfers-paradise', 'Surfers Paradise', 'Main party hub with clubs, bars, rooftops and tourist nightlife.', 1),
    ('broadbeach', 'Broadbeach', 'More upscale nightlife with casino, cocktails and lounges.', 2),
    ('burleigh-heads', 'Burleigh Heads', 'Trendy coastal nightlife with social bars and rooftops.', 3),
    ('miami', 'Miami', 'Creative nightlife, live music and event-driven venues.', 4)
on conflict (id) do update set
    name = excluded.name,
    description = excluded.description,
    priority = excluded.priority;

delete from public.venues
where slug in (
    'the-avenue-surfers',
    'bedroom-lounge-bar',
    'havana-rnb',
    'elsewhere',
    'cali-beach-club',
    'the-island-rooftop',
    'skypoint-bistro-bar',
    'nineteen-at-the-star',
    'atrium-bar',
    'burleigh-pavilion',
    'justin-lane',
    'miami-marketta'
);

insert into public.venues (
    slug,
    name,
    area,
    city,
    category,
    vibe_blurb,
    launch_priority,
    is_active,
    precinct_id,
    address,
    price_level,
    nightlife_score,
    featured
)
values
    ('the-avenue-surfers', 'The Avenue', 'Surfers Paradise', 'Gold Coast', 'bar_club', 'Live music, party energy, and late-night traffic.', 460, true, 'surfers-paradise', '3-15 Orchid Avenue, Surfers Paradise QLD 4217', 2, 9, true),
    ('bedroom-lounge-bar', 'Bedroom Lounge Bar', 'Surfers Paradise', 'Gold Coast', 'nightclub', 'VIP dance floor with late-night RnB and EDM.', 460, true, 'surfers-paradise', '26 Orchid Ave, Surfers Paradise QLD 4217', 3, 9, true),
    ('havana-rnb', 'Havana RnB Nightclub', 'Surfers Paradise', 'Gold Coast', 'nightclub', 'Late-night RnB and hip hop focus.', 450, true, 'surfers-paradise', '26 Orchid Ave, Surfers Paradise QLD 4217', 3, 8, true),
    ('elsewhere', 'Elsewhere', 'Surfers Paradise', 'Gold Coast', 'club_bar', 'Indie DJs, local scene energy, and a late-night crowd.', 450, true, 'surfers-paradise', '1/23 Cavill Ave, Surfers Paradise QLD 4217', 2, 8, true),
    ('cali-beach-club', 'Cali Beach Club', 'Surfers Paradise', 'Gold Coast', 'beach_club', 'Day party pool club with upscale events.', 450, true, 'surfers-paradise', '21a Elkhorn Ave, Surfers Paradise QLD 4217', 3, 8, true),
    ('the-island-rooftop', 'The Island Rooftop', 'Surfers Paradise', 'Gold Coast', 'rooftop_bar', 'Rooftop cocktails with DJs and social energy.', 450, true, 'surfers-paradise', '3128 Surfers Paradise Blvd, Surfers Paradise QLD 4217', 3, 8, true),
    ('skypoint-bistro-bar', 'SkyPoint Bistro + Bar', 'Surfers Paradise', 'Gold Coast', 'bar', 'Big views, cocktails, and tourist-friendly nightlife.', 420, true, 'surfers-paradise', 'Level 77, Q1 Building, Corner of Clifford St & Surfers Paradise Blvd, Surfers Paradise QLD 4217', 3, 7, false),
    ('nineteen-at-the-star', 'Nineteen at The Star', 'Broadbeach', 'Gold Coast', 'rooftop_bar', 'Luxury rooftop cocktails and upscale nights out.', 350, true, 'broadbeach', 'Level 19, The Darling, 1 Casino Drive, Broadbeach QLD 4218', 4, 8, true),
    ('atrium-bar', 'Atrium Bar', 'Broadbeach', 'Gold Coast', 'bar', 'Casino bar with cocktails, live music, and social traffic.', 320, true, 'broadbeach', 'Casino Level, The Star Gold Coast, Broadbeach Island, Broadbeach QLD 4218', 3, 7, false),
    ('burleigh-pavilion', 'Burleigh Pavilion', 'Burleigh Heads', 'Gold Coast', 'bar', 'Beachfront sessions with strong social energy.', 250, true, 'burleigh-heads', '3a/43 Goodwin Terrace, Burleigh Heads QLD 4220', 3, 8, true),
    ('justin-lane', 'Justin Lane', 'Burleigh Heads', 'Gold Coast', 'rooftop_bar', 'Rooftop cocktails, dining, and social nights.', 240, true, 'burleigh-heads', '1708-1710 Gold Coast Highway, Burleigh Heads QLD 4220', 3, 7, true),
    ('miami-marketta', 'Miami Marketta', 'Miami', 'Gold Coast', 'live_music', 'Live music, food, and event-driven nightlife.', 140, true, 'miami', '23 Hillcrest Parade, Miami QLD 4220', 2, 7, true)
returning slug, name, area;
