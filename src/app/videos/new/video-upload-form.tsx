"use client";
/* eslint-disable @next/next/no-img-element */

import { useState, useTransition } from "react";
import { createClient } from "@/lib/supabase/client";

type Props = {
  userId: string;
};

function slugifyFileName(fileName: string) {
  const parts = fileName.split(".");
  const extension = parts.length > 1 ? parts.pop()?.toLowerCase() ?? "mp4" : "mp4";
  const base = parts.join(".") || "video";

  return `${base
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 40)}.${extension}`;
}

async function pickFileNative(): Promise<File | null> {
  try {
    const { FilePicker } = await import("@capawesome/capacitor-file-picker");
    const result = await FilePicker.pickFiles({
      types: ["video/*", "image/*"],
      limit: 1,
      readData: true,
    });

    const picked = result.files[0];
    if (!picked || !picked.data) return null;

    const binary = atob(picked.data);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
      bytes[i] = binary.charCodeAt(i);
    }

    const mimeType = picked.mimeType || "video/mp4";
    const fileName = picked.name || `video-${Date.now()}.mp4`;

    return new File([bytes], fileName, { type: mimeType });
  } catch {
    return null;
  }
}

function isNativePlatform() {
  try {
    const { Capacitor } = require("@capacitor/core");
    return Capacitor.isNativePlatform();
  } catch {
    return false;
  }
}

export function VideoUploadForm({ userId }: Props) {
  const [fileName, setFileName] = useState("");
  const [storagePath, setStoragePath] = useState("");
  const [playbackUrl, setPlaybackUrl] = useState("");
  const [previewKind, setPreviewKind] = useState<"video" | "image">("video");
  const [uploadError, setUploadError] = useState("");
  const [isPending, startTransition] = useTransition();

  const uploadFile = (file: File) => {
    setFileName(file.name);
    setPreviewKind(file.type.startsWith("image/") ? "image" : "video");
    setUploadError("");

    startTransition(async () => {
      const supabase = createClient();
      const safeName = slugifyFileName(file.name);
      const path = `${userId}/${Date.now()}-${safeName}`;

      const { error } = await supabase.storage
        .from("videos")
        .upload(path, file, {
          cacheControl: "3600",
          upsert: false,
          contentType: file.type,
        });

      if (error) {
        setStoragePath("");
        setPlaybackUrl("");
        setUploadError(error.message);
        return;
      }

      const { data } = supabase.storage.from("videos").getPublicUrl(path);

      setStoragePath(path);
      setPlaybackUrl(data.publicUrl);
      setUploadError("");
    });
  };

  const handleFileChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];

    if (!file) {
      setFileName("");
      setStoragePath("");
      setPlaybackUrl("");
      setPreviewKind("video");
      setUploadError("");
      return;
    }

    uploadFile(file);
  };

  const handleNativePick = () => {
    startTransition(async () => {
      const file = await pickFileNative();
      if (file) {
        uploadFile(file);
      }
    });
  };

  const native = isNativePlatform();

  return (
    <>
      <div>
        <label className="mb-2 block text-sm font-semibold" htmlFor="video_file">
          Upload video or photo
        </label>
        {native ? (
          <button
            className="w-full rounded-2xl border border-black/10 bg-white px-4 py-3 text-left text-[var(--muted)]"
            onClick={handleNativePick}
            type="button"
          >
            {fileName || "Tap to choose a file"}
          </button>
        ) : (
          <input
            accept="video/*,image/*"
            className="w-full rounded-2xl border border-black/10 bg-white px-4 py-3 outline-none"
            id="video_file"
            onChange={handleFileChange}
            type="file"
          />
        )}
        <p className="mt-2 text-sm text-[var(--muted)]">
          Upload directly from your device. Videos and images both become feed
          posts.
        </p>
      </div>

      <input name="storage_path" type="hidden" value={storagePath} />
      <input name="uploaded_playback_url" type="hidden" value={playbackUrl} />

      {isPending ? (
        <p className="rounded-2xl bg-amber-50 px-4 py-3 text-sm text-amber-800">
          Uploading {fileName || "video"}...
        </p>
      ) : null}

      {playbackUrl ? (
        <div className="space-y-3 rounded-2xl bg-emerald-50 px-4 py-3 text-sm text-emerald-800">
          <p>Uploaded successfully. Your media file is ready to publish.</p>
          {previewKind === "image" ? (
            <img
              alt={fileName || "Uploaded media"}
              className="max-h-64 rounded-2xl border border-emerald-200 object-contain"
              src={playbackUrl}
            />
          ) : (
            <video
              className="max-h-64 rounded-2xl border border-emerald-200 bg-black"
              controls
              muted
              playsInline
              src={playbackUrl}
            />
          )}
        </div>
      ) : null}

      {uploadError ? (
        <div className="rounded-2xl bg-red-50 px-4 py-3 text-sm text-red-700">
          {uploadError}
        </div>
      ) : null}
    </>
  );
}
