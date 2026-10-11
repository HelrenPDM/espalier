import { defineConfig, devices } from "@playwright/test";

// @playwright/test stays at the version of playwright-driver in the pinned
// nixpkgs, whose browsers shell.nix provides in PLAYWRIGHT_BROWSERS_PATH.
// Chromium runs every spec. Firefox and WebKit run only the cookie check of
// e2e/dev-cookie.spec.ts.
export default defineConfig({
  testDir: "e2e",
  use: { baseURL: "http://localhost:5173" },
  projects: [
    { name: "chromium", use: { ...devices["Desktop Chrome"] } },
    {
      name: "firefox",
      testMatch: /dev-cookie\.spec\.ts/,
      use: { ...devices["Desktop Firefox"] },
    },
    {
      name: "webkit",
      testMatch: /dev-cookie\.spec\.ts/,
      use: { ...devices["Desktop Safari"] },
    },
  ],
  // The Vite proxy forwards /health to Phoenix, so the URL answers 200 once
  // both servers run.
  webServer: {
    command: "make run",
    cwd: "..",
    url: "http://localhost:5173/health",
    reuseExistingServer: true,
    timeout: 180_000,
  },
});
