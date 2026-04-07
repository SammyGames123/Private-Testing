"use client";

import { useRouter } from "next/navigation";
import { useRef, useState, useCallback, useEffect } from "react";

type FilterName = "none" | "bw" | "warm" | "cool" | "vintage" | "vivid";

const FILTERS: { name: FilterName; label: string; css: string }[] = [
  { name: "none", label: "Normal", css: "none" },
  { name: "bw", label: "B&W", css: "grayscale(1)" },
  { name: "warm", label: "Warm", css: "sepia(0.35) saturate(1.3) brightness(1.05)" },
  { name: "cool", label: "Cool", css: "saturate(0.9) brightness(1.05) hue-rotate(15deg)" },
  { name: "vintage", label: "Vintage", css: "sepia(0.25) contrast(1.1) brightness(0.95) saturate(0.85)" },
  { name: "vivid", label: "Vivid", css: "saturate(1.6) contrast(1.1) brightness(1.05)" },
];

const TEXT_COLORS = [
  "#ffffff", "#000000", "#ff3b30", "#ff9500", "#ffcc00",
  "#34c759", "#007aff", "#5856d6", "#af52de", "#ff2d55",
];

type TextOverlay = {
  id: string;
  text: string;
  x: number;
  y: number;
  color: string;
  fontSize: number;
};

type EditorTab = "filters" | "text" | "music";

type VideoEditorProps = {
  videoUrl: string;
  storagePath: string;
  duration: string;
};

// ─── Icons ───

function PlayIcon() {
  return (
    <svg fill="currentColor" height="48" viewBox="0 0 24 24" width="48">
      <path d="M8 5v14l11-7z" />
    </svg>
  );
}

