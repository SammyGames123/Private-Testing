"use client";

import { useRouter } from "next/navigation";
import { useRef, useState, useCallback, useEffect } from "react";
import { createClient } from "@/lib/supabase/client";

type CameraRecorderProps = {
  userId: string;
};

type FilterName = "none" | "bw" | "warm" | "cool" | "vintage" | "vivid";
type AspectRatio = "9:16" | "1:1" | "16:9";

const FILTERS: { name: FilterName; label: string; css: string }[] = [
  { name: "none", label: "Normal", css: "none" },
  { name: "bw", label: "B&W", css: "grayscale(1)" },
  { name: "warm", label: "Warm", css: "sepia(0.35) saturate(1.3) brightness(1.05)" },
  { name: "cool", label: "Cool", css: "saturate(0.9) brightness(1.05) hue-rotate(15deg)" },
  { name: "vintage", label: "Vintage", css: "sepia(0.25) contrast(1.1) brightness(0.95) saturate(0.85)" },
  { name: "vivid", label: "Vivid", css: "saturate(1.6) contrast(1.1) brightness(1.05)" },
];

const RATIO_LABELS: Record<AspectRatio, string> = {
  "9:16": "9:16",
  "1:1": "1:1",
  "16:9": "16:9",
};

const RATIO_ASPECT: Record<AspectRatio, number> = {
  "9:16": 9 / 16,
  "1:1": 1,
  "16:9": 16 / 9,
};

function slugifyFileName(fileName: string) {
  const parts = fileName.split(".");
  const extension = parts.length > 1 ? parts.pop()?.toLowerCase() ?? "mp4" : "mp4";
  const base = parts.join(".") || "video";
  return `${base.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 40)}.${extension}`;
}

// SVG Icons
function CloseIcon() {
  return (
    <svg fill="none" height="28" viewBox="0 0 24 24" width="28">
      <path d="m6 6 12 12M18 6 6 18" stroke="currentColor" strokeLinecap="round" strokeWidth="2" />
    </svg>
  );
}

function CameraIcon() {
  return (
    <svg fill="none" height="36" viewBox="0 0 24 24" width="36">
      <path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
      <circle cx="12" cy="13" r="4" stroke="currentColor" strokeWidth="1.5" />
    </svg>
  );
}

