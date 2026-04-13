import { createClient } from "@/lib/supabase/server";

export type VideoRecord = {
  id: string;
  title: string;
  caption: string | null;
  category: string | null;
  playback_url: string | null;
  thumbnail_url: string | null;
  visibility: "public" | "private" | "unlisted";
  is_pinned: boolean;
  is_archived: boolean;
  created_at: string;
  video_tags: { tag: string }[] | null;
};

function formatTimeAgo(dateString: string) {
  const diffSeconds = Math.max(
    0,
    Math.floor((Date.now() - new Date(dateString).getTime()) / 1000),
  );

  if (diffSeconds >= 86400) {
    return `${Math.floor(diffSeconds / 86400)}d ago`;
  }
  if (diffSeconds >= 3600) {
    return `${Math.floor(diffSeconds / 3600)}h ago`;
  }
  if (diffSeconds >= 60) {
    return `${Math.floor(diffSeconds / 60)}m ago`;
  }
  return "just now";
}

export function toVideoAgeLabel(dateString: string) {
  return formatTimeAgo(dateString);
}

export async function getCurrentUserVideos(userId: string) {
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("videos")
    .select(
      `
        id,
        title,
        caption,
        category,
        playback_url,
        thumbnail_url,
        visibility,
        is_pinned,
        is_archived,
        created_at,
        video_tags (tag)
      `,
    )
    .eq("creator_id", userId)
    .order("is_pinned", { ascending: false })
    .order("created_at", { ascending: false });

  return {
    videos: (data as VideoRecord[] | null) ?? [],
    error,
  };
}
