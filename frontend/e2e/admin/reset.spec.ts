import {
  expect,
  test,
  type APIRequestContext,
  type BrowserContext,
  type Page,
} from "@playwright/test";
import {
  e2eAddress,
  enrollWithPasskey,
  invitedName,
  linkPattern,
  openMailLink,
} from "../support/account.ts";
import { addAuthenticator } from "../support/authenticator.ts";
import { findInMail } from "../support/mailpit.ts";
import {
  createStaffUser,
  projectBaseURL,
  type StaffUser,
} from "../support/staff.ts";

const MAILPIT = "http://localhost:8025";

// An admin resets the second factors of an enrolled invitee (decision D11);
// Mailpit holds the `factors_reset` mail and a new invitation, whose link
// leads to the enrollment (task 0015, step 20).
test.describe.configure({ mode: "serial" });

const email = e2eAddress("-reset");
const name = invitedName(email);
let admin: StaffUser;
let inviteeContext: BrowserContext;
let invitee: Page;

/** Every invitation link to `to` in Mailpit, newest first. */
async function invitationLinks(
  request: APIRequestContext,
  to: string,
): Promise<string[]> {
  const pattern = linkPattern(projectBaseURL(), "invite");
  const search = await request.get(`${MAILPIT}/api/v1/search`, {
    params: { query: `to:${to}`, limit: 20 },
  });
  const links: string[] = [];
  for (const { ID } of (await search.json()).messages) {
    const message = await (
      await request.get(`${MAILPIT}/api/v1/message/${ID}`)
    ).json();
    const match = (message.Text as string).match(pattern);
    if (match) links.push(match[0]);
  }
  return links;
}

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

test("a reset of the second factors sends the factors_reset mail and a new invitation", async ({
  request,
}) => {
  await enrollWithPasskey(invitee, request, projectBaseURL(), email);
  const firstLinks = await invitationLinks(request, email);
  expect(firstLinks).toHaveLength(1);

  const { page } = admin;
  await page.goto("/admin/users");
  const lookup = page.getByRole("region", { name: "Find a person" });
  await lookup.getByLabel("E-mail address").fill(email);
  await lookup.getByRole("button", { name: "Find" }).click();
  await lookup
    .getByRole("button", { name: `Reset second factors ${name}` })
    .click();

  const dialog = page.getByRole("dialog", {
    name: "Reset the second factors?",
  });
  const confirm = dialog.getByRole("button", { name: "Reset second factors" });
  await expect(confirm).toBeDisabled();
  await dialog
    .getByLabel("The organization has verified this person's identity")
    .check();
  await confirm.click();
  await expect(
    page.getByText(
      `The second factors of ${name} are reset. A new invitation is on its way.`,
    ),
  ).toBeVisible();

  await findInMail(request, email, /removed every second factor/);
  let fresh = "";
  await expect
    .poll(
      async () => {
        const links = await invitationLinks(request, email);
        fresh = links.find((link) => !firstLinks.includes(link)) ?? "";
        return fresh;
      },
      { timeout: 15_000 },
    )
    .not.toBe("");

  await openMailLink(invitee, fresh);
  await expect(
    invitee.getByRole("heading", { level: 1, name: "Accept the invitation" }),
  ).toBeVisible();
  await invitee.getByRole("button", { name: "Continue" }).click();
  await expect(invitee).toHaveURL(/\/enroll$/);
});
