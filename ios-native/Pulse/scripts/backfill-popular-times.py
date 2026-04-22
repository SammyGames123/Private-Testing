#!/usr/bin/env python3
"""Fetch weekly busyness forecasts from BestTime.app and emit idempotent
SQL inserts for the public.venue_popular_times table.

Usage
-----

1. Sign up at https://besttime.app, grab your PRIVATE API key (starts with
   `pri_`). The PUBLIC key (`pub_`) won't work for forecast generation.

2. Apply the schema migration once in Supabase:

       supabase/venues_add_popular_times.sql

3. Run this script:

       BESTTIME_API_KEY_PRIVATE='pri_xxx' \
       SUPABASE_SERVICE_ROLE_KEY='eyJ...' \
       python3 scripts/backfill-popular-times.py

4. Paste the generated supabase/venues_popular_times_backfill.sql into the
   Supabase SQL editor and Run.

Notes
-----

- BestTime caches forecasts ~3 months. Each new-forecast call counts as one
  query on your plan. 140 venues at pay-as-you-go ≈ USD $0.28, one-off.
- BestTime `day_info.day_int` is Monday-first 0-indexed (0=Mon..6=Sun).
  Postgres extract(dow) is 0=Sun..6=Sat — we remap with (day_int + 1) % 7.
- `day_raw` is 24 ints per day (0-100 busyness). IMPORTANT: it does NOT start
  at midnight — it starts at 6am of the BestTime day and runs 24h forward.
  So day_raw[0] = 6am, day_raw[17] = 11pm, day_raw[18] = midnight of the NEXT
  calendar day, day_raw[23] = 5am next day. We shift indices back to real
  (weekday, hour) pairs before inserting. Closed hours appear as 0 in
  day_raw; we insert them as busyness=0, which correctly reflects "not busy".
- Venues without enough foot-traffic signal get status `Unavailable` from
  BestTime and are listed as comments at the bottom of the generated SQL.
"""

from __future__ import annotations

import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib import error, parse, request


SUPABASE_URL = os.environ.get(
    "SUPABASE_URL", "https://qrkttpwrnquptrkewdfv.supabase.co"
)
# Prefer the service_role key (bypasses RLS) so this one-off scrape can read
# every venue including columns anon RLS policies hide. Fall back to the
# public anon key shipped in the iOS client if only that is set.
SUPABASE_SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
SUPABASE_ANON_KEY = os.environ.get(
    "SUPABASE_ANON_KEY",
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFya3R0cHdybnF1cHRya2V3ZGZ2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU0MTc1NjksImV4cCI6MjA5MDk5MzU2OX0.vB2bAd-gDg4YtPYxA34M0-zKbHOogxbBIa0GwRguIAk",
)
SUPABASE_READ_KEY = SUPABASE_SERVICE_KEY or SUPABASE_ANON_KEY
OUT_PATH = (
    Path(__file__).resolve().parent.parent
    / "supabase"
    / "venues_popular_times_backfill.sql"
)
BESTTIME_ENDPOINT = "https://besttime.app/api/v1/forecasts"
REQUEST_SPACING_SECONDS = 0.5  # BestTime tolerates ~2 req/sec on paid plans


def fetch_venues() -> list[dict]:
    query = parse.urlencode(
        {
            "select": "id,slug,name,address,google_place_id",
            "google_place_id": "not.is.null",
            "is_active": "eq.true",
            "order": "launch_priority.desc",
        }
    )
    url = f"{SUPABASE_URL}/rest/v1/venues?{query}"
    req = request.Request(
        url,
        headers={
            "apikey": SUPABASE_READ_KEY,
            "Authorization": f"Bearer {SUPABASE_READ_KEY}",
            "Accept": "application/json",
        },
    )
    try:
        with request.urlopen(req, timeout=30) as resp:
            return json.load(resp)
    except error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        sys.stderr.write(f"Supabase returned {exc.code}: {body}\n")
        sys.exit(1)


def sql_escape(value) -> str:
    if value is None:
        return "null"
    return "'" + str(value).replace("'", "''") + "'"


def besttime_day_to_pg_dow(day_int: int) -> int:
    """BestTime day_info.day_int: 0=Mon..6=Sun (Monday-first, zero-indexed).
    Postgres extract(dow): 0=Sun..6=Sat."""
    return (day_int + 1) % 7


def fetch_forecast(api_key: str, venue_name: str, venue_address: str) -> dict:
    params = parse.urlencode(
        {
            "api_key_private": api_key,
            "venue_name": venue_name,
            "venue_address": venue_address,
        }
    )
    url = f"{BESTTIME_ENDPOINT}?{params}"
    req = request.Request(url, method="POST")
    try:
        with request.urlopen(req, timeout=60) as resp:
            return json.load(resp)
    except error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code}: {body[:300]}") from exc


