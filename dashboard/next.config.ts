import type { NextConfig } from "next";
import path from "path";

const nextConfig: NextConfig = {
  compress: true,
  // Pin workspace root so Vercel/Turbopack don't pick a parent lockfile.
  turbopack: {
    root: path.join(__dirname),
  },
};

export default nextConfig;
