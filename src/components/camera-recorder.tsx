"use client";

import { useRouter } from "next/navigation";
import { useEffect, useRef, useState, useCallback } from "react";
import { createClient } from "@/lib/supabase/client";

type CameraRecorderProps = {
  userId: string;
};

type RecordingLimit = 15 | 60 | 600;
type AspectRatio = "9:16" | "1:1" | "16:9";
type FilterName = "none" | "bw" | "warm" | "cool" | "vintage" | "vivid";

const FILTERS: { name: FilterName; label: string; css: string }[] = [
  { name: "none", label: "Normal", css: "none" },
  { name: "bw", label: "B&W", css: "grayscale(1)" },
  { name: "warm", label: "Warm", css: "sepia(0.35) saturate(1.3) brightness(1.05)" },
  { name: "cool", label: "Cool", css: "saturate(0.9) brightness(1.05) hue-rotate(15deg)" },
  { name: "vintage", label: "Vintage", css: "sepia(0.25) contrast(1.1) brightness(0.95) saturate(0.85)" },
  { name: "vivid", label: "Vivid", css: "saturate(1.6) contrast(1.1) brightness(1.05)" },
];

const RATIO_CONSTRAINTS: Record<AspectRatio, { width: number; height: number }> = {
  "9:16": { width: 1080, height: 1920 },
  "1:1": { width: 1080, height: 1080 },
  "16:9": { width: 1920, height: 1080 },
};

function formatTime(seconds: number) {
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return `${m}:${s.toString().padStart(2, "0")}`;
}

function slugifyFileName(fileName: string) {
  const parts = fileName.split(".");
  const extension = parts.length > 1 ? parts.pop()?.toLowerCase() ?? "mp4" : "mp4";
  const base = parts.join(".") || "video";
  return `${base.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 40)}.${extension}`;
}

// ─── SVG Icons ───

function CloseIcon() {
  return (
    <svg fill="none" height="28" viewBox="0 0 24 24" width="28">
      <path d="m6 6 12 12M18 6 6 18" stroke="currentColor" strokeLinecap="round" strokeWidth="2" />
    </svg>
  );
}

function FlashIcon({ on }: { on: boolean }) {
  return on ? (
    <svg fill="currentColor" height="24" viewBox="0 0 24 24" width="24">
      <path d="M7 2v11h3v9l7-12h-4l4-8z" />
    </svg>
  ) : (
    <svg fill="none" height="24" viewBox="0 0 24 24" width="24">
      <path d="M7 2v11h3v9l7-12h-4l4-8z" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" />
      <path d="M3 21 21 3" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
    </svg>
  );
}

