# Google Places Venue Linking

Spilltop now supports storing a stable Google Places identity for each venue instead
of treating coordinates as a one-off enrichment step.

## What gets stored

- `google_place_id`
- `google_place_name`
- `google_last_synced_at`
- `latitude`
- `longitude`
- `address` when the row does not already have one

The enrichment script uses Google Places API (New) Text Search and stores the
place `id` field as the canonical Google identifier for the venue.

## Apply the schema

Run the contents of this file in the Supabase SQL editor first:

- `supabase/venues_add_google_place_link.sql`

## Generate the Google linkage backfill

```bash
GOOGLE_PLACES_API_KEY=your_key_here \
node scripts/backfill-venue-coordinates.js \
  --input /Users/samsumsion/Downloads/gold_coast_nightlife_claude_ready.json \
  --out supabase/venues_backfill_coordinates.sql
```

Then run the generated SQL in Supabase.

## Recommended order

1. Apply `supabase/venues_add_google_place_link.sql`
2. Regenerate `supabase/venues_backfill_coordinates.sql`
3. Run the generated backfill SQL in Supabase
4. Relaunch the app
