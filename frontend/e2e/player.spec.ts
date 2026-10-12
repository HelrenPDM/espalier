import { AxeBuilder } from "@axe-core/playwright";
import { expect, test, type Locator, type Page } from "@playwright/test";
import { readFileSync, statSync } from "node:fs";
import { parse } from "yaml";
import { signInAsDemo } from "./support/demo.ts";

const WCAG_TAGS = ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"];

// The demo pack (0008 step 12) is the source of every label, key and title
// the spec uses.
const pack = (path: string) =>
  readFileSync(new URL(`../../content/demo/${path}`, import.meta.url), "utf8");

interface PackOption {
  key: string;
  label: string;
  correct: boolean;
}
interface PackItem {
  key: string;
  kind: string;
  stem: string;
  core: boolean;
  lesson?: string;
  reveals?: string[];
  objectives?: string[];
  options?: PackOption[];
}
interface PackObjective {
  key: string;
  statement: string;
  area: string;
}

const SLUG: string = parse(pack("pack.yaml")).key;
const STATIONS: { kind: string; title: string; module?: number }[] = parse(
  pack("stations.yaml"),
);
const ITEMS: PackItem[] = parse(pack("modules/01-basics/items.yaml"));
const [EXAM]: { title: string; items: string[] }[] = parse(
  pack("modules/01-basics/assessment.yaml"),
);
const OBJECTIVES: PackObjective[] = parse(
  pack("modules/01-basics/objectives.yaml"),
);
const OBJECTIVE_KEYS: string[] = [
  ...OBJECTIVES,
  ...(parse(pack("modules/02-checking/objectives.yaml")) as PackObjective[]),
].map((objective) => objective.key);
const WORKSHOP_TITLE: string = (
  parse(pack("formats.yaml")) as { key: string; title: string }[]
).find((format) => format.key === "workshop")!.title;

/** The `title` of the front matter of a lesson file of module 1. */
const lessonTitle = (key: string): string =>
  parse(pack(`modules/01-basics/lessons/${key}.md`).split("---")[1]).title;

// Stations take their positions from their order in `stations.yaml`.
const MODULE_1_POSITION =
  STATIONS.findIndex(
    (station) => station.kind === "module" && station.module === 1,
  ) + 1;
const MODULE_1_TITLE = STATIONS[MODULE_1_POSITION - 1].title;

const PRACTICE_ITEMS = ITEMS.filter((item) => !EXAM.items.includes(item.key));
const EXAM_ITEMS = EXAM.items.map((key) =>
  ITEMS.find((item) => item.key === key)!,
);
const REVEALING = PRACTICE_ITEMS.find(
  (item) => (item.reveals ?? []).length > 0,
)!;
const statement = (key: string) =>
  OBJECTIVES.find((objective) => objective.key === key)!.statement;
const options = (item: PackItem, correct: boolean) =>
  (item.options ?? []).filter((option) => option.correct === correct);

/** The frame of an item, located by its stem. */
const itemFrame = (scope: Page | Locator, item: PackItem) =>
  scope.getByRole("group", { name: item.stem, exact: true });

/** Chooses the correct options of a choice item, or one wrong option. */
async function answer(frame: Locator, item: PackItem, correct: boolean) {
  if (item.kind === "multiple_choice") {
    for (const option of options(item, true))
      await frame.getByRole("checkbox", { name: option.label }).check();
    if (!correct)
      await frame
        .getByRole("checkbox", { name: options(item, false)[0].label })
        .check();
    return;
  }
  const option = options(item, correct)[0];
  await frame.getByRole("radio", { name: option.label, exact: true }).click();
}

async function expectNoAxeViolations(page: Page, label: string) {
  const results = await new AxeBuilder({ page }).withTags(WCAG_TAGS).analyze();
  expect(results.violations, label).toEqual([]);
}

