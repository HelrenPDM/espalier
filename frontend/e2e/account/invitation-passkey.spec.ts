import {
  expect,
  test,
  type BrowserContext,
  type CDPSession,
  type Page,
} from "@playwright/test";
import {
  acceptInvitation,
  confirmCodesSaved,
  createPasskeyAndDownloadCodes,
  downloadCodes,
  e2eAddress,
  expectCleanStorage,
  invitedName,
  readSession,
  signOutThroughMenu,
} from "../support/account.ts";
import { addAuthenticator } from "../support/authenticator.ts";
import { devPost } from "../support/dev.ts";
import { blockConditionalRequest } from "../support/passkey.ts";

// Invitation, passkey enrollment, recovery codes, tab synchronization,
// passkey sign-in, step-up and sessions (task 0011 step 18). The tests
// share one browser context and run in order.
test.describe.configure({ mode: "serial" });

const email = e2eAddress();
const name = invitedName(email);
let context: BrowserContext;
let page: Page;
let cdp: CDPSession;
let authenticatorId: string;
let codes: string[] = [];

test.beforeAll(async ({ browser, baseURL }) => {
  context = await browser.newContext({ baseURL });
  page = await context.newPage();
  ({ cdp, authenticatorId } = await addAuthenticator(page, {
    defaultBackupEligibility: true,
    defaultBackupState: true,
  }));
});

test.afterAll(async () => {
  await context.close();
});

const secrets = async () => {
  const { csrf_token: csrfToken } = await readSession(page);
  return [
    csrfToken,
    email,
    ...codes,
    ...codes.map((code) => code.replaceAll("-", "")),
  ];
};

test("the invitation leads through the passkey enrollment to saved codes", async ({
  request,
  baseURL,
}) => {
  await acceptInvitation(page, request, baseURL!, email);
  codes = await createPasskeyAndDownloadCodes(page);

  expect(codes).toHaveLength(10);
  for (const code of codes)
    expect(code.replaceAll("-", "")).toMatch(/^[A-Z2-7]{26}$/);

  await confirmCodesSaved(page);
  await expect(page).toHaveURL(/\/$/);
  expect((await readSession(page)).session?.strength).toBe("mfa");
  await expectCleanStorage(page, await secrets());
});

test("sign-out in one tab shows /sign-in in the other tab without a reload", async () => {
  const other = await context.newPage();
  await blockConditionalRequest(other);
  await other.goto("/");
  await expect(other.getByRole("button", { name })).toBeVisible();

  await signOutThroughMenu(page, name);

  await expect(page).toHaveURL(/\/sign-in$/);
  await expect(other).toHaveURL(/\/sign-in$/, { timeout: 5_000 });
  await other.close();
});

test("the passkey button signs in with the passkey", async () => {
  await blockConditionalRequest(page);
  await page.goto("/sign-in");
  await page.getByRole("button", { name: "Sign in with a passkey" }).click();

  await expect(page).toHaveURL(/\/$/);
  await expect(page.getByRole("button", { name })).toBeVisible();
  await page.unrouteAll();
});

test("the security page lists the synced passkey whose Remove is disabled", async () => {
  await page.goto("/account/security");
  const passkeys = page.getByRole("region", { name: "Passkeys" });

  // The first match is the nickname; "Remove" repeats it for screen readers.
  await expect(passkeys.getByText(/^Passkey of /).first()).toBeVisible();
  await expect(
    passkeys.getByRole("button", { name: /^Remove Passkey of / }),
  ).toBeDisabled();
  await expect(passkeys.getByText("Synced", { exact: true })).toBeVisible();
  await expect(
    passkeys.getByRole("button", { name: /^Remove/ }),
  ).toBeDisabled();
  await expectCleanStorage(page, await secrets());
});

test("new recovery codes after the recent-auth window pass a passkey step-up", async () => {
  expect(await devPost(page, "age-recent-auth")).toBe(204);
  const recovery = page.getByRole("region", { name: "Recovery codes" });

  await recovery.getByRole("button", { name: "Create new codes" }).click();
  await page
    .getByRole("dialog", { name: "Create new recovery codes?" })
    .getByRole("button", { name: "Create new codes" })
    .click();
  const stepUp = page.getByRole("dialog", { name: "Confirm it is you" });
  await stepUp.getByRole("button", { name: "Use a passkey" }).click();

  await expect(
    page.getByRole("heading", { name: "Save your recovery codes" }),
  ).toBeVisible();
  const fresh = await downloadCodes(page);
  expect(fresh).toHaveLength(10);
  expect(fresh.filter((code) => codes.includes(code))).toEqual([]);
  codes = fresh;
  await page.getByLabel("I have saved these codes").check();
  await page.getByRole("button", { name: "Continue" }).click();
});

test("a second context signs in with the same credential, and the first one ends its session", async ({
  browser,
  baseURL,
}) => {
  const { credentials } = await cdp.send("WebAuthn.getCredentials", {
    authenticatorId,
  });
  expect(credentials).toHaveLength(1);

  const second = await browser.newContext({ baseURL });
  const secondPage = await second.newPage();
  const copy = await addAuthenticator(secondPage);
  await copy.cdp.send("WebAuthn.addCredential", {
    authenticatorId: copy.authenticatorId,
    credential: credentials[0],
  });
  await blockConditionalRequest(secondPage);
  await secondPage.goto("/sign-in");
  await secondPage
    .getByRole("button", { name: "Sign in with a passkey" })
    .click();
  await expect(secondPage).toHaveURL(/\/$/);

  await page.goto("/account/security");
  const sessions = page.getByRole("region", { name: "Active sessions" });
  await expect(sessions.getByRole("listitem")).toHaveCount(2);

  expect(await devPost(page, "age-recent-auth")).toBe(204);
  await sessions.getByRole("button", { name: /^End/ }).first().click();
  await page
    .getByRole("dialog", { name: "Confirm it is you" })
    .getByRole("button", { name: "Use a passkey" })
    .click();
  await expect(sessions.getByRole("listitem")).toHaveCount(1);

  await blockConditionalRequest(secondPage);
  await secondPage.goto("/account/security");
  await expect(secondPage).toHaveURL(/\/sign-in/);
  await second.close();
});
