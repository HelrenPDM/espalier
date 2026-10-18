import { AxeBuilder } from "@axe-core/playwright";
import { expect, test, type Locator, type Page } from "@playwright/test";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, extname, join } from "node:path";
import { signInAsDemo } from "../support/demo.ts";
import {
  expectImageLoaded,
  expectNoHorizontalOverflow,
  expectVideoPlaysWithCaptions,
  writeMediaFixtures,
  type MediaFixtures,
} from "../support/media.ts";
import {
  createStaffUser,
  projectBaseURL,
  type StaffUser,
} from "../support/staff.ts";

// The media library of task 0018 (step 23): an author uploads a PNG, an
// SVG, an MP4 and its WebVTT captions, generated at the start, waits until
// the library has converted them, adds them to a new draft of the
// workbench, places them in the lesson, imports and publishes the pack. A
// learner then sees both figures and plays the video with its captions.
// The pack has a name of its own per run, so its program leaves the demo
// program alone; the draft is deleted at the end.
test.describe.configure({ mode: "serial" });

const WCAG_TAGS = ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"];

/** The lesson of the empty pack (`Espalier.Workbench.Skeleton`). */
const LESSON = "modules/01-first-module/lessons/01-first-lesson.md";
const LESSON_TITLE = "First lesson";
const MODULE_TITLE = "First module";
/** The demo slot of the learner; the other specs use other slots. */
const LEARNER_SLOT = 7;

const STAMP = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
const PACK_NAME = `E2E media ${STAMP}`;
const FIGURE_ALT = "A rectangle of one colour.";
const DIAGRAM_ALT = "A light blue box with the words Test diagram.";
const VIDEO_TITLE = "A test pattern with a tone";

let author: StaffUser;
let dir = "";
let fixtures: MediaFixtures;
let draftId: string | null = null;
let draftDeleted = false;
let packKey = "";

/** The title that the library gives an uploaded file: its name without extension. */
const titleOf = (path: string) => basename(path, extname(path));

/** The draft path that "Add to draft" suggests: `media/<title>.<delivery ext>`. */
const draftPath = (path: string, ext: string) =>
  `media/${titleOf(path)}.${ext}`;

const stepUpPasskey = (page: Page): Locator =>
  page
    .getByRole("dialog", { name: "Confirm it is you" })
    .getByRole("button", { name: "Use a passkey" });

async function expectNoAxeViolations(page: Page, label: string) {
  const results = await new AxeBuilder({ page }).withTags(WCAG_TAGS).analyze();
  expect(results.violations, label).toEqual([]);
}

async function expectAnnounced(page: Page, text: string | RegExp) {
  await expect(
    page.getByRole("status").filter({ hasText: text }),
  ).toBeVisible();
}

/** The card of an asset of the library, found by its title. */
const card = (page: Page, title: string): Locator =>
  page
    .getByRole("listitem")
    .filter({ has: page.getByRole("button", { name: title, exact: true }) });

const escapeRegExp = (value: string) =>
  value.replace(/[.*+?^${}()|[\]\\/]/g, "\\$&");

/** The button of a file in the tree of the draft (see workbench.spec.ts). */
function fileButton(page: Page, path: string): Locator {
  const slash = path.lastIndexOf("/");
  const file = escapeRegExp(path.slice(slash + 1));
  const name = `^${file}\\s*,\\s*${escapeRegExp(path.slice(0, slash + 1))}(\\s*,|$)`;
  return page
    .getByRole("navigation", { name: "Files of the draft" })
    .getByRole("button", { name: new RegExp(name) });
}

interface DraftBody {
  pack_key: string | null;
  files: { id: string; path: string }[];
  media: { id: string; path: string; asset: { kind: string } }[];
}

async function readDraft(page: Page): Promise<DraftBody> {
  const answer = await page.request.get(`/api/admin/pack-drafts/${draftId}`);
  expect(answer.status()).toBe(200);
  return (await answer.json()) as DraftBody;
}

