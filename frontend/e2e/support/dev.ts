import type { Page } from "@playwright/test";

/**
 * Sends `POST /api/dev/e2e/<path>` (task 0011, development only) as `fetch`
 * inside the page, like `signInAsDemo` of 0010: `GET /api/session` for the
 * CSRF token, then the POST with that token. A page that is not on the
 * application yet opens `/signed-out` first and waits for the SPA's own
 * session answer, so its session cookie does not replace the one whose
 * token the helper uses. Returns the status.
 */
export async function devPost(
  page: Page,
  path: string,
  body: unknown = {},
): Promise<number> {
  if (!page.url().startsWith("http")) {
    const sessionLoaded = page.waitForResponse(
      (response) => new URL(response.url()).pathname === "/api/session",
    );
    await page.goto("/signed-out");
    await sessionLoaded;
  }

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
