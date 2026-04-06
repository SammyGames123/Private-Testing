"use client";
/* eslint-disable @next/next/no-img-element */

import Link from "next/link";
import { useRouter } from "next/navigation";
import { startTransition, useEffect, useMemo, useRef, useState } from "react";
import type { ReactNode } from "react";
import { addComment, toggleLikeInline } from "@/app/engagement/actions";
import { toggleFollow } from "@/app/follows/actions";
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
    <svg aria-hidden="true" fill="none" height="26" viewBox="0 0 24 24" width="26">
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
    <svg aria-hidden="true" fill="none" height="26" viewBox="0 0 24 24" width="26">
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
    <svg aria-hidden="true" fill="none" height="26" viewBox="0 0 24 24" width="26">
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
  const [observedActiveId, setObservedActiveId] = useState<string | null>(null);
  const [openCommentsFor, setOpenCommentsFor] = useState<string | null>(null);
  const [dismissedGuestGate, setDismissedGuestGate] = useState(false);
  const [localFeedCards, setLocalFeedCards] = useState(feedCards);
  const [pendingLikeIds, setPendingLikeIds] = useState<string[]>([]);
  const activeId = observedActiveId ?? localFeedCards[0]?.id ?? "";

  useEffect(() => {
    if (pendingLikeIds.length > 0) {
      return;
    }

    setLocalFeedCards(feedCards);
  }, [feedCards, pendingLikeIds]);

  useEffect(() => {
    if (localFeedCards.length === 0) {
      return;
    }

    const observer = new IntersectionObserver(
      (entries) => {
        const bestEntry = entries
          .filter((entry) => entry.isIntersecting)
          .sort((left, right) => right.intersectionRatio - left.intersectionRatio)[0];

        if (!bestEntry) {
          return;
        }

        const id = bestEntry.target.getAttribute("data-feed-id");

        if (id) {
          setObservedActiveId(id);
        }
      },
      {
        threshold: [0.45, 0.7, 0.9],
      },
    );

    for (const element of slideRefs.current) {
      if (element) {
        observer.observe(element);
      }
    }

    return () => {
      observer.disconnect();
    };
  }, [localFeedCards]);

  const cardsById = useMemo(
    () => new Map(localFeedCards.map((card) => [card.id, card])),
    [localFeedCards],
  );
  const activeIndex = localFeedCards.findIndex((card) => card.id === activeId);
  const openCommentsCard = openCommentsFor ? cardsById.get(openCommentsFor) : null;
  const showGuestGate =
    guestMode && activeIndex >= guestPromptAfter && !dismissedGuestGate;

  async function handleLike(videoId: string) {
    const currentCard = cardsById.get(videoId);

    if (!currentCard) {
      return;
    }

    const nextLikedState = !currentCard.likedByCurrentUser;
    const nextLikesCount = Math.max(
      0,
      currentCard.likesCount + (nextLikedState ? 1 : -1),
    );

    setLocalFeedCards((currentCards) =>
      currentCards.map((card) =>
        card.id === videoId
          ? {
              ...card,
              likedByCurrentUser: nextLikedState,
              likesCount: nextLikesCount,
              likes: new Intl.NumberFormat("en-US", {
                notation: "compact",
                maximumFractionDigits: 1,
              }).format(nextLikesCount),
            }
          : card,
      ),
    );
    setPendingLikeIds((currentIds) =>
      currentIds.includes(videoId) ? currentIds : [...currentIds, videoId],
    );

    try {
      const result = await toggleLikeInline(videoId);

      if (!result.ok) {
        setLocalFeedCards((currentCards) =>
          currentCards.map((card) => (card.id === videoId ? currentCard : card)),
        );

        if (result.requiresAuth) {
          router.push("/auth/login");
        }

        return;
      }

      startTransition(() => {
        router.refresh();
      });
    } catch {
      setLocalFeedCards((currentCards) =>
        currentCards.map((card) => (card.id === videoId ? currentCard : card)),
      );
    } finally {
      setPendingLikeIds((currentIds) =>
        currentIds.filter((currentId) => currentId !== videoId),
      );
    }
  }

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
          ref={(element) => {
            slideRefs.current[index] = element;
          }}
        >
          <div className="feed-video-card">
            <FeedMedia active={activeId === post.id} post={post} />

            <div className="feed-overlay">
              <div className="feed-overlay-main">
                <p className="text-sm text-white/70">
                  {(post.creatorHandle || "@creator") +
                    " - " +
                    post.age +
                    " - " +
                    post.views +
                    " views"}
                </p>
                <h2 className="mt-3 text-3xl font-semibold tracking-[-0.05em] text-white">
                  {post.title}
                </h2>
                <p className="mt-3 max-w-2xl text-sm leading-7 text-white/82">
                  {post.caption ?? "No caption yet."}
                </p>
                <p className="feed-why">{post.whyRecommended}</p>
                <div className="mt-4 flex flex-wrap gap-2">
                  {post.tags.map((tag) => (
                    <span className="feed-tag" key={tag}>
                      #{tag}
                    </span>
                  ))}
                </div>
              </div>

              <div className="feed-overlay-side feed-overlay-icons">
                {guestMode ? (
                  <Link
                    aria-label="Create an account to like posts"
                    className="feed-icon-button"
                    href="/auth/sign-up"
                  >
                    <HeartIcon />
                    <span>{post.likes}</span>
                  </Link>
                ) : (
                  <button
                    aria-label={post.likedByCurrentUser ? "Unlike post" : "Like post"}
                    className={
                      post.likedByCurrentUser
                        ? "feed-icon-button active"
                        : "feed-icon-button"
                    }
                    disabled={pendingLikeIds.includes(post.id)}
                    onClick={() => {
                      void handleLike(post.id);
                    }}
                    type="button"
                  >
                    <HeartIcon />
                    <span>{post.likes}</span>
                  </button>
                )}

                {guestMode ? (
                  <Link
                    aria-label="Create an account to comment"
                    className="feed-icon-button"
                    href="/auth/sign-up"
                  >
                    <CommentIcon />
                    <span>{post.comments}</span>
                  </Link>
                ) : (
                  <button
                    aria-expanded={openCommentsFor === post.id}
                    aria-label="Open comments"
                    className={
                      openCommentsFor === post.id
                        ? "feed-icon-button active"
                        : "feed-icon-button"
                    }
                    onClick={() =>
                      setOpenCommentsFor((current) => (current === post.id ? null : post.id))
                    }
                    type="button"
                  >
                    <CommentIcon />
                    <span>{post.comments}</span>
                  </button>
                )}

                {post.creatorId ? (
                  guestMode ? (
                    <Link
                      aria-label="Create an account to follow creators"
                      className="feed-icon-button"
                      href="/auth/sign-up"
                    >
                      <FollowIcon />
                      <span>Add</span>
                    </Link>
                  ) : (
                    <form action={toggleFollow}>
                      <input name="target_user_id" type="hidden" value={post.creatorId} />
                      <input name="redirect_to" type="hidden" value={redirectTarget} />
                      <button
                        aria-label={
                          post.followedCreatorByCurrentUser
                            ? "Unfollow creator"
                            : "Follow creator"
                        }
                        className={
                          post.followedCreatorByCurrentUser
                            ? "feed-icon-button active"
                            : "feed-icon-button"
                        }
                        type="submit"
                      >
                        <FollowIcon />
                        <span>{post.followedCreatorByCurrentUser ? "On" : "Add"}</span>
                      </button>
                    </form>
                  )
                ) : null}

                <div className="feed-match-pill">
                  <strong>{post.score}</strong>
                  <span>match</span>
                </div>
              </div>
            </div>
          </div>
        </article>
      ))}

      {openCommentsCard ? (
        <div className="feed-comments-backdrop" onClick={() => setOpenCommentsFor(null)}>
          <section
            aria-label="Comments"
            className="feed-comments-sheet"
            onClick={(event) => event.stopPropagation()}
          >
            <div className="feed-comments-header">
              <div>
                <p className="eyebrow">Conversation</p>
                <h3 className="mt-2 text-2xl font-semibold tracking-[-0.05em] text-[var(--ink)]">
                  {openCommentsCard.title}
                </h3>
              </div>
              <button
                aria-label="Close comments"
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
                <p className="text-sm leading-6 text-[var(--muted)]">
                  No comments yet. Be the first to jump in.
                </p>
              )}
            </div>

            <form action={addComment} className="feed-comments-form">
              <input name="video_id" type="hidden" value={openCommentsCard.id} />
              <input name="redirect_to" type="hidden" value={redirectTarget} />
              <textarea name="body" placeholder="Add a comment" />
              <button className="feed-primary-button" type="submit">
                Post
              </button>
            </form>
          </section>
        </div>
      ) : null}

      {showGuestGate ? (
        <div
          className="feed-comments-backdrop"
          onClick={() => setDismissedGuestGate(true)}
        >
          <section
            aria-label="Create account"
            className="feed-comments-sheet"
            onClick={(event) => event.stopPropagation()}
          >
            <div className="feed-comments-header">
              <div>
                <p className="eyebrow">Keep watching</p>
                <h3 className="mt-2 text-3xl font-semibold tracking-[-0.05em] text-[var(--ink)]">
                  Create an account to unlock the full feed.
                </h3>
              </div>
              <button
                aria-label="Close sign up prompt"
                className="feed-comments-close"
                onClick={() => setDismissedGuestGate(true)}
                type="button"
              >
                <CloseIcon />
              </button>
            </div>

            <p className="mt-4 text-sm leading-7 text-[var(--muted)]">
              You have previewed a couple of posts already. Sign up to keep
              scrolling, follow creators, like videos, comment, and build your
              personal feed.
            </p>

            <div className="mt-6 flex flex-col gap-3 sm:flex-row">
              <Link className="feed-primary-button" href="/auth/sign-up">
                Create account
              </Link>
              <Link className="feed-ghost-auth-button" href="/auth/login">
                Sign in
              </Link>
            </div>
          </section>
        </div>
      ) : null}
    </>
  );
}
