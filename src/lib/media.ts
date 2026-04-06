const imageExtensions = new Set([
  "jpg",
  "jpeg",
  "png",
  "gif",
  "webp",
  "avif",
  "bmp",
  "svg",
  "heic",
  "heif",
]);

export type MediaKind = "video" | "image";

function getUrlPath(url: string) {
  try {
    return new URL(url).pathname;
  } catch {
    return url;
  }
}

function getFileExtension(url: string) {
  const pathname = getUrlPath(url).toLowerCase();
  const cleanPath = pathname.split("?")[0]?.split("#")[0] ?? pathname;
  const segments = cleanPath.split(".");
  return segments.length > 1 ? segments.pop() ?? "" : "";
}

export function inferMediaKind(playbackUrl: string | null | undefined): MediaKind {
  if (!playbackUrl) {
    return "video";
  }

  return imageExtensions.has(getFileExtension(playbackUrl)) ? "image" : "video";
}
