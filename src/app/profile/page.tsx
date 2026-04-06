import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/lib/profiles";
import { saveProfile } from "./actions";

type SearchParams = Record<string, string | string[] | undefined>;

function getStringParam(
  searchParams: SearchParams,
  key: "success" | "error",
) {
  return typeof searchParams[key] === "string" ? searchParams[key] : "";
}

export default async function ProfilePage(props: {
  searchParams: Promise<SearchParams>;
}) {
  const searchParams = await props.searchParams;
  const success = getStringParam(searchParams, "success");
  const error = getStringParam(searchParams, "error");
  const { user, profile } = await getCurrentProfile();

  if (!user) {
    redirect("/auth/login");
  }

  const interests = profile?.interests?.join(", ") ?? "";

  return (
    <main className="min-h-screen bg-[linear-gradient(135deg,_#f8f1e7_0%,_#efe4d5_100%)] px-4 py-8 text-[var(--ink)]">
      <div className="mx-auto max-w-5xl space-y-6">
        <section className="rounded-[32px] border border-black/10 bg-white/78 p-6 shadow-[0_24px_70px_rgba(74,49,29,0.12)]">
          <div className="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <p className="eyebrow">Profile editor</p>
              <h1 className="text-5xl font-semibold tracking-[-0.06em]">
                Shape your creator identity
              </h1>
              <p className="mt-4 max-w-2xl text-base leading-7 text-[var(--muted)]">
                Update your public profile so the app can use it for feed cards,
                follows, comments, and creator pages.
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
            <form action={saveProfile} className="space-y-5">
              <div>
                <label
                  className="mb-2 block text-sm font-semibold"
                  htmlFor="display_name"
                >
                  Display name
                </label>
                <input
                  className="w-full rounded-2xl border border-black/10 bg-white px-4 py-3 outline-none"
                  defaultValue={profile?.display_name ?? ""}
                  id="display_name"
                  name="display_name"
                  placeholder="Sammy Rivers"
                />
              </div>

              <div>
                <label className="mb-2 block text-sm font-semibold" htmlFor="username">
                  Username
                </label>
                <input
                  className="w-full rounded-2xl border border-black/10 bg-white px-4 py-3 outline-none"
                  defaultValue={profile?.username ?? ""}
                  id="username"
                  name="username"
                  placeholder="sammy"
                />
                <p className="mt-2 text-sm text-[var(--muted)]">
                  Letters, numbers, and underscores work best.
                </p>
              </div>

              <div>
                <label className="mb-2 block text-sm font-semibold" htmlFor="bio">
                  Bio
                </label>
                <textarea
                  className="min-h-32 w-full rounded-2xl border border-black/10 bg-white px-4 py-3 outline-none"
                  defaultValue={profile?.bio ?? ""}
                  id="bio"
                  name="bio"
                  placeholder="Builder, editor, and all-night idea collector."
                />
              </div>

              <div>
                <label className="mb-2 block text-sm font-semibold" htmlFor="interests">
                  Interests
                </label>
                <input
                  className="w-full rounded-2xl border border-black/10 bg-white px-4 py-3 outline-none"
                  defaultValue={interests}
                  id="interests"
                  name="interests"
                  placeholder="music, travel, food, education"
                />
                <p className="mt-2 text-sm text-[var(--muted)]">
                  Comma-separated. These will help with recommendations later.
                </p>
              </div>

              <button
                className="w-full rounded-2xl bg-[var(--accent)] px-4 py-3 font-semibold text-white"
                type="submit"
              >
                Save profile
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
              <p className="eyebrow">Current state</p>
              <div className="mt-4 space-y-4">
                <article className="studio-panel">
                  <strong className="block text-base text-[var(--ink)]">Email</strong>
                  <p className="mt-2 text-sm leading-6 text-[var(--muted)]">
                    {user.email}
                  </p>
                </article>
                <article className="studio-panel">
                  <strong className="block text-base text-[var(--ink)]">Username</strong>
                  <p className="mt-2 text-sm leading-6 text-[var(--muted)]">
                    {profile?.username ?? "Not set"}
                  </p>
                </article>
                <article className="studio-panel">
                  <strong className="block text-base text-[var(--ink)]">Interests</strong>
                  <p className="mt-2 text-sm leading-6 text-[var(--muted)]">
                    {interests || "Not set"}
                  </p>
                </article>
              </div>
            </section>

            <section className="rounded-[32px] border border-black/10 bg-white/78 p-6 shadow-[0_24px_70px_rgba(74,49,29,0.12)]">
              <p className="eyebrow">What this unlocks</p>
              <div className="mt-4 space-y-3 text-sm leading-6 text-[var(--muted)]">
                <p>Creator cards can show your real name and bio.</p>
                <p>Recommended feeds can use your interests later.</p>
                <p>Comments, follows, and messages can point to your profile.</p>
              </div>
            </section>
          </aside>
        </section>
      </div>
    </main>
  );
}
