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

const TEXT_SIZES = [
  { label: "S", size: 18 },
  { label: "M", size: 28 },
  { label: "L", size: 40 },
  { label: "XL", size: 56 },
];

type TextOverlay = {
  id: string;
  text: string;
  x: number;
  y: number;
  color: string;
  fontSize: number;
  bold: boolean;
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

function PauseIcon() {
  return (
    <svg fill="currentColor" height="48" viewBox="0 0 24 24" width="48">
      <path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z" />
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

function DeleteIcon() {
  return (
    <svg fill="none" height="20" viewBox="0 0 24 24" width="20">
      <path d="M3 6h18M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

export function VideoEditor({ videoUrl, storagePath, duration }: VideoEditorProps) {
  const router = useRouter();
  const videoRef = useRef<HTMLVideoElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const dragRef = useRef<{ id: string; startX: number; startY: number; origX: number; origY: number } | null>(null);

  const [playing, setPlaying] = useState(true);
  const [filter, setFilter] = useState<FilterName>("none");
  const [activeTab, setActiveTab] = useState<EditorTab | null>(null);
  const [textOverlays, setTextOverlays] = useState<TextOverlay[]>([]);
  const [editingTextId, setEditingTextId] = useState<string | null>(null);
  const [newTextInput, setNewTextInput] = useState("");
  const [newTextColor, setNewTextColor] = useState("#ffffff");
  const [newTextSize, setNewTextSize] = useState(28);
  const [newTextBold, setNewTextBold] = useState(true);
  const [showAddText, setShowAddText] = useState(false);
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

  // Add text overlay
  const handleAddText = useCallback(() => {
    if (!newTextInput.trim()) return;
    const overlay: TextOverlay = {
      id: `t-${Date.now()}`,
      text: newTextInput.trim(),
      x: 50,
      y: 50,
      color: newTextColor,
      fontSize: newTextSize,
      bold: newTextBold,
    };
    setTextOverlays((prev) => [...prev, overlay]);
    setNewTextInput("");
    setShowAddText(false);
  }, [newTextInput, newTextColor, newTextSize, newTextBold]);

  // Delete text overlay
  const deleteOverlay = useCallback((id: string) => {
    setTextOverlays((prev) => prev.filter((t) => t.id !== id));
    if (editingTextId === id) setEditingTextId(null);
  }, [editingTextId]);

  // Drag text overlay
  const handleTouchStart = useCallback((id: string, e: React.TouchEvent) => {
    const touch = e.touches[0];
    const overlay = textOverlays.find((t) => t.id === id);
    if (!overlay) return;
    dragRef.current = { id, startX: touch.clientX, startY: touch.clientY, origX: overlay.x, origY: overlay.y };
  }, [textOverlays]);

  const handleTouchMove = useCallback((e: React.TouchEvent) => {
    if (!dragRef.current || !containerRef.current) return;
    const touch = e.touches[0];
    const rect = containerRef.current.getBoundingClientRect();
    const dx = ((touch.clientX - dragRef.current.startX) / rect.width) * 100;
    const dy = ((touch.clientY - dragRef.current.startY) / rect.height) * 100;
    const newX = Math.max(5, Math.min(95, dragRef.current.origX + dx));
    const newY = Math.max(5, Math.min(95, dragRef.current.origY + dy));
    setTextOverlays((prev) =>
      prev.map((t) => (t.id === dragRef.current!.id ? { ...t, x: newX, y: newY } : t)),
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
    // Store text overlays in sessionStorage for the post page
    if (textOverlays.length > 0) {
      sessionStorage.setItem("pulse_text_overlays", JSON.stringify(textOverlays));
    }
    router.push(`/videos/new/post?${params.toString()}`);
  }, [storagePath, videoUrl, duration, filter, activeFilter.css, textOverlays, router]);

  return (
    <div
      className="camera-shell"
      onTouchMove={handleTouchMove}
      onTouchEnd={handleTouchEnd}
      style={{ touchAction: "none" }}
    >
      {/* Video preview with filter */}
      <div ref={containerRef} style={{ position: "absolute", inset: 0 }}>
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
            onClick={() => setEditingTextId(editingTextId === t.id ? null : t.id)}
            style={{
              position: "absolute",
              left: `${t.x}%`,
              top: `${t.y}%`,
              transform: "translate(-50%, -50%)",
              color: t.color,
              fontSize: t.fontSize,
              fontWeight: t.bold ? 800 : 400,
              textShadow: "0 2px 8px rgba(0,0,0,0.6), 0 0 2px rgba(0,0,0,0.4)",
              zIndex: 15,
              cursor: "grab",
              userSelect: "none",
              WebkitUserSelect: "none",
              padding: "0.25rem 0.5rem",
              border: editingTextId === t.id ? "1px dashed rgba(255,255,255,0.5)" : "1px dashed transparent",
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
                  top: -12,
                  right: -12,
                  width: 24,
                  height: 24,
                  borderRadius: 12,
                  background: "#ff3b30",
                  border: "none",
                  color: "white",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  padding: 0,
                }}
                type="button"
              >
                <DeleteIcon />
              </button>
            )}
          </div>
        ))}

        {/* Tap to play/pause */}
        <button
          onClick={togglePlay}
          style={{
            position: "absolute",
            inset: 0,
            background: "transparent",
            border: "none",
            zIndex: 5,
            cursor: "pointer",
          }}
          type="button"
        >
          {!playing && (
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
            }}>
              <PlayIcon />
            </div>
          )}
        </button>
      </div>

      {/* Top bar */}
      <div className="camera-top-bar">
        <button
          className="camera-icon-btn"
          onClick={() => router.back()}
          type="button"
        >
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
            cursor: "pointer",
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
            style={{ background: "none", border: "none", color: "rgba(255,255,255,0.6)", padding: 0, fontSize: "1.1rem", lineHeight: 1 }}
            type="button"
          >
            ×
          </button>
        </div>
      )}

      {/* Bottom toolbar tabs */}
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
        {/* Panel content */}
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

        {activeTab === "text" && !showAddText && (
          <div style={{ padding: "1rem", display: "flex", flexDirection: "column", gap: "0.75rem" }}>
            <button
              onClick={() => setShowAddText(true)}
              style={{
                background: "rgba(255,255,255,0.1)",
                border: "1px solid rgba(255,255,255,0.2)",
                borderRadius: 14,
                color: "white",
                padding: "0.85rem",
                fontSize: "0.95rem",
                fontWeight: 600,
                cursor: "pointer",
              }}
              type="button"
            >
              + Add Text
            </button>
            {textOverlays.length > 0 && (
              <p style={{ color: "rgba(255,255,255,0.5)", fontSize: "0.75rem", textAlign: "center" }}>
                Drag text to reposition. Tap to select.
              </p>
            )}
          </div>
        )}

        {activeTab === "text" && showAddText && (
          <div style={{ padding: "1rem", display: "flex", flexDirection: "column", gap: "0.75rem" }}>
            <input
              autoFocus
              onChange={(e) => setNewTextInput(e.target.value)}
              placeholder="Type your text..."
              style={{
                width: "100%",
                borderRadius: 14,
                border: "1px solid rgba(255,255,255,0.2)",
                background: "rgba(255,255,255,0.08)",
                color: "white",
                padding: "0.85rem 1rem",
                fontSize: "1rem",
              }}
              value={newTextInput}
            />

            {/* Color picker */}
            <div style={{ display: "flex", gap: "0.4rem", justifyContent: "center" }}>
              {TEXT_COLORS.map((c) => (
                <button
                  key={c}
                  onClick={() => setNewTextColor(c)}
                  style={{
                    width: 28,
                    height: 28,
                    borderRadius: 14,
                    background: c,
                    border: newTextColor === c ? "2px solid white" : "2px solid transparent",
                    outline: newTextColor === c ? "2px solid var(--accent, #e040fb)" : "none",
                    cursor: "pointer",
                    padding: 0,
                  }}
                  type="button"
                />
              ))}
            </div>

            {/* Size + Bold */}
            <div style={{ display: "flex", gap: "0.5rem", justifyContent: "center", alignItems: "center" }}>
              {TEXT_SIZES.map((s) => (
                <button
                  key={s.label}
                  onClick={() => setNewTextSize(s.size)}
                  style={{
                    padding: "0.4rem 0.75rem",
                    borderRadius: 10,
                    background: newTextSize === s.size ? "var(--accent, #e040fb)" : "rgba(255,255,255,0.1)",
                    color: "white",
                    border: "none",
                    fontWeight: 600,
                    fontSize: "0.85rem",
                    cursor: "pointer",
                  }}
                  type="button"
                >
                  {s.label}
                </button>
              ))}
              <button
                onClick={() => setNewTextBold((b) => !b)}
                style={{
                  padding: "0.4rem 0.75rem",
                  borderRadius: 10,
                  background: newTextBold ? "var(--accent, #e040fb)" : "rgba(255,255,255,0.1)",
                  color: "white",
                  border: "none",
                  fontWeight: 800,
                  fontSize: "0.85rem",
                  cursor: "pointer",
                }}
                type="button"
              >
                B
              </button>
            </div>

            <div style={{ display: "flex", gap: "0.5rem" }}>
              <button
                onClick={() => { setShowAddText(false); setNewTextInput(""); }}
                style={{
                  flex: 1,
                  padding: "0.75rem",
                  borderRadius: 14,
                  background: "rgba(255,255,255,0.1)",
                  color: "white",
                  border: "none",
                  fontWeight: 600,
                  cursor: "pointer",
                }}
                type="button"
              >
                Cancel
              </button>
              <button
                disabled={!newTextInput.trim()}
                onClick={handleAddText}
                style={{
                  flex: 1,
                  padding: "0.75rem",
                  borderRadius: 14,
                  background: "var(--accent, #e040fb)",
                  color: "white",
                  border: "none",
                  fontWeight: 600,
                  cursor: "pointer",
                  opacity: newTextInput.trim() ? 1 : 0.5,
                }}
                type="button"
              >
                Add
              </button>
            </div>
          </div>
        )}

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
                cursor: "pointer",
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
                  cursor: "pointer",
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
                setShowAddText(false);
              }}
              style={{
                background: "none",
                border: "none",
                color: activeTab === tab ? "var(--accent, #e040fb)" : "white",
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                gap: "0.2rem",
                cursor: "pointer",
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
    </div>
  );
}
