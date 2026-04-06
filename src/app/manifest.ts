import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Pulse",
    short_name: "Pulse",
    description:
      "Pulse is a mobile-first social feed for short videos, photos, comments, and direct messages.",
    start_url: "/feed",
    display: "standalone",
    background_color: "#120d11",
    theme_color: "#f56b33",
    orientation: "portrait",
    categories: ["social", "entertainment", "lifestyle"],
    icons: [
      {
        src: "/icon",
        sizes: "512x512",
        type: "image/png",
      },
      {
        src: "/apple-icon",
        sizes: "180x180",
        type: "image/png",
      },
    ],
  };
}
