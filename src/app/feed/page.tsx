import Link from "next/link";
import { FeedExperience } from "@/components/feed-experience";
import { getHomeData } from "@/lib/feed";
import { createClient } from "@/lib/supabase/server";

type FeedPageProps = {
  searchParams?: Promise<{
    tab?: string;
  }>;
};

function parseCompactCount(value: string) {
  const normalized = value.trim().toUpperCase();

  if (!normalized) {
    return 0;
  }

  if (normalized.endsWith("M")) {
    return Math.round(Number.parseFloat(normalized) * 1_000_000);
  }

  if (normalized.endsWith("K")) {
    return Math.round(Number.parseFloat(normalized) * 1_000);
  }

  return Number.parseInt(normalized, 10) || 0;
}

export default async function FeedPage({ searchParams }: FeedPageProps) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const resolvedSearchParams = await searchParams;
  const activeTab = resolvedSearchParams?.tab === "following" ? "following" : "for-you";
  const guestMode = !user;

  const homeData = await getHomeData(activeTab);
  const feedCards =
    activeTab === "following"
      ? (homeData.feed ?? [])
      : (homeData.feed ??
          homeData.fallbackFeed.map((post) => ({
            id: post.id,
            creatorId: "",
            creatorName: "",
            creatorHandle: "",
            playbackUrl: post.videoUrl,
            thumbnailUrl: null,
            title: post.title,
            caption: post.caption,
            category: post.category,
            tags: post.tags,
            likesCount: parseCompactCount(post.likes),
            likes: post.likes,
            commentsCount: parseCompactCount(post.comments),
            comments: post.comments,
            views: post.views,
            age: post.age,
            score: post.score,
            whyRecommended: "trending from recent engagement",
            likedByCurrentUser: false,
            followedCreatorByCurrentUser: false,
            recentComments: [],
          })));

  const redirectTarget = activeTab === "following" ? "/feed?tab=following" : "/feed";

  return (
    <main className="feed-shell">
      <div className="feed-topbar">
        <div className="feed-tab-strip">
          <Link
            className={activeTab === "for-you" ? "feed-tab active" : "feed-tab"}
            href="/feed"
          >
            For You
          </Link>
          {guestMode ? (
            <Link className="feed-tab" href="/auth/sign-up">
              Following
            </Link>
          ) : (
            <Link
              className={activeTab === "following" ? "feed-tab active" : "feed-tab"}
              href="/feed?tab=following"
            >
              Following
            </Link>
          )}
        </div>
      </div>

      <section className="feed-scroll">
        <FeedExperience
          empty={
            <article className="feed-empty-state">
              <p className="eyebrow !text-white/70">Nothing here yet</p>
              <h2 className="mt-3 text-2xl font-semibold tracking-[-0.05em] text-white">
                Follow creators to fill your feed
              </h2>
              <div className="mt-6 flex flex-col gap-3">
                <Link className="feed-primary-button" href="/feed">
                  Back to For You
                </Link>
              </div>
            </article>
          }
          feedCards={feedCards}
          guestMode={guestMode}
          guestPromptAfter={2}
          redirectTarget={redirectTarget}
        />
      </section>
    </main>
  );
}
