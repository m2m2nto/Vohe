import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Lockfiles elsewhere on the machine can make Turbopack infer the wrong
  // workspace root; this app is self-contained in web/.
  turbopack: { root: __dirname },
};

export default nextConfig;
