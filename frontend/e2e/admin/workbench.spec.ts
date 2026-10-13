import { AxeBuilder } from "@axe-core/playwright";
import { expect, test, type Locator, type Page } from "@playwright/test";
import { devPost } from "../support/dev.ts";
import { createStaffUser, type StaffUser } from "../support/staff.ts";

// An author edits the published demo program in the pack workbench, checks
// the draft, saves after a step-up, imports the draft and publishes it
// (task 0016a, step 16). The changed objective belongs to module 2, whose
// statements no other spec reads from the live program. At its end the
// spec deletes the draft and restores the demo program.
test.describe.configure({ mode: "serial" });

const WCAG_TAGS = ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"];

const PROGRAM_TITLE = "AI assistant basics (demo)";
const PACK_KEY = "ai-assistant-basics-demo";

/** The directory that the writer gives module 2 of the demo pack. */
const MODULE_DIR = "modules/02-checking-the-output";
const OBJECTIVES = `${MODULE_DIR}/objectives.yaml`;
const MODULE_FILE = `${MODULE_DIR}/module.yaml`;
const OBJECTIVE_KEY = "m2-method-release-check";

const OLD_STATEMENT =
  "Learners can run the release checks on a generated text and confirm them with their initials.";
const NEW_STATEMENT =
  "Learners can run the release checks on a generated text and sign them off with their initials.";
/** The line that the save after the step-up adds to the objectives. */
const COMMENT = "# The statement of the release check names the sign-off.";

let author: StaffUser;
let draftId: string | null = null;
let draftDeleted = false;

const escapeRegExp = (value: string) =>
  value.replace(/[.*+?^${}()|[\]\\/]/g, "\\$&");

/**
 * The button of a file in the tree, with or without the unsaved marker:
 * the file name, then the directory and the marker in visually hidden
 * text, whose separators the name computation may surround with spaces.
 */
function fileButton(page: Page, path: string): Locator {
  const slash = path.lastIndexOf("/");
  const file = escapeRegExp(path.slice(slash + 1));
  const name =
    slash === -1
      ? `^${file}(\\s*,|$)`
      : `^${file}\\s*,\\s*${escapeRegExp(path.slice(0, slash + 1))}(\\s*,|$)`;
  return page
    .getByRole("navigation", { name: "Files of the draft" })
    .getByRole("button", { name: new RegExp(name) });
}

const editorOf = (page: Page, path: string): Locator =>
  page.getByRole("textbox", { name: `Content of ${path}`, exact: true });

const cursorStatus = (page: Page): Locator =>
  page.getByText(/^Line \d+, column \d+$/);

interface DraftFile {
  id: string;
  path: string;
}

/** The stored content of a file of the draft, read through the API. */
async function storedContent(page: Page, path: string): Promise<string> {
  const draft = await page.request.get(`/api/admin/pack-drafts/${draftId}`);
  expect(draft.status()).toBe(200);
  const { files } = (await draft.json()) as { files: DraftFile[] };
  const entry = files.find((file) => file.path === path);
  expect(entry, `${path} in the draft`).toBeDefined();
  const file = await page.request.get(
    `/api/admin/pack-drafts/${draftId}/files/${entry?.id}`,
  );
  expect(file.status()).toBe(200);
  return ((await file.json()) as { content: string }).content;
}

/** The lines of an objective in a YAML list of objectives. */
function objectiveBlock(lines: string[], key: string) {
  const start = lines.findIndex((line) =>
    new RegExp(`^- key: ['"]?${escapeRegExp(key)}['"]?$`).test(line),
  );
  expect(start, `the objective ${key}`).toBeGreaterThanOrEqual(0);
  let end = start + 1;
  while (end < lines.length && !lines[end].startsWith("- ")) end += 1;
  return { start, end };
}

