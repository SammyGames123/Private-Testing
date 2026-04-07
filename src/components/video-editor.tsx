"use client";

import { useRouter } from "next/navigation";
import { useRef, useState, useCallback } from "react";

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

const SHAPES = [
  { id: "circle", label: "Circle", svg: '<circle cx="50" cy="50" r="40" stroke="COLOR" stroke-width="4" fill="none"/>' },
  { id: "square", label: "Square", svg: '<rect x="10" y="10" width="80" height="80" stroke="COLOR" stroke-width="4" fill="none"/>' },
  { id: "triangle", label: "Triangle", svg: '<polygon points="50,10 90,90 10,90" stroke="COLOR" stroke-width="4" fill="none"/>' },
  { id: "star", label: "Star", svg: '<polygon points="50,5 61,35 95,35 68,57 79,91 50,70 21,91 32,57 5,35 39,35" stroke="COLOR" stroke-width="3" fill="none"/>' },
  { id: "heart", label: "Heart", svg: '<path d="M50,30 A20,20,0,0,1,90,30 A20,20,0,0,1,50,80 A20,20,0,0,1,10,30 A20,20,0,0,1,50,30Z" stroke="COLOR" stroke-width="3" fill="none"/>' },
  { id: "arrow", label: "Arrow", svg: '<path d="M20,50 L80,50 M60,30 L80,50 L60,70" stroke="COLOR" stroke-width="4" fill="none" stroke-linecap="round" stroke-linejoin="round"/>' },
  { id: "circle-filled", label: "Circle", svg: '<circle cx="50" cy="50" r="40" fill="COLOR"/>' },
  { id: "square-filled", label: "Square", svg: '<rect x="10" y="10" width="80" height="80" fill="COLOR"/>' },
];

type Overlay = {
  id: string;
  type: "text" | "shape";
  // text props
  text?: string;
  // shape props
  shapeId?: string;
  shapeSvg?: string;
  // common
  x: number;
  y: number;
  color: string;
  scale: number;
  rotation: number;
};

type EditorTab = "filters" | "text" | "shapes";

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

function FilterIcon() {
  return (
    <svg fill="none" height="24" viewBox="0 0 24 24" width="24">
      <circle cx="8" cy="10" r="5" stroke="currentColor" strokeWidth="2" />
      <circle cx="16" cy="10" r="5" stroke="currentColor" strokeWidth="2" />
      <circle cx="12" cy="16" r="5" stroke="currentColor" strokeWidth="2" />
    </svg>
  );
}

