import { readFile } from "node:fs/promises";
import { expect, type APIRequestContext, type Page } from "@playwright/test";
import { devPost } from "./dev.ts";
import { findInMail } from "./mailpit.ts";
import { blockConditionalRequest } from "./passkey.ts";

/** A fresh address per spec, so runs do not collide. */
export function e2eAddress(suffix = ""): string {
  const random = Math.random().toString(36).slice(2, 8);
  return `e2e-${Date.now()}-${random}${suffix}@example.test`;
}

const escapeRegExp = (value: string) =>
  value.replace(/[.*+?^${}()|[\]\\/]/g, "\\$&");

/**
 * The pattern of a mail link to `path` of the SPA. With `PUBLIC_URL`
 * `http://localhost:5173` (the default `baseURL`) the invitation link
 * matches `/http:\/\/localhost:5173\/invite#token=[A-Za-z0-9_-]+/`.
 */
export function linkPattern(baseURL: string, path: string): RegExp {
  return new RegExp(
    `${escapeRegExp(baseURL.replace(/\/$/, ""))}\\/${escapeRegExp(path)}#token=[A-Za-z0-9_-]+`,
  );
}

type SessionBody = {
  user: { display_name: string | null; email: string | null } | null;
  session: { strength: string } | null;
  csrf_token: string;
  providers: { key: string; type: string; label: string }[];
};

/** `GET /api/session` as `fetch` inside the page. */
export function readSession(page: Page): Promise<SessionBody> {
  return page.evaluate(async () => {
    const response = await fetch("/api/session", {
      credentials: "same-origin",
    });
    return (await response.json()) as SessionBody;
  });
}

/**
 * Opens a link of a mail as a new document, as a mail client does. A
 * `goto` from `/recover` to `/recover#token=…` would only change the
 * fragment of the loaded page.
 */
export async function openMailLink(page: Page, link: string) {
  await page.goto("about:blank");
  await page.goto(link);
}

/** Invites `email` through the development route and opens the mailed link. */
export async function acceptInvitation(
  page: Page,
  request: APIRequestContext,
  baseURL: string,
  email: string,
) {
  expect(await devPost(page, "invitations", { email })).toBe(202);
  const link = await findInMail(request, email, linkPattern(baseURL, "invite"));
  await openMailLink(page, link);
  await expect(
    page.getByRole("heading", { level: 1, name: "Accept the invitation" }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Continue" }).click();
  await expect(page).toHaveURL(/\/enroll$/);
}

/**
 * The passkey path of the enrollment wizard up to the recovery codes panel.
 * Returns the codes of the downloaded file in their display form.
 */
export async function createPasskeyAndDownloadCodes(
  page: Page,
): Promise<string[]> {
  await page.getByRole("button", { name: "Create a passkey" }).click();
  await page.getByRole("button", { name: "Create the passkey" }).click();
  await expect(
    page.getByRole("heading", { name: "Save your recovery codes" }),
  ).toBeVisible();
  return downloadCodes(page);
}

/** Saves the codes of the panel through "Download" and reads the file. */
export async function downloadCodes(page: Page): Promise<string[]> {
  const downloaded = page.waitForEvent("download");
  await page.getByRole("button", { name: "Download" }).click();
  const download = await downloaded;
  expect(download.suggestedFilename()).toBe("recovery-codes.txt");
  const path = await download.path();
  const text = await readFile(path, "utf8");
  return text
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => /^[A-Z2-7-]{20,}$/.test(line));
}

/** Confirms the saved codes and leaves the panel. */
export async function confirmCodesSaved(page: Page) {
  const proceed = page.getByRole("button", { name: "Continue" });
  await expect(proceed).toBeDisabled();
  await page.getByLabel("I have saved these codes").check();
  await proceed.click();
}

/** Invitation, passkey and saved codes: a signed-in `mfa` session. */
export async function enrollWithPasskey(
  page: Page,
  request: APIRequestContext,
  baseURL: string,
  email: string,
): Promise<string[]> {
  await acceptInvitation(page, request, baseURL, email);
  const codes = await createPasskeyAndDownloadCodes(page);
  await confirmCodesSaved(page);
  await expect(page).toHaveURL(/\/$/);
  return codes;
}

/**
 * Signs out through the user menu of the header. The sign-out lands on
 * `/sign-in`, whose conditional request a virtual authenticator with
 * presence simulation would complete at once; the helper therefore blocks
 * that request first (`blockConditionalRequest`).
 */
export async function signOutThroughMenu(page: Page, displayName: string) {
  await blockConditionalRequest(page);
  await page.getByRole("button", { name: displayName }).click();
  await page.getByRole("menuitem", { name: "Sign out" }).click();
}

/** The display name that `POST /api/dev/e2e/invitations` gives an invitee. */
export const invitedName = (email: string) => `E2E ${email}`;

/**
 * The storage check of ASVS 14.3.3: `localStorage` holds no keys other than
 * the theme, the language and the player state of 0012, `sessionStorage` is
 * empty, no stored value holds one of `secrets`, and `document.cookie` shows
 * no `espalier` cookie (the session cookie is `HttpOnly`).
 */
export async function expectCleanStorage(page: Page, secrets: string[]) {
  const storage = await page.evaluate(() => ({
    local: Object.entries(localStorage),
    session: Object.entries(sessionStorage),
  }));
  const cookie = await page.evaluate<string>("document.cookie");
  // 0012 step 2 adds the player state keys to this list.
  const allowed = ["theme", "i18nextLng"];
  expect(
    storage.local.map(([key]) => key).filter((key) => !allowed.includes(key)),
  ).toEqual([]);
  expect(storage.session).toEqual([]);
  const values = [...storage.local, ...storage.session].map(
    ([key, value]) => `${key}=${value}`,
  );
  for (const secret of secrets) {
    expect(values.filter((value) => value.includes(secret))).toEqual([]);
  }
  expect(cookie).not.toContain("espalier");
}
