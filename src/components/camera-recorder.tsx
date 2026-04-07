"use client";

import { useRouter } from "next/navigation";
import { useState, useCallback } from "react";
import { createClient } from "@/lib/supabase/client";

type CameraRecorderProps = {
  userId: string;
};

function slugifyFileName(fileName: string) {
  const parts = fileName.split(".");
  const extension = parts.length > 1 ? parts.pop()?.toLowerCase() ?? "mp4" : "mp4";
  const base = parts.join(".") || "video";
  return `${base.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 40)}.${extension}`;
}

function CloseIcon() {
  return (
    <svg fill="none" height="28" viewBox="0 0 24 24" width="28">
      <path d="m6 6 12 12M18 6 6 18" stroke="currentColor" strokeLinecap="round" strokeWidth="2" />
    </svg>
  );
}

export function CameraRecorder({ userId }: CameraRecorderProps) {
  const router = useRouter();
  const [mode, setMode] = useState<"choose" | "recording" | "uploading">("choose");
  const [error, setError] = useState("");
  const [uploadProgress, setUploadProgress] = useState("");

  const handlePickVideo = useCallback(async () => {
    try {
      const { FilePicker } = await import("@capawesome/capacitor-file-picker");
      const result = await FilePicker.pickVideos({ limit: 1, readData: true });
      const picked = result.files[0];
      if (!picked?.data) return;

      setMode("uploading");
      setUploadProgress("Uploading video...");

      const binary = atob(picked.data);
      const bytes = new Uint8Array(binary.length);
      for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);

      const mimeType = picked.mimeType || "video/mp4";
      const fileName = picked.name || `video-${Date.now()}.mp4`;
      const file = new File([bytes], fileName, { type: mimeType });

      await uploadAndNavigate(file);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to pick video");
      setMode("choose");
    }
  }, []);

  const handlePickPhoto = useCallback(async () => {
    try {
      const { FilePicker } = await import("@capawesome/capacitor-file-picker");
      const result = await FilePicker.pickImages({ limit: 1, readData: true });
      const picked = result.files[0];
      if (!picked?.data) return;

      setMode("uploading");
      setUploadProgress("Uploading photo...");

      const binary = atob(picked.data);
      const bytes = new Uint8Array(binary.length);
      for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);

      const mimeType = picked.mimeType || "image/jpeg";
      const fileName = picked.name || `photo-${Date.now()}.jpg`;
      const file = new File([bytes], fileName, { type: mimeType });

      await uploadAndNavigate(file);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to pick photo");
      setMode("choose");
    }
  }, []);

  const handleRecordVideo = useCallback(async () => {
    try {
      const { Camera, CameraResultType, CameraSource } = await import("@capacitor/camera");
      const result = await Camera.pickImages({
        limit: 1,
        quality: 100,
      });

      const photo = result.photos[0];
      if (!photo?.webPath) {
        // Fallback: try using the native video picker
        setError("Use 'Choose Video' to select a recorded video from your library.");
        return;
      }

      setMode("uploading");
      setUploadProgress("Uploading...");

      const response = await fetch(photo.webPath);
      const blob = await response.blob();
      const file = new File([blob], `photo-${Date.now()}.jpg`, { type: "image/jpeg" });

      await uploadAndNavigate(file);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Camera cancelled");
      setMode("choose");
    }
  }, []);

  const handleWebRecord = useCallback(async () => {
    // For web browsers that support getUserMedia
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: "environment", width: { ideal: 1080 }, height: { ideal: 1920 } },
        audio: true,
      });

      // Open a simple recording interface
      const mediaRecorder = new MediaRecorder(stream, {
        mimeType: MediaRecorder.isTypeSupported("video/mp4") ? "video/mp4" : "video/webm",
        videoBitsPerSecond: 8_000_000,
      });

      const chunks: Blob[] = [];
      mediaRecorder.ondataavailable = (e) => {
        if (e.data.size > 0) chunks.push(e.data);
      };

      setMode("recording");

      return new Promise<void>((resolve) => {
        mediaRecorder.onstop = async () => {
          for (const track of stream.getTracks()) track.stop();
          const blob = new Blob(chunks, { type: mediaRecorder.mimeType });
          const ext = blob.type.includes("mp4") ? "mp4" : "webm";
          const file = new File([blob], `recording-${Date.now()}.${ext}`, { type: blob.type });

          setMode("uploading");
          setUploadProgress("Uploading recording...");
          await uploadAndNavigate(file);
          resolve();
        };

        mediaRecorder.start(500);

        // Auto-stop after 60s
        setTimeout(() => {
          if (mediaRecorder.state === "recording") mediaRecorder.stop();
        }, 60000);
      });
    } catch {
      setError("Camera not available in this browser. Use 'Choose Video' instead.");
      setMode("choose");
    }
  }, []);

  const uploadAndNavigate = async (file: File) => {
    const supabase = createClient();
    const safeName = slugifyFileName(file.name);
    const path = `${userId}/${Date.now()}-${safeName}`;

    const { error: uploadError } = await supabase.storage
      .from("videos")
      .upload(path, file, {
        cacheControl: "3600",
        upsert: false,
        contentType: file.type,
      });

    if (uploadError) {
      setError(`Upload failed: ${uploadError.message}`);
      setMode("choose");
      return;
    }

    const { data } = supabase.storage.from("videos").getPublicUrl(path);

    const params = new URLSearchParams({
      storage_path: path,
      playback_url: data.publicUrl,
      duration: "0",
    });
    router.push(`/videos/new/post?${params.toString()}`);
  };

  const isNative = typeof window !== "undefined" && "Capacitor" in window;

  return (
    <div className="camera-shell">
      {/* Close button */}
      <div className="camera-top-bar">
        <button className="camera-icon-btn" onClick={() => router.back()} type="button">
          <CloseIcon />
        </button>
        <div />
        <div style={{ width: 28 }} />
      </div>

      {/* Main content area */}
      <div style={{
        position: "absolute",
        inset: 0,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        padding: "2rem",
        gap: "1rem",
      }}>
        {mode === "uploading" ? (
          <>
            <div style={{
              width: 48,
              height: 48,
              border: "3px solid rgba(255,255,255,0.2)",
              borderTopColor: "var(--accent)",
              borderRadius: "999px",
              animation: "camera-pulse 0.8s linear infinite",
            }} />
            <p style={{ color: "white", fontWeight: 700, fontSize: "1.1rem" }}>
              {uploadProgress}
            </p>
          </>
        ) : mode === "recording" ? (
          <>
            <div className="camera-recording-badge" style={{ marginBottom: "1rem" }}>
              <span className="camera-rec-dot" />
              <span>Recording...</span>
            </div>
            <p style={{ color: "rgba(255,255,255,0.5)", fontSize: "0.9rem" }}>
              Recording will auto-stop after 60s
            </p>
          </>
        ) : (
          <>
            <h2 style={{
              color: "white",
              fontSize: "1.5rem",
              fontWeight: 700,
              textAlign: "center",
              marginBottom: "0.5rem",
            }}>
              Create a post
            </h2>
            <p style={{
              color: "rgba(255,255,255,0.5)",
              fontSize: "0.9rem",
              textAlign: "center",
              marginBottom: "1.5rem",
              lineHeight: 1.5,
            }}>
              Record or choose media from your library
            </p>

            {/* Action buttons */}
            <div style={{ width: "100%", maxWidth: 320, display: "grid", gap: "0.75rem" }}>
              {isNative ? (
                <>
                  <button
                    className="camera-action-btn"
                    onClick={() => void handlePickVideo()}
                    type="button"
                  >
                    <CameraVideoIcon />
                    <span>Choose Video</span>
                  </button>
                  <button
                    className="camera-action-btn"
                    onClick={() => void handlePickPhoto()}
                    type="button"
                  >
                    <PhotoIcon />
                    <span>Choose Photo</span>
                  </button>
                </>
              ) : (
                <>
                  <button
                    className="camera-action-btn"
                    onClick={() => void handleWebRecord()}
                    type="button"
                  >
                    <RecordIcon />
                    <span>Record Video</span>
                  </button>
                  <label className="camera-action-btn" style={{ cursor: "pointer" }}>
                    <UploadFileIcon />
                    <span>Upload File</span>
                    <input
                      accept="video/*,image/*"
                      onChange={async (e) => {
                        const file = e.target.files?.[0];
                        if (!file) return;
                        setMode("uploading");
                        setUploadProgress("Uploading...");
                        await uploadAndNavigate(file);
                      }}
                      style={{ display: "none" }}
                      type="file"
                    />
                  </label>
                </>
              )}
            </div>

            {error ? (
              <p style={{
                marginTop: "1rem",
                padding: "0.75rem 1rem",
                borderRadius: 12,
                background: "rgba(239,68,68,0.15)",
                color: "#fca5a5",
                fontSize: "0.85rem",
                textAlign: "center",
                maxWidth: 320,
                width: "100%",
              }}>
                {error}
              </p>
            ) : null}
          </>
        )}
      </div>
    </div>
  );
}