test("a learner goes through module 1 on the short path", async ({ page }) => {
  test.setTimeout(120_000);
  await signInAsDemo(page, 2);

  await page.goto("/");
  await page.getByRole("link", { name: "AI assistant basics (demo)" }).click();
  await expect(page).toHaveURL(`/programs/${SLUG}`);
  await page.getByRole("radio", { name: "Short path" }).click();
  await expect(page.getByRole("radio", { name: "Short path" })).toBeChecked();

  await page
    .getByRole("navigation", { name: "Stations" })
    .getByRole("link", { name: MODULE_1_TITLE })
    .click();
  await expect(page).toHaveURL(
    `/programs/${SLUG}/stations/${MODULE_1_POSITION}`,
  );
  await expect(
    page.getByRole("heading", { level: 1, name: MODULE_1_TITLE }),
  ).toBeFocused();

  // The objectives panel: the four areas in order and the five statements.
  const panel = page.getByRole("region", { name: "Objectives of this topic" });
  await expect(panel.getByRole("heading", { level: 3 })).toHaveText([
    "Subject competence",
    "Method competence",
    "Self competence",
    "Social competence",
  ]);
  for (const objective of OBJECTIVES)
    await expect(panel.getByText(objective.statement)).toBeVisible();

  // Every practice item except the poll shows one chip.
  for (const item of PRACTICE_ITEMS) {
    const chips = itemFrame(page, item).getByRole("list", {
      name: "Objectives of this item",
    });
    if (item.kind === "poll") await expect(chips).toHaveCount(0);
    else await expect(chips.getByRole("listitem")).toHaveCount(1);
  }

  await expectNoAxeViolations(page, "module 1 before the completion");

  // Reveal on a wrong answer on the short path.
  const revealedTitle = lessonTitle(REVEALING.reveals![0]);
  const explanation = page
    .getByRole("region", { name: revealedTitle })
    .getByRole("button", { name: "Explanation" });
  await expect(explanation).toHaveAttribute("aria-expanded", "false");
  const revealing = itemFrame(page, REVEALING);
  await answer(revealing, REVEALING, false);
  await revealing.getByRole("button", { name: "Check answer" }).click();
  await expect(revealing.getByRole("status")).toContainText("Not correct.");
  await expect(revealing.getByRole("status")).toContainText(revealedTitle);
  await expect(explanation).toHaveAttribute("aria-expanded", "true");

  // The exam: the core item wrong fails, all answers correct pass.
  const exam = page.getByRole("region", { name: EXAM.title });
  for (const item of EXAM_ITEMS)
    await answer(itemFrame(exam, item), item, !item.core);
  await exam.getByRole("button", { name: "Submit the exam" }).click();
  await expect(exam.locator("[data-outcome]")).toHaveAttribute(
    "data-outcome",
    "failed_core",
  );
  await expect(exam.getByRole("status")).toContainText(
    "a core question is answered wrong",
  );
  await exam.getByRole("button", { name: "New attempt" }).click();
  for (const item of EXAM_ITEMS)
    await answer(itemFrame(exam, item), item, true);
  await exam.getByRole("button", { name: "Submit the exam" }).click();
  await expect(exam.locator("[data-outcome]")).toHaveAttribute(
    "data-outcome",
    "passed",
  );

  // Completion. A demo user who completed the module in an earlier run sees
  // the summary at once.
  const complete = page.getByRole("button", { name: "Complete module" });
  if (await complete.isVisible()) await complete.click();
  const summary = page.getByRole("region", { name: "Module complete" });
  await expect(summary).toBeVisible();
  await expect(summary).not.toContainText("%");

  const entry = (key: string) =>
    summary.getByRole("listitem").filter({ hasText: statement(key) });
  for (const key of [
    "m1-subject-next-word",
    "m1-subject-varying-answers",
    "m1-method-check-claims",
  ])
    await expect(entry(key).locator("[data-status]")).toHaveAttribute(
      "data-status",
      "evidenced",
    );
  // An attendance certificate for the demo user can exist from outside this
  // spec, so the workshop objectives are open with the note or evidenced.
  for (const key of [
    "m1-self-own-responsibility",
    "m1-social-team-transparency",
  ]) {
    const status = await entry(key)
      .locator("[data-status]")
      .getAttribute("data-status");
    expect(["open", "evidenced"], key).toContain(status);
    if (status === "open")
      await expect(entry(key)).toContainText(WORKSHOP_TITLE);
  }

  await expectNoAxeViolations(page, "module 1 after the completion");

  // The browser entry and the progress answer.
  const progressAnswer = await page.request.get(
    `/api/me/progress?program=${SLUG}`,
  );
  expect(progressAnswer.ok()).toBe(true);
  const progress = (await progressAnswer.json()) as Record<string, unknown>;
  const storage = Object.fromEntries(
    await page.evaluate(() => Object.entries(localStorage)),
  );
  const key = `espalier.player.${SLUG}`;
  const raw = storage[key];
  expect(raw, key).toBeTruthy();
  const entryValue = JSON.parse(raw!) as Record<string, unknown>;
  if ("answered_item_ids" in progress) {
    expect(Object.keys(entryValue).sort()).toEqual(
      ["o", "openedExplanations", "v", "visitedStations"].sort(),
    );
  } else {
    expect(Object.keys(entryValue).sort()).toEqual(
      [
        "answeredItems",
        "o",
        "openedExplanations",
        "v",
        "visitedStations",
      ].sort(),
    );
    expect(entryValue.answeredItems).not.toEqual([]);
  }
  // The owner tag is a digest prefix and holds no id.
  expect(entryValue.o).toMatch(/^[0-9a-f]{16}$/);
  for (const objectiveKey of OBJECTIVE_KEYS)
    expect(raw, objectiveKey).not.toContain(objectiveKey);
  expect(
    Object.keys(storage).filter(
      (name) => name.startsWith("espalier.") && name !== key,
    ),
  ).toEqual([]);
});