/** The index of the line of `field` in the objective `key`. */
function fieldIndex(text: string, key: string, field: string): number {
  const lines = text.split("\n");
  const { start, end } = objectiveBlock(lines, key);
  const index = lines.findIndex(
    (line, at) =>
      at > start && at < end && new RegExp(`^\\s+${field}: `).test(line),
  );
  expect(index, `${field} of ${key}`).toBeGreaterThan(start);
  return index;
}

/** `text` with the line of `field` of the objective `key` replaced. */
function withField(
  text: string,
  key: string,
  field: string,
  value: string,
): string {
  const lines = text.split("\n");
  const index = fieldIndex(text, key, field);
  lines[index] = lines[index].replace(/: .*$/, `: ${value}`);
  return lines.join("\n");
}

/**
 * Replaces the text of the open editor: focus, select all and insert. The
 * spec computes the text from the stored content, because the editor
 * renders only the lines in view.
 */
async function replaceText(page: Page, path: string, text: string) {
  await editorOf(page, path).click();
  await page.keyboard.press("ControlOrMeta+A");
  await page.keyboard.insertText(text);
  await expect(fileButton(page, path)).toHaveAccessibleName(/,\s*unsaved$/);
  await expect(
    page.getByText("Unsaved changes", { exact: true }),
  ).toBeVisible();
}

async function expectAnnounced(page: Page, text: string | RegExp) {
  await expect(
    page.getByRole("status").filter({ hasText: text }),
  ).toBeVisible();
}

/** Saves the open file with Ctrl+S and waits for the announcement. */
async function saveWithShortcut(page: Page, path: string) {
  await page.keyboard.press("ControlOrMeta+S");
  await expectAnnounced(page, `Saved ${path}`);
  await expect(page.getByText("Unsaved changes", { exact: true })).toHaveCount(
    0,
  );
}

/** Runs the check and waits for its announcement. */
async function runCheck(page: Page): Promise<Locator> {
  await page.getByRole("button", { name: "Check", exact: true }).click();
  await expectAnnounced(page, /^Check finished: \d+ errors?, \d+ warnings?$/);
  return page.getByRole("region", { name: "Check report", exact: true });
}

/**
 * "Use a passkey" in the step-up dialog of the API client. The dialog
 * element itself has no size of its own, so the spec waits for its button.
 */
const stepUpPasskey = (page: Page): Locator =>
  page
    .getByRole("dialog", { name: "Confirm it is you" })
    .getByRole("button", { name: "Use a passkey" });

async function expectNoAxeViolation(page: Page) {
  const results = await new AxeBuilder({ page }).withTags(WCAG_TAGS).analyze();
  expect(results.violations).toEqual([]);
}

/** Deletes the draft from the list of the open workbench page. */
async function deleteDraft(page: Page, id: string) {
  const row = page
    .getByRole("row")
    .filter({ has: page.locator(`a[href="/admin/workbench/${id}"]`) });
  await row.getByRole("button", { name: /^Delete / }).click();
  await page
    .getByRole("dialog", { name: "Delete this draft?" })
    .getByRole("button", { name: "Delete" })
    .click();
  await expectAnnounced(page, `The draft ${PROGRAM_TITLE} is deleted.`);
  await expect(row).toHaveCount(0);
}

/**
 * Uploads `GET /api/dev/e2e/demo-pack.zip` and publishes it, as
 * `packs.spec.ts` does, so the live program holds the statements of
 * `content/demo` again.
 */
async function restoreDemoProgram(page: Page) {
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
  await page.getByRole("button", { name: "Publish" }).click();
  await page
    .getByRole("dialog", { name: `Publish ${PACK_KEY}?` })
    .getByRole("button", { name: "Publish" })
    .click();
  await expect(page.getByText("The pack is published.")).toBeVisible();
}

test.beforeAll(async ({ browser }) => {
  test.setTimeout(60_000);
  author = await createStaffUser(browser, "author");
});

