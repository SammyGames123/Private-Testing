import Link from "next/link";
import { requestPasswordReset } from "../actions";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function ForgotPasswordPage(props: {
  searchParams: Promise<SearchParams>;
}) {
  const searchParams = await props.searchParams;
  const message =
    typeof searchParams.success === "string" ? searchParams.success : "";
  const error =
    typeof searchParams.error === "string" ? searchParams.error : "";
  const next =
    typeof searchParams.next === "string" && searchParams.next.startsWith("/")
      ? searchParams.next
      : "/admin";

  return (
    <main className="auth-shell">
      <div className="auth-card">
        <p className="auth-logo">Spilltop</p>
        <h1>Reset password</h1>
        <p className="auth-subtitle">
          Enter your admin email and we&apos;ll send a secure reset link.
        </p>

        <form action={requestPasswordReset} className="auth-form">
          <input name="next" type="hidden" value={next} />

          <div className="auth-field">
            <label htmlFor="email">Email</label>
            <input
              autoComplete="email"
              defaultValue="support@spilltop.com"
              id="email"
              name="email"
              placeholder="support@spilltop.com"
              required
              type="email"
            />
          </div>

          <button className="auth-submit" type="submit">
            Send reset link
          </button>
        </form>

        {message ? (
          <p className="auth-message auth-message-success">{message}</p>
        ) : null}

        {error ? (
          <p className="auth-message auth-message-error">{error}</p>
        ) : null}

        <p className="auth-footer">
          Remembered it? <Link href={`/auth/login?next=${encodeURIComponent(next)}`}>Back to login</Link>
        </p>
      </div>
    </main>
  );
}
