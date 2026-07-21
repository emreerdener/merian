import type { NextConfig } from "next";
import path from "node:path";

const nextConfig: NextConfig = {
  reactStrictMode: true,
  turbopack: {
    root: path.resolve(__dirname, "../..")
  },
  async rewrites() {
    return [
      {
        source: "/.well-known/apple-app-site-association",
        destination: "/apple-app-site-association"
      }
    ];
  }
};

export default nextConfig;
