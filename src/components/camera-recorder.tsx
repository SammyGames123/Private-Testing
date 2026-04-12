"use client";

import { useRouter } from "next/navigation";
import { useEffect, useRef, useState, useCallback } from "react";
import { createClient } from "@/lib/supabase/client";
interface NativeCameraPlugin {
  open(options: { mode: string }): Promise<{
    filePath: string;
    type: string;
    duration: number;
  }>;
  readFile(options: { path: string }): Promise<{
    data: string;
    mimeType: string;
    size: number;
  }>;
}

function getIsNative(): boolean {
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const { Capacitor } = require("@capacitor/core");
    return Capacitor.isNativePlatform();
  } catch {
    return false;
  }
}

function convertFileSrc(filePath: string): string {
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const { Capacitor } = require("@capacitor/core");
    return Capacitor.convertFileSrc(filePath);
  } catch {
    return filePath;
  }
}

let _nativeCameraCache: NativeCameraPlugin | null | undefined;
function getNativeCamera(): NativeCameraPlugin | null {
  if (_nativeCameraCache !== undefined) return _nativeCameraCache;
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const { registerPlugin } = require("@capacitor/core");
    _nativeCameraCache = registerPlugin<NativeCameraPlugin>("NativeCamera");
    return _nativeCameraCache;
  } catch {
    _nativeCameraCache = null;
    return null;
  }
}

type CameraRecorderProps = {
  userId: string;
};

type CaptureMode = "photo" | "video";
type RecordingLimit = 15 | 60 | 600;
type FilterName = "none" | "bw" | "warm" | "cool" | "vintage" | "vivid";

const FILTERS: { name: FilterName; label: string; css: string }[] = [
  { name: "none", label: "Normal", css: "none" },
  { name: "bw", label: "B&W", css: "grayscale(1)" },
  { name: "warm", label: "Warm", css: "sepia(0.35) saturate(1.3) brightness(1.05)" },
  { name: "cool", label: "Cool", css: "saturate(0.9) brightness(1.05) hue-rotate(15deg)" },
  { name: "vintage", label: "Vintage", css: "sepia(0.25) contrast(1.1) brightness(0.95) saturate(0.85)" },
  { name: "vivid", label: "Vivid", css: "saturate(1.6) contrast(1.1) brightness(1.05)" },
];

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