function ShapesIcon() {
  return (
    <svg fill="none" height="24" viewBox="0 0 24 24" width="24">
      <circle cx="8" cy="8" r="5" stroke="currentColor" strokeWidth="2" />
      <rect x="13" y="13" width="8" height="8" rx="1" stroke="currentColor" strokeWidth="2" />
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

export function VideoEditor({ videoUrl, storagePath, duration }: VideoEditorProps) {
  const router = useRouter();
  const videoRef = useRef<HTMLVideoElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const textInputRef = useRef<HTMLInputElement>(null);

  // Gesture refs
  const gestureRef = useRef<{
    id: string;
    startX: number;
    startY: number;
    origX: number;
    origY: number;
    startDist: number;
    startAngle: number;
    origScale: number;
    origRotation: number;
    moved: boolean;
  } | null>(null);

  const [playing, setPlaying] = useState(true);
  const [muted, setMuted] = useState(false);
  const [filter, setFilter] = useState<FilterName>("none");
  const [activeTab, setActiveTab] = useState<EditorTab | null>(null);
  const [overlays, setOverlays] = useState<Overlay[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [pendingText, setPendingText] = useState<{ x: number; y: number } | null>(null);
  const [textInput, setTextInput] = useState("");
  const [currentColor, setCurrentColor] = useState("#ffffff");

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

  // Toggle mute
  const toggleMute = useCallback(() => {
    const v = videoRef.current;
    if (v) v.muted = !v.muted;
    setMuted((m) => !m);
  }, []);

  // Tap video
  const handleVideoTap = useCallback((e: React.MouseEvent) => {
    if (activeTab === "text" && !selectedId) {
      const rect = containerRef.current?.getBoundingClientRect();
      if (!rect) return;
      const x = ((e.clientX - rect.left) / rect.width) * 100;
      const y = ((e.clientY - rect.top) / rect.height) * 100;
      setPendingText({ x, y });
      setTextInput("");
      setTimeout(() => textInputRef.current?.focus(), 50);
    } else if (selectedId) {
      setSelectedId(null);
    } else {
      togglePlay();
    }
  }, [activeTab, selectedId, togglePlay]);

  // Confirm text
  const confirmText = useCallback(() => {
    if (!textInput.trim() || !pendingText) return;
    setOverlays((prev) => [...prev, {
      id: `t-${Date.now()}`,
      type: "text",
      text: textInput.trim(),
      x: pendingText.x,
      y: pendingText.y,
      color: currentColor,
      scale: 1,
      rotation: 0,
    }]);
    setPendingText(null);
    setTextInput("");
  }, [textInput, pendingText, currentColor]);

  // Add shape
  const addShape = useCallback((shapeId: string) => {
    const shape = SHAPES.find((s) => s.id === shapeId);
    if (!shape) return;
    setOverlays((prev) => [...prev, {
      id: `s-${Date.now()}`,
      type: "shape",
      shapeId: shape.id,
      shapeSvg: shape.svg,
      x: 50,
      y: 45,
      color: currentColor,
      scale: 1,
      rotation: 0,
    }]);
  }, [currentColor]);

  // Delete overlay
  const deleteOverlay = useCallback((id: string) => {
    setOverlays((prev) => prev.filter((o) => o.id !== id));
    setSelectedId(null);
  }, []);

  // ─── Gesture handling (drag + pinch to scale + rotate) ───

  const getTouchInfo = (touches: React.TouchList) => {
    if (touches.length === 1) {
      return { x: touches[0].clientX, y: touches[0].clientY, dist: 0, angle: 0 };
    }
    const dx = touches[1].clientX - touches[0].clientX;
    const dy = touches[1].clientY - touches[0].clientY;
    return {
      x: (touches[0].clientX + touches[1].clientX) / 2,
      y: (touches[0].clientY + touches[1].clientY) / 2,
      dist: Math.sqrt(dx * dx + dy * dy),
      angle: Math.atan2(dy, dx) * (180 / Math.PI),
    };
  };

  const handleOverlayTouchStart = useCallback((id: string, e: React.TouchEvent) => {
    e.stopPropagation();
    const overlay = overlays.find((o) => o.id === id);
    if (!overlay) return;
    setSelectedId(id);
    const info = getTouchInfo(e.touches);
    gestureRef.current = {
      id,
      startX: info.x,
      startY: info.y,
      origX: overlay.x,
      origY: overlay.y,
      startDist: info.dist || 1,
      startAngle: info.angle,
      origScale: overlay.scale,
      origRotation: overlay.rotation,
      moved: false,
    };
  }, [overlays]);

  const handleTouchMove = useCallback((e: React.TouchEvent) => {
    const g = gestureRef.current;
    if (!g || !containerRef.current) return;
    const rect = containerRef.current.getBoundingClientRect();
    const info = getTouchInfo(e.touches);
    g.moved = true;

    // Drag
    const dx = ((info.x - g.startX) / rect.width) * 100;
    const dy = ((info.y - g.startY) / rect.height) * 100;
    const newX = Math.max(2, Math.min(98, g.origX + dx));
    const newY = Math.max(2, Math.min(98, g.origY + dy));

    // Pinch to scale
    let newScale = g.origScale;
    let newRotation = g.origRotation;
    if (e.touches.length >= 2 && info.dist > 0) {
      newScale = Math.max(0.3, Math.min(5, g.origScale * (info.dist / g.startDist)));
      newRotation = g.origRotation + (info.angle - g.startAngle);
    }

    const gId = g.id;
    setOverlays((prev) =>
      prev.map((o) => (o.id === gId ? { ...o, x: newX, y: newY, scale: newScale, rotation: newRotation } : o)),
    );
  }, []);

  const handleTouchEnd = useCallback(() => {
    gestureRef.current = null;
  }, []);

  // Navigate to post form
  const handleNext = useCallback(() => {
    const params = new URLSearchParams({
      storage_path: storagePath,
      playback_url: videoUrl,
      duration,
      filter: filter !== "none" ? activeFilter.css : "",
    });
    if (overlays.length > 0) {
      sessionStorage.setItem("pulse_overlays", JSON.stringify(overlays));
    }
    router.push(`/videos/new/post?${params.toString()}`);
  }, [storagePath, videoUrl, duration, filter, activeFilter.css, overlays, router]);

  const isTextMode = activeTab === "text";

  return (
    <div
      className="camera-shell"
      onTouchMove={handleTouchMove}
      onTouchEnd={handleTouchEnd}
      style={{ touchAction: "none" }}
    >
      {/* Video preview */}
      <div ref={containerRef} style={{ position: "absolute", inset: 0 }} onClick={handleVideoTap}>
        <video
          autoPlay
          className="camera-preview"
          loop
          muted={muted}
          playsInline
          ref={videoRef}
          src={videoUrl}
          style={{ filter: activeFilter.css }}
        />

        {/* Overlays */}
        {overlays.map((o) => (
          <div
            key={o.id}
            onTouchStart={(e) => handleOverlayTouchStart(o.id, e)}
            onClick={(e) => {
              e.stopPropagation();
              setSelectedId(selectedId === o.id ? null : o.id);
            }}
            style={{
              position: "absolute",
              left: `${o.x}%`,
              top: `${o.y}%`,
              transform: `translate(-50%, -50%) scale(${o.scale}) rotate(${o.rotation}deg)`,
              zIndex: 15,
              userSelect: "none",
              WebkitUserSelect: "none",
              border: selectedId === o.id ? "1px dashed rgba(255,255,255,0.6)" : "none",
              borderRadius: 8,
              padding: o.type === "text" ? "0.25rem 0.5rem" : "0.25rem",
            }}
          >
            {o.type === "text" && (
              <span style={{
                color: o.color,
                fontSize: 28,
                fontWeight: 800,
                textShadow: "0 2px 8px rgba(0,0,0,0.6), 0 0 2px rgba(0,0,0,0.4)",
                whiteSpace: "nowrap",
              }}>
                {o.text}
              </span>
            )}
            {o.type === "shape" && o.shapeSvg && (
              <svg
                viewBox="0 0 100 100"
                width="80"
                height="80"
                dangerouslySetInnerHTML={{ __html: o.shapeSvg.replace(/COLOR/g, o.color) }}
              />
            )}
            {selectedId === o.id && (
              <button
                onClick={(e) => { e.stopPropagation(); deleteOverlay(o.id); }}
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

        {/* Pending text preview */}
        {pendingText && (
          <div
            onClick={(e) => e.stopPropagation()}
            style={{
              position: "absolute",
              left: `${pendingText.x}%`,
              top: `${pendingText.y}%`,
              transform: "translate(-50%, -50%)",
              zIndex: 25,
              color: currentColor,
              fontSize: 28,
              fontWeight: 800,
              textShadow: "0 2px 8px rgba(0,0,0,0.6)",
            }}
          >
            {textInput || <span style={{ opacity: 0.4 }}>Type here...</span>}
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

        {/* Tap hint */}
        {isTextMode && !pendingText && overlays.filter((o) => o.type === "text").length === 0 && (
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
        <div style={{ display: "flex", alignItems: "center", gap: "0.75rem" }}>
          <button
            onClick={toggleMute}
            style={{ background: "none", border: "none", color: "white", padding: 4 }}
            type="button"
          >
            <VolumeIcon muted={muted} />
          </button>
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
      </div>

      {/* Text input bar */}
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
          <div style={{ display: "flex", gap: "0.35rem", justifyContent: "center", marginBottom: "0.75rem" }}>
            {TEXT_COLORS.map((c) => (
              <button
                key={c}
                onClick={() => setCurrentColor(c)}
                style={{
                  width: 26,
                  height: 26,
                  borderRadius: 13,
                  background: c,
                  border: currentColor === c ? "2px solid white" : "2px solid rgba(255,255,255,0.2)",
                  outline: currentColor === c ? "2px solid var(--accent, #e040fb)" : "none",
                  padding: 0,
                }}
                type="button"
              />
            ))}
          </div>
          <div style={{ display: "flex", gap: "0.5rem", alignItems: "center" }}>
            <button
              onClick={() => { setPendingText(null); setTextInput(""); }}
              style={{ background: "none", border: "none", color: "rgba(255,255,255,0.6)", fontSize: "0.9rem", fontWeight: 600, padding: "0.5rem" }}
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

      {/* Bottom toolbar */}
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
              <p style={{ color: "rgba(255,255,255,0.5)", fontSize: "0.8rem", textAlign: "center" }}>
                {overlays.some((o) => o.type === "text")
                  ? "Tap video to add more. Pinch to resize. Two fingers to rotate."
                  : "Tap anywhere on the video to place text"}
              </p>
            </div>
          )}

          {/* Shapes panel */}
          {activeTab === "shapes" && (
            <div style={{ padding: "1rem 0.5rem 0.5rem" }}>
              <div style={{ display: "flex", gap: "0.35rem", justifyContent: "center", marginBottom: "0.75rem" }}>
                {TEXT_COLORS.map((c) => (
                  <button
                    key={c}
                    onClick={() => setCurrentColor(c)}
                    style={{
                      width: 22,
                      height: 22,
                      borderRadius: 11,
                      background: c,
                      border: currentColor === c ? "2px solid white" : "2px solid rgba(255,255,255,0.2)",
                      outline: currentColor === c ? "2px solid var(--accent, #e040fb)" : "none",
                      padding: 0,
                    }}
                    type="button"
                  />
                ))}
              </div>
              <div style={{ display: "flex", gap: "0.5rem", overflowX: "auto", padding: "0 0.5rem" }}>
                {SHAPES.map((s) => (
                  <button
                    key={s.id}
                    onClick={() => addShape(s.id)}
                    style={{
                      flexShrink: 0,
                      width: 56,
                      height: 56,
                      borderRadius: 12,
                      background: "rgba(255,255,255,0.08)",
                      border: "1px solid rgba(255,255,255,0.15)",
                      display: "flex",
                      alignItems: "center",
                      justifyContent: "center",
                      padding: 4,
                    }}
                    type="button"
                  >
                    <svg
                      viewBox="0 0 100 100"
                      width="36"
                      height="36"
                      dangerouslySetInnerHTML={{ __html: s.svg.replace(/COLOR/g, "white") }}
                    />
                  </button>
                ))}
              </div>
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
              { tab: "shapes" as EditorTab, icon: <ShapesIcon />, label: "Shapes" },
            ]).map(({ tab, icon, label }) => (
              <button
                key={tab}
                onClick={() => {
                  setActiveTab(activeTab === tab ? null : tab);
                  setSelectedId(null);
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
