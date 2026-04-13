"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { useState } from "react";
import { createVideoFromCamera } from "./actions";

export default function PostFormPage() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const playbackUrl = searchParams.get("playback_url") ?? "";
  const storagePath = searchParams.get("storage_path") ?? "";
  const duration = searchParams.get("duration") ?? "";
  const thumbnailUrl = searchParams.get("thumbnail_url") ?? "";
  const isPhoto = /\.(jpg|jpeg|png|webp)(\?|$)/i.test(playbackUrl) || storagePath.match(/\.(jpg|jpeg|png|webp)$/i);
  const [error, setError] = useState("");
  const [submitting, setSubmitting] = useState(false);

  if (!playbackUrl) {
    return (
      <main className="auth-shell">
        <div className="auth-card" style={{ textAlign: "center" }}>
          <h1>No content found</h1>
          <p className="auth-subtitle">Take a photo or record a video first.</p>
          <button
            className="auth-submit"
            onClick={() => router.push("/videos/new/camera")}
            style={{ marginTop: "1.5rem" }}
            type="button"
          >
            Open Camera
          </button>
        </div>
      </main>
    );
  }

  const handleSubmit = async (formData: FormData) => {
    setSubmitting(true);
    setError("");
    try {
      await createVideoFromCamera(formData);
    } catch (err) {
      setError("Failed to publish. Try again.");
      setSubmitting(false);
    }
  };

  return (
    <main className="auth-shell" style={{ justifyContent: "flex-start", paddingTop: "calc(env(safe-area-inset-top, 0px) + 1rem)" }}>
      <div style={{ width: "100%", maxWidth: 480 }}>
        {/* Preview */}
        <div style={{ borderRadius: 16, overflow: "hidden", marginBottom: "1.25rem", maxHeight: 280 }}>
          {isPhoto ? (
            <img
              alt="Preview"
              src={playbackUrl}
              style={{ width: "100%", height: 280, objectFit: "cover", display: "block", background: "#111" }}
            />
          ) : (
            <video
              autoPlay
              loop
              muted
              playsInline
              src={playbackUrl}
              style={{ width: "100%", height: 280, objectFit: "cover", display: "block", background: "#111" }}
            />
          )}
        </div>

        <form action={handleSubmit} style={{ display: "grid", gap: "1rem" }}>
          <input name="playback_url" type="hidden" value={playbackUrl} />
          <input name="storage_path" type="hidden" value={storagePath} />
          <input name="duration_seconds" type="hidden" value={duration} />
          <input name="thumbnail_url" type="hidden" value={thumbnailUrl} />
          <input name="visibility" type="hidden" value="public" />

          <div className="auth-field">
            <label htmlFor="title">Title</label>
            <input
              id="title"
              name="title"
              placeholder="Give your post a title"
              required
            />
          </div>

          <div className="auth-field">
            <label htmlFor="caption">Caption</label>
            <textarea
              id="caption"
              name="caption"
              placeholder="Write a caption..."
              rows={3}
              style={{
                width: "100%",
                borderRadius: 14,
                border: "1px solid rgba(255,255,255,0.1)",
                background: "rgba(255,255,255,0.06)",
                color: "white",
                padding: "0.9rem 1rem",
                font: "inherit",
                fontSize: "1rem",
                resize: "none",
              }}
            />
          </div>

          <button
            className="auth-submit"
            disabled={submitting}
            type="submit"
          >
            {submitting ? "Publishing..." : "Publish"}
          </button>

          <button
            className="auth-submit"
            onClick={() => router.push("/videos/new/camera")}
            type="button"
            style={{
              background: "rgba(255,255,255,0.08)",
              border: "1px solid rgba(255,255,255,0.15)",
            }}
          >
            {isPhoto ? "Retake Photo" : "Retake Video"}
          </button>

          {error ? (
            <p className="auth-message auth-message-error">{error}</p>
          ) : null}
        </form>
      </div>
    </main>
  );
}
