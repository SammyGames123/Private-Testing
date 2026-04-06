import Link from "next/link";
import { redirect } from "next/navigation";
import { FeedExperience } from "@/components/feed-experience";
import { getHomeData } from "@/lib/feed";
import { createClient } from "@/lib/supabase/server";

type FeedPageProps = {
  searchParams?: Promise<{
    tab?: string;
  }>;
};

export default async function FeedPage({ searchParams }: FeedPageProps) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/auth/login");
  }

  const resolvedSearchParams = await searchParams;
  const activeTab = resolvedSearchParams?.tab === "following" ? "following" : "for-you";
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
            likes: post.likes,
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
        <div>
          <p className="eyebrow !text-white/70">Full feed</p>
          <h1 className="text-3xl font-semibold tracking-[-0.05em] text-white">
            {activeTab === "following" ? "Following" : "For You"}
          </h1>
        </div>
        <div className="flex flex-wrap items-center gap-3">
          <div className="feed-tab-strip">
            <Link
              className={activeTab === "for-you" ? "feed-tab active" : "feed-tab"}
              href="/feed"
            >
              For You
            </Link>
            <Link
              className={activeTab === "following" ? "feed-tab active" : "feed-tab"}
              href="/feed?tab=following"
            >
              Following
            </Link>
          </div>
          <Link className="feed-ghost-button" href="/">
            Back home
          </Link>
          <Link className="feed-primary-button" href="/videos/new">
            Upload
          </Link>
        </div>
      </div>

      <section className="feed-scroll">
        <FeedExperience
          empty={
            <article className="feed-empty-state">
              <p className="eyebrow !text-white/70">Nothing here yet</p>
              <h2 className="mt-3 text-3xl font-semibold tracking-[-0.05em] text-white">
                Follow a few creators to unlock your Following feed.
              </h2>
              <p className="mt-3 max-w-xl text-sm leading-7 text-white/78">
                Your `For You` feed can still recommend content, but the
                `Following` tab only fills once you start following people.
              </p>
              <div className="mt-6 flex flex-wrap gap-3">
                <Link className="feed-primary-button" href="/">
                  Find creators
                </Link>
                <Link className="feed-ghost-button" href="/feed">
                  Back to For You
                </Link>
              </div>
            </article>
          }
          feedCards={feedCards}
          redirectTarget={redirectTarget}
        />
      </section>
    </main>
  );
}