async function storedContent(page: Page, path: string): Promise<string> {
  const { files } = await readDraft(page);
  const entry = files.find((file) => file.path === path);
  expect(entry, `${path} in the draft`).toBeDefined();
  const answer = await page.request.get(
    `/api/admin/pack-drafts/${draftId}/files/${entry?.id}`,
  );
  expect(answer.status()).toBe(200);
  return ((await answer.json()) as { content: string }).content;
}

/** Deletes the draft of this run from the list of the workbench. */
async function deleteDraft(page: Page) {
  await page.goto("/admin/workbench");
  const row = page
    .getByRole("row")
    .filter({ has: page.locator(`a[href="/admin/workbench/${draftId}"]`) });
  await row.getByRole("button", { name: /^Delete / }).click();
  await page
    .getByRole("dialog", { name: "Delete this draft?" })
    .getByRole("button", { name: "Delete" })
    .click();
  await expectAnnounced(page, `The draft ${PACK_NAME} is deleted.`);
  await expect(row).toHaveCount(0);
  draftDeleted = true;
}

test.beforeAll(async ({ browser }) => {
  test.setTimeout(90_000);
  dir = await mkdtemp(join(tmpdir(), "espalier-media-"));
  fixtures = await writeMediaFixtures(dir, STAMP);
  author = await createStaffUser(browser, "author");
  // The second factor ages after ten minutes; a step-up passes with the
  // passkey of the virtual authenticator.
  await author.page.addLocatorHandler(
    stepUpPasskey(author.page),
    async (button) => {
      await button.click();
    },
  );
});

test.afterAll(async () => {
  test.setTimeout(60_000);
  try {
    if (author !== undefined && draftId !== null && !draftDeleted) {
      // A failed run may leave unsaved text behind: leave without asking.
      author.page.on("dialog", (dialog) => void dialog.accept());
      await deleteDraft(author.page);
    }
  } finally {
    await author?.context.close();
    if (dir !== "") await rm(dir, { recursive: true, force: true });
  }
});

