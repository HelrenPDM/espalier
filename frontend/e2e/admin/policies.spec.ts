import { expect, test } from "@playwright/test";
import { createStaffUser, type StaffUser } from "../support/staff.ts";

// An admin publishes a policy version with `requires_refresher`, and the
// publish dialog shows the number of affected credentials (task 0015,
// step 20).
test.describe.configure({ mode: "serial" });

let admin: StaffUser;

test.beforeAll(async ({ browser }) => {
  admin = await createStaffUser(browser, "admin");
});

test.afterAll(async () => {
  await admin.context.close();
});

test("an admin publishes a policy version with a refresher and sees the count", async () => {
  const { page } = admin;
  const suffix = Math.random().toString(36).slice(2, 8);
  const title = `E2E policy ${suffix}`;

  await page.goto("/admin/policies");
  const create = page.getByRole("region", { name: "New policy" });
  await create.getByLabel("Title").fill(title);
  await create.getByLabel("Key", { exact: true }).fill(`e2e-policy-${suffix}`);
  await create.getByRole("button", { name: "Create the policy" }).click();
  await expect(page.getByText(`The policy ${title} is created.`)).toBeVisible();

  await page.getByRole("button", { name: "New draft" }).click();
  await page.getByLabel("In effect from").fill("2026-01-01");
  await page
    .getByLabel("Text (Markdown)")
    .fill("# Usage\n\nUse assistants for drafts only.");
  await page.getByRole("button", { name: "Save the draft" }).click();
  await expect(
    page.getByText("The draft of version 1 is saved."),
  ).toBeVisible();

  await page.getByRole("button", { name: "Publish Version 1" }).click();
  const dialog = page.getByRole("dialog", {
    name: `Publish version 1 of ${title}`,
  });
  await dialog.getByLabel("Requires a refresher").check();
  await expect(
    dialog.getByText(
      /^With this option, \d+ credentials? moves? to Refresher due now\.$/,
    ),
  ).toBeVisible();
  await dialog.getByRole("button", { name: "Publish" }).click();
  await expect(page.getByText("Version 1 is published.")).toBeVisible();
});
