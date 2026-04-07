"use client";
/* eslint-disable @next/next/no-img-element */

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useRef, useState, useCallback } from "react";
import type { ReactNode } from "react";
import { addComment, toggleLikeInline } from "@/app/engagement/actions";
import { toggleFollowInline } from "@/app/follows/actions";
import type { LiveFeedCard } from "@/lib/feed";
import { inferMediaKind } from "@/lib/media";

type FeedExperienceProps = {
  feedCards: LiveFeedCard[];
  redirectTarget: string;
  empty: ReactNode;
  guestMode?: boolean;
  guestPromptAfter?: number;
};

function HeartIcon() {
  return (
    <svg aria-hidden="true" fill="none" height="30" viewBox="0 0 24 24" width="30">
      <path
        d="M12 20.5s-7-4.35-7-10.14A4.36 4.36 0 0 1 9.42 6c1.1 0 2.16.42 2.58 1.34C12.42 6.42 13.48 6 14.58 6A4.36 4.36 0 0 1 19 10.36C19 16.15 12 20.5 12 20.5Z"
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="1.8"
      />
    </svg>
  );
}

function CommentIcon() {
  return (
    <svg aria-hidden="true" fill="none" height="30" viewBox="0 0 24 24" width="30">
      <path
        d="M7 18.5 4.5 20V7.75A2.75 2.75 0 0 1 7.25 5h9.5a2.75 2.75 0 0 1 2.75 2.75v6.5A2.75 2.75 0 0 1 16.75 17H8.2z"
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="1.8"
      />
    </svg>
  );
}

function FollowIcon() {
  return (
    <svg aria-hidden="true" fill="none" height="30" viewBox="0 0 24 24" width="30">
      <path
        d="M12 7.5a3 3 0 1 0 0-6 3 3 0 0 0 0 6ZM6 20a6 6 0 0 1 12 0M19 9v6M16 12h6"
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="1.8"
      />
    </svg>
  );
}

