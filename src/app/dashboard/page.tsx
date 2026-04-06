/* eslint-disable @next/next/no-img-element */
import { signOut } from "@/app/auth/actions";
import { inferMediaKind } from "@/lib/media";
import { getCurrentProfile } from "@/lib/profiles";
import { getCurrentUserVideos, toVideoAgeLabel } from "@/lib/videos";
import Link from "next/link";
import { redirect } from "next/navigation";

export default async function DashboardPage() {
  const { user, profile, profileError } = await getCurrentProfile();

  if (!user) {
    redirect("/auth/login");
  }

  const { videos } = await getCurrentUserVideos(user.id);

  return (
    <main className="min-h-screen bg-[linear-gradient(135deg,_#f8f1e7_0%,_#efe4d5_100%)] px-4 py-8 text-[var(--ink)]">
      <div className="mx-auto max-w-6xl space-y-6">
        <section className="rounded-[32px] border border-black/10 bg-white/78 p-6 shadow-[0_24px_70px_rgba(74,49,29,0.12)]">
          <p className="eyebrow">Private dashboard</p>
          <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
            <div>
              <h1 className="text-5xl font-semibold tracking-[-0.06em]">
                You are signed in
              </h1>
              <p className="mt-4 text-base leading-7 text-[var(--muted)]">
                Auth is now working with Supabase cookies and server-side route
                protection.
              </p>
              <p className="mt-3 text-sm text-[var(--muted)]">
                Signed in as <strong className="text-[var(--ink)]">{user.email}</strong>
              </p>
              <p className="mt-2 text-sm text-[var(--muted)]">
                Profile status:{" "}
                <strong className="text-[var(--ink)]">
                  {profile ? "connected" : "waiting for schema setup"}
                </strong>
              </p>
            </div>

            <div className="flex flex-wrap gap-3">
              <Link
                className="rounded-2xl bg-[var(--accent)] px-4 py-3 font-semibold text-white"
                href="/profile"
              >
                Edit profile
              </Link>
              <Link
                className="rounded-2xl border border-black/10 bg-white px-4 py-3 font-semibold"
                href="/messages"
              >
                Inbox
              </Link>
              <Link
                className="rounded-2xl border border-black/10 bg-white px-4 py-3 font-semibold"
                href="/feed"
              >
                Feed
              </Link>
              <Link
                className="rounded-2xl border border-black/10 bg-white px-4 py-3 font-semibold"
                href="/videos/new"
              >
                Upload media
              </Link>
              <form action={signOut}>
                <button
                  className="rounded-2xl border border-black/10 bg-white px-4 py-3 font-semibold"
                  type="submit"
                >
                  Sign out
                </button>
              </form>
            </div>
          </div>
        </section>

        <section className="grid gap-4 md:grid-cols-3">
          <article className="studio-panel">
            <strong className="block text-base text-[var(--ink)]">Profile</strong>
            <p className="mt-2 text-sm leading-6 text-[var(--muted)]">
              {profile
                ? `@${profile.username ?? "creator"} is ready to connect to videos, follows, and comments.`
                : "Run the Supabase SQL schema so the app can create and read profile rows."}
            </p>
          </article>
          <article className="studio-panel">
            <strong className="block text-base text-[var(--ink)]">Then</strong>
            <p className="mt-2 text-sm leading-6 text-[var(--muted)]">
              Replace demo feed data with real Supabase queries.
            </p>
          </article>
          <article className="studio-panel">
            <strong className="block text-base text-[var(--ink)]">After that</strong>
            <p className="mt-2 text-sm leading-6 text-[var(--muted)]">
              Build upload, likes, comments, follows, and messages.
            </p>
          </article>
        </section>

        {profile ? (
          <section className="rounded-[32px] border border-black/10 bg-white/78 p-6 shadow-[0_24px_70px_rgba(74,49,29,0.12)]">
            <p className="eyebrow">Current profile</p>
            <div className="mt-4 grid gap-4 md:grid-cols-3">
              <article className="studio-panel">
                <strong className="block text-base text-[var(--ink)]">Display name</strong>
                <p className="mt-2 text-sm leading-6 text-[var(--muted)]">
                  {profile.display_name ?? "Not set yet"}
                </p>
              </article>
              <article className="studio-panel">
                <strong className="block text-base text-[var(--ink)]">Username</strong>
                <p className="mt-2 text-sm leading-6 text-[var(--muted)]">
                  {profile.username ?? "Not set yet"}
                </p>
              </article>
              <article className="studio-panel">
                <strong className="block text-base text-[var(--ink)]">Bio</strong>
                <p className="mt-2 text-sm leading-6 text-[var(--muted)]">
                  {profile.bio ?? "No bio yet"}
                </p>
              </article>
            </div>
          </section>
        ) : null}

        <section className="rounded-[32px] border border-black/10 bg-white/78 p-6 shadow-[0_24px_70px_rgba(74,49,29,0.12)]">
          <div className="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <p className="eyebrow">Your posts</p>
              <h2 className="text-3xl font-semibold tracking-[-0.05em]">
                Creator uploads
              </h2>
            </div>
            <Link
              className="rounded-2xl bg-[var(--accent)] px-4 py-3 font-semibold text-white"
              href="/videos/new"
            >
              Publish another post
            </Link>
          </div>

          {videos.length > 0 ? (
            <div className="mt-4 grid gap-4 md:grid-cols-2">
              {videos.map((video) => (
                <article className="studio-panel" key={video.id}>
                  {video.playback_url ? (
                    inferMediaKind(video.playback_url) === "image" ? (
                      <img
                        alt={video.title}
                        className="mb-4 aspect-[4/5] w-full rounded-[20px] border border-black/8 object-cover"
                        src={video.playback_url}
                      />
                    ) : (
                      <video
                        className="mb-4 aspect-[4/5] w-full rounded-[20px] border border-black/8 bg-black object-cover"
                        controls
                        muted
                        playsInline
                        src={video.playback_url}
                      />
                    )
                  ) : null}
                  <div className="flex items-start justify-between gap-4">
                    <div>
                      <strong className="block text-base text-[var(--ink)]">
                        {video.title}
                      </strong>
                      <p className="mt-2 text-sm leading-6 text-[var(--muted)]">
                        {(video.category ?? "uncategorized") +
                          " - " +
                          toVideoAgeLabel(video.created_at)}
                      </p>
                    </div>
                    <span className="pill">{video.visibility}</span>
                  </div>
                  <p className="mt-3 text-sm leading-6 text-[var(--muted)]">
                    {video.caption ?? "No caption yet."}
                  </p>
                  <div className="mt-3 flex flex-wrap gap-2">
                    {(video.video_tags ?? []).map((tag) => (
                      <span className="pill" key={tag.tag}>
                        #{tag.tag}
                      </span>
                    ))}
                  </div>
                  {video.playback_url ? (
                    <a
                      className="mt-4 inline-block text-sm font-semibold text-[var(--accent-2)]"
                      href={video.playback_url}
                      rel="noreferrer"
                      target="_blank"
                    >
                      Open playback URL
                    </a>
                  ) : null}
                </article>
              ))}
            </div>
          ) : (
            <p className="mt-4 text-sm leading-7 text-[var(--muted)]">
              You have not published any posts yet. Use the upload button to
              create your first video or photo.
            </p>
          )}
        </section>

        {profileError ? (
          <section className="rounded-[32px] border border-amber-200 bg-amber-50 p-6 text-amber-900 shadow-[0_24px_70px_rgba(74,49,29,0.12)]">
            <p className="eyebrow text-amber-700">Database setup needed</p>
            <p className="mt-3 text-sm leading-7">
              The app can authenticate you, but the `profiles` table is not
              available yet. Run the SQL in `supabase/schema.sql` inside the
              Supabase SQL Editor, then refresh this page.
            </p>
          </section>
        ) : null}
      </div>
    </main>
  );
}
