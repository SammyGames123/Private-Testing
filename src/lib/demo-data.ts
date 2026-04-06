export type Creator = {
  id: string;
  name: string;
  handle: string;
  niche: string;
  followers: string;
  blurb: string;
};

export type VideoPost = {
  id: string;
  creatorId: string;
  videoUrl: string;
  title: string;
  caption: string;
  category: string;
  tags: string[];
  likes: string;
  comments: string;
  views: string;
  age: string;
  score: number;
};

export type Thread = {
  id: string;
  withUser: string;
  preview: string;
  age: string;
};

export const creators: Creator[] = [
  {
    id: "creator-1",
    name: "Luna Loops",
    handle: "@lunaloops",
    niche: "Music edits",
    followers: "128K",
    blurb: "Color-drenched night edits, tempo cuts, and creator collabs.",
  },
  {
    id: "creator-2",
    name: "Plate Passport",
    handle: "@platepassport",
    niche: "Food travel",
    followers: "92K",
    blurb: "Street food stories, quick city guides, and restaurant reels.",
  },
  {
    id: "creator-3",
    name: "Coach Nova",
    handle: "@coachnova",
    niche: "Fitness",
    followers: "61K",
    blurb: "Short-form training plans built for consistency and retention.",
  },
];

export const posts: VideoPost[] = [
  {
    id: "post-1",
    creatorId: "creator-1",
    videoUrl:
      "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4",
    title: "Neon tram at 2AM",
    caption: "Fast-cut city textures slowed just enough to catch the glow.",
    category: "Travel",
    tags: ["music", "travel", "city"],
    likes: "24.8K",
    comments: "1.2K",
    views: "310K",
    age: "2h ago",
    score: 94,
  },
  {
    id: "post-2",
    creatorId: "creator-2",
    videoUrl:
      "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4",
    title: "Five-dollar noodle stop",
    caption: "A tiny place with huge flavor and a line out the door.",
    category: "Food",
    tags: ["food", "travel", "budget"],
    likes: "18.6K",
    comments: "870",
    views: "204K",
    age: "5h ago",
    score: 89,
  },
  {
    id: "post-3",
    creatorId: "creator-3",
    videoUrl:
      "https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4",
    title: "12-minute cardio ladder",
    caption: "Low equipment, full-body, and built for people who miss days sometimes.",
    category: "Fitness",
    tags: ["fitness", "education", "routine"],
    likes: "11.3K",
    comments: "530",
    views: "118K",
    age: "8h ago",
    score: 83,
  },
];

export const threads: Thread[] = [
  {
    id: "thread-1",
    withUser: "Luna Loops",
    preview: "If you launch creator waitlists, I want in on day one.",
    age: "12m ago",
  },
  {
    id: "thread-2",
    withUser: "Plate Passport",
    preview: "A collab invite flow would be perfect after the first release.",
    age: "49m ago",
  },
];

export const algorithmSignals = [
  "followed creators",
  "watch time",
  "rewatches",
  "liked tags",
  "comment activity",
  "recency",
];

export function getCreatorById(id: string) {
  return creators.find((creator) => creator.id === id);
}