function FlipIcon() {
  return (
    <svg fill="none" height="24" viewBox="0 0 24 24" width="24">
      <path d="M16 3h5v5M8 21H3v-5M21 3l-7 7M3 21l7-7" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function TimerIcon() {
  return (
    <svg fill="none" height="24" viewBox="0 0 24 24" width="24">
      <circle cx="12" cy="13" r="8" stroke="currentColor" strokeWidth="2" />
      <path d="M12 9v4l2.5 2.5M10 2h4" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
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

function UploadIcon() {
  return (
    <svg fill="none" height="22" viewBox="0 0 24 24" width="22">
      <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M17 8l-5-5-5 5M12 3v12" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

export function CameraRecorder({ userId }: CameraRecorderProps) {
  const router = useRouter();
  const videoRef = useRef<HTMLVideoElement>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const mediaRecorderRef = useRef<MediaRecorder | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const [ready, setReady] = useState(false);
  const [recording, setRecording] = useState(false);
  const [elapsed, setElapsed] = useState(0);
  const [flash, setFlash] = useState(false);
  const [facingMode, setFacingMode] = useState<"user" | "environment">("environment");
  const [ratio, setRatio] = useState<AspectRatio>("9:16");
  const [filter, setFilter] = useState<FilterName>("none");
  const [limit, setLimit] = useState<RecordingLimit>(60);
  const [showFilters, setShowFilters] = useState(false);
  const [showTimers, setShowTimers] = useState(false);
  const [showRatios, setShowRatios] = useState(false);
  const [recordedBlob, setRecordedBlob] = useState<Blob | null>(null);
  const [reviewUrl, setReviewUrl] = useState<string | null>(null);
  const [uploading, setUploading] = useState(false);
  const [uploadProgress, setUploadProgress] = useState("");
  const [cameraError, setCameraError] = useState("");

  const activeFilter = FILTERS.find((f) => f.name === filter) ?? FILTERS[0];

  // ─── Start camera ───
  const startCamera = useCallback(async () => {
    if (streamRef.current) {
      for (const track of streamRef.current.getTracks()) track.stop();
    }

    const constraints = RATIO_CONSTRAINTS[ratio];
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: {
          facingMode,
          width: { ideal: constraints.width },
          height: { ideal: constraints.height },
          frameRate: { ideal: 60, min: 30 },
        },
        audio: true,
      });
      streamRef.current = stream;

      if (videoRef.current) {
        videoRef.current.srcObject = stream;
        await videoRef.current.play();
      }

      // Flash (torch) support
      const videoTrack = stream.getVideoTracks()[0];
      if (videoTrack && flash) {
        try {
          await videoTrack.applyConstraints({
            // @ts-expect-error - torch is not in the standard type
            advanced: [{ torch: true }],
          });
        } catch {
          // torch not supported
        }
      }

      setReady(true);
      setCameraError("");
    } catch (err) {
      setReady(false);
      setCameraError(
        err instanceof Error ? err.message : "Camera access denied. Check permissions in Settings."
      );
    }
  }, [facingMode, ratio, flash]);

  useEffect(() => {
    void startCamera();
    return () => {
      if (streamRef.current) {
        for (const track of streamRef.current.getTracks()) track.stop();
      }
      if (timerRef.current) clearInterval(timerRef.current);
    };
  }, [startCamera]);

  // ─── Toggle flash ───
  const toggleFlash = useCallback(async () => {
    const next = !flash;
    setFlash(next);
    const track = streamRef.current?.getVideoTracks()[0];
    if (track) {
      try {
        await track.applyConstraints({
          // @ts-expect-error - torch is not in the standard type
          advanced: [{ torch: next }],
        });
      } catch {
        // not supported
      }
    }
  }, [flash]);

  // ─── Flip camera ───
  const flipCamera = useCallback(() => {
    setFacingMode((m) => (m === "user" ? "environment" : "user"));
  }, []);

  // ─── Start recording ───
  const startRecording = useCallback(() => {
    if (!streamRef.current) return;

    chunksRef.current = [];
    const mimeType = MediaRecorder.isTypeSupported("video/mp4")
      ? "video/mp4"
      : MediaRecorder.isTypeSupported("video/webm;codecs=h264")
        ? "video/webm;codecs=h264"
        : "video/webm";

    const recorder = new MediaRecorder(streamRef.current, {
      mimeType,
      videoBitsPerSecond: 12_000_000,
    });

    recorder.ondataavailable = (e) => {
      if (e.data.size > 0) chunksRef.current.push(e.data);
    };

    recorder.onstop = () => {
      const blob = new Blob(chunksRef.current, { type: mimeType });
      const url = URL.createObjectURL(blob);
      setRecordedBlob(blob);
      setReviewUrl(url);
    };

    recorder.start(500);
    mediaRecorderRef.current = recorder;
    setRecording(true);
    setElapsed(0);

    timerRef.current = setInterval(() => {
      setElapsed((prev) => {
        const next = prev + 1;
        if (next >= limit) {
          stopRecording();
        }
        return next;
      });
    }, 1000);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [limit]);

  // ─── Stop recording ───
  const stopRecording = useCallback(() => {
    if (mediaRecorderRef.current?.state === "recording") {
      mediaRecorderRef.current.stop();
    }
    if (timerRef.current) {
      clearInterval(timerRef.current);
      timerRef.current = null;
    }
    setRecording(false);
  }, []);

  // ─── Handle file upload from library ───
  const handleFileUpload = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const url = URL.createObjectURL(file);
    setRecordedBlob(file);
    setReviewUrl(url);
  }, []);

  // ─── Retake ───
  const handleRetake = useCallback(() => {
    if (reviewUrl) URL.revokeObjectURL(reviewUrl);
    setRecordedBlob(null);
    setReviewUrl(null);
    setElapsed(0);
    void startCamera();
  }, [reviewUrl, startCamera]);

  // ─── Upload and go to post form ───
  const handleNext = useCallback(async () => {
    if (!recordedBlob) return;
    setUploading(true);
    setUploadProgress("Uploading video...");

    try {
      const supabase = createClient();
      const ext = recordedBlob.type.includes("mp4") ? "mp4" : "webm";
      const fileName = `recording-${Date.now()}.${ext}`;
      const safeName = slugifyFileName(fileName);
      const path = `${userId}/${Date.now()}-${safeName}`;

      const { error } = await supabase.storage
        .from("videos")
        .upload(path, recordedBlob, {
          cacheControl: "3600",
          upsert: false,
          contentType: recordedBlob.type,
        });

      if (error) {
        setUploadProgress(`Upload failed: ${error.message}`);
        setUploading(false);
        return;
      }

      const { data } = supabase.storage.from("videos").getPublicUrl(path);

      const params = new URLSearchParams({
        storage_path: path,
        playback_url: data.publicUrl,
        duration: String(elapsed),
        filter: filter !== "none" ? activeFilter.css : "",
        ratio,
      });
      router.push(`/videos/new/post?${params.toString()}`);
    } catch {
      setUploadProgress("Upload failed. Try again.");
      setUploading(false);
    }
  }, [recordedBlob, userId, elapsed, router, filter, activeFilter.css, ratio]);

  // Close popups on tap elsewhere
  const closePopups = () => {
    setShowFilters(false);
    setShowTimers(false);
    setShowRatios(false);
  };

  // ─── Review screen after recording ───
  if (reviewUrl) {
    return (
      <div className="camera-shell">
        <video
          autoPlay
          className="camera-preview"
          loop
          playsInline
          src={reviewUrl}
          style={{ filter: activeFilter.css }}
        />

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

        {/* Right side editing controls */}
        <div className="camera-side-controls">
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

  // ─── Camera viewfinder (TikTok-style) ───
  return (
    <div className="camera-shell" onClick={closePopups}>
      {/* Hidden file input for upload from library */}
      <input
        ref={fileInputRef}
        type="file"
        accept="video/*,image/*"
        onChange={handleFileUpload}
        style={{ display: "none" }}
      />

      {/* Live camera preview */}
      <video
        autoPlay
        className="camera-preview"
        muted
        playsInline
        ref={videoRef}
        style={{ filter: activeFilter.css }}
      />

      {/* Camera error overlay */}
      {cameraError && (
        <div style={{
          position: "absolute",
          inset: 0,
          zIndex: 30,
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          padding: "2rem",
          textAlign: "center",
          background: "rgba(0,0,0,0.85)",
        }}>
          <p style={{ fontSize: "1.1rem", fontWeight: 700, color: "white" }}>Camera unavailable</p>
          <p style={{ marginTop: "0.75rem", fontSize: "0.9rem", color: "rgba(255,255,255,0.6)", lineHeight: 1.5 }}>
            {cameraError}
          </p>
          <button
            onClick={() => void startCamera()}
            style={{
              marginTop: "1.5rem",
              padding: "0.85rem 1.5rem",
              borderRadius: 14,
              background: "var(--accent)",
              color: "white",
              border: "none",
              fontWeight: 700,
              fontSize: "0.95rem",
            }}
            type="button"
          >
            Try again
          </button>
        </div>
      )}

      {/* Top bar */}
      <div className="camera-top-bar">
        <button className="camera-icon-btn" onClick={() => router.back()} type="button">
          <CloseIcon />
        </button>

        <div className="camera-top-center">
          {recording && (
            <div className="camera-recording-badge">
              <span className="camera-rec-dot" />
              <span>{formatTime(elapsed)}</span>
              <span className="camera-rec-limit">/ {formatTime(limit)}</span>
            </div>
          )}
        </div>

        <div style={{ width: 28 }} />
      </div>

      {/* Right side controls (hidden while recording) */}
      {!recording && (
        <div className="camera-side-controls">
          <button className="camera-side-btn" onClick={() => void toggleFlash()} type="button">
            <FlashIcon on={flash} />
            <span>Flash</span>
          </button>

          <button className="camera-side-btn" onClick={flipCamera} type="button">
            <FlipIcon />
            <span>Flip</span>
          </button>

          <button
            className="camera-side-btn"
            onClick={(e) => {
              e.stopPropagation();
              setShowTimers((v) => !v);
              setShowFilters(false);
              setShowRatios(false);
            }}
            type="button"
          >
            <TimerIcon />
            <span>{limit < 60 ? `${limit}s` : limit === 60 ? "60s" : "10m"}</span>
          </button>

          <button
            className="camera-side-btn"
            onClick={(e) => {
              e.stopPropagation();
              setShowRatios((v) => !v);
              setShowFilters(false);
              setShowTimers(false);
            }}
            type="button"
          >
            <RatioIcon />
            <span>{ratio}</span>
          </button>

          <button
            className="camera-side-btn"
            onClick={(e) => {
              e.stopPropagation();
              setShowFilters((v) => !v);
              setShowTimers(false);
              setShowRatios(false);
            }}
            type="button"
          >
            <FilterIcon />
            <span>Filter</span>
          </button>
        </div>
      )}

      {/* Timer picker popup */}
      {showTimers && (
        <div className="camera-popup camera-popup-right" onClick={(e) => e.stopPropagation()}>
          {([15, 60, 600] as RecordingLimit[]).map((t) => (
            <button
              className={`camera-popup-item ${limit === t ? "active" : ""}`}
              key={t}
              onClick={() => { setLimit(t); setShowTimers(false); }}
              type="button"
            >
              {t < 60 ? `${t}s` : t === 60 ? "60s" : "10m"}
            </button>
          ))}
        </div>
      )}

      {/* Ratio picker popup */}
      {showRatios && (
        <div className="camera-popup camera-popup-right" onClick={(e) => e.stopPropagation()}>
          {(["9:16", "1:1", "16:9"] as AspectRatio[]).map((r) => (
            <button
              className={`camera-popup-item ${ratio === r ? "active" : ""}`}
              key={r}
              onClick={() => { setRatio(r); setShowRatios(false); }}
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

      {/* Bottom: record button + upload */}
      <div className="camera-bottom-bar">
        {recording ? (
          <button
            className="camera-record-btn camera-record-btn-stop"
            onClick={stopRecording}
            type="button"
          >
            <span className="camera-stop-square" />
          </button>
        ) : (
          <>
            {/* Upload from library button */}
            <button
              className="camera-side-btn"
              onClick={() => fileInputRef.current?.click()}
              type="button"
              style={{ position: "absolute", left: "2rem", bottom: "2.5rem" }}
            >
              <UploadIcon />
              <span style={{ fontSize: "0.65rem" }}>Upload</span>
            </button>

            {/* Record button */}
            <button
              className="camera-record-btn"
              disabled={!ready}
              onClick={startRecording}
              type="button"
            >
              <span className="camera-record-inner" />
            </button>
          </>
        )}
      </div>
    </div>
  );
}
