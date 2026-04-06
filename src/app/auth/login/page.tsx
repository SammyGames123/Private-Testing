import Link from "next/link";
import { login } from "../actions";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function LoginPage(props: {
  searchParams: Promise<SearchParams>;
}) {
  const searchParams = await props.searchParams;
  const message =
    typeof searchParams.success === "string" ? searchParams.success : "";
  const error =
    typeof searchParams.error === "string" ? searchParams.error : "";

  return (
    <main className="auth-shell">
      <div className="auth-card">
        <p className="auth-logo">Pulse</p>
        <h1>Welcome back</h1>
        <p className="auth-subtitle">
          Sign in to your account to continue
        </p>

        <form action={login} className="auth-form">
          <div className="auth-field">
            <label htmlFor="email">Email</label>
            <input
              id="email"
              name="email"
              placeholder="you@example.com"
              required
              type="email"
            />
          </div>

          <div className="auth-field">
            <label htmlFor="password">Password</label>
            <input
              id="password"
              name="password"
              placeholder="Your password"
              required
              type="password"
            />
          </div>

          <button className="auth-submit" type="submit">
            Sign in
          </button>
        </form>

        {message ? (
          <p className="auth-message auth-message-success">{message}</p>
        ) : null}

        {error ? (
          <p className="auth-message auth-message-error">{error}</p>
        ) : null}

        <p className="auth-footer">
          Don&apos;t have an account?{" "}
          <Link href="/auth/sign-up">Sign up</Link>
        </p>
      </div>
    </main>
  );
}
