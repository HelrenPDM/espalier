import type { Page } from "@playwright/test";

/**
 * Aborts the first `POST /api/auth/passkey/options` after the call: the
 * conditional request of the sign-in page, which is the first options
 * request after a load. The page ignores the aborted request, so a spec
 * that calls this before it loads `/sign-in` signs in through the passkey
 * button only.
 */
export async function blockConditionalRequest(page: Page) {
  let first = true;
  await page.route("**/api/auth/passkey/options", async (route) => {
    if (first) {
      first = false;
      await route.abort();
    } else {
      await route.continue();
    }
  });
}