function CheckIcon() {
  return (
    <svg aria-hidden="true" fill="none" height="30" viewBox="0 0 24 24" width="30">
      <path
        d="M5 12l5 5L20 7"
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="2"
      />
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

type FeedMediaProps = {
  post: LiveFeedCard;
  active: boolean;
};

function FeedMedia({ post, active }: FeedMediaProps) {
  const mediaKind = inferMediaKind(post.playbackUrl);
  const videoRef = useRef<HTMLVideoElement | null>(null);

  useEffect(() => {
    if (mediaKind !== "video" || !videoRef.current) {
      return;
    }

    const video = videoRef.current;
    video.muted = false;
    video.defaultMuted = false;
    video.volume = 1;

    if (!active) {
      video.pause();
      return;
    }

    const playVideo = async () => {
      try {
        await video.play();
      } catch {
        video.muted = true;

        try {
          await video.play();
        } catch {
          return;
        }

        const enableAudio = async () => {
          video.muted = false;

          try {
            await video.play();
          } catch {
            return;
          } finally {
            window.removeEventListener("pointerdown", enableAudio);
            window.removeEventListener("keydown", enableAudio);
          }
        };

        window.addEventListener("pointerdown", enableAudio, { once: true });
        window.addEventListener("keydown", enableAudio, { once: true });
      }
    };

    void playVideo();

    return () => {
      video.pause();
    };
  }, [active, mediaKind]);

  if (mediaKind === "image" && post.playbackUrl) {
    return (
      <img
        alt={post.title}
        className="feed-video"
        loading="eager"
        src={post.playbackUrl}
      />
    );
  }

  if (post.playbackUrl) {
    return (
      <video
        autoPlay
        className="feed-video"
        loop
        playsInline
        poster={post.thumbnailUrl ?? undefined}
        ref={videoRef}
        src={post.playbackUrl}
      />
    );
  }

  return (
    <div className="feed-video feed-video-fallback">
      <div>
        <p className="text-xs uppercase tracking-[0.25em] text-white/70">
          {post.category ?? "Post"}
        </p>
        <h2 className="mt-3 text-3xl font-semibold tracking-[-0.05em] text-white">
          {post.title}
        </h2>
      </div>
    </div>
  );
}

export function FeedExperience({
  feedCards,
  redirectTarget,
  empty,
  guestMode = false,
  guestPromptAfter = 2,
}: FeedExperienceProps) {
  const router = useRouter();
  const slideRefs = useRef<(HTMLElement | null)[]>([]);
  const [activeIndex, setActiveIndex] = useState(0);
  const [openCommentsFor, setOpenCommentsFor] = useState<string | null>(null);
  const [dismissedGuestGate, setDismissedGuestGate] = useState(false);
  const [localFeedCards, setLocalFeedCards] = useState(feedCards);
  const modifiedIdsRef = useRef<Set<string>>(new Set());
  const activeId = localFeedCards[activeIndex]?.id ?? "";

  // Sync feed cards from server, but preserve locally-modified items
  useEffect(() => {
    setLocalFeedCards((current) => {
      const currentById = new Map(current.map((c) => [c.id, c]));
      return feedCards.map((serverCard) => {
        if (modifiedIdsRef.current.has(serverCard.id)) {
          return currentById.get(serverCard.id) ?? serverCard;
        }
        return serverCard;
      });
    });
  }, [feedCards]);

  // IntersectionObserver for snap detection
  useEffect(() => {
    if (localFeedCards.length === 0) return;

    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting && entry.intersectionRatio > 0.5) {
            const idx = slideRefs.current.indexOf(entry.target as HTMLElement);
            if (idx >= 0) setActiveIndex(idx);
          }
        }
      },
      { threshold: [0.5, 0.9] },
    );

    for (const el of slideRefs.current) {
      if (el) observer.observe(el);
    }

    return () => observer.disconnect();
  }, [localFeedCards]);

  const handleLike = useCallback(
    async (videoId: string) => {
      const idx = localFeedCards.findIndex((c) => c.id === videoId);
      if (idx < 0) return;
      const card = localFeedCards[idx];

      const nextLiked = !card.likedByCurrentUser;
      const nextCount = Math.max(0, card.likesCount + (nextLiked ? 1 : -1));

      modifiedIdsRef.current.add(videoId);
      setLocalFeedCards((cards) =>
        cards.map((c) =>
          c.id === videoId
            ? {
                ...c,
                likedByCurrentUser: nextLiked,
                likesCount: nextCount,
                likes: new Intl.NumberFormat("en-US", {
                  notation: "compact",
                  maximumFractionDigits: 1,
                }).format(nextCount),
              }
            : c,
        ),
      );

      try {
        const result = await toggleLikeInline(videoId);
        if (!result.ok) {
          modifiedIdsRef.current.delete(videoId);
          setLocalFeedCards((cards) =>
            cards.map((c) => (c.id === videoId ? card : c)),
          );
          if (result.requiresAuth) router.push("/auth/login");
        }
      } catch {
        modifiedIdsRef.current.delete(videoId);
        setLocalFeedCards((cards) =>
          cards.map((c) => (c.id === videoId ? card : c)),
        );
      }
    },
    [localFeedCards, router],
  );

  const handleFollow = useCallback(
    async (creatorId: string) => {
      const idx = localFeedCards.findIndex((c) => c.creatorId === creatorId);
      if (idx < 0) return;
      const card = localFeedCards[idx];
      const nextFollowed = !card.followedCreatorByCurrentUser;

      // Mark all cards by this creator as locally modified
      const creatorCardIds = localFeedCards
        .filter((c) => c.creatorId === creatorId)
        .map((c) => c.id);
      for (const id of creatorCardIds) modifiedIdsRef.current.add(id);

      setLocalFeedCards((cards) =>
        cards.map((c) =>
          c.creatorId === creatorId
            ? { ...c, followedCreatorByCurrentUser: nextFollowed }
            : c,
        ),
      );

      try {
        const result = await toggleFollowInline(creatorId);
        if (!result.ok) {
          for (const id of creatorCardIds) modifiedIdsRef.current.delete(id);
          setLocalFeedCards((cards) =>
            cards.map((c) =>
              c.creatorId === creatorId
                ? { ...c, followedCreatorByCurrentUser: card.followedCreatorByCurrentUser }
                : c,
            ),
          );
          if (result.requiresAuth) router.push("/auth/login");
        }
      } catch {
        for (const id of creatorCardIds) modifiedIdsRef.current.delete(id);
        setLocalFeedCards((cards) =>
          cards.map((c) =>
            c.creatorId === creatorId
              ? { ...c, followedCreatorByCurrentUser: card.followedCreatorByCurrentUser }
              : c,
          ),
        );
      }
    },
    [localFeedCards, router],
  );

  const openCommentsCard = openCommentsFor
    ? localFeedCards.find((c) => c.id === openCommentsFor)
    : null;

  const showGuestGate =
    guestMode && activeIndex >= guestPromptAfter && !dismissedGuestGate;

  if (localFeedCards.length === 0) {
    return <>{empty}</>;
  }

  return (
    <>
      {localFeedCards.map((post, index) => (
        <article
          className="feed-slide"
          data-feed-id={post.id}
          key={post.id}
          ref={(el) => {
            slideRefs.current[index] = el;
          }}
        >
          <FeedMedia active={activeId === post.id} post={post} />

          <div className="feed-overlay">
            <div className="feed-overlay-inner">
              {/* Left: text info */}
              <div className="feed-overlay-main">
                <p className="feed-creator">
                  @{post.creatorHandle || "creator"}
                </p>
                <h2 className="feed-title">{post.title}</h2>
                {post.caption ? (
                  <p className="feed-caption">{post.caption}</p>
                ) : null}
                {post.tags.length > 0 ? (
                  <div className="feed-tags-row">
                    {post.tags.map((tag) => (
                      <span className="feed-tag" key={tag}>
                        #{tag}
                      </span>
                    ))}
                  </div>
                ) : null}
              </div>

              {/* Right: action buttons */}
              <div className="feed-overlay-side">
                {/* Like */}
                {guestMode ? (
                  <Link
                    aria-label="Sign up to like"
                    className="feed-icon-button"
                    href="/auth/sign-up"
                  >
                    <HeartIcon />
                    <span>{post.likes}</span>
                  </Link>
                ) : (
                  <button
                    aria-label={post.likedByCurrentUser ? "Unlike" : "Like"}
                    className={
                      post.likedByCurrentUser
                        ? "feed-icon-button active"
                        : "feed-icon-button"
                    }
                    onClick={() => void handleLike(post.id)}
                    type="button"
                  >
                    <HeartIcon />
                    <span>{post.likes}</span>
                  </button>
                )}

                {/* Comment */}
                {guestMode ? (
                  <Link
                    aria-label="Sign up to comment"
                    className="feed-icon-button"
                    href="/auth/sign-up"
                  >
                    <CommentIcon />
                    <span>{post.comments}</span>
                  </Link>
                ) : (
                  <button
                    aria-label="Comments"
                    className={
                      openCommentsFor === post.id
                        ? "feed-icon-button active"
                        : "feed-icon-button"
                    }
                    onClick={() =>
                      setOpenCommentsFor((c) =>
                        c === post.id ? null : post.id,
                      )
                    }
                    type="button"
                  >
                    <CommentIcon />
                    <span>{post.comments}</span>
                  </button>
                )}

                {/* Follow */}
                {post.creatorId ? (
                  guestMode ? (
                    <Link
                      aria-label="Sign up to follow"
                      className="feed-icon-button"
                      href="/auth/sign-up"
                    >
                      <FollowIcon />
                      <span>Follow</span>
                    </Link>
                  ) : (
                    <button
                      aria-label={
                        post.followedCreatorByCurrentUser
                          ? "Unfollow"
                          : "Follow"
                      }
                      className={
                        post.followedCreatorByCurrentUser
                          ? "feed-icon-button follow-active"
                          : "feed-icon-button"
                      }
                      onClick={() => void handleFollow(post.creatorId)}
                      type="button"
                    >
                      {post.followedCreatorByCurrentUser ? (
                        <CheckIcon />
                      ) : (
                        <FollowIcon />
                      )}
                      <span>
                        {post.followedCreatorByCurrentUser
                          ? "Following"
                          : "Follow"}
                      </span>
                    </button>
                  )
                ) : null}
              </div>
            </div>
          </div>
        </article>
      ))}

      {/* Comments sheet */}
      {openCommentsCard ? (
        <div
          className="feed-comments-backdrop"
          onClick={() => setOpenCommentsFor(null)}
        >
          <section
            aria-label="Comments"
            className="feed-comments-sheet"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="feed-comments-header">
              <h3>Comments</h3>
              <button
                aria-label="Close"
                className="feed-comments-close"
                onClick={() => setOpenCommentsFor(null)}
                type="button"
              >
                <CloseIcon />
              </button>
            </div>

            <div className="feed-comments-list">
              {openCommentsCard.recentComments.length > 0 ? (
                openCommentsCard.recentComments.map((comment) => (
                  <article className="feed-comment-card" key={comment.id}>
                    <strong>{comment.authorHandle}</strong>
                    <p>{comment.body}</p>
                  </article>
                ))
              ) : (
                <p className="text-sm text-white/40">
                  No comments yet. Be the first.
                </p>
              )}
            </div>

            <form action={addComment} className="feed-comments-form">
              <input
                name="video_id"
                type="hidden"
                value={openCommentsCard.id}
              />
              <input
                name="redirect_to"
                type="hidden"
                value={redirectTarget}
              />
              <textarea name="body" placeholder="Add a comment..." />
              <button className="feed-primary-button" type="submit">
                Post
              </button>
            </form>
          </section>
        </div>
      ) : null}

      {/* Guest gate */}
      {showGuestGate ? (
        <div className="feed-guest-gate">
          <div className="feed-guest-gate-card">
            <h3>Sign up to keep watching</h3>
            <p>
              Create an account to unlock the full feed, follow creators, like
              videos, and build your personal recommendations.
            </p>
            <div className="mt-6 flex flex-col gap-3">
              <Link className="feed-primary-button" href="/auth/sign-up">
                Create account
              </Link>
              <Link className="feed-ghost-auth-button" href="/auth/login">
                Sign in
              </Link>
              <button
                className="mt-2 text-sm text-white/40"
                onClick={() => setDismissedGuestGate(true)}
                type="button"
              >
                Maybe later
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </>
  );
}
