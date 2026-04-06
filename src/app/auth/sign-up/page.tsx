import Link from "next/link";
import { signup } from "../actions";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function SignUpPage(props: {
  searchParams: Promise<SearchParams>;
}) {
  const searchParams = await props.searchParams;
  const message =
    typeof searchParams.success === "string" ? searchParams.success : "";
  const error =
    typeof searchParams.error === "string" ? searchParams.error : "";

  return (
    <main className="min-h-screen bg-[linear-gradient(135deg,_#f8f1e7_0%,_#efe4d5_100%)] px-4 py-8 text-[var(--ink)]">
      <div className="mx-auto grid max-w-5xl gap-6 lg:grid-cols-[1.1fr_0.9fr]">
        <section className="rounded-[32px] border border-black/10 bg-white/72 p-6 shadow-[0_24px_70px_rgba(74,49,29,0.12)]">
          <p className="eyebrow">Create account</p>
          <h1 className="mt-3 text-5xl font-semibold tracking-[-0.06em]">
            Start building your creator identity
          </h1>
          <p className="mt-4 max-w-xl text-base leading-7 text-[var(--muted)]">
            Sign up with email and password first. Once that works, we can add
            profiles, usernames, avatars, and onboarding flows on top.
          </p>

          <div className="mt-8 grid gap-3 sm:grid-cols-2">
            <div className="studio-panel">
              <strong className="block text-base text-[var(--ink)]">Phase 1</strong>
              <p className="mt-2 text-sm leading-6 text-[var(--muted)]">
                Email and password auth, protected routes, and session-aware UI.
              </p>
            </div>
            <div className="studio-panel">
              <strong className="block text-base text-[var(--ink)]">Phase 2</strong>
              <p className="mt-2 text-sm leading-6 text-[var(--muted)]">
                Public profiles, follows, creator pages, and the real feed.
              </p>
            </div>
          </div>
        </section>

        <section className="rounded-[32px] border border-black/10 bg-white/82 p-6 shadow-[0_24px_70px_rgba(74,49,29,0.12)]">
          <form action={signup} className="space-y-4">
            <div>
              <label className="mb-2 block text-sm font-semibold" htmlFor="email">
                Email
              </label>
              <input
                className="w-full rounded-2xl border border-black/10 bg-white px-4 py-3 outline-none"
                id="email"
                name="email"
                placeholder="you@example.com"
                required
                type="email"
              />
            </div>

            <div>
              <label
                className="mb-2 block text-sm font-semibold"
                htmlFor="password"
              >
                Password
              </label>
              <input
                className="w-full rounded-2xl border border-black/10 bg-white px-4 py-3 outline-none"
                id="password"
                minLength={6}
                name="password"
                placeholder="Minimum 6 characters"
                required
                type="password"
              />
            </div>

            <button
              className="w-full rounded-2xl bg-[var(--accent)] px-4 py-3 font-semibold text-white"
              type="submit"
            >
              Create account
            </button>
          </form>

          {message ? (
            <p className="mt-4 rounded-2xl bg-emerald-50 px-4 py-3 text-sm text-emerald-700">
              {message}
            </p>
          ) : null}

          {error ? (
            <p className="mt-4 rounded-2xl bg-red-50 px-4 py-3 text-sm text-red-700">
              {error}
            </p>
          ) : null}

          <p className="mt-6 text-sm text-[var(--muted)]">
            Already have an account?{" "}
            <Link className="font-semibold text-[var(--accent-2)]" href="/auth/login">
              Sign in
            </Link>
          </p>
        </section>
      </div>
    </main>
  );
}
