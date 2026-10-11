import type { Page } from "@playwright/test";

/**
 * Opens `/signed-out` and waits for the SPA's own `GET /api/session`. The
 * page sends no other request, so the session cookie of that answer stays
 * in place for the requests of the spec that follow. A spec that starts on
 * `/sign-in` instead races two requests that each can set a new cookie (the
 * SPA's first session request and the conditional passkey request) against
 * its own `GET /api/session`, and a following POST can answer 403 `csrf`.
 */
export async function openSettledPage(page: Page): Promise<void> {
  const sessionLoaded = page.waitForResponse(
    (response) => new URL(response.url()).pathname === "/api/session",
  );
  await page.goto("/signed-out");
  await sessionLoaded;
}

/**
 * Sends `POST /api/dev/e2e/<path>` (task 0011, development only) as `fetch`
 * inside the page, like `signInAsDemo` of 0010: `GET /api/session` for the
 * CSRF token, then the POST with that token. A page that is not on the
 * application yet opens `/signed-out` first (`openSettledPage`). Returns the
 * status.
 */
export async function devPost(
  page: Page,
  path: string,
  body: unknown = {},
): Promise<number> {
  if (!page.url().startsWith("http")) await openSettledPage(page);

  return page.evaluate(
    async ({ path, body }) => {
      const session = await fetch("/api/session", {
        credentials: "same-origin",
      });
      const { csrf_token: csrfToken } = (await session.json()) as {
        csrf_token: string;
      };
      const response = await fetch(`/api/dev/e2e/${path}`, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "content-type": "application/json",
          "x-csrf-token": csrfToken,
        },
        body: JSON.stringify(body),
      });
      return response.status;
    },
    { path, body },
  );
}
