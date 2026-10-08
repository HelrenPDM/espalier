import { defineConfig, type Plugin } from "vite";
import react from "@vitejs/plugin-react";

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
  plugins: [react(), exitWithPhoenix()],
  base: command === "build" ? "/spa/" : "/",
  server: {
    port: 5173,
    strictPort: true,
    proxy: {
      "/api": "http://localhost:4000",
      "/auth": "http://localhost:4000",
      "/health": "http://localhost:4000",
    },
  },
  build: { outDir: "../priv/static/spa", emptyOutDir: true },
}));