/** Upload a blob to Supabase in the background. Returns the public URL and storage path. */
function uploadInBackground(
  blob: Blob,
  userId: string,
  onProgress: (msg: string) => void,
  onDone: (result: { publicUrl: string; storagePath: string } | null) => void,
) {
  const supabase = createClient();
  const isImage = blob.type.startsWith("image/");
  const ext = isImage ? "jpg" : blob.type.includes("mp4") ? "mp4" : "webm";
  const prefix = isImage ? "photo" : "recording";
  const safeName = slugifyFileName(`${prefix}-${Date.now()}.${ext}`);
  // Use a single "videos" bucket for both photos and videos
  const bucket = "videos";
  const path = `${userId}/${Date.now()}-${safeName}`;

  onProgress("Uploading...");

  supabase.storage
    .from(bucket)
    .upload(path, blob, { cacheControl: "3600", upsert: false, contentType: blob.type })
    .then(({ error }) => {
      if (error) {
        onProgress(`Upload failed: ${error.message}`);
        onDone(null);
        return;
      }
      const { data } = supabase.storage.from(bucket).getPublicUrl(path);
      onProgress("Uploaded");
      onDone({ publicUrl: data.publicUrl, storagePath: path });
    })
    .catch(() => {
      onProgress("Upload failed");
      onDone(null);
    });
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
  const uploadResultRef = useRef<{ publicUrl: string; storagePath: string } | null>(null);

  const [captureMode, setCaptureMode] = useState<CaptureMode>("video");
  const [ready, setReady] = useState(false);
  const [recording, setRecording] = useState(false);
  const [photoUrl, setPhotoUrl] = useState<string | null>(null);
  const [elapsed, setElapsed] = useState(0);
  const [flash, setFlash] = useState(false);
  const [facingMode, setFacingMode] = useState<"user" | "environment">("environment");
  const [filter, setFilter] = useState<FilterName>("none");
  const [limit, setLimit] = useState<RecordingLimit>(60);
  const [showFilters, setShowFilters] = useState(false);
  const [showTimers, setShowTimers] = useState(false);
  const [recordedBlob, setRecordedBlob] = useState<Blob | null>(null);
  const [reviewUrl, setReviewUrl] = useState<string | null>(null);
  const [uploadStatus, setUploadStatus] = useState("");
  const [cameraError, setCameraError] = useState("");
  const [nativeLoading, setNativeLoading] = useState(false);
  const [isNative, setIsNative] = useState(false);
  const [platformChecked, setPlatformChecked] = useState(false);

  // Detect native platform on client side only
  useEffect(() => {
    const native = getIsNative();
    setIsNative(native);
    setPlatformChecked(true);
  }, []);
  const activeFilter = FILTERS.find((f) => f.name === filter) ?? FILTERS[0];

  // ─── Native camera flow (iOS) ───
  const openNativeCamera = useCallback(async (mode: CaptureMode) => {
    setNativeLoading(true);
    try {
      const nativeCamera = getNativeCamera();
      if (!nativeCamera) {
        setNativeLoading(false);
        return;
      }
      const result = await nativeCamera.open({ mode });

      // Use the converted URL for preview display (video/img src)
      const previewUrl = convertFileSrc(result.filePath);

      if (result.type === "photo") {
        setPhotoUrl(previewUrl);
        setReviewUrl(null);
        setElapsed(0);
      } else {
        setReviewUrl(previewUrl);
        setPhotoUrl(null);
        setElapsed(Math.round(result.duration));
      }

      // Read the file via the native plugin (bypasses WKWebView file access restrictions)
      setUploadStatus("Reading file...");
      try {
        const fileData = await nativeCamera.readFile({ path: result.filePath });
        // Decode base64 to Blob
        const binary = atob(fileData.data);
        const bytes = new Uint8Array(binary.length);
        for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
        const blob = new Blob([bytes], { type: fileData.mimeType });
        setRecordedBlob(blob);
        uploadResultRef.current = null;
        uploadInBackground(blob, userId, setUploadStatus, (uploadResult) => {
          uploadResultRef.current = uploadResult;
        });
      } catch (readErr) {
        setUploadStatus(`Read failed: ${readErr instanceof Error ? readErr.message : "unknown"}`);
      }
    } catch {
      // User cancelled or error — just stay on camera screen
    } finally {
      setNativeLoading(false);
    }
  }, [userId]);

  // ─── Start camera — request the highest quality the device supports ───
  const startCamera = useCallback(async () => {
    if (streamRef.current) {
      for (const track of streamRef.current.getTracks()) track.stop();
    }

    try {
      // Request 4K at max frame rate — the browser will give the best it can
      const stream = await navigator.mediaDevices.getUserMedia({
        video: {
          facingMode,
          width: { ideal: 3840 },
          height: { ideal: 2160 },
          frameRate: { ideal: 60 },
        },
        audio: true,
      });
      streamRef.current = stream;

      if (videoRef.current) {
        videoRef.current.srcObject = stream;
        await videoRef.current.play();
      }

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
  }, [facingMode, flash]);

  useEffect(() => {
    if (!platformChecked) return; // Wait until we know if native or web
    if (isNative) {
      // On native, launch the native camera immediately
      void openNativeCamera(captureMode);
    } else {
      void startCamera();
    }
    return () => {
      if (streamRef.current) {
        for (const track of streamRef.current.getTracks()) track.stop();
      }
      if (timerRef.current) clearInterval(timerRef.current);
    };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [platformChecked]);

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

  // ─── Start recording (max quality) ───
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
      videoBitsPerSecond: 20_000_000, // 20 Mbps for high quality
    });

    recorder.ondataavailable = (e) => {
      if (e.data.size > 0) chunksRef.current.push(e.data);
    };

    recorder.onstop = () => {
      const blob = new Blob(chunksRef.current, { type: mimeType });
      const url = URL.createObjectURL(blob);
      setRecordedBlob(blob);
      setReviewUrl(url);

      // Start uploading immediately in the background
      uploadResultRef.current = null;
      uploadInBackground(blob, userId, setUploadStatus, (result) => {
        uploadResultRef.current = result;
      });
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
  }, [limit, userId]);

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

  // ─── Take photo (full resolution from live stream) ───
  const takePhoto = useCallback(() => {
    const video = videoRef.current;
    if (!video) return;
    const canvas = document.createElement("canvas");
    // Use the actual video resolution for max quality
    canvas.width = video.videoWidth || 3840;
    canvas.height = video.videoHeight || 2160;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
    canvas.toBlob((blob) => {
      if (!blob) return;
      const url = URL.createObjectURL(blob);
      setRecordedBlob(blob);
      setPhotoUrl(url);
      setReviewUrl(null);
      // Start uploading immediately
      uploadResultRef.current = null;
      uploadInBackground(blob, userId, setUploadStatus, (result) => {
        uploadResultRef.current = result;
      });
    }, "image/jpeg", 0.95);
  }, [userId]);

  // ─── Handle file upload from library ───
  const handleFileUpload = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const url = URL.createObjectURL(file);
    setRecordedBlob(file);
    setReviewUrl(url);

    // Start uploading immediately in the background
    uploadResultRef.current = null;
    uploadInBackground(file, userId, setUploadStatus, (result) => {
      uploadResultRef.current = result;
    });
  }, [userId]);

  // ─── Retake ───
  const handleRetake = useCallback(() => {
    if (reviewUrl) URL.revokeObjectURL(reviewUrl);
    if (photoUrl) URL.revokeObjectURL(photoUrl);
    setRecordedBlob(null);
    setReviewUrl(null);
    setPhotoUrl(null);
    setElapsed(0);
    setUploadStatus("");
    uploadResultRef.current = null;
    if (isNative) {
      void openNativeCamera(captureMode);
    } else {
      void startCamera();
    }
  }, [reviewUrl, photoUrl, startCamera, isNative, openNativeCamera, captureMode]);

  // ─── Navigate to editor (video) or post form (photo) ───
  const handleNext = useCallback(() => {
    const result = uploadResultRef.current;
    if (result) {
      const params = new URLSearchParams({
        storage_path: result.storagePath,
        playback_url: result.publicUrl,
        duration: String(elapsed),
      });
      // Photos go straight to post, videos go to editor
      const dest = photoUrl ? "/videos/new/post" : "/videos/new/edit";
      router.push(`${dest}?${params.toString()}`);
    } else if (uploadStatus.startsWith("Upload failed")) {
      // Retry upload
      if (recordedBlob) {
        uploadInBackground(recordedBlob, userId, setUploadStatus, (r) => {
          uploadResultRef.current = r;
        });
      }
    }
    // else: still uploading, button shows progress
  }, [elapsed, router, uploadStatus, recordedBlob, userId, photoUrl]);

  const closePopups = () => {
    setShowFilters(false);
    setShowTimers(false);
  };

  // Is the background upload done?
  const uploadDone = uploadResultRef.current !== null;
  const uploadFailed = uploadStatus.startsWith("Upload failed");

  // ─── Photo review screen ───
  if (photoUrl) {
    return (
      <div className="camera-shell">
        <img
          alt="Captured photo"
          className="camera-preview"
          src={photoUrl}
          style={{ objectFit: "cover" }}
        />
        <div className="camera-top-bar">
          <button className="camera-icon-btn" onClick={handleRetake} type="button">
            <CloseIcon />
          </button>
          <div className="camera-top-center">
            <span style={{ color: "white", fontSize: "1rem", fontWeight: 600 }}>Photo</span>
          </div>
          <div style={{ width: 28 }} />
        </div>
        {!uploadDone && (
          <div style={{
            position: "absolute",
            bottom: 100,
            left: "50%",
            transform: "translateX(-50%)",
            background: uploadFailed ? "rgba(200,30,30,0.85)" : "rgba(0,0,0,0.6)",
            borderRadius: 20,
            padding: "0.4rem 1rem",
            color: "white",
            fontSize: "0.75rem",
            zIndex: 20,
            maxWidth: "80%",
            textAlign: "center",
          }}>
            {uploadStatus || "Preparing..."}
          </div>
        )}
        <div className="camera-review-bar">
          <button className="camera-review-btn" onClick={handleRetake} type="button">
            Retake
          </button>
          <button
            className={`camera-review-btn camera-review-next${!uploadDone && !uploadFailed ? " camera-review-uploading" : ""}`}
            disabled={!uploadDone && !uploadFailed}
            onClick={handleNext}
            type="button"
          >
            {uploadFailed ? "Retry" : uploadDone ? "Next" : "Uploading..."}
          </button>
        </div>
      </div>
    );
  }

  // ─── Video review screen after recording ───
  if (reviewUrl) {
    return (
      <div className="camera-shell" onClick={closePopups}>
        <video
          autoPlay
          className="camera-preview"
          loop
          playsInline
          src={reviewUrl}
        />
        <div className="camera-top-bar">
          <button className="camera-icon-btn" onClick={handleRetake} type="button">
            <CloseIcon />
          </button>
          <div className="camera-top-center">
            <span style={{ color: "white", fontSize: "1rem", fontWeight: 600 }}>Preview</span>
          </div>
          <div style={{ width: 28 }} />
        </div>
        {!uploadDone && (
          <div style={{
            position: "absolute",
            bottom: 100,
            left: "50%",
            transform: "translateX(-50%)",
            background: uploadFailed ? "rgba(200,30,30,0.85)" : "rgba(0,0,0,0.6)",
            borderRadius: 20,
            padding: "0.4rem 1rem",
            color: "white",
            fontSize: "0.75rem",
            zIndex: 20,
            maxWidth: "80%",
            textAlign: "center",
          }}>
            {uploadStatus || "Preparing..."}
          </div>
        )}
        <div className="camera-review-bar">
          <button className="camera-review-btn" onClick={handleRetake} type="button">
            Retake
          </button>
          <button
            className={`camera-review-btn camera-review-next${!uploadDone && !uploadFailed ? " camera-review-uploading" : ""}`}
            disabled={!uploadDone && !uploadFailed}
            onClick={handleNext}
            type="button"
          >
            {uploadFailed ? "Retry" : uploadDone ? "Edit" : "Uploading..."}
          </button>
        </div>
      </div>
    );
  }

  // ─── Native platform: show loading or prompt to open camera ───
  if (isNative) {
    return (
      <div className="camera-shell">
        <div style={{
          position: "absolute",
          inset: 0,
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          background: "black",
          gap: "1.5rem",
        }}>
          {nativeLoading ? (
            <p style={{ color: "rgba(255,255,255,0.7)", fontSize: "1rem" }}>
              Opening camera...
            </p>
          ) : (
            <>
              <p style={{ color: "rgba(255,255,255,0.7)", fontSize: "1rem" }}>
                Camera closed
              </p>
              <div style={{ display: "flex", gap: "1rem" }}>
                <button
                  onClick={() => void openNativeCamera("video")}
                  style={{
                    padding: "0.85rem 1.5rem",
                    borderRadius: 14,
                    background: "var(--accent, #ff2d55)",
                    color: "white",
                    border: "none",
                    fontWeight: 700,
                    fontSize: "0.95rem",
                  }}
                  type="button"
                >
                  Record Video
                </button>
                <button
                  onClick={() => void openNativeCamera("photo")}
                  style={{
                    padding: "0.85rem 1.5rem",
                    borderRadius: 14,
                    background: "rgba(255,255,255,0.15)",
                    color: "white",
                    border: "1px solid rgba(255,255,255,0.3)",
                    fontWeight: 700,
                    fontSize: "0.95rem",
                  }}
                  type="button"
                >
                  Take Photo
                </button>
              </div>
              <button
                onClick={() => router.back()}
                style={{
                  marginTop: "0.5rem",
                  background: "none",
                  border: "none",
                  color: "rgba(255,255,255,0.5)",
                  fontSize: "0.9rem",
                }}
                type="button"
              >
                Go Back
              </button>
            </>
          )}
        </div>
      </div>
    );
  }

  // ─── Camera viewfinder (web fallback) ───
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

          {captureMode === "video" && (
            <button
              className="camera-side-btn"
              onClick={(e) => {
                e.stopPropagation();
                setShowTimers((v) => !v);
                setShowFilters(false);
              }}
              type="button"
            >
              <TimerIcon />
              <span>{limit < 60 ? `${limit}s` : limit === 60 ? "60s" : "10m"}</span>
            </button>
          )}

          <button
            className="camera-side-btn"
            onClick={(e) => {
              e.stopPropagation();
              setShowFilters((v) => !v);
              setShowTimers(false);
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

      {/* Bottom: mode toggle + capture button + upload */}
      <div className="camera-bottom-bar" style={{ flexDirection: "column", gap: "1rem" }}>
        {/* Mode toggle (Photo / Video) */}
        {!recording && (
          <div style={{ display: "flex", gap: "1.25rem", justifyContent: "center" }}>
            {(["photo", "video"] as CaptureMode[]).map((m) => (
              <button
                key={m}
                onClick={() => setCaptureMode(m)}
                style={{
                  background: "none",
                  border: "none",
                  color: captureMode === m ? "white" : "rgba(255,255,255,0.45)",
                  fontWeight: captureMode === m ? 700 : 500,
                  fontSize: "0.95rem",
                  textTransform: "capitalize",
                  padding: "0.25rem 0.5rem",
                  borderBottom: captureMode === m ? "2px solid white" : "2px solid transparent",
                }}
                type="button"
              >
                {m}
              </button>
            ))}
          </div>
        )}

        {/* Capture row */}
        <div style={{ position: "relative", display: "flex", alignItems: "center", justifyContent: "center", width: "100%" }}>
          {/* Upload from library button */}
          {!recording && (
            <button
              className="camera-side-btn"
              onClick={() => fileInputRef.current?.click()}
              type="button"
              style={{ position: "absolute", left: "2rem" }}
            >
              <UploadIcon />
              <span style={{ fontSize: "0.65rem" }}>Upload</span>
            </button>
          )}

          {recording ? (
            <button
              className="camera-record-btn camera-record-btn-stop"
              onClick={stopRecording}
              type="button"
            >
              <span className="camera-stop-square" />
            </button>
          ) : captureMode === "video" ? (
            <button
              className="camera-record-btn"
              disabled={!ready}
              onClick={startRecording}
              type="button"
            >
              <span className="camera-record-inner" />
            </button>
          ) : (
            <button
              disabled={!ready}
              onClick={takePhoto}
              style={{
                width: 76,
                height: 76,
                borderRadius: "50%",
                border: "4px solid white",
                background: "rgba(255,255,255,0.15)",
                cursor: "pointer",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                padding: 0,
                opacity: ready ? 1 : 0.4,
              }}
              type="button"
            >
              <span style={{
                width: 60,
                height: 60,
                borderRadius: "50%",
                background: "white",
                display: "block",
              }} />
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
