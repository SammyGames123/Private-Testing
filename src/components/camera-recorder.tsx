"use client";

import { useRouter } from "next/navigation";
import { useRef, useState, useCallback } from "react";
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

function CameraIcon() {
  return (
    <svg fill="none" height="48" viewBox="0 0 24 24" width="48">
      <path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
      <circle cx="12" cy="13" r="4" stroke="currentColor" strokeWidth="1.5" />
    </svg>
  );
}

function UploadIcon() {
  return (
    <svg fill="none" height="48" viewBox="0 0 24 24" width="48">
      <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M17 8l-5-5-5 5M12 3v12" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

export function CameraRecorder({ userId }: CameraRecorderProps) {
  const router = useRouter();
  const cameraInputRef = useRef<HTMLInputElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const [uploading, setUploading] = useState(false);
  const [uploadProgress, setUploadProgress] = useState("");

  const handleFileSelected = useCallback((file: File) => {
    setSelectedFile(file);
    const url = URL.createObjectURL(file);
    setPreviewUrl(url);
  }, []);

  const handleCameraCapture = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const file = e.target.files?.[0];
      if (file) handleFileSelected(file);
    },
    [handleFileSelected],
  );

  const handleFileUpload = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const file = e.target.files?.[0];
      if (file) handleFileSelected(file);
    },
    [handleFileSelected],
  );

  const handleRetake = useCallback(() => {
    if (previewUrl) URL.revokeObjectURL(previewUrl);
    setSelectedFile(null);
    setPreviewUrl(null);
    if (cameraInputRef.current) cameraInputRef.current.value = "";
    if (fileInputRef.current) fileInputRef.current.value = "";
  }, [previewUrl]);

  const handleNext = useCallback(async () => {
    if (!selectedFile) return;
    setUploading(true);
    setUploadProgress("Uploading...");

    try {
      const supabase = createClient();
      const safeName = slugifyFileName(selectedFile.name);
      const path = `${userId}/${Date.now()}-${safeName}`;

      const { error } = await supabase.storage
        .from("videos")
        .upload(path, selectedFile, {
          cacheControl: "3600",
          upsert: false,
          contentType: selectedFile.type,
        });

      if (error) {
        setUploadProgress(`Upload failed: ${error.message}`);
        setUploading(false);
        return;
      }

      const { data } = supabase.storage.from("videos").getPublicUrl(path);

      // Get video duration
      let duration = 0;
      if (previewUrl) {
        duration = await new Promise<number>((resolve) => {
          const video = document.createElement("video");
          video.preload = "metadata";
          video.onloadedmetadata = () => resolve(Math.round(video.duration));
          video.onerror = () => resolve(0);
          video.src = previewUrl;
        });
      }

      const params = new URLSearchParams({
        storage_path: path,
        playback_url: data.publicUrl,
        duration: String(duration),
      });
      router.push(`/videos/new/post?${params.toString()}`);
    } catch {
      setUploadProgress("Upload failed. Try again.");
      setUploading(false);
    }
  }, [selectedFile, userId, previewUrl, router]);

  // Review screen after selecting/recording
  if (previewUrl && selectedFile) {
    const isVideo = selectedFile.type.startsWith("video/");
    return (
      <div className="camera-shell">
        {isVideo ? (
          <video
            autoPlay
            className="camera-preview"
            loop
            playsInline
            src={previewUrl}
          />
        ) : (
          <img
            alt="Preview"
            className="camera-preview"
            src={previewUrl}
            style={{ objectFit: "contain" }}
          />
        )}

        <div className="camera-review-bar">
          <button className="camera-review-btn" onClick={handleRetake} type="button">
            Retake
          </button>
          <button
            className="camera-review-btn camera-review-next"
            disabled={uploading}
            onClick={() => void handleNext()}
            type="button"
          >
            {uploading ? uploadProgress : "Next"}
          </button>
        </div>
      </div>
    );
  }

  // Main selection screen
  return (
    <div className="camera-shell">
      {/* Hidden native inputs */}
      <input
        ref={cameraInputRef}
        type="file"
        accept="video/*"
        capture="environment"
        onChange={handleCameraCapture}
        style={{ display: "none" }}
      />
      <input
        ref={fileInputRef}
        type="file"
        accept="video/*,image/*"
        onChange={handleFileUpload}
        style={{ display: "none" }}
      />

      {/* Top bar */}
      <div className="camera-top-bar">
        <button
          className="camera-icon-btn"
          onClick={() => router.back()}
          type="button"
        >
          <CloseIcon />
        </button>
        <div className="camera-top-center" />
        <div style={{ width: 28 }} />
      </div>

      {/* Center content */}
      <div style={{
        position: "absolute",
        inset: 0,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        gap: "1.5rem",
        padding: "2rem",
      }}>
        <h2 style={{
          color: "white",
          fontSize: "1.4rem",
          fontWeight: 700,
          marginBottom: "0.5rem",
        }}>
          Create a post
        </h2>

        <button
          onClick={() => cameraInputRef.current?.click()}
          type="button"
          style={{
            width: "100%",
            maxWidth: 280,
            padding: "1.25rem",
            borderRadius: 16,
            background: "var(--accent, #e040fb)",
            color: "white",
            border: "none",
            fontSize: "1rem",
            fontWeight: 700,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            gap: "0.75rem",
            cursor: "pointer",
          }}
        >
          <CameraIcon />
          Record Video
        </button>

        <button
          onClick={() => fileInputRef.current?.click()}
          type="button"
          style={{
            width: "100%",
            maxWidth: 280,
            padding: "1.25rem",
            borderRadius: 16,
            background: "rgba(255,255,255,0.1)",
            color: "white",
            border: "1px solid rgba(255,255,255,0.2)",
            fontSize: "1rem",
            fontWeight: 700,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            gap: "0.75rem",
            cursor: "pointer",
          }}
        >
          <UploadIcon />
          Upload from Library
        </button>
      </div>
    </div>
  );
}
