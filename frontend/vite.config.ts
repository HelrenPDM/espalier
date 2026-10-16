/// <reference types="vitest/config" />
import { defineConfig, searchForWorkspaceRoot, type Plugin } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

// `make run` starts the dev server as a Phoenix watcher in its own session, so
// it would outlive Phoenix and keep port 5173. Phoenix holds the other end of
// its standard input, so the server exits when that input closes. A direct
// `npm run dev < /dev/null` therefore exits at once. Vitest also calls
// configureServer and would end a run early with exit code 0, so the hook
// skips it.
function exitWithPhoenix(): Plugin {
  return {
    name: "espalier:exit-with-phoenix",
    apply: "serve",
    configureServer() {
      if (process.env.VITEST) return;
      process.stdin.on("close", () => process.exit(0));
      process.stdin.resume();
    },
  };
}

export default defineConfig(({ command }) => ({
  plugins: [react(), tailwindcss(), exitWithPhoenix()],
  base: command === "build" ? "/spa/" : "/",
  server: {
    port: 5173,
    strictPort: true,
    // The SPA route /auth/finish stays with Vite; every other path below
    // /auth belongs to Phoenix (README section 5), as do the media files
    // below /media (task 0018, step 13).
    proxy: {
      "/api": "http://localhost:4000",
      "^/auth/(?!finish)": "http://localhost:4000",
      "/health": "http://localhost:4000",
      "/media": "http://localhost:4000",
    },
    // The suspend-data test of task 0016 reads the demo pack with
    // `import.meta.glob`; the pack holds only public demo content.
    fs: {
      allow: [searchForWorkspaceRoot(process.cwd()), "../content/demo"],
    },
  },
  build: { outDir: "../priv/static/spa", emptyOutDir: true },
  test: {
    environment: "jsdom",
    setupFiles: ["./src/test/setup.ts"],
    // The specs in e2e/ belong to Playwright.
    include: ["src/**/*.test.{ts,tsx}"],
  },
}));
