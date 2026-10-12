import {
  expect,
  test,
  type Browser,
  type BrowserContext,
  type CDPSession,
  type Page,
} from "@playwright/test";
import { e2eAddress, enrollWithPasskey, invitedName } from "./account.ts";
import { addAuthenticator } from "./authenticator.ts";
import { devPost } from "./dev.ts";
import { blockConditionalRequest } from "./passkey.ts";

/** The roles of the admin area (task 0015, step 5). */
export type StaffRole =
  "author" | "admin" | "facilitator" | "analyst" | "registrar";

/** A signed-in staff member in a browser context of its own. */
export interface StaffUser {
  context: BrowserContext;
  page: Page;
  cdp: CDPSession;
  authenticatorId: string;
  email: string;
  name: string;
}

/** The `baseURL` of the running project, `http://localhost:5173` by default. */
export function projectBaseURL(): string {
  return test.info().project.use.baseURL ?? "http://localhost:5173";
}

/** Signs in with the passkey of the page's virtual authenticator. */
export async function signInWithPasskey(page: Page): Promise<void> {
  await blockConditionalRequest(page);
  await page.goto("/sign-in");
  await page.getByRole("button", { name: "Sign in with a passkey" }).click();
  await expect(page).toHaveURL(/\/$/);
  await page.unrouteAll();
}

/**
 * Creates a staff member with `role` (task 0015, step 20): invites a fresh
 * address through `POST /api/dev/e2e/invitations`, opens the link from
 * Mailpit, enrolls a passkey through the Chromium DevTools virtual
 * authenticator, grants the role through `POST /api/dev/e2e/role-grants`
 * and signs in again with the passkey, because the grant ends the user's
 * sessions. The passkey satisfies the passkey gate of the admin routes and
 * the recent second factor.
 */
export async function createStaffUser(
  browser: Browser,
  role: StaffRole,
): Promise<StaffUser> {
  const baseURL = projectBaseURL();
  const context = await browser.newContext({ baseURL });
  const page = await context.newPage();
  const { cdp, authenticatorId } = await addAuthenticator(page);
  const email = e2eAddress(`-${role}`);

  await enrollWithPasskey(page, context.request, baseURL, email);
  expect(await devPost(page, "role-grants", { email, role })).toBe(204);
  await signInWithPasskey(page);

  return {
    context,
    page,
    cdp,
    authenticatorId,
    email,
    name: invitedName(email),
  };
}