test("a second person in the same browser sees none of the visited stations of the first", async ({
  page,
}) => {
  const visited = page
    .getByRole("navigation", { name: "Stations" })
    .getByText("Visited");

  await signInAsDemo(page, 5);
  await page.goto(`/programs/${SLUG}/stations/2`);
  await expect(
    page.getByRole("heading", { level: 1, name: STATIONS[1].title }),
  ).toBeVisible();
  await expect(visited).toHaveCount(1);

  // The next person signs in on the same browser and opens station 1: only
  // that station counts as visited, because the entry of the first person
  // carries another owner tag.
  await signInAsDemo(page, 6);
  await page.goto(`/programs/${SLUG}/stations/1`);
  await expect(
    page.getByRole("heading", { level: 1, name: STATIONS[0].title }),
  ).toBeVisible();
  await expect(visited).toHaveCount(1);
  await expect(
    page
      .getByRole("navigation", { name: "Stations" })
      .getByRole("link", { name: STATIONS[1].title }),
  ).not.toContainText("Visited");
});

test("every station renders without console errors and fits 360 pixels", async ({
  page,
}) => {
  test.setTimeout(120_000);
  const errors: string[] = [];
  page.on("console", (message) => {
    if (message.type() === "error") errors.push(message.text());
  });
  page.on("pageerror", (error) => errors.push(error.message));
  await signInAsDemo(page, 2);

  for (const width of [1280, 360]) {
    await page.setViewportSize({ width, height: 800 });
    for (const [index, station] of STATIONS.entries()) {
      await page.goto(`/programs/${SLUG}/stations/${index + 1}`);
      await expect(
        page.getByRole("heading", { level: 1, name: station.title }),
      ).toBeVisible();
      const [scrollWidth, viewport] = await page.evaluate<[number, number]>(
        "[document.documentElement.scrollWidth, window.innerWidth]",
      );
      expect(scrollWidth, `${station.title} at ${width}`).toBeLessThanOrEqual(
        viewport,
      );
    }
  }

  // An open tooltip of a glossary term or an objective chip stays inside
  // the viewport as well.
  await page.goto(`/programs/${SLUG}/stations/${MODULE_1_POSITION}`);
  await expect(
    page.getByRole("region", { name: "Objectives of this topic" }),
  ).toBeVisible();
  const triggers = page.locator(
    "main .prose button, main ul[aria-label='Objectives of this item'] a",
  );
  const count = await triggers.count();
  expect(count).toBeGreaterThan(0);
  for (let index = 0; index < count; index++) {
    await triggers.nth(index).focus();
    await expect(page.getByTestId("tooltip")).toBeVisible();
    const [scrollWidth, viewport] = await page.evaluate<[number, number]>(
      "[document.documentElement.scrollWidth, window.innerWidth]",
    );
    expect(scrollWidth, `tooltip ${index} at 360`).toBeLessThanOrEqual(
      viewport,
    );
  }
  expect(errors).toEqual([]);
});

test("the handbook prints on A4 without the navigation", async ({
  page,
}, testInfo) => {
  await signInAsDemo(page, 2);
  await page.goto(`/programs/${SLUG}/handbook`);
  await expect(
    page.getByRole("heading", { level: 1, name: "Handbook" }),
  ).toBeVisible();
  await expect(page.getByRole("heading", { level: 2 }).first()).toBeVisible();

  await page.emulateMedia({ media: "print" });
  await expect(page.getByRole("link", { name: "Espalier" })).toBeHidden();
  await expect(page.getByRole("button", { name: "Print" })).toBeHidden();

  const path = testInfo.outputPath("handbook.pdf");
  await page.pdf({ path, format: "A4" });
  expect(statSync(path).size).toBeGreaterThan(0);
});
