import { createClient } from "@/lib/supabase/server";
import { creators, posts, threads } from "@/lib/demo-data";
import type { Profile } from "@/lib/profiles";

export type FeedMode = "for-you" | "following";

export type LiveComment = {
  id: string;
  body: string;
  authorHandle: string;
};

export type LiveCreatorCard = {
  id: string;
  name: string;
  handle: string;
  niche: string;
  followers: string;
  blurb: string;
  followedByCurrentUser: boolean;
};

export type LiveFeedCard = {
  id: string;
  creatorId: string;
  creatorName: string;
  creatorHandle: string;
  playbackUrl: string | null;
  thumbnailUrl: string | null;
  title: string;
  caption: string | null;
  category: string | null;
  tags: string[];
  likesCount: number;
  likes: string;
  commentsCount: number;
  comments: string;
  views: string;
  age: string;
  score: number;
  whyRecommended: string;
  likedByCurrentUser: boolean;
  followedCreatorByCurrentUser: boolean;
  recentComments: LiveComment[];
};

export type InboxPreview = {
  id: string;
  withUser: string;
  preview: string;
  age: string;
};

type VideoRow = {
  id: string;
  title: string;
  caption: string | null;
  category: string | null;
  playback_url: string | null;
  thumbnail_url: string | null;
  created_at: string;
  creator_id: string;
  profiles: Pick<Profile, "username" | "display_name"> | Pick<Profile, "username" | "display_name">[] | null;
  video_tags: { tag: string }[] | null;
  likes: { user_id: string }[] | null;
  comments:
    | {
        id: string;
        body: string;
        profiles: Pick<Profile, "username"> | Pick<Profile, "username">[] | null;
      }[]
    | null;
  watch_events: { id: string }[] | null;
};

type ProfileRow = Pick<
  Profile,
  "id" | "username" | "display_name" | "bio"
> & {
  follows_following?: { follower_id: string }[] | null;
  follows_followers?: { following_id: string }[] | null;
};

type WatchEventRow = {
  video_id: string;
  watch_seconds: number;
  completed: boolean;
  rewatch_count: number;
};

type LikeRow = {
  video_id: string;
};

function formatCompactCount(count: number) {
  if (count >= 1_000_000) {
    return `${(count / 1_000_000).toFixed(1)}M`;
  }
  if (count >= 1_000) {
    return `${(count / 1_000).toFixed(1)}K`;
  }
  return `${count}`;
}

function formatTimeAgo(dateString: string) {
  const diffSeconds = Math.max(
    0,
    Math.floor((Date.now() - new Date(dateString).getTime()) / 1000),
  );
  const day = 86400;
  const hour = 3600;
  const minute = 60;

  if (diffSeconds >= day) {
    return `${Math.floor(diffSeconds / day)}d ago`;
  }
  if (diffSeconds >= hour) {
    return `${Math.floor(diffSeconds / hour)}h ago`;
  }
  if (diffSeconds >= minute) {
    return `${Math.floor(diffSeconds / minute)}m ago`;
  }
  return "just now";
}

function getProfileObject(
  profile: VideoRow["profiles"],
): Pick<Profile, "username" | "display_name"> | null {
  if (!profile) {
    return null;
  }

  return Array.isArray(profile) ? (profile[0] ?? null) : profile;
}

function normalizeToken(value: string) {
  return value.trim().toLowerCase();
}

function buildPreferenceMap(values: string[], weight: number) {
  const map = new Map<string, number>();

  for (const value of values) {
    const token = normalizeToken(value);

    if (!token) {
      continue;
    }

    map.set(token, (map.get(token) ?? 0) + weight);
  }

  return map;
}

function getCommentProfileObject(
  profile:
    | Pick<Profile, "username">
    | Pick<Profile, "username">[]
    | null,
): Pick<Profile, "username"> | null {
  if (!profile) {
    return null;
  }

  return Array.isArray(profile) ? (profile[0] ?? null) : profile;
}

function calculateScore(row: VideoRow) {
  const likesCount = row.likes?.length ?? 0;
  const commentsCount = row.comments?.length ?? 0;
  const viewsCount = row.watch_events?.length ?? 0;
  return Math.min(
    99,
    60 + likesCount * 4 + commentsCount * 5 + Math.min(viewsCount, 20),
  );
}

function getHoursSinceCreated(dateString: string) {
  return Math.max(
    1,
    (Date.now() - new Date(dateString).getTime()) / (1000 * 60 * 60),
  );
}

