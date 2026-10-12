import { expect, test, type Page } from "@playwright/test";
import { readFileSync } from "node:fs";
import { parse } from "yaml";
import { signInAsDemo } from "./support/demo.ts";
import { devPost } from "./support/dev.ts";

// Task 0014: the self-assessment preselects the path, and the test session
// notes stay in the browser. The demo pack (0008 step 12) is the source of
// every label, key and title the spec uses.
const pack = (path: string) =>
  readFileSync(new URL(`../../content/demo/${path}`, import.meta.url), "utf8");

interface PackSegment {
  key: string;
  label: string;
  default_path: "short" | "full";
}
interface PackItem {
  key: string;
  kind: string;
  stem: string;
  reveals?: string[];
  options?: { key: string; label: string; correct: boolean }[];
}

const SLUG: string = parse(pack("pack.yaml")).key;
const STATIONS: { kind: string; title: string; module?: number }[] = parse(
  pack("stations.yaml"),
);
const SEGMENTS: PackSegment[] = parse(pack("segments.yaml"));
const ITEMS: PackItem[] = parse(pack("modules/01-basics/items.yaml"));
const FORMATS: { key: string; title: string }[] = parse(pack("formats.yaml"));

// Stations take their positions from their order in `stations.yaml`.
const positionOf = (kind: string, module?: number) =>
  STATIONS.findIndex(
    (station) =>
      station.kind === kind &&
      (module === undefined || station.module === module),
  ) + 1;
const SELF_ASSESSMENT = positionOf("self_assessment");
const MODULE_1 = positionOf("module", 1);
const FORMATS_STATION = positionOf("companion_formats");

const SHORT = SEGMENTS.find((segment) => segment.default_path === "short")!;
const FULL = SEGMENTS.find((segment) => segment.default_path === "full")!;

// The practice item that reveals a lesson whose explanation starts
// collapsed on the short path (0012 addendum, tests).
const REVEALING = ITEMS.find((item) => (item.reveals ?? []).length > 0)!;
const lessonTitle = (key: string): string =>
  parse(pack(`modules/01-basics/lessons/${key}.md`).split("---")[1]).title;
const REVEALED_TITLE = lessonTitle(REVEALING.reveals![0]);

// The demo slots of this spec; the other specs use other slots.
const SLOT_SHORT = 11;
const SLOT_FULL = 12;
const SLOT_NOTES = 13;

/**
 * Deletes the demo users of `slots` through the development route, so that
 * they answer the self-assessment for the first time. A stack without
 * development routes answers 404 and must start with a fresh database.
 */
async function resetDemo(page: Page, slots: number[]) {
  const status = await devPost(page, "reset-demo", { slots });
  expect([204, 404], "POST /api/dev/e2e/reset-demo").toContain(status);
}

/** Every request of the page, as method, URL, headers and body. */
function recordRequests(page: Page): string[] {
  const sent: string[] = [];
  page.on("request", (request) =>
    sent.push(
      [
        request.method(),
        request.url(),
        JSON.stringify(request.headers()),
        request.postData() ?? "",
      ].join("\n"),
    ),
  );
  return sent;
}

async function chooseSegment(page: Page, segment: PackSegment) {
  await page.goto(`/programs/${SLUG}/stations/${SELF_ASSESSMENT}`);
  const saved = page.waitForResponse(
    (response) =>
      new URL(response.url()).pathname === "/api/self-assessments" &&
      response.request().method() === "POST",
  );
  await page.getByRole("button", { name: segment.label, exact: true }).click();
  expect((await saved).status()).toBe(200);
  await expect(page.locator("[data-outcome]")).toHaveAttribute(
    "data-outcome",
    "recorded",
  );
}

