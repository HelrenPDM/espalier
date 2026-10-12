import { expect, test, type BrowserContext, type Page } from "@playwright/test";
import {
  confirmCodesSaved,
  createPasskeyAndDownloadCodes,
  e2eAddress,
  linkPattern,
  openMailLink,
} from "../support/account.ts";
import { addAuthenticator } from "../support/authenticator.ts";
import { devPost } from "../support/dev.ts";
import { findInMail } from "../support/mailpit.ts";
import {
  createStaffUser,
  projectBaseURL,
  type StaffUser,
} from "../support/staff.ts";

// An admin invites a person from the Users page; the invitee enrolls a
// passkey in a second browser context; after the recent-auth window,
// "Disable" passes a passkey step-up, and the invitee's next request
// answers 401 (task 0015, step 20).
test.describe.configure({ mode: "serial" });

const email = e2eAddress("-invitee");
const name = `E2E Invitee ${Math.random().toString(36).slice(2, 8)}`;
let admin: StaffUser;
let inviteeContext: BrowserContext;
let invitee: Page;

test.beforeAll(async ({ browser }) => {
  admin = await createStaffUser(browser, "admin");
  inviteeContext = await browser.newContext({ baseURL: projectBaseURL() });
  invitee = await inviteeContext.newPage();
  await addAuthenticator(invitee);
});

test.afterAll(async () => {
  await inviteeContext.close();
  await admin.context.close();
});

test("an admin invites a person, whose mail link leads to the enrollment", async ({
  request,
}) => {
  const { page } = admin;
  await page.goto("/admin/users");
  const invite = page.getByRole("region", { name: "Invite a person" });
  await invite.getByLabel("E-mail address").fill(email);
  await invite.getByLabel("Display name").fill(name);
  await invite.getByRole("button", { name: "Send invitation" }).click();
  await expect(
    page.getByText(
      "The invitation is on its way. Its link is valid for 10 minutes.",
    ),
  ).toBeVisible();

  const link = await findInMail(
    request,
    email,
    linkPattern(projectBaseURL(), "invite"),
  );
  await openMailLink(invitee, link);
  await expect(
    invitee.getByRole("heading", { level: 1, name: "Accept the invitation" }),
  ).toBeVisible();
  await invitee.getByRole("button", { name: "Continue" }).click();
  await expect(invitee).toHaveURL(/\/enroll$/);
  await createPasskeyAndDownloadCodes(invitee);
  await confirmCodesSaved(invitee);
  await expect(invitee).toHaveURL(/\/$/);
  expect((await invitee.request.get("/api/programs")).status()).toBe(200);
});

test("Disable passes a passkey step-up, and the invitee's next request answers 401", async () => {
  const { page } = admin;
  expect(await devPost(page, "age-recent-auth")).toBe(204);

  await page.goto("/admin/users");
  const lookup = page.getByRole("region", { name: "Find a person" });
  await lookup.getByLabel("E-mail address").fill(email);
  await lookup.getByRole("button", { name: "Find" }).click();
  await lookup.getByRole("button", { name: `Disable ${name}` }).click();

  await page
    .getByRole("dialog", { name: "Disable this account?" })
    .getByRole("button", { name: "Disable" })
    .click();
  const stepUp = page.getByRole("dialog", { name: "Confirm it is you" });
  await stepUp.getByRole("button", { name: "Use a passkey" }).click();
  await expect(
    page.getByText(
      `${name} is disabled, and every session of the person has ended.`,
    ),
  ).toBeVisible();

  expect((await invitee.request.get("/api/programs")).status()).toBe(401);
});