function rankVideoForUser(args: {
  row: VideoRow;
  followingSet: Set<string>;
  likedVideoIds: Set<string>;
  watchedVideoIds: Set<string>;
  interestMap: Map<string, number>;
  categoryAffinityMap: Map<string, number>;
  tagAffinityMap: Map<string, number>;
  watchEventsByVideoId: Map<string, WatchEventRow>;
}) {
  const {
    row,
    followingSet,
    likedVideoIds,
    watchedVideoIds,
    interestMap,
    categoryAffinityMap,
    tagAffinityMap,
    watchEventsByVideoId,
  } = args;

  const likesCount = row.likes?.length ?? 0;
  const commentsCount = row.comments?.length ?? 0;
  const hoursSinceCreated = getHoursSinceCreated(row.created_at);
  const recencyBoost = Math.max(0, 24 - Math.min(24, hoursSinceCreated / 3));
  const engagementBoost = Math.min(16, likesCount * 1.8 + commentsCount * 2.4);
  const followingBoost = followingSet.has(row.creator_id) ? 28 : 0;
  const alreadyLikedBoost = likedVideoIds.has(row.id) ? 14 : 0;
  const alreadyWatchedBoost = watchedVideoIds.has(row.id) ? 8 : 0;

  const categoryToken = row.category ? normalizeToken(row.category) : "";
  const interestCategoryBoost =
    (categoryToken ? interestMap.get(categoryToken) ?? 0 : 0) * 4;
  const affinityCategoryBoost =
    (categoryToken ? categoryAffinityMap.get(categoryToken) ?? 0 : 0) * 6;

  const tagTokens = row.video_tags?.map((tagRow) => normalizeToken(tagRow.tag)) ?? [];
  const tagInterestBoost = tagTokens.reduce(
    (total, token) => total + (interestMap.get(token) ?? 0) * 3,
    0,
  );
  const tagAffinityBoost = tagTokens.reduce(
    (total, token) => total + (tagAffinityMap.get(token) ?? 0) * 4,
    0,
  );

  const watchEvent = watchEventsByVideoId.get(row.id);
  const watchQualityBoost = watchEvent
    ? Math.min(
        18,
        watchEvent.watch_seconds / 6 +
          (watchEvent.completed ? 8 : 0) +
          watchEvent.rewatch_count * 4,
      )
    : 0;

  const score =
    48 +
    recencyBoost +
    engagementBoost +
    followingBoost +
    alreadyLikedBoost +
    alreadyWatchedBoost +
    interestCategoryBoost +
    affinityCategoryBoost +
    tagInterestBoost +
    tagAffinityBoost +
    watchQualityBoost;

  const reasons: string[] = [];

  if (followingBoost > 0) {
    reasons.push("from a creator you follow");
  }

  if (affinityCategoryBoost > 0 || tagAffinityBoost > 0) {
    reasons.push("matches categories and tags you engage with");
  } else if (interestCategoryBoost > 0 || tagInterestBoost > 0) {
    reasons.push("fits your profile interests");
  }

  if (watchQualityBoost > 0) {
    reasons.push("similar to videos you watch deeply");
  }

  if (reasons.length === 0) {
    reasons.push("trending from recent engagement");
  }

  return {
    score: Math.min(99, Math.round(score)),
    whyRecommended: reasons[0],
  };
}

function mapVideoRowToFeedCard(args: {
  row: VideoRow;
  userId: string | undefined;
  followingSet: Set<string>;
  score: number;
  whyRecommended: string;
}) {
  const { row, userId, followingSet, score, whyRecommended } = args;
  const profile = getProfileObject(row.profiles);
  const likesCount = row.likes?.length ?? 0;
  const commentsCount = row.comments?.length ?? 0;
  const viewsCount = row.watch_events?.length ?? 0;
  const likedByCurrentUser =
    row.likes?.some((likeRow) => likeRow.user_id === userId) ?? false;
  const recentComments =
    row.comments?.slice(0, 3).map((commentRow) => {
      const commentProfile = getCommentProfileObject(commentRow.profiles);
      return {
        id: commentRow.id,
        body: commentRow.body,
        authorHandle: `@${commentProfile?.username ?? "creator"}`,
      };
    }) ?? [];

  return {
    id: row.id,
    creatorId: row.creator_id,
    creatorName: profile?.display_name ?? "Creator",
    creatorHandle: `@${profile?.username ?? "creator"}`,
    playbackUrl: row.playback_url,
    thumbnailUrl: row.thumbnail_url,
    title: row.title,
    caption: row.caption,
    category: row.category,
    tags: row.video_tags?.map((tagRow) => tagRow.tag) ?? [],
    likesCount,
    likes: formatCompactCount(likesCount),
    commentsCount,
    comments: formatCompactCount(commentsCount),
    views: formatCompactCount(viewsCount),
    age: formatTimeAgo(row.created_at),
    score,
    whyRecommended,
    likedByCurrentUser,
    followedCreatorByCurrentUser: followingSet.has(row.creator_id),
    recentComments,
  };
}