def main() -> None:
    api_key = os.environ.get("BESTTIME_API_KEY_PRIVATE")
    if not api_key:
        sys.stderr.write("BESTTIME_API_KEY_PRIVATE env var not set.\n")
        sys.exit(1)
    if not api_key.startswith("pri_"):
        sys.stderr.write(
            "BESTTIME_API_KEY_PRIVATE does not start with 'pri_'. "
            "Did you paste the public key by mistake?\n"
        )
        sys.exit(1)

    venues = fetch_venues()
    sys.stderr.write(
        f"Loaded {len(venues)} active venues with google_place_id from Supabase\n"
    )

    out_lines: list[str] = [
        "-- Auto-generated by scripts/backfill-popular-times.py",
        f"-- Generated: {datetime.now(timezone.utc).isoformat()}",
        "-- Source: BestTime.app forecast API",
        f"-- Venues queried: {len(venues)}",
        "",
        "begin;",
        "",
    ]

    hits = 0
    misses: list[tuple[str, str]] = []
    total_rows = 0

    for index, venue in enumerate(venues, start=1):
        slug = venue.get("slug") or "(no-slug)"
        venue_id = venue.get("id")
        name = venue.get("name")
        address = venue.get("address")

        if not venue_id or not name or not address:
            misses.append((slug, "missing id/name/address"))
            continue

        sys.stderr.write(f"[{index}/{len(venues)}] {slug} … ")
        sys.stderr.flush()

        try:
            result = fetch_forecast(api_key, name, address)
        except Exception as exc:
            sys.stderr.write(f"error: {exc}\n")
            misses.append((slug, str(exc)))
            time.sleep(REQUEST_SPACING_SECONDS)
            continue

        status = (result or {}).get("status")
        if isinstance(status, str) and status.lower() not in ("ok", "cache"):
            message = result.get("message") or status
            sys.stderr.write(f"status {status}: {message}\n")
            misses.append((slug, f"status={status}: {message}"))
            time.sleep(REQUEST_SPACING_SECONDS)
            continue

        analysis = (result or {}).get("analysis") or []
        if not analysis:
            sys.stderr.write("no analysis\n")
            misses.append((slug, "no analysis returned"))
            time.sleep(REQUEST_SPACING_SECONDS)
            continue

        # Replace any existing rows for this venue so this script is idempotent.
        out_lines.append(
            f"delete from public.venue_popular_times where venue_id = {sql_escape(venue_id)};"
        )

        # Collect all (weekday, hour, busyness) tuples for this venue, then
        # emit a single multi-row INSERT. Supabase's SQL editor chokes on very
        # large scripts; one INSERT per venue (168 rows) keeps file size down.
        tuples: list[str] = []
        for day in analysis:
            day_info = day.get("day_info") or {}
            day_int = day_info.get("day_int")
            if day_int is None:
                continue
            base_weekday = besttime_day_to_pg_dow(int(day_int))
            day_raw = day.get("day_raw") or []
            for i, value in enumerate(day_raw):
                if value is None or value < 0:
                    continue
                # day_raw[i] corresponds to real hour (i + 6) % 24 — indices
                # 0..17 are same-day hours 6am..11pm; 18..23 are 0am..5am of
                # the NEXT calendar day.
                actual_hour = (i + 6) % 24
                actual_weekday = base_weekday if i < 18 else (base_weekday + 1) % 7
                busyness = max(0, min(100, int(value)))
                tuples.append(
                    f"({sql_escape(venue_id)}, {actual_weekday}, {actual_hour}, {busyness})"
                )

        rows_for_venue = len(tuples)
        if tuples:
            out_lines.append(
                "insert into public.venue_popular_times "
                "(venue_id, weekday, hour, busyness) values\n  "
                + ",\n  ".join(tuples)
                + ";"
            )

        total_rows += rows_for_venue
        hits += 1
        sys.stderr.write(f"{rows_for_venue} hourly rows\n")
        time.sleep(REQUEST_SPACING_SECONDS)

    out_lines.extend(["", "commit;", ""])

    if misses:
        out_lines.append("-- Misses (BestTime forecast unavailable):")
        for slug, reason in misses:
            out_lines.append(f"-- {slug}: {reason}")
        out_lines.append("")

    OUT_PATH.write_text("\n".join(out_lines))

    sys.stderr.write(
        f"\nWrote {total_rows} rows for {hits} venues to {OUT_PATH}\n"
    )
    if misses:
        sys.stderr.write(
            f"{len(misses)} venues returned no data (listed as comments).\n"
        )


if __name__ == "__main__":
    main()