test("an author uploads media, places them in a lesson and publishes the pack", async () => {
  test.setTimeout(240_000);
  const { page } = author;

  await test.step("start an empty pack in the workbench", async () => {
    await page.goto("/admin/workbench");
    const start = page.getByRole("region", { name: "Empty pack" });
    await start.getByLabel("Name of the pack").fill(PACK_NAME);
    await start.getByRole("button", { name: "Start an empty pack" }).click();
    await expect(page).toHaveURL(/\/admin\/workbench\/[0-9a-f-]{36}$/);
    draftId = new URL(page.url()).pathname.split("/").pop() ?? null;
    await expect(
      page.getByRole("heading", { level: 1, name: PACK_NAME }),
    ).toBeVisible();
    packKey = (await readDraft(page)).pack_key ?? "";
    expect(packKey).toMatch(/^e2e-media-/);
  });

  await test.step("upload four files and wait until each is ready", async () => {
    await page.goto("/admin/media");
    await expect(
      page.getByRole("heading", { level: 1, name: "Media library" }),
    ).toBeVisible();
    await page
      .getByLabel("Choose files")
      .setInputFiles([fixtures.png, fixtures.svg, fixtures.mp4, fixtures.vtt]);

    const uploads = page.getByRole("status", { name: "Uploads" });
    for (const path of Object.values(fixtures)) {
      const entry = uploads
        .getByRole("listitem")
        .filter({ hasText: basename(path) });
      await expect(entry).toHaveAttribute("data-state", "done", {
        timeout: 60_000,
      });
      await expect(entry).toContainText(
        "Uploaded. The library converts the file now.",
      );
    }

    // The page reads the list again every two seconds while a file is
    // converted; the video takes longest.
    const kinds: [string, string][] = [
      [fixtures.png, "Image"],
      [fixtures.svg, "SVG graphic"],
      [fixtures.mp4, "Video"],
      [fixtures.vtt, "Captions"],
    ];
    for (const [path, kind] of kinds) {
      const entry = card(page, titleOf(path));
      await expect(entry).toHaveAttribute("data-status", "ready", {
        timeout: 120_000,
      });
      await expect(entry).toContainText(kind);
    }
    await expectNoAxeViolations(page, "the media library");
  });

  await test.step("add each file to the draft from its detail dialog", async () => {
    const files: [string, string][] = [
      [fixtures.png, "webp"],
      [fixtures.svg, "svg"],
      [fixtures.mp4, "webm"],
      [fixtures.vtt, "vtt"],
    ];
    for (const [path, ext] of files) {
      const title = titleOf(path);
      await card(page, title)
        .getByRole("button", { name: title, exact: true })
        .click();
      // The dialog element has no size of its own, so the spec waits for
      // its content.
      const dialog = page.getByRole("dialog", { name: title });
      const draftChoice = dialog.getByRole("button", { name: /^Draft/ });
      await expect(draftChoice).toBeVisible();
      await draftChoice.click();
      await page.getByRole("option", { name: PACK_NAME }).click();
      await expect(dialog.getByLabel("Path in the draft")).toHaveValue(
        draftPath(path, ext),
      );
      if (ext === "webp") await expectNoAxeViolations(page, "the dialog");
      await dialog.getByRole("button", { name: "Add to draft" }).click();
      await expect(
        dialog.getByText(`Added at ${draftPath(path, ext)}.`),
      ).toBeVisible();
      await dialog.getByRole("button", { name: "Close" }).click();
      await expect(dialog).toHaveCount(0);
    }

    // Three media entries, and the captions as a text file.
    const draft = await readDraft(page);
    expect(draft.media.map((entry) => entry.path).sort()).toEqual(
      [
        draftPath(fixtures.mp4, "webm"),
        draftPath(fixtures.svg, "svg"),
        draftPath(fixtures.png, "webp"),
      ].sort(),
    );
    expect(draft.files.map((file) => file.path)).toContain(
      draftPath(fixtures.vtt, "vtt"),
    );
  });

  await test.step("place the media in the lesson and check the draft", async () => {
    await page.goto(`/admin/workbench/${draftId}`);
    await expect(
      page.getByRole("heading", { level: 1, name: PACK_NAME }),
    ).toBeVisible();
    // The tree shows the media entries below media/ with their kind.
    await expect(
      fileButton(page, draftPath(fixtures.mp4, "webm")),
    ).toHaveAccessibleName(/, Video$/);

    const stored = await storedContent(page, LESSON);
    const lesson = [
      stored.trimEnd(),
      "",
      `:::figure{src=${draftPath(fixtures.png, "webp")} alt="${FIGURE_ALT}" size=small provenance=invented}`,
      "A raster image from the media library.",
      ":::",
      "",
      `:::figure{src=${draftPath(fixtures.svg, "svg")} alt="${DIAGRAM_ALT}" size=medium provenance=invented}`,
      "An SVG graphic from the media library.",
      ":::",
      "",
      `:::video{src=${draftPath(fixtures.mp4, "webm")} title="${VIDEO_TITLE}" captions="${draftPath(fixtures.vtt, "vtt")}:en" provenance=invented}`,
      "The clip shows a moving test pattern while a steady tone plays.",
      ":::",
      "",
    ].join("\n");

    await fileButton(page, LESSON).click();
    const editor = page.getByRole("textbox", {
      name: `Content of ${LESSON}`,
      exact: true,
    });
    await editor.click();
    await page.keyboard.press("ControlOrMeta+A");
    await page.keyboard.insertText(lesson);
    await page.keyboard.press("ControlOrMeta+S");
    await expectAnnounced(page, `Saved ${LESSON}`);
    expect(await storedContent(page, LESSON)).toBe(lesson);

    await page.getByRole("button", { name: "Check", exact: true }).click();
    await expectAnnounced(page, /^Check finished: \d+ errors?, \d+ warnings?$/);
    await expect(
      page
        .getByRole("region", { name: "Check report", exact: true })
        .getByRole("heading", { name: "Errors (0)", exact: true }),
    ).toBeVisible();
  });

  await test.step("import and publish the draft", async () => {
    await page.getByRole("button", { name: "Create import" }).click();
    await expect(page).toHaveURL(/\/admin\/packs\/[0-9a-f-]{36}$/);

    // The table of the section "Media" lists the files of the import, all
    // ready, and no video lacks captions.
    const rows = page
      .getByRole("table", { name: "Media", exact: true })
      .locator("tbody tr");
    await expect(rows).toHaveCount(4);
    for (const row of await rows.all())
      await expect(row).toHaveAttribute("data-status", "ready");
    await expect(
      page.getByRole("note").filter({ hasText: "Videos without captions" }),
    ).toHaveCount(0);

    const publish = page.getByRole("button", { name: "Publish" });
    await expect(publish).toBeEnabled();
    await publish.click();
    await page
      .getByRole("dialog", { name: `Publish ${packKey}?` })
      .getByRole("button", { name: "Publish" })
      .click();
    await expect(page.getByText("The pack is published.")).toBeVisible();
  });

  await test.step("delete the draft", async () => {
    await deleteDraft(page);
  });
});

