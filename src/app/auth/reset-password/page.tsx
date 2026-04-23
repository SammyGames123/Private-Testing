import { updatePassword } from "../actions";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function ResetPasswordPage(props: {
  searchParams: Promise<SearchParams>;
}) {
  const searchParams = await props.searchParams;
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
        <h1>Choose a new password</h1>
        <p className="auth-subtitle">
          Set a new password for your account, then you&apos;ll be sent back to admin.
        </p>

        <form action={updatePassword} className="auth-form">
          <input name="next" type="hidden" value={next} />

          <div className="auth-field">
            <label htmlFor="password">New password</label>
            <input
              autoComplete="new-password"
              id="password"
              minLength={8}
              name="password"
              placeholder="At least 8 characters"
              required
              type="password"
            />
          </div>

          <div className="auth-field">
            <label htmlFor="confirmPassword">Confirm password</label>
            <input
              autoComplete="new-password"
              id="confirmPassword"
              minLength={8}
              name="confirmPassword"
              placeholder="Repeat password"
              required
              type="password"
            />
          </div>

          <button className="auth-submit" type="submit">
            Update password
          </button>
        </form>

        {error ? (
          <p className="auth-message auth-message-error">{error}</p>
        ) : null}
      </div>
    </main>
  );
}
