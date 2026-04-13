"use client";
/* eslint-disable @next/next/no-img-element */

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import {
  deletePost,
  editPost,
  toggleArchivePost,
  togglePinPost,
} from "@/app/dashboard/posts/[id]/actions";
import { inferMediaKind } from "@/lib/media";
import type { VideoRecord } from "@/lib/videos";

type MyPostsFeedProps = {
  videos: VideoRecord[];
  initialVideoId: string;
};

function BackIcon() {
  return (
    <svg aria-hidden="true" fill="none" height="28" viewBox="0 0 24 24" width="28">
      <path
        d="M15 6 9 12l6 6"
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="2"
      />
    </svg>
  );
}

function MoreIcon() {
  return (
    <svg aria-hidden="true" fill="none" height="28" viewBox="0 0 24 24" width="28">
      <circle cx="5" cy="12" fill="currentColor" r="2" />
      <circle cx="12" cy="12" fill="currentColor" r="2" />
      <circle cx="19" cy="12" fill="currentColor" r="2" />
    </svg>
  );
}

function CloseIcon() {
  return (
    <svg aria-hidden="true" fill="none" height="22" viewBox="0 0 24 24" width="22">
      <path
        d="m6 6 12 12M18 6 6 18"
        stroke="currentColor"
        strokeLinecap="round"
        strokeWidth="1.8"
      />
    </svg>
  );
}

type SlideMediaProps = {
  video: VideoRecord;
  active: boolean;
};

function SlideMedia({ video, active }: SlideMediaProps) {
  const mediaKind = inferMediaKind(video.playback_url);
  const videoRef = useRef<HTMLVideoElement | null>(null);

  useEffect(() => {
    if (mediaKind !== "video" || !videoRef.current) {
      return;
    }

    const el = videoRef.current;

    if (!active) {
      el.pause();
      return;
    }

    const playVideo = async () => {
      try {
        await el.play();
      } catch {
        el.muted = true;
        try {
          await el.play();
        } catch {
          return;
        }
      }
    };

    void playVideo();

    return () => {
      el.pause();
    };
  }, [active, mediaKind]);

  if (mediaKind === "image" && video.playback_url) {
    return (
      <img
        alt={video.title}
        className="feed-video"
        loading="eager"
        src={video.playback_url}
      />
    );
  }

  if (video.playback_url) {
    return (
      <video
        autoPlay
        className="feed-video"
        loop
        playsInline
        poster={video.thumbnail_url ?? undefined}
        ref={videoRef}
        src={video.playback_url}
      />
    );
  }

  return (
    <div className="feed-video feed-video-fallback">
      <div>
        <h2 className="mt-3 text-3xl font-semibold tracking-[-0.05em] text-white">
          {video.title}
        </h2>
      </div>
    </div>
  );
}