for (const [slot, segment] of [
  [SLOT_SHORT, SHORT],
  [SLOT_FULL, FULL],
] as const) {
  test(`a segment with the default path ${segment.default_path} preselects it, and the module view follows`, async ({
    page,
  }) => {
    await resetDemo(page, [slot]);
    await signInAsDemo(page, slot);
    const sent = recordRequests(page);

    await chooseSegment(page, segment);
    const pathName =
      segment.default_path === "short" ? "Short path" : "Full path";
    await expect(page.getByRole("radio", { name: pathName })).toBeChecked();

    // The server stores the path as preselected, not as a manual choice,
    // and the SPA sends no PATCH of the enrollment.
    const progress = (await (
      await page.request.get(`/api/me/progress?program=${SLUG}`)
    ).json()) as {
      enrollment: { path: string; path_chosen_manually: boolean };
    };
    expect(progress.enrollment.path).toBe(segment.default_path);
    expect(progress.enrollment.path_chosen_manually).toBe(false);
    expect(sent.filter((request) => request.startsWith("PATCH\n"))).toEqual([]);

    // The short path starts the explanation collapsed, the full path open.
    await page.goto(`/programs/${SLUG}/stations/${MODULE_1}`);
    const explanation = page
      .getByRole("region", { name: REVEALED_TITLE })
      .getByRole("button", { name: "Explanation" });
    await expect(explanation).toHaveAttribute(
      "aria-expanded",
      segment.default_path === "short" ? "false" : "true",
    );

    // A second visit states that the answer was recorded and shows the path.
    await page.goto(`/programs/${SLUG}/stations/${SELF_ASSESSMENT}`);
    await expect(page.locator("[data-outcome]")).toHaveAttribute(
      "data-outcome",
      "already",
    );
    await expect(page.getByRole("radio", { name: pathName })).toBeChecked();
  });
}

test("the test notes show a walk-through and never reach the server", async ({
  page,
}) => {
  test.setTimeout(90_000);
  await resetDemo(page, [SLOT_NOTES]);
  await signInAsDemo(page, SLOT_NOTES);
  const session = (await (await page.request.get("/api/session")).json()) as {
    user: { id: string; display_name: string };
    csrf_token: string;
    flags: { test_notes: boolean };
  };
  test.skip(
    !session.flags.test_notes,
    "The server runs with TEST_NOTES=false.",
  );
  const sent = recordRequests(page);

  // Self-assessment on the short path, then a manual switch to full and
  // back, which the notes record.
  await chooseSegment(page, SHORT);
  await page.getByRole("radio", { name: "Full path" }).click();
  await page.getByRole("radio", { name: "Short path" }).click();
  await expect(page.getByRole("radio", { name: "Short path" })).toBeChecked();

  // A wrong answer on the short path reveals the explanation.
  await page.goto(`/programs/${SLUG}/stations/${MODULE_1}`);
  const frame = page.getByRole("group", { name: REVEALING.stem, exact: true });
  const wrong = (REVEALING.options ?? []).find((option) => !option.correct)!;
  await frame.getByRole("radio", { name: wrong.label, exact: true }).click();
  await frame.getByRole("button", { name: "Check answer" }).click();
  await expect(frame.getByRole("status")).toContainText("Not correct.");

  // A vote for a companion format.
  await page.goto(`/programs/${SLUG}/stations/${FORMATS_STATION}`);
  const workshop = FORMATS.find((format) => format.key === "workshop")!;
  const vote = page
    .getByRole("article", { name: workshop.title })
    .getByRole("button", { name: "Would use" });
  await vote.click();
  await expect(vote).toHaveAttribute("aria-pressed", "true");

  const panel = page.getByRole("region", { name: "Test notes" });
  const log = panel.getByRole("textbox", { name: "Recorded events" });
  await expect(log).toHaveValue(
    new RegExp(`Station ${SELF_ASSESSMENT} opened`),
  );
  const text = await log.inputValue();
  for (const line of [
    `Station ${MODULE_1} opened`,
    `Station ${FORMATS_STATION} opened`,
    "Path switched: Full path",
    "Path switched: Short path",
    "answered wrongly",
    "Explanations opened after the answer to item",
    `Vote for a format at station ${FORMATS_STATION}`,
  ])
    expect(text, line).toContain(line);
  expect(text).toMatch(/^\+\d+:\d{2} /m);

  // The log lives in sessionStorage under espalier.test_notes, and no
  // request carries the key, the stored value, an event name or a line of
  // the panel.
  const stored = (await page.evaluate(
    "window.sessionStorage.getItem('espalier.test_notes')",
  )) as string | null;
  expect(stored).not.toBeNull();
  for (const value of [
    session.user.id,
    session.user.display_name,
    session.csrf_token,
  ])
    expect(stored).not.toContain(value);
  const forbidden = [
    "espalier.test_notes",
    stored!,
    "station_opened",
    "path_switched",
    "item_answered",
    "explanation_revealed",
    "format_voted",
    "answered wrongly",
    "Path switched",
  ];
  expect(sent.length).toBeGreaterThan(0);
  for (const request of sent)
    for (const value of forbidden)
      expect(request, `a request carries ${value}`).not.toContain(value);
});
