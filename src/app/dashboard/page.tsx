/* eslint-disable @next/next/no-img-element */
import { signOut } from "@/app/auth/actions";
import { inferMediaKind } from "@/lib/media";
import { getCurrentProfile } from "@/lib/profiles";
import { getCurrentUserVideos } from "@/lib/videos";
import Link from "next/link";
import { redirect } from "next/navigation";

export default async function DashboardPage() {
  const { user, profile } = await getCurrentProfile();

  if (!user) {
    redirect("/auth/login");
  }

  const { videos } = await getCurrentUserVideos(user.id);

  const displayName = profile?.display_name ?? profile?.username ?? "Creator";
  const handle = profile?.username ? `@${profile.username}` : user.email ?? "";
  const initial = displayName.charAt(0).toUpperCase();

  return (
    <main
      style={{
        minHeight: "100vh",
        background: "black",
        color: "white",
        padding: "1.5rem 1rem 6rem",
      }}
    >
      {/* Header: avatar, name, handle */}
      <section style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: "0.6rem" }}>
        {profile?.avatar_url ? (
          <img
            alt={displayName}
            src={profile.avatar_url}
            style={{
              width: 96,
              height: 96,
              borderRadius: "50%",
              objectFit: "cover",
              marginTop: "1rem",
            }}
          />
        ) : (
          <div
            style={{
              width: 96,
              height: 96,
              borderRadius: "50%",
              background: "rgba(255,255,255,0.08)",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              fontSize: "2.25rem",
              fontWeight: 700,
              color: "rgba(255,255,255,0.7)",
              marginTop: "1rem",
            }}
          >
            {initial}
          </div>
        )}

        <p style={{ fontSize: "1.15rem", fontWeight: 700, margin: 0 }}>
          {displayName}
        </p>
        <p style={{ fontSize: "0.9rem", color: "rgba(255,255,255,0.55)", margin: 0 }}>
          {handle}
        </p>

        {profile?.bio ? (
          <p
            style={{
              fontSize: "0.85rem",
              color: "rgba(255,255,255,0.7)",
              maxWidth: 320,
              textAlign: "center",
              margin: "0.5rem 0 0",
              lineHeight: 1.4,
            }}
          >
            {profile.bio}
          </p>
        ) : null}
      </section>

      {/* Stats row */}
      <section
        style={{
          display: "flex",
          justifyContent: "center",
          gap: "2.5rem",
          marginTop: "1.25rem",
        }}
      >
        <div style={{ textAlign: "center" }}>
          <strong style={{ fontSize: "1.1rem" }}>{videos.length}</strong>
          <p style={{ fontSize: "0.75rem", color: "rgba(255,255,255,0.55)", margin: 0 }}>
            Posts
          </p>
        </div>
      </section>

      {/* Action buttons */}
      <section style={{ display: "flex", gap: "0.6rem", marginTop: "1.25rem", justifyContent: "center" }}>
        <Link
          href="/profile"
          style={{
            flex: "0 1 auto",
            padding: "0.55rem 1.25rem",
            borderRadius: 10,
            background: "rgba(255,255,255,0.1)",
            color: "white",
            fontSize: "0.85rem",
            fontWeight: 600,
            textDecoration: "none",
            border: "1px solid rgba(255,255,255,0.12)",
          }}
        >
          Edit profile
        </Link>
        <form action={signOut} style={{ display: "inline-block" }}>
          <button
            type="submit"
            style={{
              padding: "0.55rem 1.25rem",
              borderRadius: 10,
              background: "rgba(255,255,255,0.1)",
              color: "white",
              fontSize: "0.85rem",
              fontWeight: 600,
              border: "1px solid rgba(255,255,255,0.12)",
              cursor: "pointer",
            }}
          >
            Sign out
          </button>
        </form>
      </section>

      {/* Posts grid */}
      <section style={{ marginTop: "2rem" }}>
        {videos.length > 0 ? (
          <div
            style={{
              display: "grid",
              gridTemplateColumns: "1fr 1fr 1fr",
              gap: 4,
            }}
          >
            {videos.map((video) => {
              const isImage = video.playback_url
                ? inferMediaKind(video.playback_url) === "image"
                : false;
              // For videos without a stored thumbnail, append #t=0.1 to force
              // the browser to render the first frame as a still image
              const videoSrc =
                video.playback_url && !isImage
                  ? `${video.playback_url}#t=0.1`
                  : video.playback_url;
              return (
                <div
                  key={video.id}
                  style={{
                    aspectRatio: "9 / 16",
                    background: "rgba(255,255,255,0.05)",
                    borderRadius: 4,
                    overflow: "hidden",
                    position: "relative",
                  }}
                >
                  {video.playback_url ? (
                    isImage ? (
                      <img
                        alt={video.title}
                        src={video.playback_url}
                        style={{
                          width: "100%",
                          height: "100%",
                          objectFit: "cover",
                        }}
                      />
                    ) : video.thumbnail_url ? (
                      <img
                        alt={video.title}
                        src={video.thumbnail_url}
                        style={{
                          width: "100%",
                          height: "100%",
                          objectFit: "cover",
                        }}
                      />
                    ) : (
                      <video
                        muted
                        playsInline
                        preload="auto"
                        src={videoSrc ?? undefined}
                        style={{
                          width: "100%",
                          height: "100%",
                          objectFit: "cover",
                        }}
                      />
                    )
                  ) : null}
                </div>
              );
            })}
          </div>
        ) : (
          <div
            style={{
              textAlign: "center",
              color: "rgba(255,255,255,0.5)",
              fontSize: "0.9rem",
              padding: "3rem 1rem",
            }}
          >
            <p style={{ margin: "0 0 1rem" }}>No posts yet</p>
            <Link
              href="/videos/new/camera"
              style={{
                display: "inline-block",
                padding: "0.6rem 1.25rem",
                borderRadius: 10,
                background: "var(--accent)",
                color: "white",
                fontSize: "0.85rem",
                fontWeight: 600,
                textDecoration: "none",
              }}
            >
              Create your first post
            </Link>
          </div>
        )}
      </section>
    </main>
  );
}
