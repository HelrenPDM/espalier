import { expect, test } from "@playwright/test";
import {
  confirmCodesSaved,
  createPasskeyAndDownloadCodes,
  readSession,
  signOutThroughMenu,
} from "../support/account.ts";
import { addAuthenticator } from "../support/authenticator.ts";
import { devPost, openSettledPage } from "../support/dev.ts";

// The Entra-like profile of the mock OIDC provider (task 0006, step 15;
// `.env.example`, block "Development against the mock OIDC provider").
const KEY = "entra";
const FIXTURE_BUTTON = "Sign in as ada";
const DISPLAY_NAME = "Ada Example";
// The development port of the mock (README section 6.7).
const MOCK_PORT = process.env.E2E_MOCK_OIDC_PORT ?? "4010";

test(
  "an OIDC sign-in enrolls a passkey, signs in again with it and ends at the provider's logout",
  { tag: "@oidc" },
  async ({ page }) => {
    // The provider check and the reset run on a page without the
    // conditional passkey request of /sign-in (`openSettledPage`).
    await openSettledPage(page);
    const { providers } = await readSession(page);
    const provider = providers.find((entry) => entry.key === KEY);
    test.skip(provider === undefined, `no provider ${KEY} configured`);
    // The spec signs in through the mock, and its reset deletes every user
    // linked to the provider. A provider of a real tenant skips the spec
    // before the reset, decided by the target of the provider's start route.
    const start = await page.request.get(`/auth/oidc/${KEY}`, {
      maxRedirects: 0,
    });
    const target = new URL(start.headers()["location"] ?? "", "http://invalid");
    test.skip(
      target.hostname !== "localhost" || target.port !== MOCK_PORT,
      `provider ${KEY} is not the mock OIDC provider on port ${MOCK_PORT}`,
    );
    const label = provider!.label;

    await addAuthenticator(page);
    expect(await devPost(page, "reset", { provider_keys: [KEY] })).toBe(204);

    const finish = page.waitForResponse(
      (response) => new URL(response.url()).pathname === "/api/auth/finish",
    );
    await page.goto("/sign-in");
    await page.getByRole("button", { name: label, exact: true }).click();
    await page.getByRole("button", { name: FIXTURE_BUTTON }).click();
    expect(await (await finish).json()).toEqual({
      next: "enroll_second_factor",
    });
    await expect(page).toHaveURL(/\/enroll$/);

    await createPasskeyAndDownloadCodes(page);
    await confirmCodesSaved(page);
    await expect(
      page.getByRole("button", { name: DISPLAY_NAME }),
    ).toBeVisible();
    await signOutThroughMenu(page, DISPLAY_NAME);

    await page.goto("/sign-in");
    await page.getByRole("button", { name: label, exact: true }).click();
    await page.getByRole("button", { name: FIXTURE_BUTTON }).click();
    await expect(
      page.getByRole("heading", { name: "Confirm your sign-in" }),
    ).toBeVisible();
    await page.getByRole("button", { name: "Use a passkey" }).click();
    await expect(page).toHaveURL(/\/$/);

    const logout = page.waitForRequest((request) => {
      const url = new URL(request.url());
      return url.port === MOCK_PORT && url.pathname.endsWith("/logout");
    });
    await signOutThroughMenu(page, DISPLAY_NAME);
    await logout;
    await expect(page).toHaveURL(/\/signed-out$/);
    await expect(
      page.getByRole("heading", { level: 1, name: "You are signed out" }),
    ).toBeVisible();
  },
);
