import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  allowedDevOrigins: ["192.168.20.61"],
  turbopack: {
    root: __dirname,
  },
};

export default nextConfig;
