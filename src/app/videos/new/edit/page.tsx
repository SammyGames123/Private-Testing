"use client";

import { useSearchParams, useRouter } from "next/navigation";
import { VideoEditor } from "@/components/video-editor";

export default function EditPage() {
  const searchParams = useSearchParams();
  const router = useRouter();
  const playbackUrl = searchParams.get("playback_url") ?? "";
  const storagePath = searchParams.get("storage_path") ?? "";
  const duration = searchParams.get("duration") ?? "";

  if (!playbackUrl) {
    return (
      <main className="auth-shell">
        <div className="auth-card" style={{ textAlign: "center" }}>
          <h1>No video found</h1>
          <p className="auth-subtitle">Record a video first.</p>
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

  return (
    <VideoEditor
      videoUrl={playbackUrl}
      storagePath={storagePath}
      duration={duration}
    />
  );
}
