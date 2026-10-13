import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { defineConfig, type Plugin } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

/** The directory of this file, `frontend/`. */
const FRONTEND = import.meta.dirname;

/** The files that every package carries next to the player. */
const LICENSE_FILES = ["LICENSE", "NOTICE"] as const;

// Apache-2.0 section 4 requires a copy of LICENSE (4 a) and NOTICE (4 d)
// with every redistribution in object form, and a SCORM package carries the
// compiled player into a third-party LMS. The plugin reads both files from
// the parent directory of frontend/ (the repository root, or / in the
// frontend stage of the Dockerfile) and emits them under their own names
// next to scorm.html. A missing file fails the build.
function licenseFiles(): Plugin {
  return {
    name: "espalier:license-files",
    apply: "build",
    generateBundle() {
      for (const fileName of LICENSE_FILES) {
        const path = resolve(FRONTEND, "..", fileName);
        let source: Uint8Array;
        try {
          source = readFileSync(path);
        } catch {
          this.error(
            `${path} is missing: the SCORM player carries ${fileName} next to scorm.html (Apache-2.0 section 4).`,
          );
        }
        this.emitFile({ type: "asset", fileName, source });
      }
    },
  };
}

// The player of the SCORM packages (task 0016, step 3): scorm.html with one
// script assets/player.js and one stylesheet assets/player.css, without
// hashes and with relative URLs, so that the export worker copies the
// directory into every package as it is.
export default defineConfig({
  plugins: [react(), tailwindcss(), licenseFiles()],
  base: "./",
  publicDir: false,
  build: {
    outDir: "../priv/scorm_player",
    emptyOutDir: true,
    cssCodeSplit: false,
    // The player is one chunk by design, larger than the default limit of
    // 500 kB.
    chunkSizeWarningLimit: 1024,
    rolldownOptions: {
      input: resolve(FRONTEND, "scorm.html"),
      output: {
        // One chunk: dynamic imports end up in player.js.
        codeSplitting: false,
        entryFileNames: "assets/player.js",
        assetFileNames: "assets/player[extname]",
      },
    },
  },
});