export async function getHomeData(mode: FeedMode = "for-you") {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const [
    { data: videoRows, error: videosError },
    { data: profileRows, error: profilesError },
    { data: currentUserFollowing },
    { data: currentProfile },
    { data: currentUserLikes },
    { data: currentUserWatchEvents },
  ] =
    await Promise.all([
      supabase
        .from("videos")
        .select(
          `
            id,
            title,
            caption,
            category,
            playback_url,
            thumbnail_url,
            created_at,
            creator_id,
            profiles:creator_id (username, display_name),
            video_tags (tag),
            likes (user_id),
            comments (
              id,
              body,
              profiles:user_id (username)
            ),
            watch_events (id)
          `,
        )
        .order("created_at", { ascending: false })
        .limit(24),
      supabase
        .from("profiles")
        .select(
          `
            id,
            username,
            display_name,
            bio,
            follows_following:follows!follows_following_id_fkey (follower_id),
            follows_followers:follows!follows_follower_id_fkey (following_id)
          `,
        )
        .limit(6),
      user
        ? supabase
            .from("follows")
            .select("following_id")
            .eq("follower_id", user.id)
        : Promise.resolve({ data: [], error: null }),
      user
        ? supabase
            .from("profiles")
            .select("interests")
            .eq("id", user.id)
            .maybeSingle<Pick<Profile, "interests">>()
        : Promise.resolve({ data: null, error: null }),
      user
        ? supabase
            .from("likes")
            .select("video_id")
            .eq("user_id", user.id)
            .limit(100)
        : Promise.resolve({ data: [], error: null }),
      user
        ? supabase
            .from("watch_events")
            .select("video_id, watch_seconds, completed, rewatch_count")
            .eq("user_id", user.id)
            .order("created_at", { ascending: false })
            .limit(100)
        : Promise.resolve({ data: [], error: null }),
    ]);

  const followingSet = new Set(
    (currentUserFollowing ?? []).map((row) => row.following_id),
  );
  const likedVideoIds = new Set(
    ((currentUserLikes as LikeRow[] | null) ?? []).map((row) => row.video_id),
  );
  const watchRows = (currentUserWatchEvents as WatchEventRow[] | null) ?? [];
  const watchedVideoIds = new Set(watchRows.map((row) => row.video_id));
  const watchEventsByVideoId = new Map(
    watchRows.map((row) => [row.video_id, row]),
  );

  const videoRowsArray = (videoRows as VideoRow[] | null) ?? [];
  const videoById = new Map(videoRowsArray.map((row) => [row.id, row]));

  const interestValues = currentProfile?.interests ?? [];
  const interestMap = buildPreferenceMap(interestValues, 1);

  const categoryAffinityValues: string[] = [];
  const tagAffinityValues: string[] = [];

  for (const row of videoRowsArray) {
    if (likedVideoIds.has(row.id) || watchedVideoIds.has(row.id)) {
      if (row.category) {
        categoryAffinityValues.push(row.category);
      }

      for (const tagRow of row.video_tags ?? []) {
        tagAffinityValues.push(tagRow.tag);
      }
    }
  }

  for (const likedRow of (currentUserLikes as LikeRow[] | null) ?? []) {
    const row = videoById.get(likedRow.video_id);

    if (!row) {
      continue;
    }

    if (row.category) {
      categoryAffinityValues.push(row.category);
    }

    for (const tagRow of row.video_tags ?? []) {
      tagAffinityValues.push(tagRow.tag);
    }
  }

  const categoryAffinityMap = buildPreferenceMap(categoryAffinityValues, 1);
  const tagAffinityMap = buildPreferenceMap(tagAffinityValues, 1);

  const rankedFeedRows = videoRowsArray
    .filter((row) =>
      mode === "following" ? followingSet.has(row.creator_id) : true,
    )
    .map((row) => {
      if (mode === "following") {
        return {
          row,
          score: calculateScore(row) + (followingSet.has(row.creator_id) ? 20 : 0),
          whyRecommended: "from a creator you follow",
        };
      }

      return {
        row,
        ...rankVideoForUser({
          row,
          followingSet,
          likedVideoIds,
          watchedVideoIds,
          interestMap,
          categoryAffinityMap,
          tagAffinityMap,
          watchEventsByVideoId,
        }),
      };
    })
    .sort((left, right) => {
      if (right.score !== left.score) {
        return right.score - left.score;
      }

      return (
        new Date(right.row.created_at).getTime() -
        new Date(left.row.created_at).getTime()
      );
    })
    .slice(0, 12);

  const liveFeed: LiveFeedCard[] = rankedFeedRows.map(({ row, score, whyRecommended }) =>
    mapVideoRowToFeedCard({
      row,
      userId: user?.id,
      followingSet,
      score,
      whyRecommended,
    }),
  );

  const liveCreators: LiveCreatorCard[] =
    (profileRows as ProfileRow[] | null)?.map((row) => ({
      id: row.id,
      name: row.display_name ?? row.username ?? "Creator",
      handle: `@${row.username ?? "creator"}`,
      niche: "Creator profile",
      followers: formatCompactCount(row.follows_following?.length ?? 0),
      blurb: row.bio ?? "This creator has not written a bio yet.",
      followedByCurrentUser: followingSet.has(row.id),
    })) ?? [];

  return {
    feed: liveFeed.length > 0 ? liveFeed : null,
    creators: liveCreators.length > 0 ? liveCreators : null,
    inbox: threads as InboxPreview[],
    usedFallback:
      liveFeed.length === 0 || liveCreators.length === 0 || !!videosError || !!profilesError,
    fallbackFeed: posts,
    fallbackCreators: creators,
    mode,
  };
}
