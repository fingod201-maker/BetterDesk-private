import path from "node:path";
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "standalone",
  // Dependencies are hoisted to the workspace root (../node_modules).
  turbopack: { root: path.resolve(process.cwd(), "..") },
};

export default nextConfig;
