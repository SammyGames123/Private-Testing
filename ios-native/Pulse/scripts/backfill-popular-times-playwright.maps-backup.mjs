import fs from "node:fs/promises";
import process from "node:process";
import { chromium } from "playwright";
import { createClient } from "@supabase/supabase-js";

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const OUTPUT = process.env.OUTPUT_SQL || "supabase/venues_popular_times_backfill.sql";

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  process.exit(1);
}

const DAY_NAMES = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
const DAY_SHORT = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function sqlEscape(value) {
  return String(value).replace(/'/g, "''");
}

function normalizeHour(hourText) {
  const t = hourText.trim().toUpperCase().replace(/\./g, "");
  const m = t.match(/^(\d{1,2})(?::(\d{2}))?\s*(AM|PM)?$/);
  if (!m) return null;
  let hour = parseInt(m[1], 10);
  const meridiem = m[3];
  if (meridiem === "AM") {
    if (hour === 12) hour = 0;
  } else if (meridiem === "PM") {
    if (hour !== 12) hour += 12;
  }
  return hour >= 0 && hour <= 23 ? hour : null;
}

function busynessFromLabel(label) {
  const raw = label.replace(/\s+/g, " ").trim();

  const pct = raw.match(/(\d{1,3})\s*%/);
  if (pct) {
    const value = Math.max(0, Math.min(100, parseInt(pct[1], 10)));
    return value;
  }

  const phrases = [
    [/as busy as it gets/i, 100],
    [/very busy/i, 85],
    [/busy/i, 70],
    [/a little busy/i, 45],
    [/not too busy/i, 25],
    [/usually not busy/i, 15],
    [/not busy/i, 10],
    [/quiet/i, 10],
  ];

  for (const [re, score] of phrases) {
    if (re.test(raw)) return score;
  }

  return null;
}

function extractHourFromLabel(label) {
  const raw = label.replace(/\s+/g, " ").trim();

  const patterns = [
    /\b(\d{1,2}(?::\d{2})?\s?(?:AM|PM))\b/i,
    /\bat\s+(\d{1,2}(?::\d{2})?\s?(?:AM|PM))\b/i,
    /\b(\d{1,2})\s*o'?clock\b/i,
  ];

  for (const re of patterns) {
    const m = raw.match(re);
    if (m) {
      const hour = normalizeHour(m[1]);
      if (hour !== null) return hour;
    }
  }

  return null;
}

async function dismissConsent(page) {
  const selectors = [
    'button:has-text("Accept all")',
    'button:has-text("I agree")',
    'button:has-text("Accept")',
    'button:has-text("Reject all")',
  ];

  for (const sel of selectors) {
    try {
      const el = page.locator(sel).first();
      if (await el.isVisible({ timeout: 1000 })) {
        await el.click({ timeout: 1000 });
        await sleep(1000);
        return;
      }
    } catch {}
  }
}

async function openPopularTimes(page, placeId, venueName) {
  const url = `https://www.google.com/maps/place/?q=place_id:${encodeURIComponent(placeId)}&hl=en&gl=au`;
  await page.goto(url, { waitUntil: "domcontentloaded", timeout: 60000 });
  await dismissConsent(page);
  await page.waitForLoadState("networkidle", { timeout: 15000 }).catch(() => {});
  await sleep(2000);

  const title = await page.title().catch(() => "");
  if (/sorry|unusual traffic|detected unusual/i.test(title)) {
    throw new Error("Google anti-bot page shown");
  }

  const bodyText = await page.locator("body").innerText().catch(() => "");
  if (/no results found|did not match any locations/i.test(bodyText)) {
    throw new Error(`No Google Maps result for ${venueName}`);
  }
}

async function collectPopularForCurrentDay(page) {
  return await page.evaluate(() => {
    const labels = [];
    const all = Array.from(document.querySelectorAll("[aria-label]"));
    for (const el of all) {
      const label = el.getAttribute("aria-label");
      if (label) labels.push(label);
    }
    return labels;
  });
}

async function clickDay(page, dayName, dayShort) {
  const candidates = [
    `button[aria-label*="${dayName}"]`,
    `button[aria-label*="${dayShort}"]`,
    `button:has-text("${dayShort}")`,
    `[role="tab"][aria-label*="${dayName}"]`,
    `[role="tab"]:has-text("${dayShort}")`,
  ];

  for (const sel of candidates) {
    try {
      const el = page.locator(sel).first();
      if (await el.isVisible({ timeout: 1000 })) {
        await el.click({ timeout: 1000 });
        await sleep(800);
        return true;
      }
    } catch {}
  }
  return false;
}

function parseLabelsToHours(labels) {
  const rows = [];
  const seen = new Set();

  for (const label of labels) {
    const hour = extractHourFromLabel(label);
    const busyness = busynessFromLabel(label);
    if (hour === null || busyness === null) continue;

    const key = `${hour}:${busyness}`;
    if (seen.has(key)) continue;
    seen.add(key);

    rows.push({ hour, busyness, label });
  }

  rows.sort((a, b) => a.hour - b.hour);
  return rows;
}

async function scrapeVenue(page, venue) {
  await openPopularTimes(page, venue.google_place_id, venue.name);

  const dayMap = new Map();

  for (let weekday = 0; weekday < 7; weekday++) {
    const clicked = await clickDay(page, DAY_NAMES[weekday], DAY_SHORT[weekday]);
    if (!clicked && weekday !== 0) {
      continue;
    }

    const labels = await collectPopularForCurrentDay(page);
    const parsed = parseLabelsToHours(labels);

    if (parsed.length) {
      dayMap.set(weekday, parsed);
    }
  }

  return dayMap;
}

function buildSql(venueRows, misses) {
  const lines = [];
  lines.push("-- Auto-generated by scripts/backfill-popular-times-playwright.mjs");
  lines.push(`-- Generated: ${new Date().toISOString()}`);
  lines.push(`-- Venues queried: ${venueRows.length + misses.length}`);
  lines.push("");
  lines.push("begin;");
  lines.push("");
  lines.push("delete from public.venue_popular_times;");
  lines.push("");

  for (const venue of venueRows) {
    for (const row of venue.rows) {
      lines.push(
        `insert into public.venue_popular_times (venue_id, weekday, hour, busyness, updated_at) values ('${venue.id}', ${row.weekday}, ${row.hour}, ${row.busyness}, now()) on conflict (venue_id, weekday, hour) do update set busyness = excluded.busyness, updated_at = now();`
      );
    }
    lines.push("");
  }

  if (misses.length) {
    lines.push("-- No popular times extracted for these venues:");
    for (const miss of misses) {
      lines.push(`-- ${miss.slug} | ${sqlEscape(miss.name)} | ${sqlEscape(miss.reason)}`);
    }
    lines.push("");
  }

  lines.push("commit;");
  lines.push("");
  return lines.join("\n");
}

async function main() {
  const { data: venues, error } = await supabase
    .from("venues")
    .select("id, slug, name, google_place_id")
    .eq("is_active", true)
    .not("google_place_id", "is", null)
    .order("launch_priority", { ascending: false });

  if (error) {
    console.error(error);
    process.exit(1);
  }

  console.log(`Loaded ${venues.length} active venues with google_place_id from Supabase`);

  const browser = await chromium.launch({
    headless: true,
    args: ["--disable-blink-features=AutomationControlled"],
  });

  const context = await browser.newContext({
    locale: "en-AU",
    timezoneId: "Australia/Brisbane",
    userAgent:
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    viewport: { width: 1440, height: 1100 },
  });

  const page = await context.newPage();

  const successes = [];
  const misses = [];

  for (let i = 0; i < venues.length; i++) {
    const venue = venues[i];
    process.stderr.write(`[${i + 1}/${venues.length}] ${venue.slug} … `);

    try {
      const dayMap = await scrapeVenue(page, venue);

      if (!dayMap.size) {
        misses.push({ ...venue, reason: "no popular times found in rendered page" });
        process.stderr.write("no data\n");
      } else {
        const rows = [];
        for (const [weekday, entries] of dayMap.entries()) {
          for (const entry of entries) {
            rows.push({
              weekday,
              hour: entry.hour,
              busyness: entry.busyness,
            });
          }
        }

        successes.push({ id: venue.id, slug: venue.slug, name: venue.name, rows });
        process.stderr.write(`${rows.length} rows\n`);
      }
    } catch (err) {
      misses.push({ ...venue, reason: err.message || String(err) });
      process.stderr.write(`error: ${err.message || err}\n`);
    }

    await sleep(1800);
  }

  await browser.close();

  const sql = buildSql(successes, misses);
  await fs.writeFile(OUTPUT, sql, "utf8");

  console.log(`Wrote ${successes.reduce((n, v) => n + v.rows.length, 0)} rows for ${successes.length} venues to ${OUTPUT}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
