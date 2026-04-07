import type { CapacitorConfig } from "@capacitor/cli";

const appUrl =
  process.env.CAPACITOR_LIVE_URL ?? "https://192.168.20.9:3000";

const config: CapacitorConfig = {
  appId: "au.com.imaginefashion.pulse",
  appName: "Pulse",
  webDir: ".next",
  server: {
    url: appUrl,
    cleartext: true,
    androidScheme: "https",
    allowNavigation: [new URL(appUrl).hostname],
  },
  android: {
    backgroundColor: "#120d11",
  },
  ios: {
    backgroundColor: "#120d11",
    contentInset: "never",
    preferredContentMode: "mobile",
    scheme: "Pulse",
    allowsLinkPreview: false,
  },
  plugins: {
    CapacitorHttp: {
      enabled: false,
    },
  },
};

export default config;
