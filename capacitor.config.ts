import type { CapacitorConfig } from "@capacitor/cli";

const appUrl =
  process.env.CAPACITOR_LIVE_URL ?? "https://your-pulse-site.vercel.app";

const config: CapacitorConfig = {
  appId: "au.com.imaginefashion.pulse",
  appName: "Pulse",
  webDir: ".next",
  server: {
    url: appUrl,
    cleartext: false,
    androidScheme: "https",
    allowNavigation: [new URL(appUrl).hostname],
  },
  android: {
    backgroundColor: "#120d11",
  },
  ios: {
    backgroundColor: "#120d11",
    contentInset: "always",
    preferredContentMode: "mobile",
    scheme: "Pulse",
  },
};

export default config;
