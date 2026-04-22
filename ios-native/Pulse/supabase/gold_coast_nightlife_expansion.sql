-- Gold Coast nightlife venue expansion (2026-04-18)
-- Source: gold_coast_nightlife_claude_ready.json (142 venues)
-- Skips any venue whose slug already exists in the venues table.

alter table public.venues
    add column if not exists google_place_id text,
    add column if not exists google_place_name text,
    add column if not exists google_last_synced_at timestamp with time zone;

-- Expand precincts to cover new suburbs
insert into public.nightlife_precincts (id, name, description, priority)
values
    ('coolangatta', 'Coolangatta', 'Border surf town with relaxed nightlife and ocean views.', 5),
    ('southport', 'Southport', 'Local CBD with a growing bar scene and pub culture.', 6),
    ('mermaid-beach', 'Mermaid Beach', 'Coastal strip of casual bars, beach clubs, and rooftops.', 7),
    ('main-beach', 'Main Beach', 'Upscale marina precinct with waterfront bars and dining.', 8),
    ('palm-beach', 'Palm Beach', 'Southern surf town with laid-back bars and beach culture.', 9)
on conflict (id) do update set
    name = excluded.name,
    description = excluded.description,
    priority = excluded.priority;

-- Insert all 142 venues, skipping slugs that already exist
insert into public.venues (
    slug, name, area, city, category,
    is_active, address, nightlife_score,
    launch_priority, precinct_id, price_level, featured
)
select
    v.slug, v.name, v.area, v.city, v.category,
    true, v.address, v.nightlife_score,
    v.nightlife_score, v.precinct_id, v.price_level, v.featured
