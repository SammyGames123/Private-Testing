import { headers } from "next/headers";

function trimTrailingSlash(value: string) {
  return value.endsWith("/") ? value.slice(0, -1) : value;
}

const FALLBACK_PUBLIC_SITE_URL = "https://admin.spilltop.com";

export async function getSiteUrl() {
  const explicitUrl =
    process.env.NEXT_PUBLIC_SITE_URL ||
    process.env.SITE_URL ||
    process.env.CAPACITOR_LIVE_URL;

  if (explicitUrl) {
    return trimTrailingSlash(explicitUrl);
  }

  const headerStore = await headers();
  const forwardedProto = headerStore.get("x-forwarded-proto") ?? "https";
  const forwardedHost = headerStore.get("x-forwarded-host");
  const host = forwardedHost ?? headerStore.get("host");

  if (host) {
    return `${forwardedProto}://${host}`;
  }

  if (process.env.VERCEL_URL) {
    return `https://${process.env.VERCEL_URL}`;
  }

  return "http://localhost:3000";
}

export async function getAuthSiteUrl() {
  const explicitAuthUrl =
    process.env.NEXT_PUBLIC_AUTH_SITE_URL ||
    process.env.AUTH_SITE_URL;

  if (explicitAuthUrl) {
    return trimTrailingSlash(explicitAuthUrl);
  }

  const siteUrl = await getSiteUrl();

  if (
    siteUrl.includes("localhost") ||
    siteUrl.includes("127.0.0.1")
  ) {
    return siteUrl;
  }

  if (
    siteUrl.includes("vercel.app") ||
    siteUrl.includes("admin.spilltop.com")
  ) {
    return FALLBACK_PUBLIC_SITE_URL;
  }

  return siteUrl;
}