function UploadIcon() {
  return (
    <svg fill="none" height="36" viewBox="0 0 24 24" width="36">
      <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M17 8l-5-5-5 5M12 3v12" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function RatioIcon() {
  return (
    <svg fill="none" height="24" viewBox="0 0 24 24" width="24">
      <rect x="3" y="3" width="18" height="18" rx="3" stroke="currentColor" strokeWidth="2" />
      <path d="M3 9h18M9 3v18" stroke="currentColor" strokeWidth="1.5" />
    </svg>
  );
}

function FilterIcon() {
  return (
    <svg fill="none" height="24" viewBox="0 0 24 24" width="24">
      <circle cx="8" cy="10" r="5" stroke="currentColor" strokeWidth="2" />
      <circle cx="16" cy="10" r="5" stroke="currentColor" strokeWidth="2" />
      <circle cx="12" cy="16" r="5" stroke="currentColor" strokeWidth="2" />
    </svg>
  );
}

function VolumeIcon({ muted }: { muted: boolean }) {
  return muted ? (
    <svg fill="none" height="24" viewBox="0 0 24 24" width="24">
      <path d="M11 5L6 9H2v6h4l5 4V5zM23 9l-6 6M17 9l6 6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  ) : (
    <svg fill="none" height="24" viewBox="0 0 24 24" width="24">
      <path d="M11 5L6 9H2v6h4l5 4V5zM19.07 4.93a10 10 0 0 1 0 14.14M15.54 8.46a5 5 0 0 1 0 7.07" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

export function CameraRecorder({ userId }: CameraRecorderProps) {
  const router = useRouter();
  const cameraInputRef = useRef<HTMLInputElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const videoRef = useRef<HTMLVideoElement>(null);

  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const [filter, setFilter] = useState<FilterName>("none");
  const [ratio, setRatio] = useState<AspectRatio>("9:16");
  const [showFilters, setShowFilters] = useState(false);
  const [showRatios, setShowRatios] = useState(false);
  const [muted, setMuted] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [uploadProgress, setUploadProgress] = useState("");
  const [videoDimensions, setVideoDimensions] = useState({ w: 1080, h: 1920 });

  const activeFilter = FILTERS.find((f) => f.name === filter) ?? FILTERS[0];

  // Get video natural dimensions for cropping
  useEffect(() => {
    if (!previewUrl || !selectedFile?.type.startsWith("video/")) return;
    const v = document.createElement("video");
    v.preload = "metadata";
    v.onloadedmetadata = () => {
      setVideoDimensions({ w: v.videoWidth, h: v.videoHeight });
    };
    v.src = previewUrl;
  }, [previewUrl, selectedFile]);

  const handleFileSelected = useCallback((file: File) => {
    setSelectedFile(file);
    const url = URL.createObjectURL(file);
    setPreviewUrl(url);
    setFilter("none");
    setRatio("9:16");
    setShowFilters(false);
    setShowRatios(false);
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
    setShowFilters(false);
    setShowRatios(false);
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

      let duration = 0;
      if (previewUrl && selectedFile.type.startsWith("video/")) {
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
        filter: filter !== "none" ? activeFilter.css : "",
        ratio,
      });
      router.push(`/videos/new/post?${params.toString()}`);
    } catch {
      setUploadProgress("Upload failed. Try again.");
      setUploading(false);
    }
  }, [selectedFile, userId, previewUrl, router, filter, activeFilter.css, ratio]);

  const closePopups = () => {
    setShowFilters(false);
    setShowRatios(false);
  };

  // Compute crop style for aspect ratio preview
  const getCropStyle = (): React.CSSProperties => {
    const targetAspect = RATIO_ASPECT[ratio];
    const videoAspect = videoDimensions.w / videoDimensions.h;

    if (ratio === "9:16") {
      // Full height, no crop needed for portrait video
      return { width: "100%", height: "100%", objectFit: "cover" as const };
    }

    if (targetAspect > videoAspect) {
      // Target is wider than video — crop top/bottom
      const scale = targetAspect / videoAspect;
      return {
        width: "100%",
        height: `${scale * 100}%`,
        objectFit: "cover" as const,
        position: "absolute" as const,
        top: "50%",
        left: "50%",
        transform: "translate(-50%, -50%)",
      };
    }
    // Target is taller — crop sides
    const scale = videoAspect / targetAspect;
    return {
      width: `${scale * 100}%`,
      height: "100%",
      objectFit: "cover" as const,
      position: "absolute" as const,
      top: "50%",
      left: "50%",
      transform: "translate(-50%, -50%)",
    };
  };

  const getContainerStyle = (): React.CSSProperties => {
    if (ratio === "9:16") {
      return { position: "absolute", inset: 0, overflow: "hidden" };
    }
    const aspect = RATIO_ASPECT[ratio];
    const maxW = "100%";
    return {
      position: "absolute",
      top: "50%",
      left: "50%",
      transform: "translate(-50%, -50%)",
      width: maxW,
      aspectRatio: `${aspect}`,
      maxHeight: "80vh",
      overflow: "hidden",
      borderRadius: 12,
    };
  };

  // ─── Editing screen after selecting/recording ───
  if (previewUrl && selectedFile) {
    const isVideo = selectedFile.type.startsWith("video/");

    return (
      <div className="camera-shell" onClick={closePopups}>
        {/* Preview with filter + crop */}
        <div style={getContainerStyle()}>
          {isVideo ? (
            <video
              autoPlay
              loop
              muted={muted}
              playsInline
              ref={videoRef}
              src={previewUrl}
              style={{
                ...getCropStyle(),
                filter: activeFilter.css,
              }}
            />
          ) : (
            <img
              alt="Preview"
              src={previewUrl}
              style={{
                ...getCropStyle(),
                filter: activeFilter.css,
              }}
            />
          )}
        </div>

        {/* Top bar */}
        <div className="camera-top-bar">
          <button className="camera-icon-btn" onClick={handleRetake} type="button">
            <CloseIcon />
          </button>
          <div className="camera-top-center">
            <span style={{ color: "white", fontSize: "1rem", fontWeight: 600 }}>Edit</span>
          </div>
          <div style={{ width: 28 }} />
        </div>

        {/* Right side controls */}
        <div className="camera-side-controls">
          {isVideo && (
            <button className="camera-side-btn" onClick={() => setMuted((m) => !m)} type="button">
              <VolumeIcon muted={muted} />
              <span>{muted ? "Unmute" : "Mute"}</span>
            </button>
          )}

          <button
            className="camera-side-btn"
            onClick={(e) => {
              e.stopPropagation();
              setShowRatios((v) => !v);
              setShowFilters(false);
            }}
            type="button"
          >
            <RatioIcon />
            <span>{RATIO_LABELS[ratio]}</span>
          </button>

          <button
            className="camera-side-btn"
            onClick={(e) => {
              e.stopPropagation();
              setShowFilters((v) => !v);
              setShowRatios(false);
            }}
            type="button"
          >
            <FilterIcon />
            <span>Filter</span>
          </button>
        </div>

        {/* Ratio picker popup */}
        {showRatios && (
          <div className="camera-popup camera-popup-right" onClick={(e) => e.stopPropagation()}>
            {(["9:16", "1:1", "16:9"] as AspectRatio[]).map((r) => (
              <button
                className={`camera-popup-item ${ratio === r ? "active" : ""}`}
                key={r}
                onClick={() => {
                  setRatio(r);
                  setShowRatios(false);
                }}
                type="button"
              >
                {r}
              </button>
            ))}
          </div>
        )}

        {/* Filter strip */}
        {showFilters && (
          <div className="camera-filter-strip" onClick={(e) => e.stopPropagation()}>
            {FILTERS.map((f) => (
              <button
                className={`camera-filter-chip ${filter === f.name ? "active" : ""}`}
                key={f.name}
                onClick={() => setFilter(f.name)}
                type="button"
              >
                {f.label}
              </button>
            ))}
          </div>
        )}

        {/* Bottom bar */}
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

  // ─── Main selection screen ───
  return (
    <div className="camera-shell">
      {/* Hidden native inputs — capture opens native iOS camera */}
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
        gap: "1.25rem",
        padding: "2rem",
      }}>
        <h2 style={{
          color: "white",
          fontSize: "1.5rem",
          fontWeight: 700,
          marginBottom: "0.25rem",
        }}>
          Create a post
        </h2>
        <p style={{
          color: "rgba(255,255,255,0.5)",
          fontSize: "0.85rem",
          marginBottom: "0.75rem",
          textAlign: "center",
        }}>
          Record a new video or upload from your library
        </p>

        <button
          onClick={() => cameraInputRef.current?.click()}
          type="button"
          style={{
            width: "100%",
            maxWidth: 300,
            padding: "1.1rem 1.5rem",
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
            maxWidth: 300,
            padding: "1.1rem 1.5rem",
            borderRadius: 16,
            background: "rgba(255,255,255,0.08)",
            color: "white",
            border: "1px solid rgba(255,255,255,0.15)",
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
