import type { Metadata, Viewport } from "next";
import { BottomNav } from "@/components/bottom-nav";
import { PwaBoot } from "@/components/pwa-boot";
import { createClient } from "@/lib/supabase/server";
import "./globals.css";

export const metadata: Metadata = {
  applicationName: "Pulse",
  title: {
    default: "Pulse",
    template: "%s | Pulse",
  },
  description: "Pulse is a mobile-first social feed for short videos, photos, comments, and direct messages.",
  manifest: "/manifest.webmanifest",
  appleWebApp: {
    capable: true,
    statusBarStyle: "black-translucent",
    title: "Pulse",
  },
  formatDetection: {
    telephone: false,
  },
  icons: {
    apple: "/apple-icon",
    icon: [
      { url: "/icon", sizes: "512x512", type: "image/png" },
    ],
  },
};

export const viewport: Viewport = {
  themeColor: "#f56b33",
};

export default async function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  return (
    <html lang="en" className="h-full antialiased">
      <body className={user ? "min-h-full flex flex-col has-bottom-nav" : "min-h-full flex flex-col"}>
        {children}
        <PwaBoot />
        {user ? <BottomNav /> : null}
      </body>
    </html>
  );
}
