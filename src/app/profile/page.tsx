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

const fieldStyle = {
  width: "100%",
  padding: "0.75rem 0.9rem",
  borderRadius: 12,
  background: "rgba(255,255,255,0.06)",
  border: "1px solid rgba(255,255,255,0.1)",
  color: "white",
  fontSize: "0.95rem",
  outline: "none",
} as const;

const labelStyle = {
  display: "block",
  color: "rgba(255,255,255,0.75)",
  fontSize: "0.78rem",
  fontWeight: 600,
  letterSpacing: "0.02em",
  textTransform: "uppercase" as const,
  marginBottom: "0.4rem",
};

const helperStyle = {
  marginTop: "0.45rem",
  color: "rgba(255,255,255,0.45)",
  fontSize: "0.75rem",
  lineHeight: 1.4,
};

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
    <main
      style={{
        minHeight: "100vh",
        background: "black",
        color: "white",
        padding:
          "calc(env(safe-area-inset-top, 0px) + 1rem) 1rem calc(env(safe-area-inset-bottom, 0px) + 6rem)",
      }}
    >
      {/* Header */}
      <div
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          marginBottom: "1.5rem",
        }}
      >
        <Link
          aria-label="Back to profile"
          href="/dashboard"
          style={{
            width: 40,
            height: 40,
            borderRadius: "50%",
            background: "rgba(255,255,255,0.08)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            color: "white",
            textDecoration: "none",
          }}
        >
          <svg
            aria-hidden="true"
            fill="none"
            height="22"
            viewBox="0 0 24 24"
            width="22"
          >
            <path
              d="M15 6 9 12l6 6"
              stroke="currentColor"
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth="2"
            />
          </svg>
        </Link>
        <h1
          style={{
            fontSize: "1.05rem",
            fontWeight: 700,
            margin: 0,
          }}
        >
          Edit profile
        </h1>
        <div style={{ width: 40 }} aria-hidden="true" />
      </div>

      {/* Status messages */}
      {success ? (
        <p
          style={{
            margin: "0 0 1rem",
            padding: "0.75rem 1rem",
            borderRadius: 12,
            background: "rgba(34,197,94,0.12)",
            border: "1px solid rgba(34,197,94,0.3)",
            color: "#4ade80",
            fontSize: "0.85rem",
          }}
        >
          {success}
        </p>
      ) : null}

      {error ? (
        <p
          style={{
            margin: "0 0 1rem",
            padding: "0.75rem 1rem",
            borderRadius: 12,
            background: "rgba(239,68,68,0.12)",
            border: "1px solid rgba(239,68,68,0.3)",
            color: "#f87171",
            fontSize: "0.85rem",
          }}
        >
          {error}
        </p>
      ) : null}

      <form
        action={saveProfile}
        style={{
          display: "flex",
          flexDirection: "column",
          gap: "1.25rem",
        }}
      >
        <div>
          <label htmlFor="display_name" style={labelStyle}>
            Display name
          </label>
          <input
            defaultValue={profile?.display_name ?? ""}
            id="display_name"
            name="display_name"
            placeholder="Sammy Rivers"
            style={fieldStyle}
            type="text"
          />
        </div>

        <div>
          <label htmlFor="username" style={labelStyle}>
            Username
          </label>
          <input
            defaultValue={profile?.username ?? ""}
            id="username"
            name="username"
            placeholder="sammy"
            style={fieldStyle}
            type="text"
          />
          <p style={helperStyle}>
            Letters, numbers, and underscores work best.
          </p>
        </div>

        <div>
          <label htmlFor="bio" style={labelStyle}>
            Bio
          </label>
          <textarea
            defaultValue={profile?.bio ?? ""}
            id="bio"
            name="bio"
            placeholder="Builder, editor, and all-night idea collector."
            rows={4}
            style={{ ...fieldStyle, resize: "vertical", minHeight: 110 }}
          />
        </div>

        <div>
          <label htmlFor="interests" style={labelStyle}>
            Interests
          </label>
          <input
            defaultValue={interests}
            id="interests"
            name="interests"
            placeholder="music, travel, food, education"
            style={fieldStyle}
            type="text"
          />
          <p style={helperStyle}>
            Comma-separated. These help tune your recommendations.
          </p>
        </div>

        <div
          style={{
            marginTop: "0.25rem",
            padding: "0.9rem 1rem",
            borderRadius: 12,
            background: "rgba(255,255,255,0.04)",
            border: "1px solid rgba(255,255,255,0.08)",
          }}
        >
          <p
            style={{
              margin: 0,
              color: "rgba(255,255,255,0.55)",
              fontSize: "0.72rem",
              textTransform: "uppercase",
              letterSpacing: "0.05em",
              fontWeight: 600,
            }}
          >
            Email
          </p>
          <p
            style={{
              margin: "0.35rem 0 0",
              color: "white",
              fontSize: "0.9rem",
              wordBreak: "break-all",
            }}
          >
            {user.email}
          </p>
        </div>

        <button
          type="submit"
          style={{
            marginTop: "0.5rem",
            width: "100%",
            padding: "0.9rem 1rem",
            borderRadius: 12,
            background: "var(--accent)",
            color: "white",
            fontSize: "0.95rem",
            fontWeight: 700,
            border: "none",
            cursor: "pointer",
          }}
        >
          Save profile
        </button>
      </form>
    </main>
  );
}
