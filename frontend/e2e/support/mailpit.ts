import { expect, type APIRequestContext } from "@playwright/test";

const MAILPIT = "http://localhost:8025";

/**
 * Polls Mailpit (compose.dev.yaml) for up to 15 seconds for a message to
 * `to` whose plain text matches `pattern`, and returns the match. The mails
 * go out through Oban, so they arrive after the request.
 */
export async function findInMail(
  request: APIRequestContext,
  to: string,
  pattern: RegExp,
) {
  let found = "";
  await expect
    .poll(
      async () => {
        const search = await request.get(`${MAILPIT}/api/v1/search`, {
          params: { query: `to:${to}`, limit: 10 },
        });
        for (const { ID } of (await search.json()).messages) {
          const message = await (
            await request.get(`${MAILPIT}/api/v1/message/${ID}`)
          ).json();
          const match = (message.Text as string).match(pattern);
          if (match) return (found = match[0]);
        }
        return "";
      },
      { timeout: 15_000 },
    )
    .not.toBe("");
  return found;
}
