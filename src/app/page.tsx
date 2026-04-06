/* eslint-disable @next/next/no-img-element */
import Link from "next/link";
import { signOut } from "@/app/auth/actions";
import { addComment, toggleLike } from "@/app/engagement/actions";
import { toggleFollow } from "@/app/follows/actions";
import { inferMediaKind } from "@/lib/media";
import { createClient } from "@/lib/supabase/server";
import { getHomeData } from "@/lib/feed";
import {
  algorithmSignals,
  threads,
} from "@/lib/demo-data";

const productSteps = [
  {
    title: "Auth and profiles",
    copy: "Supabase Auth, onboarding, usernames, avatars, and profile metadata.",
  },
  {
    title: "Video pipeline",
    copy: "Cloudflare Stream or Mux for upload, playback, thumbnails, and encoding.",
  },
  {
    title: "Social graph",
    copy: "Tables for follows, likes, comments, watch events, and saved posts.",
  },
  {
    title: "Recommendations",
    copy: "Start with SQL scoring, then grow into event-driven ranking as usage grows.",
  },
];

const launchTracks = [
  "For You feed",
  "Following feed",
  "Creator studio",
  "Comments and likes",
  "Followers and following",
  "Direct messages",
];

export default async function Home() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const homeData = await getHomeData();

  const feedCards =
    homeData.feed ??
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
      likedByCurrentUser: false,
      followedCreatorByCurrentUser: false,
      recentComments: [],
    }));

  const creatorCards =
    homeData.creators ?? homeData.fallbackCreators.map((creator) => ({
      id: creator.id,
      name: creator.name,
      handle: creator.handle,
      niche: creator.niche,
      followers: creator.followers,
      blurb: creator.blurb,
      followedByCurrentUser: false,
    }));

  return (
    <main className="min-h-screen bg-[radial-gradient(circle_at_top_left,_rgba(255,138,92,0.25),_transparent_28%),radial-gradient(circle_at_80%_20%,_rgba(16,114,102,0.18),_transparent_24%),linear-gradient(135deg,_#f8f1e7_0%,_#efe4d5_100%)] text-[var(--ink)]">
      <div className="mx-auto flex w-full max-w-7xl flex-col gap-6 px-4 py-6 md:px-6 xl:flex-row">
        <aside className="top-6 flex h-fit shrink-0 flex-col gap-4 rounded-[28px] border border-black/10 bg-white/70 p-5 shadow-[0_24px_70px_rgba(74,49,29,0.12)] backdrop-blur md:sticky md:w-[320px]">
          <div>
            <p className="eyebrow">Production foundation</p>
            <h1 className="text-4xl font-semibold tracking-[-0.06em]">
              PulsePlay
            </h1>
            <p className="mt-3 text-sm leading-6 text-[var(--muted)]">
              A real Next.js foundation for the short-form video product you
              want to build next.
            </p>
          </div>

          <section className="rounded-[22px] border border-black/8 bg-white/65 p-4">
            <p className="eyebrow">MVP scope</p>
            <div className="flex flex-wrap gap-2">
              {launchTracks.map((track) => (
                <span className="pill" key={track}>
                  {track}
                </span>
              ))}
            </div>
          </section>

          <section className="rounded-[22px] border border-black/8 bg-white/65 p-4">
            <p className="eyebrow">Algorithm inputs</p>
            <div className="flex flex-wrap gap-2">
              {algorithmSignals.map((signal) => (
                <span className="pill pill-alt" key={signal}>
                  {signal}
                </span>
              ))}
            </div>
          </section>

          <section className="rounded-[22px] border border-black/8 bg-white/65 p-4">
            <p className="eyebrow">Next backend</p>
            <ul className="space-y-3 text-sm text-[var(--muted)]">
              <li>Next.js App Router for product UI and server actions.</li>
              <li>Supabase for auth, Postgres, realtime, and row-level security.</li>
              <li>Mux or Cloudflare Stream for video uploads and playback.</li>
              <li>Vercel for hosting and preview deployments.</li>
            </ul>
          </section>
        </aside>

        <div className="flex min-w-0 flex-1 flex-col gap-6">
          <section className="rounded-[32px] border border-black/10 bg-white/72 p-6 shadow-[0_24px_70px_rgba(74,49,29,0.12)] backdrop-blur">
            <div className="flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
              <div className="max-w-3xl">
                <p className="eyebrow">Next.js starter</p>
                <h2 className="max-w-3xl text-4xl font-semibold tracking-[-0.06em] sm:text-6xl">
                  Build the real version with a product-ready shell instead of a
                  blank template.
                </h2>
              </div>
              <div className="flex flex-wrap gap-2 lg:max-w-sm lg:justify-end">
                <span className="pill">Auth</span>
                <span className="pill">Uploads</span>
                <span className="pill">Profiles</span>
                <span className="pill">Social graph</span>
                <span className="pill">Recommendation feed</span>
              </div>
            </div>

            <div className="mt-6 flex flex-wrap items-center gap-3">
              {user ? (
                <>
                  <Link
                    className="rounded-2xl bg-[var(--accent-2)] px-4 py-3 font-semibold text-white"
                    href="/feed"
                  >
                    Open feed
                  </Link>
                  <Link
                    className="rounded-2xl bg-[var(--accent)] px-4 py-3 font-semibold text-white"
                    href="/dashboard"
                  >
                    Open dashboard
                  </Link>
                  <form action={signOut}>
                    <button
                      className="rounded-2xl border border-black/10 bg-white px-4 py-3 font-semibold"
                      type="submit"
                    >
                      Sign out
                    </button>
                  </form>
                  <span className="text-sm text-[var(--muted)]">
                    Signed in as {user.email}
                  </span>
                </>
              ) : (
                <>
                  <Link
                    className="rounded-2xl bg-[var(--accent)] px-4 py-3 font-semibold text-white"
                    href="/auth/sign-up"
                  >
                    Create account
                  </Link>
                  <Link
                    className="rounded-2xl border border-black/10 bg-white px-4 py-3 font-semibold"
                    href="/auth/login"
                  >
                    Sign in
                  </Link>
                </>
              )}
            </div>

            {homeData.usedFallback ? (
              <p className="mt-4 text-sm text-[var(--muted)]">
                Live auth is connected. Feed cards are still using fallback demo
                data until you add real videos and creator content in Supabase.
              </p>
            ) : (
              <p className="mt-4 text-sm text-[var(--muted)]">
                This homepage is reading live creators and videos from Supabase.
              </p>
            )}
          </section>

          <section className="grid gap-6 xl:grid-cols-[minmax(0,1.45fr)_minmax(300px,0.85fr)]">
            <div className="space-y-6">
              <section className="rounded-[28px] border border-black/10 bg-white/72 p-5 shadow-[0_24px_70px_rgba(74,49,29,0.12)] backdrop-blur">
                <div className="mb-4 flex items-end justify-between gap-4">
                  <div>
                    <p className="eyebrow">Feed preview</p>
                    <h3 className="text-2xl font-semibold tracking-[-0.05em]">
                      Recommended for this viewer
                    </h3>
                  </div>
                  <span className="pill">Ranked server-side first</span>
                </div>

                <div className="space-y-4">
                  {feedCards.map((post) => (
                    <article
                      className="grid gap-4 rounded-[24px] border border-black/8 bg-white/70 p-4 lg:grid-cols-[260px_minmax(0,1fr)]"
                      key={post.id}
                    >
                      {post.playbackUrl ? (
                        inferMediaKind(post.playbackUrl) === "image" ? (
                          <div className="overflow-hidden rounded-[22px] border border-black/8 bg-white">
                            <img
                              alt={post.title}
                              className="h-full min-h-[420px] w-full object-cover"
                              src={post.playbackUrl}
                            />
                          </div>
                        ) : (
                          <div className="overflow-hidden rounded-[22px] border border-black/8 bg-black">
                            <video
                              className="h-full min-h-[420px] w-full object-cover"
                              controls
                              playsInline
                              poster={post.thumbnailUrl ?? undefined}
                              src={post.playbackUrl}
                            />
                          </div>
                        )
                      ) : (
                        <div className="flex aspect-[9/14] items-end rounded-[22px] bg-[linear-gradient(180deg,_rgba(14,20,24,0.14),_rgba(14,20,24,0.54)),linear-gradient(135deg,_#f7b393,_#0f7c6d)] p-4 text-white">
                          <div>
                            <p className="text-xs uppercase tracking-[0.25em] text-white/70">
                              {post.category ?? "Video"}
                            </p>
                            <h4 className="mt-2 text-2xl font-semibold tracking-[-0.05em]">
                              {post.title}
                            </h4>
                          </div>
                        </div>
                      )}

                      <div className="flex flex-col gap-4">
                        <div className="flex flex-wrap items-start justify-between gap-3">
                          <div>
                            <p className="text-sm text-[var(--muted)]">
                              {(post.creatorHandle || "@creator") +
                                " - " +
                                post.age +
                                " - " +
                                post.views +
                                " views"}
                            </p>
                            <p className="mt-2 text-base text-[var(--muted)]">
                              {post.caption ?? "No caption yet."}
                            </p>
                          </div>
                          <span className="pill pill-score">{post.score} match</span>
                        </div>

                        <div className="flex flex-wrap gap-2">
                          {post.tags.map((tag) => (
                            <span className="pill" key={tag}>
                              #{tag}
                            </span>
                          ))}
                        </div>

                        <div className="grid gap-3 text-sm text-[var(--muted)] sm:grid-cols-3">
                          <div className="stat-box">
                            <strong>{post.likes}</strong>
                            <span>likes</span>
                          </div>
                          <div className="stat-box">
                            <strong>{post.comments}</strong>
                            <span>comments</span>
                          </div>
                          <div className="stat-box">
                            <strong>{post.creatorName || "Creator"}</strong>
                            <span>creator</span>
                          </div>
                        </div>

                        {user && homeData.feed ? (
                          <div className="grid gap-3">
                            <div className="flex flex-wrap gap-3">
                              <form action={toggleLike}>
                                <input name="video_id" type="hidden" value={post.id} />
                                <input name="redirect_to" type="hidden" value="/" />
                                <button
                                  className="rounded-2xl border border-black/10 bg-white px-4 py-3 text-sm font-semibold"
                                  type="submit"
                                >
                                  {post.likedByCurrentUser ? "Unlike" : "Like"}
                                </button>
                              </form>
                              {post.creatorId ? (
                                <form action={toggleFollow}>
                                  <input
                                    name="target_user_id"
                                    type="hidden"
                                    value={post.creatorId}
                                  />
                                  <input
                                    name="redirect_to"
                                    type="hidden"
                                    value="/"
                                  />
                                  <button
                                    className="rounded-2xl border border-black/10 bg-white px-4 py-3 text-sm font-semibold"
                                    type="submit"
                                  >
                                    {post.followedCreatorByCurrentUser
                                      ? "Following"
                                      : "Follow creator"}
                                  </button>
                                </form>
                              ) : null}
                            </div>

                            <form action={addComment} className="flex flex-col gap-3">
                              <input name="video_id" type="hidden" value={post.id} />
                              <input name="redirect_to" type="hidden" value="/" />
                              <textarea
                                className="min-h-24 w-full rounded-2xl border border-black/10 bg-white px-4 py-3 text-sm outline-none"
                                name="body"
                                placeholder="Write a comment"
                              />
                              <button
                                className="rounded-2xl bg-[var(--accent)] px-4 py-3 text-sm font-semibold text-white"
                                type="submit"
                              >
                                Post comment
                              </button>
                            </form>

                            {post.recentComments.length > 0 ? (
                              <div className="grid gap-3">
                                {post.recentComments.map((comment) => (
                                  <article
                                    className="rounded-[20px] border border-black/8 bg-white/75 p-4"
                                    key={comment.id}
                                  >
                                    <strong className="text-sm text-[var(--ink)]">
                                      {comment.authorHandle}
                                    </strong>
                                    <p className="mt-2 text-sm leading-6 text-[var(--muted)]">
                                      {comment.body}
                                    </p>
                                  </article>
                                ))}
                              </div>
                            ) : (
                              <p className="text-sm text-[var(--muted)]">
                                No comments yet. Start the conversation.
                              </p>
                            )}
                          </div>
                        ) : null}
                      </div>
                    </article>
                  ))}
                </div>
              </section>

              <section className="rounded-[28px] border border-black/10 bg-white/72 p-5 shadow-[0_24px_70px_rgba(74,49,29,0.12)] backdrop-blur">
                <div className="mb-4">
                  <p className="eyebrow">Creator studio</p>
                  <h3 className="text-2xl font-semibold tracking-[-0.05em]">
                    First upload flow to build
                  </h3>
                </div>

                <div className="grid gap-4 md:grid-cols-2">
                  <div className="studio-panel">
                    <p className="text-sm font-semibold uppercase tracking-[0.2em] text-[var(--accent-2)]">
                      Input
                    </p>
                    <ul className="mt-3 space-y-3 text-sm leading-6 text-[var(--muted)]">
                      <li>Video upload</li>
                      <li>Title and caption</li>
                      <li>Tags and category</li>
                      <li>Thumbnail selection</li>
                    </ul>
                  </div>
                  <div className="studio-panel">
                    <p className="text-sm font-semibold uppercase tracking-[0.2em] text-[var(--accent-2)]">
                      V2 editing
                    </p>
                    <ul className="mt-3 space-y-3 text-sm leading-6 text-[var(--muted)]">
                      <li>Trim start and end</li>
                      <li>Playback speed presets</li>
                      <li>Cover text overlays</li>
                      <li>Draft saving</li>
                    </ul>
                  </div>
                </div>
              </section>
            </div>

            <div className="space-y-6">
              <section className="rounded-[28px] border border-black/10 bg-white/72 p-5 shadow-[0_24px_70px_rgba(74,49,29,0.12)] backdrop-blur">
                <p className="eyebrow">Suggested creators</p>
                <h3 className="text-2xl font-semibold tracking-[-0.05em]">
                  Follow graph starter
                </h3>
                <div className="mt-4 space-y-3">
                  {creatorCards.map((creator) => (
                    <article
                      className="rounded-[20px] border border-black/8 bg-white/70 p-4"
                      key={creator.id}
                    >
                      <div className="flex items-start justify-between gap-4">
                        <div>
                          <h4 className="text-lg font-semibold">{creator.name}</h4>
                          <p className="text-sm text-[var(--muted)]">
                            {creator.handle} - {creator.niche}
                          </p>
                        </div>
                        <span className="pill">{creator.followers}</span>
                      </div>
                      <p className="mt-3 text-sm leading-6 text-[var(--muted)]">
                        {creator.blurb}
                      </p>
                      {user && homeData.creators ? (
                        <form action={toggleFollow} className="mt-4">
                          <input
                            name="target_user_id"
                            type="hidden"
                            value={creator.id}
                          />
                          <input name="redirect_to" type="hidden" value="/" />
                          <button
                            className="rounded-2xl border border-black/10 bg-white px-4 py-3 text-sm font-semibold"
                            type="submit"
                          >
                            {creator.followedByCurrentUser ? "Following" : "Follow"}
                          </button>
                        </form>
                      ) : null}
                    </article>
                  ))}
                </div>
              </section>

              <section className="rounded-[28px] border border-black/10 bg-white/72 p-5 shadow-[0_24px_70px_rgba(74,49,29,0.12)] backdrop-blur">
                <p className="eyebrow">Inbox</p>
                <h3 className="text-2xl font-semibold tracking-[-0.05em]">
                  Direct message foundation
                </h3>
                <Link
                  className="mt-4 inline-flex rounded-2xl bg-[var(--accent-2)] px-4 py-3 text-sm font-semibold text-white"
                  href="/messages"
                >
                  Open inbox
                </Link>
                <div className="mt-4 space-y-3">
                  {threads.map((thread) => (
                    <article
                      className="rounded-[20px] border border-black/8 bg-white/70 p-4"
                      key={thread.id}
                    >
                      <div className="flex items-start justify-between gap-4">
                        <strong>{thread.withUser}</strong>
                        <span className="text-sm text-[var(--muted)]">{thread.age}</span>
                      </div>
                      <p className="mt-2 text-sm leading-6 text-[var(--muted)]">
                        {thread.preview}
                      </p>
                    </article>
                  ))}
                </div>
              </section>

              <section className="rounded-[28px] border border-black/10 bg-white/72 p-5 shadow-[0_24px_70px_rgba(74,49,29,0.12)] backdrop-blur">
                <p className="eyebrow">Implementation order</p>
                <div className="mt-4 space-y-3">
                  {productSteps.map((step, index) => (
                    <article
                      className="rounded-[20px] border border-black/8 bg-white/70 p-4"
                      key={step.title}
                    >
                      <p className="text-sm uppercase tracking-[0.22em] text-[var(--accent-2)]">
                        Step {index + 1}
                      </p>
                      <h4 className="mt-2 text-lg font-semibold">{step.title}</h4>
                      <p className="mt-2 text-sm leading-6 text-[var(--muted)]">
                        {step.copy}
                      </p>
                    </article>
                  ))}
                </div>
              </section>
            </div>
          </section>
        </div>
      </div>
    </main>
  );
}
