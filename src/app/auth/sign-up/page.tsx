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
    <main className="auth-shell">
      <div className="auth-card">
        <p className="auth-logo">Pulse</p>
        <h1>Create your account</h1>
        <p className="auth-subtitle">
          Join Pulse to discover and share videos
        </p>

        <form action={signup} className="auth-form">
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
              minLength={6}
              name="password"
              placeholder="Minimum 6 characters"
              required
              type="password"
            />
          </div>

          <button className="auth-submit" type="submit">
            Create account
          </button>
        </form>

        {message ? (
          <p className="auth-message auth-message-success">{message}</p>
        ) : null}

        {error ? (
          <p className="auth-message auth-message-error">{error}</p>
        ) : null}

        <p className="auth-footer">
          Already have an account?{" "}
          <Link href="/auth/login">Sign in</Link>
        </p>
      </div>
    </main>
  );
}
