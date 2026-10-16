import {
  expect,
  test,
  type BrowserContext,
  type Locator,
  type Page,
} from "@playwright/test";
import { strFromU8, strToU8, unzipSync, zipSync } from "fflate";
import { readFileSync } from "node:fs";
import { parse } from "yaml";
import { createStaffUser, type StaffUser } from "../support/staff.ts";

// The embed of a streaming player (task 0018, steps 18 and 23): a copy of
// the demo pack under a key of its own whose first lesson embeds
// https://embed.espalier.test/player. The spec answers every request to
// that host with a small HTML page through a route and counts them. With
// MEDIA_EMBED_CONSENT=click the preview of the import shows a notice that
// names the host, and nothing reaches the host before "Load video"; after
// it the iframe loads with exactly one request. With
// MEDIA_EMBED_CONSENT=auto the iframe loads with the page. Each test skips
// on a server with the other setting, and both skip when the import reports
// that the host is not allowlisted (a dev server with another
// MEDIA_EMBED_HOSTS). The import stays unpublished.
test.describe.configure({ mode: "serial" });

const HOST = "embed.espalier.test";
const EMBED_URL = `https://${HOST}/player`;
const PLAYER_TITLE = "An embedded test player";
const PLAYER_TEXT = "Test player of the e2e spec";
const TRANSCRIPT =
  "The embedded player shows a page of text. It plays no sound.";

/** The demo lesson that gains the embed, and its title. */
const LESSON_FILE = "modules/01-basics/lessons/01-first-lesson.md";
const pack = (path: string) =>
  readFileSync(
    new URL(`../../../content/demo/${path}`, import.meta.url),
    "utf8",
  );
const LESSON_TITLE: string = parse(pack(LESSON_FILE).split("---")[1]).title;
const MODULE_TITLE: string = parse(pack("modules/01-basics/module.yaml")).title;

const STAMP = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
const PACK_KEY = `e2e-embed-${STAMP}`;

let author: StaffUser;
let importPath = "";
/** The finding of the import when the host is not allowlisted, else null. */
let notAllowlisted: string | null = null;
let consent = "";
/** The requests that reached the route of the embed host. */
const hostRequests: string[] = [];

/**
 * The demo pack as the dev route zips it, with the key and title of this
 * run and an embed block at the end of the first lesson of module 1.
 */
function embedPack(zip: Uint8Array): Uint8Array {
  const files = unzipSync(zip);
  const yaml = strFromU8(files["pack.yaml"]);
  files["pack.yaml"] = strToU8(
    yaml
      .replace(/^key: .*$/m, `key: ${PACK_KEY}`)
      .replace(/^title: .*$/m, `title: E2E embed ${STAMP}`),
  );
  const lesson = strFromU8(files[LESSON_FILE]).trimEnd();
  files[LESSON_FILE] = strToU8(
    [
      lesson,
      "",
      `:::video{embed="${EMBED_URL}" title="${PLAYER_TITLE}" provenance=invented}`,
      TRANSCRIPT,
      ":::",
      "",
    ].join("\n"),
  );
  return zipSync(files);
}

/** Answers every request to the embed host with a small page and counts it. */
async function routeEmbedHost(context: BrowserContext) {
  await context.route(`https://${HOST}/**`, async (route) => {
    hostRequests.push(route.request().url());
    await route.fulfill({
      status: 200,
      contentType: "text/html; charset=utf-8",
      body: `<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Test player</title></head><body><p>${PLAYER_TEXT}</p></body></html>`,
    });
  });
}

/** Opens the preview of the import at the station of module 1. */
async function openPreviewLesson(page: Page): Promise<Locator> {
  await page.goto(importPath);
  await page.getByRole("link", { name: "Preview" }).click();
  await expect(page).toHaveURL(new RegExp(`${importPath}/preview/`));
  await page.getByRole("link", { name: MODULE_TITLE }).first().click();
  await expect(
    page.getByRole("heading", { level: 1, name: MODULE_TITLE }),
  ).toBeVisible();
  return page.getByRole("region", { name: LESSON_TITLE, exact: true });
}

const playerFrame = (scope: Page | Locator) =>
  scope.locator(`iframe[title="${PLAYER_TITLE}"]`);