test("a learner sees both figures and plays the video with captions", async ({
  browser,
}) => {
  test.setTimeout(90_000);
  expect(packKey, "the pack of the first test").not.toBe("");
  const context = await browser.newContext({ baseURL: projectBaseURL() });
  const page = await context.newPage();
  const errors: string[] = [];
  page.on("console", (message) => {
    if (message.type() === "error") errors.push(message.text());
  });
  page.on("pageerror", (error) => errors.push(error.message));

  try {
    await signInAsDemo(page, LEARNER_SLOT);
    // The second station is the module of the empty pack.
    await page.goto(`/programs/${packKey}/stations/2`);
    await expect(
      page.getByRole("heading", { level: 1, name: MODULE_TITLE }),
    ).toBeVisible();
    const lesson = page.getByRole("region", {
      name: LESSON_TITLE,
      exact: true,
    });

    const raster = lesson.getByRole("img", { name: FIGURE_ALT });
    await expectImageLoaded(raster);
    await expect(raster).toHaveAttribute(
      "src",
      /^\/media\/[0-9a-f]{64}\.webp$/,
    );
    await expect(
      lesson
        .getByRole("figure")
        .filter({ has: page.getByRole("img", { name: FIGURE_ALT }) }),
    ).toContainText("A raster image from the media library.");

    const diagram = lesson.getByRole("img", { name: DIAGRAM_ALT });
    await expectImageLoaded(diagram);
    await expect(diagram).toHaveAttribute(
      "src",
      /^\/media\/[0-9a-f]{64}\.svg$/,
    );

    const video = lesson.locator("video");
    await expect(video.locator("source")).toHaveAttribute(
      "src",
      /^\/media\/[0-9a-f]{64}\.webm$/,
    );
    await expect(video.locator("track")).toHaveAttribute(
      "src",
      /^\/media\/[0-9a-f]{64}\.vtt$/,
    );
    await expect(lesson).toContainText(VIDEO_TITLE);
    await expectVideoPlaysWithCaptions(video);

    await expectNoAxeViolations(page, "the lesson with media");
    for (const width of [1280, 360]) {
      await page.setViewportSize({ width, height: 800 });
      await expect(raster).toBeVisible();
      await expectNoHorizontalOverflow(page, `the lesson at ${width} pixels`);
    }
    expect(errors).toEqual([]);
  } finally {
    await context.close();
  }
});
