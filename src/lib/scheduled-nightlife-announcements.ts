export type NightKey = "friday" | "saturday";

export type ScheduledAnnouncement = {
  title: string;
  body: string;
};

const fridayTitles = [
  "Friday starts here",
  "Friday plans sorted",
  "Your Friday move",
  "Friday feels loaded",
  "Fresh Friday energy",
  "Friday night is on",
  "Tonight’s your night",
  "Friday’s looking loud",
  "Time to make Friday count",
  "Weekend mode starts now",
  "Friday just got better",
  "The Friday group chat can relax",
  "Friday, handled",
] as const;

const fridayBodies = [
  "Open Spilltop, see who’s moving, and lock in your first stop before the group chat drifts.",
  "Find the busiest spots, check who’s already out, and turn your maybe-plans into a real night.",
  "If you’re heading out later, get the lay of the night now and keep your best options close.",
  "The map is live, the feed is moving, and your Friday answer is probably already on Spilltop.",
] as const;

const saturdayTitles = [
  "Saturday is calling",
  "Big Saturday energy",
  "Saturday plans, upgraded",
  "Your Saturday lineup",
  "Saturday starts with Spilltop",
  "Tonight’s going to move",
  "Saturday mode: on",
  "The night is warming up",
  "See where Saturday is happening",
  "Your Saturday shortcut",
  "Make tonight easier",
  "Saturday just found its pace",
  "Ready for the main event?",
] as const;

const saturdayBodies = [
  "The busiest rooms, the best moments, and the people already out are waiting in Spilltop.",
  "Before you bounce between group chats, check who’s live, who’s out, and where the night’s building.",
  "Saturday moves fast. Open Spilltop, read the room, and head where the energy actually is.",
  "Your next venue, the real crowd, and tonight’s momentum are already easier to read on Spilltop.",
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