function BackIcon() {
  return (
    <svg fill="none" height="24" viewBox="0 0 24 24" width="24">
      <path d="M19 12H5M12 19l-7-7 7-7" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function TextIcon() {
  return (
    <svg fill="none" height="24" viewBox="0 0 24 24" width="24">
      <path d="M4 7V4h16v3M9 20h6M12 4v16" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function MusicIcon() {
  return (
    <svg fill="none" height="24" viewBox="0 0 24 24" width="24">
      <path d="M9 18V5l12-2v13" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
      <circle cx="6" cy="18" r="3" stroke="currentColor" strokeWidth="2" />
      <circle cx="18" cy="16" r="3" stroke="currentColor" strokeWidth="2" />
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

export function VideoEditor({ videoUrl, storagePath, duration }: VideoEditorProps) {
  const router = useRouter();
  const videoRef = useRef<HTMLVideoElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const textInputRef = useRef<HTMLInputElement>(null);
  const dragRef = useRef<{ id: string; startX: number; startY: number; origX: number; origY: number } | null>(null);

  const [playing, setPlaying] = useState(true);
  const [filter, setFilter] = useState<FilterName>("none");
  const [activeTab, setActiveTab] = useState<EditorTab | null>(null);
  const [textOverlays, setTextOverlays] = useState<TextOverlay[]>([]);
  const [editingTextId, setEditingTextId] = useState<string | null>(null);
  // When user taps the video in text mode, we create a pending overlay at that position
  const [pendingText, setPendingText] = useState<{ x: number; y: number } | null>(null);
  const [textInput, setTextInput] = useState("");
  const [textColor, setTextColor] = useState("#ffffff");
  const [musicFile, setMusicFile] = useState<File | null>(null);
  const [musicName, setMusicName] = useState("");
  const musicAudioRef = useRef<HTMLAudioElement | null>(null);
  const musicInputRef = useRef<HTMLInputElement>(null);

  const activeFilter = FILTERS.find((f) => f.name === filter) ?? FILTERS[0];

  // Play/pause
  const togglePlay = useCallback(() => {
    const v = videoRef.current;
    if (!v) return;
    if (v.paused) {
      void v.play();
      setPlaying(true);
    } else {
      v.pause();
      setPlaying(false);
    }
  }, []);

  // Sync music with video
  useEffect(() => {
    if (!musicFile) return;
    const url = URL.createObjectURL(musicFile);
    const audio = new Audio(url);
    audio.loop = true;
    musicAudioRef.current = audio;
    if (playing) void audio.play();
    return () => {
      audio.pause();
      URL.revokeObjectURL(url);
      musicAudioRef.current = null;
    };
  }, [musicFile, playing]);

  // Focus input when pending text appears
  useEffect(() => {
    if (pendingText && textInputRef.current) {
      textInputRef.current.focus();
    }
  }, [pendingText]);

  // Tap video to add text (in text mode) or play/pause
  const handleVideoTap = useCallback((e: React.MouseEvent) => {
    if (activeTab === "text" && !editingTextId) {
      const rect = containerRef.current?.getBoundingClientRect();
      if (!rect) return;
      const x = ((e.clientX - rect.left) / rect.width) * 100;
      const y = ((e.clientY - rect.top) / rect.height) * 100;
      setPendingText({ x, y });
      setTextInput("");
    } else if (!editingTextId) {
      togglePlay();
    } else {
      setEditingTextId(null);
    }
  }, [activeTab, editingTextId, togglePlay]);

  // Confirm text input
  const confirmText = useCallback(() => {
    if (!textInput.trim() || !pendingText) return;
    const overlay: TextOverlay = {
      id: `t-${Date.now()}`,
      text: textInput.trim(),
      x: pendingText.x,
      y: pendingText.y,
      color: textColor,
      fontSize: 28,
    };
    setTextOverlays((prev) => [...prev, overlay]);
    setPendingText(null);
    setTextInput("");
  }, [textInput, pendingText, textColor]);

  // Cancel text input
  const cancelText = useCallback(() => {
    setPendingText(null);
    setTextInput("");
  }, []);

  // Delete text overlay
  const deleteOverlay = useCallback((id: string) => {
    setTextOverlays((prev) => prev.filter((t) => t.id !== id));
    setEditingTextId(null);
  }, []);

  // Drag text overlay
  const handleTouchStart = useCallback((id: string, e: React.TouchEvent) => {
    e.stopPropagation();
    const touch = e.touches[0];
    const overlay = textOverlays.find((t) => t.id === id);
    if (!overlay) return;
    setEditingTextId(id);
    dragRef.current = { id, startX: touch.clientX, startY: touch.clientY, origX: overlay.x, origY: overlay.y };
  }, [textOverlays]);

  const handleTouchMove = useCallback((e: React.TouchEvent) => {
    const drag = dragRef.current;
    if (!drag || !containerRef.current) return;
    const touch = e.touches[0];
    const rect = containerRef.current.getBoundingClientRect();
    const dx = ((touch.clientX - drag.startX) / rect.width) * 100;
    const dy = ((touch.clientY - drag.startY) / rect.height) * 100;
    const newX = Math.max(5, Math.min(95, drag.origX + dx));
    const newY = Math.max(5, Math.min(95, drag.origY + dy));
    const dragId = drag.id;
    setTextOverlays((prev) =>
      prev.map((t) => (t.id === dragId ? { ...t, x: newX, y: newY } : t)),
    );
  }, []);

  const handleTouchEnd = useCallback(() => {
    dragRef.current = null;
  }, []);

  // Handle music file selection
  const handleMusicSelect = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      setMusicFile(file);
      setMusicName(file.name.replace(/\.[^.]+$/, ""));
    }
  }, []);

  const removeMusic = useCallback(() => {
    if (musicAudioRef.current) {
      musicAudioRef.current.pause();
      musicAudioRef.current = null;
    }
    setMusicFile(null);
    setMusicName("");
    if (musicInputRef.current) musicInputRef.current.value = "";
  }, []);

  // Navigate to post form
  const handleNext = useCallback(() => {
    const params = new URLSearchParams({
      storage_path: storagePath,
      playback_url: videoUrl,
      duration,
      filter: filter !== "none" ? activeFilter.css : "",
    });
    if (textOverlays.length > 0) {
      sessionStorage.setItem("pulse_text_overlays", JSON.stringify(textOverlays));
    }
    router.push(`/videos/new/post?${params.toString()}`);
  }, [storagePath, videoUrl, duration, filter, activeFilter.css, textOverlays, router]);

  const isTextMode = activeTab === "text";

  return (
    <div
      className="camera-shell"
      onTouchMove={handleTouchMove}
      onTouchEnd={handleTouchEnd}
      style={{ touchAction: "none" }}
    >
      {/* Video preview with filter */}
      <div ref={containerRef} style={{ position: "absolute", inset: 0 }} onClick={handleVideoTap}>
        <video
          autoPlay
          className="camera-preview"
          loop
          muted
          playsInline
          ref={videoRef}
          src={videoUrl}
          style={{ filter: activeFilter.css }}
        />

        {/* Text overlays */}
        {textOverlays.map((t) => (
          <div
            key={t.id}
            onTouchStart={(e) => handleTouchStart(t.id, e)}
            onClick={(e) => {
              e.stopPropagation();
              setEditingTextId(editingTextId === t.id ? null : t.id);
            }}
            style={{
              position: "absolute",
              left: `${t.x}%`,
              top: `${t.y}%`,
              transform: "translate(-50%, -50%)",
              color: t.color,
              fontSize: t.fontSize,
              fontWeight: 800,
              textShadow: "0 2px 8px rgba(0,0,0,0.6), 0 0 2px rgba(0,0,0,0.4)",
              zIndex: 15,
              userSelect: "none",
              WebkitUserSelect: "none",
              padding: "0.25rem 0.5rem",
              border: editingTextId === t.id ? "1px dashed rgba(255,255,255,0.6)" : "none",
              borderRadius: 8,
              whiteSpace: "nowrap",
            }}
          >
            {t.text}
            {editingTextId === t.id && (
              <button
                onClick={(e) => { e.stopPropagation(); deleteOverlay(t.id); }}
                style={{
                  position: "absolute",
                  top: -14,
                  right: -14,
                  width: 28,
                  height: 28,
                  borderRadius: 14,
                  background: "#ff3b30",
                  border: "2px solid white",
                  color: "white",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  padding: 0,
                  fontSize: "1rem",
                  fontWeight: 700,
                  lineHeight: 1,
                }}
                type="button"
              >
                ×
              </button>
            )}
          </div>
        ))}

        {/* Pending text input positioned on video */}
        {pendingText && (
          <div
            onClick={(e) => e.stopPropagation()}
            style={{
              position: "absolute",
              left: `${pendingText.x}%`,
              top: `${pendingText.y}%`,
              transform: "translate(-50%, -50%)",
              zIndex: 25,
              color: textColor,
              fontSize: 28,
              fontWeight: 800,
              textShadow: "0 2px 8px rgba(0,0,0,0.6)",
            }}
          >
            {textInput || (
              <span style={{ opacity: 0.4 }}>Type here...</span>
            )}
          </div>
        )}

        {/* Play indicator */}
        {!playing && !isTextMode && (
          <div style={{
            position: "absolute",
            top: "50%",
            left: "50%",
            transform: "translate(-50%, -50%)",
            background: "rgba(0,0,0,0.4)",
            borderRadius: "50%",
            width: 72,
            height: 72,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            zIndex: 5,
            pointerEvents: "none",
          }}>
            <PlayIcon />
          </div>
        )}

        {/* Tap hint for text mode */}
        {isTextMode && !pendingText && textOverlays.length === 0 && (
          <div style={{
            position: "absolute",
            top: "50%",
            left: "50%",
            transform: "translate(-50%, -50%)",
            color: "rgba(255,255,255,0.5)",
            fontSize: "1rem",
            fontWeight: 600,
            textAlign: "center",
            pointerEvents: "none",
            zIndex: 5,
          }}>
            Tap anywhere to add text
          </div>
        )}
      </div>

      {/* Top bar */}
      <div className="camera-top-bar">
        <button className="camera-icon-btn" onClick={() => router.back()} type="button">
          <BackIcon />
        </button>
        <div className="camera-top-center">
          <span style={{ color: "white", fontSize: "1rem", fontWeight: 600 }}>Edit</span>
        </div>
        <button
          onClick={handleNext}
          style={{
            background: "var(--accent, #e040fb)",
            color: "white",
            border: "none",
            borderRadius: 20,
            padding: "0.5rem 1.25rem",
            fontWeight: 700,
            fontSize: "0.9rem",
          }}
          type="button"
        >
          Next
        </button>
      </div>

      {/* Music indicator */}
      {musicName && (
        <div style={{
          position: "absolute",
          top: "calc(env(safe-area-inset-top, 0px) + 3.5rem)",
          left: "50%",
          transform: "translateX(-50%)",
          background: "rgba(0,0,0,0.5)",
          borderRadius: 20,
          padding: "0.35rem 1rem",
          display: "flex",
          alignItems: "center",
          gap: "0.5rem",
          zIndex: 20,
        }}>
          <MusicIcon />
          <span style={{ color: "white", fontSize: "0.8rem", maxWidth: 150, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
            {musicName}
          </span>
          <button
            onClick={removeMusic}
            style={{ background: "none", border: "none", color: "rgba(255,255,255,0.6)", padding: 0, fontSize: "1.2rem", lineHeight: 1 }}
            type="button"
          >
            ×
          </button>
        </div>
      )}

      {/* Text input bar (appears when tapping in text mode) */}
      {pendingText && (
        <div
          onClick={(e) => e.stopPropagation()}
          style={{
            position: "absolute",
            bottom: 0,
            left: 0,
            right: 0,
            zIndex: 30,
            background: "rgba(0,0,0,0.9)",
            backdropFilter: "blur(20px)",
            WebkitBackdropFilter: "blur(20px)",
            padding: "0.75rem 1rem",
            paddingBottom: "calc(env(safe-area-inset-bottom, 0px) + 0.75rem)",
          }}
        >
          {/* Color picker row */}
          <div style={{ display: "flex", gap: "0.35rem", justifyContent: "center", marginBottom: "0.75rem" }}>
            {TEXT_COLORS.map((c) => (
              <button
                key={c}
                onClick={() => setTextColor(c)}
                style={{
                  width: 26,
                  height: 26,
                  borderRadius: 13,
                  background: c,
                  border: textColor === c ? "2px solid white" : "2px solid rgba(255,255,255,0.2)",
                  outline: textColor === c ? "2px solid var(--accent, #e040fb)" : "none",
                  padding: 0,
                }}
                type="button"
              />
            ))}
          </div>

          {/* Input + buttons */}
          <div style={{ display: "flex", gap: "0.5rem", alignItems: "center" }}>
            <button
              onClick={cancelText}
              style={{
                background: "none",
                border: "none",
                color: "rgba(255,255,255,0.6)",
                fontSize: "0.9rem",
                fontWeight: 600,
                padding: "0.5rem",
              }}
              type="button"
            >
              Cancel
            </button>
            <input
              ref={textInputRef}
              autoFocus
              onChange={(e) => setTextInput(e.target.value)}
              onKeyDown={(e) => { if (e.key === "Enter") confirmText(); }}
              placeholder="Type your text..."
              style={{
                flex: 1,
                borderRadius: 12,
                border: "1px solid rgba(255,255,255,0.2)",
                background: "rgba(255,255,255,0.08)",
                color: "white",
                padding: "0.7rem 0.85rem",
                fontSize: "1rem",
              }}
              value={textInput}
            />
            <button
              disabled={!textInput.trim()}
              onClick={confirmText}
              style={{
                background: "var(--accent, #e040fb)",
                color: "white",
                border: "none",
                borderRadius: 12,
                padding: "0.7rem 1rem",
                fontWeight: 700,
                fontSize: "0.9rem",
                opacity: textInput.trim() ? 1 : 0.4,
              }}
              type="button"
            >
              Done
            </button>
          </div>
        </div>
      )}

      {/* Bottom toolbar (hidden when text input is active) */}
      {!pendingText && (
        <div style={{
          position: "absolute",
          bottom: 0,
          left: 0,
          right: 0,
          zIndex: 20,
          background: activeTab ? "rgba(0,0,0,0.85)" : "transparent",
          backdropFilter: activeTab ? "blur(20px)" : "none",
          WebkitBackdropFilter: activeTab ? "blur(20px)" : "none",
          paddingBottom: "env(safe-area-inset-bottom, 0px)",
          transition: "background 0.2s",
        }}>
          {/* Filters panel */}
          {activeTab === "filters" && (
            <div style={{ padding: "1rem 0.5rem 0.5rem", overflowX: "auto", display: "flex", gap: "0.5rem" }}>
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

          {/* Text panel */}
          {activeTab === "text" && (
            <div style={{ padding: "0.75rem 1rem 0.5rem" }}>
              {textOverlays.length > 0 ? (
                <p style={{ color: "rgba(255,255,255,0.5)", fontSize: "0.8rem", textAlign: "center" }}>
                  Tap video to add more text. Drag to move. Tap text to delete.
                </p>
              ) : (
                <p style={{ color: "rgba(255,255,255,0.5)", fontSize: "0.8rem", textAlign: "center" }}>
                  Tap anywhere on the video to place text
                </p>
              )}
            </div>
          )}

          {/* Music panel */}
          {activeTab === "music" && (
            <div style={{ padding: "1rem", display: "flex", flexDirection: "column", gap: "0.75rem" }}>
              <input
                ref={musicInputRef}
                type="file"
                accept="audio/*"
                onChange={handleMusicSelect}
                style={{ display: "none" }}
              />
              <button
                onClick={() => musicInputRef.current?.click()}
                style={{
                  background: "rgba(255,255,255,0.1)",
                  border: "1px solid rgba(255,255,255,0.2)",
                  borderRadius: 14,
                  color: "white",
                  padding: "0.85rem",
                  fontSize: "0.95rem",
                  fontWeight: 600,
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  gap: "0.5rem",
                }}
                type="button"
              >
                <MusicIcon />
                {musicFile ? "Change Music" : "Add Music from Library"}
              </button>
              {musicFile && (
                <button
                  onClick={removeMusic}
                  style={{
                    background: "rgba(255,59,48,0.2)",
                    border: "1px solid rgba(255,59,48,0.3)",
                    borderRadius: 14,
                    color: "#ff3b30",
                    padding: "0.75rem",
                    fontSize: "0.9rem",
                    fontWeight: 600,
                  }}
                  type="button"
                >
                  Remove Music
                </button>
              )}
            </div>
          )}

          {/* Tab buttons */}
          <div style={{
            display: "flex",
            justifyContent: "space-around",
            padding: "0.75rem 1rem",
            borderTop: activeTab ? "1px solid rgba(255,255,255,0.1)" : "none",
          }}>
            {([
              { tab: "filters" as EditorTab, icon: <FilterIcon />, label: "Filters" },
              { tab: "text" as EditorTab, icon: <TextIcon />, label: "Text" },
              { tab: "music" as EditorTab, icon: <MusicIcon />, label: "Music" },
            ]).map(({ tab, icon, label }) => (
              <button
                key={tab}
                onClick={() => {
                  setActiveTab(activeTab === tab ? null : tab);
                  setEditingTextId(null);
                }}
                style={{
                  background: "none",
                  border: "none",
                  color: activeTab === tab ? "var(--accent, #e040fb)" : "white",
                  display: "flex",
                  flexDirection: "column",
                  alignItems: "center",
                  gap: "0.2rem",
                  opacity: activeTab === tab ? 1 : 0.7,
                  padding: "0.25rem 1rem",
                }}
                type="button"
              >
                {icon}
                <span style={{ fontSize: "0.65rem", fontWeight: 600, textTransform: "uppercase", letterSpacing: "0.5px" }}>
                  {label}
                </span>
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
