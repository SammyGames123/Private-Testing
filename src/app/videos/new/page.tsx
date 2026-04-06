import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/lib/profiles";
import { createVideo } from "../actions";
import { VideoUploadForm } from "./video-upload-form";

type SearchParams = Record<string, string | string[] | undefined>;

function getStringParam(
  searchParams: SearchParams,
  key: "success" | "error",
) {
  return typeof searchParams[key] === "string" ? searchParams[key] : "";
}

export default async function NewVideoPage(props: {
  searchParams: Promise<SearchParams>;
}) {
  const searchParams = await props.searchParams;
  const success = getStringParam(searchParams, "success");
  const error = getStringParam(searchParams, "error");
  const { user, profile } = await getCurrentProfile();

  if (!user) {
    redirect("/auth/login");
  }

  return (
    <main className="min-h-screen bg-[linear-gradient(135deg,_#f8f1e7_0%,_#efe4d5_100%)] px-4 py-8 text-[var(--ink)]">
      <div className="mx-auto max-w-6xl space-y-6">
        <section className="rounded-[32px] border border-black/10 bg-white/78 p-6 shadow-[0_24px_70px_rgba(74,49,29,0.12)]">
          <div className="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <p className="eyebrow">Creator studio</p>
              <h1 className="text-5xl font-semibold tracking-[-0.06em]">
                Publish a video or photo
              </h1>
              <p className="mt-4 max-w-2xl text-base leading-7 text-[var(--muted)]">
                This first version saves real metadata to Supabase using the
                `videos` and `video_tags` tables. Upload a file from your device
                or paste a public media URL if you prefer.
              </p>
            </div>

            <Link
              className="rounded-2xl border border-black/10 bg-white px-4 py-3 font-semibold"
              href="/dashboard"
            >
              Back to dashboard
            </Link>
          </div>
        </section>

        <section className="grid gap-6 lg:grid-cols-[minmax(0,1.1fr)_340px]">
          <section className="rounded-[32px] border border-black/10 bg-white/82 p-6 shadow-[0_24px_70px_rgba(74,49,29,0.12)]">
            <form action={createVideo} className="space-y-5">
              <VideoUploadForm userId={user.id} />

              <div>
                <label className="mb-2 block text-sm font-semibold" htmlFor="title">
                  Title
                </label>
                <input
                  className="w-full rounded-2xl border border-black/10 bg-white px-4 py-3 outline-none"
                  id="title"
                  name="title"
                  placeholder="Neon tram at 2AM"
                  required
                />
              </div>

              <div>
                <label className="mb-2 block text-sm font-semibold" htmlFor="caption">
                  Caption
                </label>
                <textarea
                  className="min-h-28 w-full rounded-2xl border border-black/10 bg-white px-4 py-3 outline-none"
                  id="caption"
                  name="caption"
                  placeholder="Tell people what makes this clip worth watching."
                />
              </div>

              <div className="grid gap-5 md:grid-cols-2">
                <div>
                  <label className="mb-2 block text-sm font-semibold" htmlFor="category">
                    Category
                  </label>
                  <input
                    className="w-full rounded-2xl border border-black/10 bg-white px-4 py-3 outline-none"
                    id="category"
                    name="category"
                    placeholder="travel"
                  />
                </div>

                <div>
                  <label
                    className="mb-2 block text-sm font-semibold"
                    htmlFor="duration_seconds"
                  >
                    Duration (seconds)
                  </label>
                  <input
                    className="w-full rounded-2xl border border-black/10 bg-white px-4 py-3 outline-none"
                    id="duration_seconds"
                    min="0"
                    name="duration_seconds"
                    placeholder="18"
                    type="number"
                  />
                </div>
              </div>

              <div>
                <label
                  className="mb-2 block text-sm font-semibold"
                  htmlFor="playback_url"
                >
                  Or paste media URL
                </label>
                <input
                  className="w-full rounded-2xl border border-black/10 bg-white px-4 py-3 outline-none"
                  id="playback_url"
                  name="playback_url"
                  placeholder="https://...mp4 or https://...jpg"
                  type="url"
                />
              </div>

              <div>
                <label
                  className="mb-2 block text-sm font-semibold"
                  htmlFor="thumbnail_url"
                >
                  Thumbnail URL
                </label>
                <input
                  className="w-full rounded-2xl border border-black/10 bg-white px-4 py-3 outline-none"
                  id="thumbnail_url"
                  name="thumbnail_url"
                  placeholder="https://...jpg"
                  type="url"
                />
              </div>

              <div className="grid gap-5 md:grid-cols-2">
                <div>
                  <label className="mb-2 block text-sm font-semibold" htmlFor="tags">
                    Tags
                  </label>
                  <input
                    className="w-full rounded-2xl border border-black/10 bg-white px-4 py-3 outline-none"
                    id="tags"
                    name="tags"
                    placeholder="music, travel, city"
                  />
                </div>

                <div>
                  <label className="mb-2 block text-sm font-semibold" htmlFor="visibility">
                    Visibility
                  </label>
                  <select
                    className="w-full rounded-2xl border border-black/10 bg-white px-4 py-3 outline-none"
                    defaultValue="public"
                    id="visibility"
                    name="visibility"
                  >
                    <option value="public">Public</option>
                    <option value="unlisted">Unlisted</option>
                    <option value="private">Private</option>
                  </select>
                </div>
              </div>

              <button
                className="w-full rounded-2xl bg-[var(--accent)] px-4 py-3 font-semibold text-white"
                type="submit"
              >
                Publish video
              </button>
            </form>

            {success ? (
              <p className="mt-4 rounded-2xl bg-emerald-50 px-4 py-3 text-sm text-emerald-700">
                {success}
              </p>
            ) : null}

            {error ? (
              <p className="mt-4 rounded-2xl bg-red-50 px-4 py-3 text-sm text-red-700">
                {error}
              </p>
            ) : null}
          </section>

          <aside className="space-y-6">
            <section className="rounded-[32px] border border-black/10 bg-white/78 p-6 shadow-[0_24px_70px_rgba(74,49,29,0.12)]">
              <p className="eyebrow">Publishing as</p>
              <div className="mt-4 space-y-4">
                <article className="studio-panel">
                  <strong className="block text-base text-[var(--ink)]">
                    {profile?.display_name ?? profile?.username ?? "Creator"}
                  </strong>
                  <p className="mt-2 text-sm leading-6 text-[var(--muted)]">
                    @{profile?.username ?? "creator"}
                  </p>
                </article>
                <article className="studio-panel">
                  <strong className="block text-base text-[var(--ink)]">Current workflow</strong>
                  <p className="mt-2 text-sm leading-6 text-[var(--muted)]">
                    You can now upload a real video file or still paste a public
                    photo and still paste a public media URL if you prefer.
                  </p>
                </article>
              </div>
            </section>

            <section className="rounded-[32px] border border-black/10 bg-white/78 p-6 shadow-[0_24px_70px_rgba(74,49,29,0.12)]">
              <p className="eyebrow">Good first test</p>
              <div className="mt-4 space-y-3 text-sm leading-6 text-[var(--muted)]">
                <p>Select a real video or photo file from your device.</p>
                <p>Use a few tags like `travel, music, city`.</p>
                <p>Run the storage SQL once if upload says the bucket or policy is missing.</p>
              </div>
            </section>
          </aside>
        </section>
      </div>
    </main>
  );
}
