import type { Page } from "@playwright/test";

/**
 * Signs the page in with the demo account of `slot` (1 to 20). The requests
 * run as `fetch` inside the page, so the browser sends the session cookie and
 * the `Origin` and `Sec-Fetch-Site` headers as it does for the SPA. The
 * server needs AUTH_DEMO=true.
 */
export async function signInAsDemo(page: Page, slot: number): Promise<void> {
  // The SPA loads the session on /sign-in. Waiting for that answer keeps its
  // session cookie from replacing the one whose CSRF token the helper uses.
  const sessionLoaded = page.waitForResponse(
    (response) => new URL(response.url()).pathname === "/api/session",
  );
  await page.goto("/sign-in");
  await sessionLoaded;

  const status = await page.evaluate(async (slot) => {
    const session = await fetch("/api/session", { credentials: "same-origin" });
    const { csrf_token: csrfToken } = (await session.json()) as {
      csrf_token: string;
    };
    const response = await fetch("/api/auth/demo", {
      method: "POST",
      credentials: "same-origin",
      headers: {
        "content-type": "application/json",
        "x-csrf-token": csrfToken,
      },
      body: JSON.stringify({ slot }),
    });
    return response.status;
  }, slot);

  if (status < 200 || status > 299)
    throw new Error(`POST /api/auth/demo answered ${status}`);
}