test.afterAll(async () => {
  test.setTimeout(90_000);
  const { page } = author;
  // A failed run may leave unsaved text or an aged second factor behind:
  // leave the page without asking, and pass the step-up with the passkey.
  page.on("dialog", (dialog) => void dialog.accept());
  await page.addLocatorHandler(stepUpPasskey(page), async (button) => {
    await button.click();
  });
  try {
    if (draftId !== null && !draftDeleted) {
      const draft = await page.request.get(`/api/admin/pack-drafts/${draftId}`);
      if (draft.status() === 200) {
        await page.goto("/admin/workbench");
        await deleteDraft(page, draftId);
      }
    }
  } finally {
    try {
      await restoreDemoProgram(page);
    } finally {
      await author.context.close();
    }
  }
});

test("an author edits the demo program in the workbench, imports and publishes it", async () => {
  test.setTimeout(180_000);
  const { page } = author;

  await test.step("start a draft from the published program", async () => {
    await page.goto("/admin/workbench");
    await expect(
      page.getByRole("heading", { level: 1, name: "Pack workbench" }),
    ).toBeVisible();
    const start = page.getByRole("region", { name: "Published program" });
    await start.getByLabel("Program").selectOption({ label: PROGRAM_TITLE });
    await start.getByRole("button", { name: "Start from the program" }).click();
    await expect(page).toHaveURL(/\/admin\/workbench\/[0-9a-f-]{36}$/);
    draftId = new URL(page.url()).pathname.split("/").pop() ?? null;
    await expect(
      page.getByRole("heading", { level: 1, name: PROGRAM_TITLE }),
    ).toBeVisible();
  });

  await test.step("an invalid depth fails the check at its line", async () => {
    const stored = await storedContent(page, OBJECTIVES);
    const depthIndex = fieldIndex(stored, OBJECTIVE_KEY, "depth");
    expect(stored.split("\n")[depthIndex]).toMatch(/^\s+depth: apply$/);
    const changed = withField(stored, OBJECTIVE_KEY, "depth", "deep");
    const depthLine = changed.split("\n")[depthIndex];

    await fileButton(page, OBJECTIVES).click();
    await expect(fileButton(page, OBJECTIVES)).toHaveAttribute(
      "aria-current",
      "true",
    );
    await expect(editorOf(page, OBJECTIVES)).toBeVisible();
    await replaceText(page, OBJECTIVES, changed);
    await saveWithShortcut(page, OBJECTIVES);
    expect(await storedContent(page, OBJECTIVES)).toBe(changed);

    // Another file is open when the entry of the report is followed.
    await fileButton(page, MODULE_FILE).click();
    await expect(editorOf(page, MODULE_FILE)).toBeVisible();

    // The one error names the file and the line of the field.
    const report = await runCheck(page);
    const line = depthIndex + 1;
    await expect(
      report.getByRole("heading", { name: "Errors (1)", exact: true }),
    ).toBeVisible();
    const entryButton = page.getByRole("button", {
      name: `${OBJECTIVES}, line ${line}`,
      exact: true,
    });
    const entry = report.getByRole("listitem").filter({ has: entryButton });
    await expect(entry).toContainText(
      "`depth` must be one of `know`, `apply`, `judge`",
    );
    await expectNoAxeViolation(page);

    await entry.getByRole("button").click();
    await expect(fileButton(page, OBJECTIVES)).toHaveAttribute(
      "aria-current",
      "true",
    );
    await expect(editorOf(page, OBJECTIVES)).toBeFocused();
    await expect(cursorStatus(page)).toHaveText(`Line ${line}, column 1`);
    // The cursor itself sits on that line: End moves it behind `deep`.
    await page.keyboard.press("End");
    await expect(cursorStatus(page)).toHaveText(
      `Line ${line}, column ${depthLine.length + 1}`,
    );
  });

  await test.step("the restored depth and a new statement pass the check", async () => {
    const stored = await storedContent(page, OBJECTIVES);
    const statement =
      stored.split("\n")[fieldIndex(stored, OBJECTIVE_KEY, "statement")];
    expect(statement).toContain(OLD_STATEMENT);
    const changed = withField(
      withField(stored, OBJECTIVE_KEY, "depth", "apply"),
      OBJECTIVE_KEY,
      "statement",
      NEW_STATEMENT,
    );

    await replaceText(page, OBJECTIVES, changed);
    await saveWithShortcut(page, OBJECTIVES);
    expect(await storedContent(page, OBJECTIVES)).toBe(changed);

    const report = await runCheck(page);
    await expect(
      report.getByRole("heading", { name: "Errors (0)", exact: true }),
    ).toBeVisible();
    const alignment = page.getByRole("region", {
      name: "Alignment",
      exact: true,
    });
    await expect(alignment.getByRole("table")).toHaveCount(2);
    await expect(alignment.locator("tbody tr")).toHaveCount(24);
    await expect(
      alignment.getByRole("heading", { name: "Alignment errors (0)" }),
    ).toBeVisible();
    await expectNoAxeViolation(page);
  });

  await test.step("a save after the second factor aged passes the step-up", async () => {
    expect(await devPost(page, "age-recent-auth")).toBe(204);
    const stored = await storedContent(page, OBJECTIVES);
    const changed = `${COMMENT}\n${stored}`;

    await replaceText(page, OBJECTIVES, changed);
    await page.keyboard.press("ControlOrMeta+S");
    const passkey = stepUpPasskey(page);
    await expect(passkey).toBeVisible();
    await passkey.click();
    await expect(passkey).toHaveCount(0);
    await expectAnnounced(page, `Saved ${OBJECTIVES}`);
    await expect(
      page.getByText("Unsaved changes", { exact: true }),
    ).toHaveCount(0);
    expect(await storedContent(page, OBJECTIVES)).toBe(changed);
  });

  await test.step("the import shows the change, previews and publishes it", async () => {
    await page.getByRole("button", { name: "Create import" }).click();
    await expect(page).toHaveURL(/\/admin\/packs\/[0-9a-f-]{36}$/);
    const importPath = new URL(page.url()).pathname;

    // The preview of module 2 shows the new statement.
    await page.getByRole("link", { name: "Preview" }).click();
    await expect(page).toHaveURL(new RegExp(`${importPath}/preview/`));
    await page
      .getByRole("link", { name: "Checking the output" })
      .first()
      .click();
    await expect(page).toHaveURL(
      new RegExp(`${importPath}/preview/programs/[^/]+/stations/\\d+$`),
    );
    const objectives = page.getByRole("region", {
      name: "Objectives of this topic",
    });
    await expect(objectives.getByText(NEW_STATEMENT)).toBeVisible();
    await expect(objectives.getByText(OLD_STATEMENT)).toHaveCount(0);

    // The publish dialog names the changed objective and its field.
    await page.getByRole("link", { name: "Back to the import" }).click();
    await expect(page).toHaveURL(new RegExp(`${importPath}$`));
    await page.getByRole("button", { name: "Publish" }).click();
    const dialog = page.getByRole("dialog", { name: `Publish ${PACK_KEY}?` });
    const objectivesChanges = dialog.locator("section").filter({
      has: page.getByRole("heading", { name: "Learning objectives" }),
    });
    await expect(objectivesChanges.getByText("Changed (1)")).toBeVisible();
    await expect(objectivesChanges.getByRole("listitem")).toHaveText([
      `${OBJECTIVE_KEY} (fields: statement)`,
    ]);
    await dialog.getByRole("button", { name: "Publish" }).click();
    await expect(page.getByText("The pack is published.")).toBeVisible();
  });

  await test.step("the workbench lists the draft and deletes it", async () => {
    await page.goto("/admin/workbench");
    const id = draftId ?? "";
    await expect(page.locator(`a[href="/admin/workbench/${id}"]`)).toHaveText(
      PROGRAM_TITLE,
    );
    await expectNoAxeViolation(page);
    await deleteDraft(page, id);
    draftDeleted = true;
  });
});