from (values
    -- Ashmore
    ('ashmore-tavern', 'Ashmore Tavern', 'Ashmore', 'Gold Coast', 'pub', 'Ashmore QLD 4214', 68, null::text, 1, false),
    ('madocke-beer-brewing-company', 'Madocke Beer Brewing Company', 'Ashmore', 'Gold Coast', 'brewery_distillery', 'Ashmore QLD 4214', 58, null, 2, false),

    -- Benowa
    ('double-barrel-kitchen-and-bar', 'Double Barrel Kitchen and Bar', 'Benowa', 'Gold Coast', 'bar', 'Benowa QLD 4217', 75, null, 2, false),
    ('benowa-tavern', 'Benowa Tavern', 'Benowa', 'Gold Coast', 'pub', 'Benowa QLD 4217', 68, null, 1, false),

    -- Biggera Waters
    ('dublin-docks-tavern', 'Dublin Docks Tavern', 'Biggera Waters', 'Gold Coast', 'pub', 'Biggera Waters QLD 4216', 68, null, 1, false),
    ('crafty-s', 'Crafty''s', 'Biggera Waters', 'Gold Coast', 'restaurant_bar', 'Biggera Waters QLD 4216', 62, null, 2, false),

    -- Broadbeach
    ('dracula-s', 'Dracula''s', 'Broadbeach', 'Gold Coast', 'entertainment', 'Broadbeach QLD 4218', 91, 'broadbeach', 2, true),
    ('pink-flamingo-spiegelclub', 'Pink Flamingo Spiegelclub', 'Broadbeach', 'Gold Coast', 'entertainment', 'Broadbeach QLD 4218', 91, 'broadbeach', 2, true),
    ('atrium-bar', 'Atrium Bar', 'Broadbeach', 'Gold Coast', 'bar', 'The Star Gold Coast, Broadbeach QLD 4218', 75, 'broadbeach', 2, false),
    ('den-devine-restaurant-music-lounge', 'Den Devine Restaurant & Music Lounge', 'Broadbeach', 'Gold Coast', 'bar', 'Broadbeach QLD 4218', 75, 'broadbeach', 2, false),
    ('fat-freddy-s-beach-bar-and-diner', 'Fat Freddy''s Beach Bar And Diner', 'Broadbeach', 'Gold Coast', 'bar', 'Broadbeach QLD 4218', 75, 'broadbeach', 2, false),
    ('garden-kitchen-bar', 'Garden Kitchen & Bar', 'Broadbeach', 'Gold Coast', 'bar', 'The Star, Broadbeach QLD 4218', 75, 'broadbeach', 2, false),
    ('roosevelt-lounge', 'Roosevelt Lounge', 'Broadbeach', 'Gold Coast', 'bar', 'Broadbeach QLD 4218', 75, 'broadbeach', 2, false),
    ('soho-bar', 'Soho Bar', 'Broadbeach', 'Gold Coast', 'bar', 'Broadbeach QLD 4218', 75, 'broadbeach', 2, false),
    ('the-vault-bar-tapas', 'The Vault Bar & Tapas', 'Broadbeach', 'Gold Coast', 'bar', 'Broadbeach QLD 4218', 75, 'broadbeach', 2, false),
    ('cherry', 'Cherry', 'Broadbeach', 'Gold Coast', 'restaurant_bar', 'Broadbeach QLD 4218', 62, 'broadbeach', 2, false),
    ('miss-moneypenny-s', 'Miss Moneypenny''s', 'Broadbeach', 'Gold Coast', 'restaurant_bar', 'Broadbeach QLD 4218', 62, 'broadbeach', 2, false),
    ('nineteen-at-the-star', 'Nineteen at The Star', 'Broadbeach', 'Gold Coast', 'restaurant_bar', 'The Star, Broadbeach QLD 4218', 62, 'broadbeach', 3, false),
    ('the-loose-moose', 'The Loose Moose', 'Broadbeach', 'Gold Coast', 'restaurant_bar', 'Broadbeach QLD 4218', 62, 'broadbeach', 2, false),
    ('the-lucky-squire', 'The Lucky Squire', 'Broadbeach', 'Gold Coast', 'restaurant_bar', 'Broadbeach QLD 4218', 62, 'broadbeach', 2, false),

    -- Bundall
    ('gold-coast-tavern', 'Gold Coast Tavern', 'Bundall', 'Gold Coast', 'pub', 'Bundall QLD 4217', 68, null, 1, false),

    -- Burleigh Heads
    ('justin-lane-rooftop', 'Justin Lane Rooftop', 'Burleigh Heads', 'Gold Coast', 'rooftop_bar', '1708-1710 Gold Coast Hwy, Burleigh Heads QLD 4220', 82, 'burleigh-heads', 3, false),
    ('affinity-bar-burleigh', 'Affinity Bar Burleigh', 'Burleigh Heads', 'Gold Coast', 'bar', 'Burleigh Heads QLD 4220', 75, 'burleigh-heads', 2, false),
    ('conkabar', 'ConKaBar', 'Burleigh Heads', 'Gold Coast', 'bar', 'Burleigh Heads QLD 4220', 75, 'burleigh-heads', 2, false),
    ('lockwood-bar', 'Lockwood Bar', 'Burleigh Heads', 'Gold Coast', 'bar', 'Burleigh Heads QLD 4220', 75, 'burleigh-heads', 2, false),
    ('maman-bar-kitchen', 'Maman Bar & Kitchen', 'Burleigh Heads', 'Gold Coast', 'bar', 'Burleigh Heads QLD 4220', 75, 'burleigh-heads', 2, false),
    ('paloma-wine-bar', 'Paloma Wine Bar', 'Burleigh Heads', 'Gold Coast', 'bar', '12 James St, Burleigh Heads QLD 4220', 75, 'burleigh-heads', 2, false),
    ('pink-monkey-bar-grill', 'Pink Monkey Bar & Grill', 'Burleigh Heads', 'Gold Coast', 'bar', 'Burleigh Heads QLD 4220', 75, 'burleigh-heads', 2, false),
    ('rosella-s', 'Rosella''s', 'Burleigh Heads', 'Gold Coast', 'bar', '1734 Gold Coast Hwy, Burleigh Heads QLD 4220', 75, 'burleigh-heads', 2, false),
    ('terronia-cocktail-bar', 'Terronia Cocktail Bar', 'Burleigh Heads', 'Gold Coast', 'bar', 'Burleigh Heads QLD 4220', 75, 'burleigh-heads', 2, false),
    ('apres-surf', 'Apres Surf', 'Burleigh Heads', 'Gold Coast', 'restaurant_bar', 'Burleigh Heads QLD 4220', 62, 'burleigh-heads', 2, false),
    ('burleigh-heads-hotel', 'Burleigh Heads Hotel', 'Burleigh Heads', 'Gold Coast', 'restaurant_bar', 'Burleigh Heads QLD 4220', 62, 'burleigh-heads', 2, false),
    ('burleigh-pavilion', 'Burleigh Pavilion', 'Burleigh Heads', 'Gold Coast', 'restaurant_bar', 'Burleigh Heads QLD 4220', 62, 'burleigh-heads', 2, false),
    ('club-burleigh', 'Club Burleigh', 'Burleigh Heads', 'Gold Coast', 'restaurant_bar', 'Burleigh Heads QLD 4220', 62, 'burleigh-heads', 2, false),
    ('local-burleigh', 'Local Burleigh', 'Burleigh Heads', 'Gold Coast', 'restaurant_bar', 'Burleigh Heads QLD 4220', 62, 'burleigh-heads', 2, false),
    ('margarita-cartel', 'Margarita Cartel', 'Burleigh Heads', 'Gold Coast', 'restaurant_bar', 'Burleigh Heads QLD 4220', 62, 'burleigh-heads', 2, false),
    ('masu-izakaya', 'Masu Izakaya', 'Burleigh Heads', 'Gold Coast', 'restaurant_bar', 'Burleigh Heads QLD 4220', 62, 'burleigh-heads', 2, false),
    ('na-mi', 'Naami', 'Burleigh Heads', 'Gold Coast', 'restaurant_bar', 'Burleigh Heads QLD 4220', 62, 'burleigh-heads', 2, false),
    ('the-crab-pot', 'The Crab Pot', 'Burleigh Heads', 'Gold Coast', 'restaurant_bar', 'Burleigh Heads QLD 4220', 62, 'burleigh-heads', 2, false),
    ('the-malibu-racquet-club', 'The Malibu Racquet Club', 'Burleigh Heads', 'Gold Coast', 'restaurant_bar', 'Burleigh Heads QLD 4220', 62, 'burleigh-heads', 2, false),
    ('the-tropic-burleigh', 'The Tropic - Burleigh', 'Burleigh Heads', 'Gold Coast', 'restaurant_bar', 'Burleigh Heads QLD 4220', 62, 'burleigh-heads', 2, false),
    ('ze-pickle', 'Ze Pickle', 'Burleigh Heads', 'Gold Coast', 'restaurant_bar', 'Burleigh Heads QLD 4220', 62, 'burleigh-heads', 2, false),

    -- Burleigh Waters
    ('burleigh-sports-club', 'Burleigh Sports Club', 'Burleigh Waters', 'Gold Coast', 'pub', 'Burleigh Waters QLD 4220', 68, null, 1, false),

    -- Coolangatta
    ('moxy-s-rooftop-bar', 'Moxy''s Rooftop Bar', 'Coolangatta', 'Gold Coast', 'rooftop_bar', 'Griffith St, Coolangatta QLD 4225', 82, 'coolangatta', 3, false),
    ('kirra-beach-house', 'Kirra Beach House', 'Coolangatta', 'Gold Coast', 'restaurant_bar', 'Coolangatta QLD 4225', 62, 'coolangatta', 2, false),
    ('the-coolangatta-hotel', 'The Coolangatta Hotel', 'Coolangatta', 'Gold Coast', 'restaurant_bar', 'Coolangatta QLD 4225', 62, 'coolangatta', 2, false),

    -- Helensvale
    ('helensvale-tavern', 'Helensvale Tavern', 'Helensvale', 'Gold Coast', 'pub', 'Helensvale QLD 4212', 68, null, 1, false),

    -- Hope Island
    ('destino', 'Destino', 'Hope Island', 'Gold Coast', 'restaurant_bar', 'Shop 38C Masthead Way, Sanctuary Cove, Hope Island QLD 4212', 62, null, 2, false),

    -- Main Beach
    ('la-luna-beach-club', 'La Luna Beach Club', 'Main Beach', 'Gold Coast', 'rooftop_bar', 'Main Beach QLD 4217', 82, 'main-beach', 3, false),
    ('pearls-bar', 'Pearls Bar', 'Main Beach', 'Gold Coast', 'bar', 'Main Beach QLD 4217', 75, 'main-beach', 2, false),
    ('mano-s-tedder-avenue', 'Mano''s Tedder Avenue', 'Main Beach', 'Gold Coast', 'restaurant_bar', 'Main Beach QLD 4217', 62, 'main-beach', 2, false),
    ('m-re-restaurant-by-la-luna', 'MĀRE Restaurant by La Luna', 'Main Beach', 'Gold Coast', 'restaurant_bar', 'Main Beach QLD 4217', 62, 'main-beach', 2, false),

    -- Mermaid Beach
    ('sue-o-rooftop', 'Sueño Rooftop', 'Mermaid Beach', 'Gold Coast', 'rooftop_bar', 'Mermaid Beach QLD 4218', 82, 'mermaid-beach', 3, false),
    ('mexicali-bar-y-taqueria-nobby-beach', 'MexiCali Bar Y Taqueria - Nobby Beach', 'Mermaid Beach', 'Gold Coast', 'bar', 'Level 1/2223 Gold Coast Hwy, Mermaid Beach QLD 4218', 79, 'mermaid-beach', 2, false),
    ('bine-bar-dining', 'Bine Bar & Dining', 'Mermaid Beach', 'Gold Coast', 'bar', 'Mermaid Beach QLD 4218', 75, 'mermaid-beach', 2, false),
    ('bon-bon-bar', 'Bon Bon Bar', 'Mermaid Beach', 'Gold Coast', 'bar', 'Mermaid Beach QLD 4218', 75, 'mermaid-beach', 2, false),
    ('lars-bar-grill', 'Lars Bar & Grill', 'Mermaid Beach', 'Gold Coast', 'bar', 'Mermaid Beach QLD 4218', 75, 'mermaid-beach', 2, false),
    ('the-cambus-wallace', 'The Cambus Wallace', 'Mermaid Beach', 'Gold Coast', 'bar', 'Mermaid Beach QLD 4218', 75, 'mermaid-beach', 2, false),
    ('mermaid-beach-tavern', 'Mermaid Beach Tavern', 'Mermaid Beach', 'Gold Coast', 'pub', 'Mermaid Beach QLD 4218', 68, 'mermaid-beach', 1, false),
    ('juju-mermaid-beach', 'Juju Mermaid Beach', 'Mermaid Beach', 'Gold Coast', 'restaurant_bar', 'Mermaid Beach QLD 4218', 62, 'mermaid-beach', 2, false),
    ('loki', 'Loki', 'Mermaid Beach', 'Gold Coast', 'restaurant_bar', 'Nobby Beach, Mermaid Beach QLD 4218', 62, 'mermaid-beach', 2, false),
    ('lupo', 'Lupo', 'Mermaid Beach', 'Gold Coast', 'restaurant_bar', 'Mermaid Beach QLD 4218', 62, 'mermaid-beach', 2, false),
    ('moustache', 'Moustache', 'Mermaid Beach', 'Gold Coast', 'restaurant_bar', 'Mermaid Beach QLD 4218', 62, 'mermaid-beach', 2, false),
    ('nightcap', 'Nightcap', 'Mermaid Beach', 'Gold Coast', 'restaurant_bar', 'Nobby Beach, Mermaid Beach QLD 4218', 62, 'mermaid-beach', 2, false),
    ('nobby-s-beach-surf-club', 'Nobby''s Beach Surf Club', 'Mermaid Beach', 'Gold Coast', 'restaurant_bar', 'Mermaid Beach QLD 4218', 62, 'mermaid-beach', 2, false),
    ('nobby-s-rock', 'Nobby''s Rock', 'Mermaid Beach', 'Gold Coast', 'restaurant_bar', 'Nobby Beach, Mermaid Beach QLD 4218', 62, 'mermaid-beach', 2, false),

    -- Mermaid Waters
    ('six-tricks-distilling-co', 'Six-Tricks Distilling Co.', 'Mermaid Waters', 'Gold Coast', 'brewery_distillery', 'Mermaid Waters QLD 4218', 58, null, 2, false),

    -- Miami
    ('the-arc-at-nobby-s', 'The Arc at Nobby''s', 'Miami', 'Gold Coast', 'restaurant_bar', 'Miami QLD 4220', 62, 'miami', 2, false),

    -- Mudgeeraba
    ('whisky-lounge', 'Whisky Lounge', 'Mudgeeraba', 'Gold Coast', 'bar', 'Mudgeeraba QLD 4213', 75, null, 2, false),
    ('whiskey-59', 'Whiskey@59', 'Mudgeeraba', 'Gold Coast', 'restaurant_bar', 'Mudgeeraba QLD 4213', 62, null, 2, false),

    -- Nerang
    ('nerang-rsl-memorial-club', 'Nerang RSL & Memorial Club', 'Nerang', 'Gold Coast', 'pub', 'Nerang QLD 4211', 68, null, 1, false),

    -- Palm Beach
    ('the-collective-palm-beach', 'The Collective Palm Beach', 'Palm Beach', 'Gold Coast', 'restaurant_bar', '1128 Gold Coast Hwy, Palm Beach QLD 4221', 62, 'palm-beach', 2, false),

    -- Parkwood
    ('parkwood-tavern', 'Parkwood Tavern', 'Parkwood', 'Gold Coast', 'pub', 'Parkwood QLD 4214', 68, null, 1, false),

    -- Southport
    ('aviary-rooftop-bar', 'Aviary Rooftop Bar', 'Southport', 'Gold Coast', 'rooftop_bar', '5 Melia Ct, Southport QLD 4215', 82, 'southport', 3, false),
    ('mr-p-p-s-deli-rooftop', 'Mr P.P.''s Deli & Rooftop', 'Southport', 'Gold Coast', 'rooftop_bar', '43 Nerang St, Southport QLD 4215', 82, 'southport', 3, false),
    ('bar-11', 'Bar 11', 'Southport', 'Gold Coast', 'bar', 'Southport QLD 4215', 75, 'southport', 2, false),
    ('carafe-wine', 'Carafe Wine', 'Southport', 'Gold Coast', 'bar', 'Southport QLD 4215', 75, 'southport', 2, false),
    ('percy-s-bar', 'Percy''s Bar', 'Southport', 'Gold Coast', 'bar', 'Southport QLD 4215', 75, 'southport', 2, false),
    ('the-vintage-bar-co', 'The Vintage Bar Co', 'Southport', 'Gold Coast', 'bar', '28-30 Smith Street, Southport QLD 4215', 75, 'southport', 2, false),
    ('vinnies-dive-bar', 'VINNIES DIVE BAR', 'Southport', 'Gold Coast', 'bar', 'Southport QLD 4215', 75, 'southport', 2, false),
    ('e-star-karaoke', 'E Star Karaoke', 'Southport', 'Gold Coast', 'karaoke', 'Southport QLD 4215', 72, 'southport', 2, false),
    ('ferry-road-tavern', 'Ferry Road Tavern', 'Southport', 'Gold Coast', 'pub', 'Southport QLD 4215', 68, 'southport', 1, false),
    ('rsl-southport', 'RSL Southport', 'Southport', 'Gold Coast', 'pub', 'Southport QLD 4215', 68, 'southport', 1, false),
    ('southport-sharks-afl-club', 'Southport Sharks AFL Club', 'Southport', 'Gold Coast', 'pub', 'Southport QLD 4215', 68, 'southport', 1, false),
    ('ground-n-sound', 'Ground N Sound', 'Southport', 'Gold Coast', 'restaurant_bar', 'Southport QLD 4215', 62, 'southport', 2, false),
    ('last-night-on-earth', 'Last Night on Earth', 'Southport', 'Gold Coast', 'restaurant_bar', '50B Nerang St, Southport QLD 4215', 62, 'southport', 2, false),
    ('sopo', 'SOPO', 'Southport', 'Gold Coast', 'restaurant_bar', 'Southport QLD 4215', 62, 'southport', 2, false),
    ('walk-ins-welcome', 'Walk-ins Welcome', 'Southport', 'Gold Coast', 'restaurant_bar', 'Southport QLD 4215', 62, 'southport', 2, false),
    ('sopo-brewing-co', 'SOPO Brewing Co.', 'Southport', 'Gold Coast', 'brewery_distillery', 'Southport QLD 4215', 58, 'southport', 2, false),

    -- Surfers Paradise — Nightclubs
    ('cocktails-nightclub', 'Cocktails Nightclub', 'Surfers Paradise', 'Gold Coast', 'nightclub', 'Surfers Paradise QLD 4217', 100, 'surfers-paradise', 3, true),
    ('desire-nightclub', 'Desire Nightclub', 'Surfers Paradise', 'Gold Coast', 'nightclub', 'Surfers Paradise QLD 4217', 100, 'surfers-paradise', 3, true),
    ('empire-r-b-nightclub', 'Empire R&B Nightclub', 'Surfers Paradise', 'Gold Coast', 'nightclub', 'Surfers Paradise QLD 4217', 100, 'surfers-paradise', 3, true),
    ('fabric-nightclub', 'Fabric Nightclub', 'Surfers Paradise', 'Gold Coast', 'nightclub', 'Surfers Paradise QLD 4217', 100, 'surfers-paradise', 3, true),
    ('havana-rnb-nightclub', 'Havana RnB Nightclub', 'Surfers Paradise', 'Gold Coast', 'nightclub', 'Surfers Paradise QLD 4217', 100, 'surfers-paradise', 3, true),
    ('mambo-gold-coast', 'Mambo Gold Coast', 'Surfers Paradise', 'Gold Coast', 'nightclub', 'Surfers Paradise QLD 4217', 100, 'surfers-paradise', 3, true),
    ('retro-s', 'Retro''s', 'Surfers Paradise', 'Gold Coast', 'nightclub', 'Surfers Paradise QLD 4217', 100, 'surfers-paradise', 3, true),
    ('retro-s-surfers-paradise', 'Retro''s Surfers Paradise', 'Surfers Paradise', 'Gold Coast', 'nightclub', 'Surfers Paradise QLD 4217', 100, 'surfers-paradise', 3, true),
    ('su-casa-gold-coast', 'Su Casa Gold Coast', 'Surfers Paradise', 'Gold Coast', 'nightclub', 'Surfers Paradise QLD 4217', 100, 'surfers-paradise', 3, true),
    ('tempo-nightclub', 'Tempo Nightclub', 'Surfers Paradise', 'Gold Coast', 'nightclub', 'Surfers Paradise QLD 4217', 100, 'surfers-paradise', 3, true),

    -- Surfers Paradise — Entertainment
    ('hollywood-showgirls', 'Hollywood Showgirls', 'Surfers Paradise', 'Gold Coast', 'entertainment', 'Surfers Paradise QLD 4217', 93, 'surfers-paradise', 2, true),

    -- Surfers Paradise — Rooftop bars
    ('lulu-rooftop-bar', 'Lulu Rooftop & Bar', 'Surfers Paradise', 'Gold Coast', 'rooftop_bar', 'Surfers Paradise QLD 4217', 87, 'surfers-paradise', 3, false),
    ('the-island-rooftop', 'The Island Rooftop', 'Surfers Paradise', 'Gold Coast', 'rooftop_bar', '3128 Surfers Paradise Blvd, Surfers Paradise QLD 4217', 87, 'surfers-paradise', 3, false),

    -- Surfers Paradise — Bars
    ('casablanca-gold-coast', 'Casablanca Gold Coast', 'Surfers Paradise', 'Gold Coast', 'bar', 'Surfers Paradise QLD 4217', 84, 'surfers-paradise', 2, false),
    ('baritalia-surfers-paradise', 'Baritalia Surfers Paradise', 'Surfers Paradise', 'Gold Coast', 'bar', 'Surfers Paradise QLD 4217', 80, 'surfers-paradise', 2, false),
    ('coast', 'COAST', 'Surfers Paradise', 'Gold Coast', 'bar', 'Surfers Paradise QLD 4217', 80, 'surfers-paradise', 2, false),
    ('chapter-verse-bar-and-lounge', 'Chapter & Verse Bar and Lounge', 'Surfers Paradise', 'Gold Coast', 'bar', 'Surfers Paradise QLD 4217', 80, 'surfers-paradise', 2, false),
    ('deck-bar', 'Deck Bar', 'Surfers Paradise', 'Gold Coast', 'bar', 'Surfers Paradise QLD 4217', 80, 'surfers-paradise', 2, false),
    ('edgewater-dining-and-lounge', 'Edgewater Dining and Lounge', 'Surfers Paradise', 'Gold Coast', 'bar', 'Surfers Paradise QLD 4217', 80, 'surfers-paradise', 2, false),
    ('inca-fusion-peruvian-latin-food-gold-coast', 'Inca Fusion - Peruvian & Latin Food', 'Surfers Paradise', 'Gold Coast', 'bar', 'Surfers Paradise QLD 4217', 80, 'surfers-paradise', 2, false),
    ('ms-margot-s-bar-eats', 'Ms Margot''s Bar & Eats', 'Surfers Paradise', 'Gold Coast', 'bar', 'Surfers Paradise QLD 4217', 80, 'surfers-paradise', 2, false),
    ('sandbar-surfers-paradise', 'Sandbar Surfers Paradise', 'Surfers Paradise', 'Gold Coast', 'bar', 'Surfers Paradise QLD 4217', 80, 'surfers-paradise', 2, false),
    ('stingray-lounge', 'Stingray Lounge', 'Surfers Paradise', 'Gold Coast', 'bar', 'Surfers Paradise QLD 4217', 80, 'surfers-paradise', 2, false),
    ('the-exhibitionist-bar', 'The Exhibitionist Bar', 'Surfers Paradise', 'Gold Coast', 'bar', 'Level 5/135 Bundall Rd, Surfers Paradise QLD 4217', 80, 'surfers-paradise', 2, false),
    ('the-yankee-s-restaurant-bar-surfers-paradise', 'The Yankee''s Restaurant & Bar', 'Surfers Paradise', 'Gold Coast', 'bar', 'Surfers Paradise QLD 4217', 80, 'surfers-paradise', 2, false),
    ('white-rhino-bar-eats', 'White Rhino Bar & Eats', 'Surfers Paradise', 'Gold Coast', 'bar', 'Surfers Paradise QLD 4217', 80, 'surfers-paradise', 2, false),

    -- Surfers Paradise — Pubs
    ('chevron-tavern', 'Chevron Tavern', 'Surfers Paradise', 'Gold Coast', 'pub', 'Surfers Paradise QLD 4217', 73, 'surfers-paradise', 2, false),
    ('surfers-paradise-beergarden', 'Surfers Paradise Beergarden', 'Surfers Paradise', 'Gold Coast', 'pub', '2 Cavill Ave, Surfers Paradise QLD 4217', 73, 'surfers-paradise', 2, false),
    ('the-local-tavern', 'The Local Tavern', 'Surfers Paradise', 'Gold Coast', 'pub', 'Surfers Paradise QLD 4217', 73, 'surfers-paradise', 2, false),
    ('waxy-s-irish-pub-and-skyline-roof-top-bar', 'Waxy''s Irish Pub and Skyline Roof Top Bar', 'Surfers Paradise', 'Gold Coast', 'pub', 'Surfers Paradise QLD 4217', 73, 'surfers-paradise', 2, false),

    -- Surfers Paradise — Restaurant bars
    ('cali-beach', 'Cali Beach', 'Surfers Paradise', 'Gold Coast', 'restaurant_bar', 'Surfers Paradise QLD 4217', 71, 'surfers-paradise', 2, false),
    ('elsewhere', 'Elsewhere', 'Surfers Paradise', 'Gold Coast', 'restaurant_bar', '1/23 Cavill Ave, Surfers Paradise QLD 4217', 71, 'surfers-paradise', 2, false),
    ('the-bedroom', 'The Bedroom', 'Surfers Paradise', 'Gold Coast', 'restaurant_bar', 'Surfers Paradise QLD 4217', 71, 'surfers-paradise', 2, false),
    ('magic-men', 'Magic Men', 'Surfers Paradise', 'Gold Coast', 'restaurant_bar', 'Surfers Paradise QLD 4217', 70, 'surfers-paradise', 2, false),
    ('bmg-cowboys', 'BMG Cowboys', 'Surfers Paradise', 'Gold Coast', 'restaurant_bar', 'Surfers Paradise QLD 4217', 67, 'surfers-paradise', 2, false),
    ('club-paradise', 'Club Paradise', 'Surfers Paradise', 'Gold Coast', 'restaurant_bar', 'Surfers Paradise QLD 4217', 67, 'surfers-paradise', 2, false),
    ('d-arcy-arms', 'D''Arcy Arms', 'Surfers Paradise', 'Gold Coast', 'restaurant_bar', 'Surfers Paradise QLD 4217', 67, 'surfers-paradise', 2, false),
    ('el-camino-cantina-surfers-paradise', 'El Camino Cantina Surfers Paradise', 'Surfers Paradise', 'Gold Coast', 'restaurant_bar', 'Surfers Paradise QLD 4217', 67, 'surfers-paradise', 2, false),
    ('finn-mccool-s-surfers-paradise', 'Finn McCool''s Surfers Paradise', 'Surfers Paradise', 'Gold Coast', 'restaurant_bar', 'Surfers Paradise QLD 4217', 67, 'surfers-paradise', 2, false),
    ('hotel-jardin', 'Hotel Jardin', 'Surfers Paradise', 'Gold Coast', 'restaurant_bar', 'Surfers Paradise QLD 4217', 67, 'surfers-paradise', 2, false),
    ('house-of-brews', 'House of Brews', 'Surfers Paradise', 'Gold Coast', 'restaurant_bar', '17 Orchid Ave, Surfers Paradise QLD 4217', 67, 'surfers-paradise', 2, false),
    ('hyde-paradiso', 'Hyde Paradiso', 'Surfers Paradise', 'Gold Coast', 'restaurant_bar', 'Surfers Paradise QLD 4217', 67, 'surfers-paradise', 2, false),
    ('la-playa-beach-and-eats', 'La Playa Beach and Eats', 'Surfers Paradise', 'Gold Coast', 'restaurant_bar', 'Surfers Paradise QLD 4217', 67, 'surfers-paradise', 2, false),
    ('shooeys', 'Shooeys', 'Surfers Paradise', 'Gold Coast', 'restaurant_bar', 'Surfers Paradise QLD 4217', 67, 'surfers-paradise', 2, false),
    ('social-house', 'Social House', 'Surfers Paradise', 'Gold Coast', 'restaurant_bar', 'Surfers Paradise QLD 4217', 67, 'surfers-paradise', 2, false),
    ('steampunk-surfers-paradise', 'Steampunk Surfers Paradise', 'Surfers Paradise', 'Gold Coast', 'restaurant_bar', 'Surfers Paradise QLD 4217', 67, 'surfers-paradise', 2, false),
    ('suzi-cue-s', 'Suzi Cue''s', 'Surfers Paradise', 'Gold Coast', 'restaurant_bar', 'Surfers Paradise QLD 4217', 67, 'surfers-paradise', 2, false),
    ('the-cavill-hotel', 'The Cavill Hotel', 'Surfers Paradise', 'Gold Coast', 'restaurant_bar', 'Surfers Paradise QLD 4217', 67, 'surfers-paradise', 2, false),
    ('the-spring', 'The Spring', 'Surfers Paradise', 'Gold Coast', 'restaurant_bar', 'Surfers Paradise QLD 4217', 67, 'surfers-paradise', 2, false),
    ('woodfired-mediterranean-grill-cafe', 'Woodfired Mediterranean Grill & Cafe', 'Surfers Paradise', 'Gold Coast', 'restaurant_bar', 'Surfers Paradise QLD 4217', 67, 'surfers-paradise', 2, false),

    -- Surfers Paradise — Nightlife tours
    ('down-under-party-tours', 'Down Under Party Tours', 'Surfers Paradise', 'Gold Coast', 'nightlife_tour', 'Surfers Paradise QLD 4217', 65, 'surfers-paradise', 1, false),
    ('wicked-nightlife-tours-club-crawl', 'Wicked Nightlife Tours - Club Crawl', 'Surfers Paradise', 'Gold Coast', 'nightlife_tour', 'Surfers Paradise QLD 4217', 65, 'surfers-paradise', 1, false),

    -- Tugun
    ('caracara-cantina-and-tequila-bar', 'Caracara Cantina And Tequila Bar', 'Tugun', 'Gold Coast', 'bar', 'Tugun QLD 4224', 75, null, 2, false)

) as v(slug, name, area, city, category, address, nightlife_score, precinct_id, price_level, featured)
where not exists (
    select 1 from public.venues existing where existing.slug = v.slug
);