// Icons
function CameraVideoIcon() {
  return (
    <svg fill="none" height="24" viewBox="0 0 24 24" width="24">
      <rect x="2" y="5" width="15" height="14" rx="3" stroke="currentColor" strokeWidth="2" />
      <path d="M17 9.5l5-3v11l-5-3v-5z" stroke="currentColor" strokeWidth="2" strokeLinejoin="round" />
    </svg>
  );
}

function PhotoIcon() {
  return (
    <svg fill="none" height="24" viewBox="0 0 24 24" width="24">
      <rect x="3" y="3" width="18" height="18" rx="3" stroke="currentColor" strokeWidth="2" />
      <circle cx="8.5" cy="8.5" r="1.5" stroke="currentColor" strokeWidth="2" />
      <path d="m3 16 5-5 4 4 3-3 6 6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function RecordIcon() {
  return (
    <svg fill="none" height="24" viewBox="0 0 24 24" width="24">
      <circle cx="12" cy="12" r="9" stroke="currentColor" strokeWidth="2" />
      <circle cx="12" cy="12" r="4" fill="#ef4444" />
    </svg>
  );
}

function UploadFileIcon() {
  return (
    <svg fill="none" height="24" viewBox="0 0 24 24" width="24">
      <path d="M12 16V4m0 0-4 4m4-4 4 4" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M20 16v2a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-2" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
    </svg>
  );
}
