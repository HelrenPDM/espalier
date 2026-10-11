import { expect, test } from "@playwright/test";
import { signInAsDemo } from "./support/demo.ts";

// Whether a browser stores the `Secure` cookie `__Host-espalier` over
// http://localhost through the Vite proxy (0004, Notes). Every browser of
// PLAYWRIGHT_BROWSERS_PATH runs this spec; docs/security/authentication.md
// records the outcome.
test("the browser stores the session cookie over http://localhost", async ({
  page,
  browserName,
}) => {
  // WebKit 26.4 drops the cookie over http://localhost, so the demo sign-in
  // answers 403 `csrf`. docs/security/authentication.md ("Cookies and CSRF")
  // records WebKit as unsuitable for development against http://localhost.
  test.fail(
    browserName === "webkit",
    "WebKit stores no Secure cookie over http://localhost",
  );

  await signInAsDemo(page, 3);

  const cookies = await page.context().cookies();
  expect(
    cookies.find((cookie) => cookie.name === "__Host-espalier"),
  ).toMatchObject({
    secure: true,
    httpOnly: true,
    sameSite: "Strict",
    path: "/",
  });

  const displayName = await page.evaluate(async () => {
    const response = await fetch("/api/session", {
      credentials: "same-origin",
    });
    const body = (await response.json()) as {
      user: { display_name: string | null } | null;
    };
    return body.user?.display_name ?? null;
  });
  expect(displayName).toBe("Test person 3");
});
