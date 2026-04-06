import type { Metadata } from "next";
import { BottomNav } from "@/components/bottom-nav";
import { createClient } from "@/lib/supabase/server";
import "./globals.css";

export const metadata: Metadata = {
  title: "PulsePlay",
  description: "Production starter for a social video platform built with Next.js.",
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
        {user ? <BottomNav /> : null}
      </body>
    </html>
  );
}
