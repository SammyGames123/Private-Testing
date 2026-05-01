export type NightKey = "friday" | "saturday";

export type ScheduledAnnouncement = {
  title: string;
  body: string;
};

const fridayTitles = [
  "Friday plans? Sorted",
  "What’s the move tonight?",
  "Friday is starting to move",
  "Your Friday shortcut",
  "Group chat going nowhere?",
  "Friday’s looking better already",
  "Tonight’s answer is easier",
  "Don’t wing Friday",
  "Friday is warming up",
  "Less maybe, more move",
  "Weekend mode is here",
  "Friday’s got options",
  "Start with Spilltop",
] as const;

const fridayBodies = [
  "Open Spilltop, check who’s out, and lock in somewhere good before the group chat starts guessing.",
  "See what’s actually moving tonight and save yourself from getting sent somewhere dead.",
  "If you’re heading out later, get a quick read on the night now and keep your best options close.",
  "The feed is moving, the map is live, and your Friday plan is probably already on Spilltop.",
] as const;

const saturdayTitles = [
  "Saturday is moving",
  "Big Saturday energy",
  "Don’t get sent somewhere mid",
  "Your Saturday shortcut",
  "See where it’s actually happening",
  "Saturday plans, handled",
  "Tonight’s going to be loud",
  "The night is picking up",
  "Skip the bad call",
  "Saturday starts here",
  "Know the vibe before you go",
  "Tonight needs a better plan",
  "Main character Saturday",
] as const;

const saturdayBodies = [
  "Check Spilltop first and go where the crowd, the moments, and the energy are actually lining up.",
  "Before the group chat sends you in circles, see who’s out and where tonight is really building.",
  "Saturday moves fast. Open Spilltop, read the room, and head where the night is actually good.",
  "Your next venue is easier to pick when you can see the real vibe before you even get there.",
] as const;

function buildRotatingMessages(
  titles: readonly string[],
  bodies: readonly string[],
): ScheduledAnnouncement[] {
  const combinations = titles.flatMap((title) =>
    bodies.map((body) => ({
      title,
      body,
    })),
  );

  return Array.from({ length: combinations.length }, (_, index) => {
    const rotatedIndex = (index * 5) % combinations.length;
    return combinations[rotatedIndex];
  });
}

const fridayMessages = buildRotatingMessages(fridayTitles, fridayBodies);
const saturdayMessages = buildRotatingMessages(saturdayTitles, saturdayBodies);

export function isNightKey(value: string): value is NightKey {
  return value === "friday" || value === "saturday";
}

function isoWeekNumber(date: Date) {
  const target = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  const dayNumber = target.getUTCDay() || 7;
  target.setUTCDate(target.getUTCDate() + 4 - dayNumber);
  const yearStart = new Date(Date.UTC(target.getUTCFullYear(), 0, 1));
  return Math.ceil((((target.getTime() - yearStart.getTime()) / 86400000) + 1) / 7);
}

function localDateKey(date: Date) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Australia/Brisbane",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}

export function scheduledAnnouncementFor(day: NightKey, date = new Date()) {
  const weekIndex = (isoWeekNumber(date) - 1) % 52;
  const messages = day === "friday" ? fridayMessages : saturdayMessages;
  const message = messages[weekIndex] ?? messages[0];

  return {
    ...message,
    day,
    weekIndex,
    localDateKey: localDateKey(date),
    dispatchKey: `${day}:${localDateKey(date)}`,
  };
}
