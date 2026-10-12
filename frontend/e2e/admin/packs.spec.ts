import { expect, test } from "@playwright/test";
import { createStaffUser, type StaffUser } from "../support/staff.ts";

// An author uploads the demo pack, reads its alignment, previews module 2
// and publishes it (task 0015, step 20).
test.describe.configure({ mode: "serial" });

let author: StaffUser;

test.beforeAll(async ({ browser }) => {
  author = await createStaffUser(browser, "author");
});

test.afterAll(async () => {
  await author.context.close();
});

test("an author uploads, checks, previews and publishes the demo pack", async () => {
  const { page } = author;
  const archive = await page.request.get("/api/dev/e2e/demo-pack.zip");
  expect(archive.status()).toBe(200);

  await page.goto("/admin/packs");
  await page.getByLabel("Pack archive (zip)").setInputFiles({
    name: "demo-pack.zip",
    mimeType: "application/zip",
    buffer: await archive.body(),
  });
  await page.getByRole("button", { name: "Upload" }).click();
  await expect(page).toHaveURL(/\/admin\/packs\/[0-9a-f-]{36}$/);
  const importPath = new URL(page.url()).pathname;

  // The alignment section: 24 matrix rows over two tables, no finding.
  const alignment = page.getByRole("region", { name: "Alignment" });
  await expect(alignment.getByRole("table")).toHaveCount(2);
  await expect(alignment.locator("tbody tr")).toHaveCount(24);
  await expect(
    alignment.getByRole("table", { name: "Module 1, mode strict" }),
  ).toBeVisible();
  await expect(
    alignment.getByRole("heading", { name: "Alignment errors (0)" }),
  ).toBeVisible();
  await expect(
    alignment.getByRole("heading", { name: "Alignment warnings (0)" }),
  ).toBeVisible();

  // The preview of module 2 behind the "Preview" banner.
  await page.getByRole("link", { name: "Preview" }).click();
  await expect(page).toHaveURL(new RegExp(`${importPath}/preview/`));
  await expect(page.getByRole("region", { name: "Preview" })).toBeVisible();
  await page.getByRole("link", { name: "Checking the output" }).first().click();
  await expect(page).toHaveURL(
    new RegExp(`${importPath}/preview/programs/[^/]+/stations/\\d+$`),
  );
  const objectives = page.getByRole("region", {
    name: "Objectives of this topic",
  });
  await expect(objectives.getByRole("listitem")).toHaveCount(3);
  await expect(
    objectives.getByText(
      "Learners can build a prompt from task, context, format and constraint.",
    ),
  ).toBeVisible();

  // The publication from the page of the import.
  await page.getByRole("link", { name: "Back to the import" }).click();
  await expect(page).toHaveURL(new RegExp(`${importPath}$`));
  await page.getByRole("button", { name: "Publish" }).click();
  const dialog = page.getByRole("dialog", {
    name: "Publish ai-assistant-basics-demo?",
  });
  await expect(dialog.getByText("Alignment warnings: 0.")).toBeVisible();
  await dialog.getByRole("button", { name: "Publish" }).click();
  await expect(page.getByText("The pack is published.")).toBeVisible();
});