export function MyPostsFeed({ videos, initialVideoId }: MyPostsFeedProps) {
  const router = useRouter();
  const scrollRef = useRef<HTMLElement | null>(null);
  const slideRefs = useRef<(HTMLElement | null)[]>([]);
  const initialIndex = Math.max(
    0,
    videos.findIndex((v) => v.id === initialVideoId),
  );
  const [activeIndex, setActiveIndex] = useState(initialIndex);
  const [menuOpenFor, setMenuOpenFor] = useState<string | null>(null);
  const [editingFor, setEditingFor] = useState<string | null>(null);

  // Scroll to the initially selected post on mount
  useEffect(() => {
    const target = slideRefs.current[initialIndex];
    if (target && scrollRef.current) {
      scrollRef.current.scrollTo({ top: target.offsetTop, behavior: "auto" });
    }
  }, [initialIndex]);

  // IntersectionObserver for snap detection
  useEffect(() => {
    if (videos.length === 0) return;

    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting && entry.intersectionRatio > 0.5) {
            const idx = slideRefs.current.indexOf(entry.target as HTMLElement);
            if (idx >= 0) setActiveIndex(idx);
          }
        }
      },
      { threshold: [0.5, 0.9], root: scrollRef.current },
    );

    for (const el of slideRefs.current) {
      if (el) observer.observe(el);
    }

    return () => observer.disconnect();
  }, [videos]);

  const activeVideo = videos[activeIndex] ?? null;
  const menuVideo = menuOpenFor
    ? videos.find((v) => v.id === menuOpenFor)
    : null;
  const editingVideo = editingFor
    ? videos.find((v) => v.id === editingFor)
    : null;

  if (videos.length === 0) {
    return (
      <main
        style={{
          minHeight: "100vh",
          background: "black",
          color: "white",
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          gap: "1rem",
          padding: "2rem",
        }}
      >
        <p style={{ color: "rgba(255,255,255,0.6)" }}>No posts yet.</p>
        <Link
          href="/dashboard"
          style={{
            padding: "0.6rem 1.25rem",
            borderRadius: 10,
            background: "rgba(255,255,255,0.12)",
            color: "white",
            textDecoration: "none",
            fontWeight: 600,
          }}
        >
          Back to profile
        </Link>
      </main>
    );
  }

  return (
    <main
      className="feed-shell"
      style={{ background: "black", position: "relative" }}
    >
      {/* Top bar with back + title */}
      <div
        style={{
          position: "fixed",
          top: 0,
          left: 0,
          right: 0,
          zIndex: 30,
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          padding:
            "calc(env(safe-area-inset-top, 0px) + 0.75rem) 0.75rem 0.75rem",
          background:
            "linear-gradient(180deg, rgba(0,0,0,0.6) 0%, transparent 100%)",
          pointerEvents: "none",
        }}
      >
        <button
          aria-label="Back to profile"
          onClick={() => router.push("/dashboard")}
          style={{
            pointerEvents: "auto",
            background: "rgba(0,0,0,0.35)",
            border: "none",
            color: "white",
            borderRadius: "50%",
            width: 40,
            height: 40,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            cursor: "pointer",
          }}
          type="button"
        >
          <BackIcon />
        </button>
        <p
          style={{
            color: "white",
            fontSize: "0.95rem",
            fontWeight: 700,
            margin: 0,
            pointerEvents: "auto",
          }}
        >
          My posts
        </p>
        <button
          aria-label="Post options"
          disabled={!activeVideo}
          onClick={() => activeVideo && setMenuOpenFor(activeVideo.id)}
          style={{
            pointerEvents: "auto",
            background: "rgba(0,0,0,0.35)",
            border: "none",
            color: "white",
            borderRadius: "50%",
            width: 40,
            height: 40,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            cursor: "pointer",
          }}
          type="button"
        >
          <MoreIcon />
        </button>
      </div>

      <section
        className="feed-scroll"
        ref={(el) => {
          scrollRef.current = el;
        }}
      >
        {videos.map((video, index) => (
          <article
            className="feed-slide"
            key={video.id}
            ref={(el) => {
              slideRefs.current[index] = el;
            }}
          >
            <SlideMedia active={index === activeIndex} video={video} />

            <div className="feed-overlay">
              <div className="feed-overlay-inner">
                <div className="feed-overlay-main">
                  <p className="feed-creator">
                    {video.is_pinned ? "📌 Pinned · " : ""}
                    {video.is_archived ? "Archived" : "Your post"}
                  </p>
                  <h2 className="feed-title">{video.title}</h2>
                  {video.caption ? (
                    <p className="feed-caption">{video.caption}</p>
                  ) : null}
                  {video.video_tags && video.video_tags.length > 0 ? (
                    <div className="feed-tags-row">
                      {video.video_tags.map((t) => (
                        <span className="feed-tag" key={t.tag}>
                          #{t.tag}
                        </span>
                      ))}
                    </div>
                  ) : null}
                </div>
              </div>
            </div>
          </article>
        ))}
      </section>

      {/* 3-dot menu sheet */}
      {menuVideo ? (
        <div
          className="feed-comments-backdrop"
          onClick={() => setMenuOpenFor(null)}
        >
          <section
            aria-label="Post options"
            className="feed-comments-sheet"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="feed-comments-header">
              <h3>Manage post</h3>
              <button
                aria-label="Close"
                className="feed-comments-close"
                onClick={() => setMenuOpenFor(null)}
                type="button"
              >
                <CloseIcon />
              </button>
            </div>

            <div
              style={{
                display: "flex",
                flexDirection: "column",
                gap: "0.5rem",
                padding: "0.5rem 1rem 1rem",
              }}
            >
              <button
                className="my-posts-menu-item"
                onClick={() => {
                  setMenuOpenFor(null);
                  setEditingFor(menuVideo.id);
                }}
                type="button"
              >
                Edit title & caption
              </button>

              <form action={togglePinPost}>
                <input name="video_id" type="hidden" value={menuVideo.id} />
                <input
                  name="next"
                  type="hidden"
                  value={menuVideo.is_pinned ? "false" : "true"}
                />
                <button className="my-posts-menu-item" type="submit">
                  {menuVideo.is_pinned ? "Unpin from profile" : "Pin to profile"}
                </button>
              </form>

              <form action={toggleArchivePost}>
                <input name="video_id" type="hidden" value={menuVideo.id} />
                <input
                  name="next"
                  type="hidden"
                  value={menuVideo.is_archived ? "false" : "true"}
                />
                <button className="my-posts-menu-item" type="submit">
                  {menuVideo.is_archived ? "Unarchive post" : "Archive post"}
                </button>
              </form>

              <form
                action={deletePost}
                onSubmit={(e) => {
                  if (
                    !window.confirm(
                      "Delete this post? This cannot be undone.",
                    )
                  ) {
                    e.preventDefault();
                  }
                }}
              >
                <input name="video_id" type="hidden" value={menuVideo.id} />
                <button
                  className="my-posts-menu-item my-posts-menu-item-danger"
                  type="submit"
                >
                  Delete post
                </button>
              </form>
            </div>
          </section>
        </div>
      ) : null}

      {/* Edit sheet */}
      {editingVideo ? (
        <div
          className="feed-comments-backdrop"
          onClick={() => setEditingFor(null)}
        >
          <section
            aria-label="Edit post"
            className="feed-comments-sheet"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="feed-comments-header">
              <h3>Edit post</h3>
              <button
                aria-label="Close"
                className="feed-comments-close"
                onClick={() => setEditingFor(null)}
                type="button"
              >
                <CloseIcon />
              </button>
            </div>

            <form
              action={editPost}
              style={{
                display: "flex",
                flexDirection: "column",
                gap: "0.75rem",
                padding: "0.5rem 1rem 1rem",
              }}
            >
              <input
                name="video_id"
                type="hidden"
                value={editingVideo.id}
              />
              <label
                style={{
                  color: "rgba(255,255,255,0.7)",
                  fontSize: "0.75rem",
                  fontWeight: 600,
                }}
              >
                Title
                <input
                  defaultValue={editingVideo.title}
                  name="title"
                  required
                  style={{
                    marginTop: "0.35rem",
                    width: "100%",
                    padding: "0.65rem 0.75rem",
                    borderRadius: 10,
                    background: "rgba(255,255,255,0.08)",
                    border: "1px solid rgba(255,255,255,0.12)",
                    color: "white",
                    fontSize: "0.95rem",
                  }}
                  type="text"
                />
              </label>
              <label
                style={{
                  color: "rgba(255,255,255,0.7)",
                  fontSize: "0.75rem",
                  fontWeight: 600,
                }}
              >
                Caption
                <textarea
                  defaultValue={editingVideo.caption ?? ""}
                  name="caption"
                  rows={3}
                  style={{
                    marginTop: "0.35rem",
                    width: "100%",
                    padding: "0.65rem 0.75rem",
                    borderRadius: 10,
                    background: "rgba(255,255,255,0.08)",
                    border: "1px solid rgba(255,255,255,0.12)",
                    color: "white",
                    fontSize: "0.95rem",
                    resize: "vertical",
                  }}
                />
              </label>
              <button className="feed-primary-button" type="submit">
                Save changes
              </button>
            </form>
          </section>
        </div>
      ) : null}

      <style>{`
        .my-posts-menu-item {
          width: 100%;
          text-align: left;
          padding: 0.85rem 1rem;
          border-radius: 12px;
          background: rgba(255, 255, 255, 0.06);
          border: 1px solid rgba(255, 255, 255, 0.08);
          color: white;
          font-size: 0.95rem;
          font-weight: 600;
          cursor: pointer;
        }
        .my-posts-menu-item:active {
          background: rgba(255, 255, 255, 0.12);
        }
        .my-posts-menu-item-danger {
          color: #ff6b6b;
        }
      `}</style>
    </main>
  );
}