test.beforeAll(async ({ browser }) => {
  test.setTimeout(90_000);
  author = await createStaffUser(browser, "author");
  const { page, context } = author;
  await routeEmbedHost(context);

  const archive = await page.request.get("/api/dev/e2e/demo-pack.zip");
  expect(archive.status()).toBe(200);
  await page.goto("/admin/packs");
  await page.getByLabel("Pack archive (zip)").setInputFiles({
    name: `${PACK_KEY}.zip`,
    mimeType: "application/zip",
    buffer: Buffer.from(embedPack(new Uint8Array(await archive.body()))),
  });
  await page.getByRole("button", { name: "Upload" }).click();
  await expect(page).toHaveURL(/\/admin\/packs\/[0-9a-f-]{36}$/);
  importPath = new URL(page.url()).pathname;

  const view = await page.request.get(`/api${importPath}`);
  expect(view.status()).toBe(200);
  const body = (await view.json()) as {
    status: string;
    report: { errors: { message: string }[] };
    media_policy: { embed_consent: string };
  };
  consent = body.media_policy.embed_consent;
  notAllowlisted =
    body.report.errors.find((entry) =>
      entry.message.includes(`host ${HOST} is not in MEDIA_EMBED_HOSTS`),
    )?.message ?? null;
  if (notAllowlisted === null)
    expect(body.report.errors, "the report of the import").toEqual([]);
});

test.afterAll(async () => {
  await author?.context.close();
});

test("with consent on click, nothing reaches the host before Load video", async () => {
  test.skip(
    notAllowlisted !== null,
    `The server does not allow ${HOST} (MEDIA_EMBED_HOSTS): ${notAllowlisted}`,
  );
  test.skip(
    consent !== "click",
    `The server runs with MEDIA_EMBED_CONSENT=${consent}.`,
  );
  const { page } = author;
  hostRequests.length = 0;

  const lesson = await openPreviewLesson(page);
  const notice = lesson.getByText(
    `This video plays in a player of ${HOST}. Loading it sends the address of your device and data of your browser to ${HOST}.`,
  );
  await notice.scrollIntoViewIfNeeded();
  await expect(notice).toBeVisible();
  const openOn = lesson.getByRole("link", { name: `Open on ${HOST}` });
  await expect(openOn).toHaveAttribute("href", EMBED_URL);
  await expect(openOn).toHaveAttribute("target", "_blank");
  await expect(openOn).toHaveAttribute("rel", "noopener noreferrer");
  await expect(playerFrame(page)).toHaveCount(0);
  await page.waitForLoadState("networkidle");
  expect(hostRequests, "requests before Load video").toEqual([]);

  await lesson.getByRole("button", { name: "Load video" }).click();
  const frame = playerFrame(lesson);
  await expect(frame).toBeVisible();
  await expect(frame).toHaveAttribute("src", EMBED_URL);
  await expect(frame).toHaveAttribute(
    "sandbox",
    "allow-scripts allow-same-origin allow-presentation allow-popups allow-popups-to-escape-sandbox",
  );
  await expect(frame).toHaveAttribute(
    "allow",
    "fullscreen; picture-in-picture; encrypted-media",
  );
  await expect(frame).toHaveAttribute(
    "referrerpolicy",
    "strict-origin-when-cross-origin",
  );
  await expect(
    page.frameLocator(`iframe[title="${PLAYER_TITLE}"]`).getByText(PLAYER_TEXT),
  ).toBeVisible();
  await expect(notice).toHaveCount(0);
  await page.waitForLoadState("networkidle");
  expect(hostRequests, "requests after Load video").toEqual([EMBED_URL]);
});

test("with consent auto, the player loads with the page", async () => {
  test.skip(
    notAllowlisted !== null,
    `The server does not allow ${HOST} (MEDIA_EMBED_HOSTS): ${notAllowlisted}`,
  );
  test.skip(
    consent !== "auto",
    `The server runs with MEDIA_EMBED_CONSENT=${consent}; restart it with auto for this test.`,
  );
  const { page } = author;
  hostRequests.length = 0;

  const lesson = await openPreviewLesson(page);
  const frame = playerFrame(lesson);
  await frame.scrollIntoViewIfNeeded();
  await expect(frame).toHaveAttribute("src", EMBED_URL);
  await expect(
    page.frameLocator(`iframe[title="${PLAYER_TITLE}"]`).getByText(PLAYER_TEXT),
  ).toBeVisible();
  await expect(lesson.getByRole("button", { name: "Load video" })).toHaveCount(
    0,
  );
  await page.waitForLoadState("networkidle");
  expect(hostRequests).toEqual([EMBED_URL]);
});
