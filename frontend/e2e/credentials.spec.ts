import { AxeBuilder } from "@axe-core/playwright";
import { expect, test, type Locator, type Page } from "@playwright/test";
import { readFileSync, statSync } from "node:fs";
import { parse } from "yaml";
import { signInAsDemo } from "./support/demo.ts";

// The acceptance walk-through of task 0013: the demo user completes modules
// 1 and 2, passes the exam of module 1 and acknowledges `usage-policy` on
// /policies; the credential `basics` then appears on the credential station
// and on /me/credentials/:id with its unlocked tasks and a validity of
// twelve months. The demo user keeps its records, so a second run against
// the same database finds the modules completed, the policy acknowledged
// and the credential issued, and passes as well. It needs the demo seed of
// `mix espalier.seed_demo`, which publishes `usage-policy`.

const WCAG_TAGS = ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"];

/** A demo slot that no other spec uses. */
const SLOT = 4;
const DISPLAY_NAME = `Test person ${SLOT}`;
const POLICY_KEY = "usage-policy";

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
  options?: PackOption[];
}
interface PackQualification {
  code: string;
  title: string;
  unlocks: string[];
  validity_kind: string;
  validity_months?: number;
  requirements: { kind: string; target: string | number }[];
}

const SLUG: string = parse(pack("pack.yaml")).key;
const STATIONS: { kind: string; title: string; module?: number }[] = parse(
  pack("stations.yaml"),
);
const ITEMS: PackItem[] = parse(pack("modules/01-basics/items.yaml"));
const [EXAM]: { title: string; items: string[] }[] = parse(
  pack("modules/01-basics/assessment.yaml"),
);
const EXAM_ITEMS = EXAM.items.map((key) =>
  ITEMS.find((item) => item.key === key)!,
);
const BASICS = (parse(pack("qualifications.yaml")) as PackQualification[]).find(
  (qualification) => qualification.code === "basics",
)!;

// Stations take their positions from their order in `stations.yaml`.
const positionOf = (match: (station: (typeof STATIONS)[number]) => boolean) =>
  STATIONS.findIndex(match) + 1;
const MODULE_POSITIONS = [1, 2].map((number) =>
  positionOf(
    (station) => station.kind === "module" && station.module === number,
  ),
);
const CREDENTIAL_POSITION = positionOf(
  (station) => station.kind === "credential",
);
const titleAt = (position: number) => STATIONS[position - 1].title;

/** The frame of an item, located by its stem. */
const itemFrame = (scope: Page | Locator, item: PackItem) =>
  scope.getByRole("group", { name: item.stem, exact: true });

/** Chooses the correct options of a choice item. */
async function answerCorrectly(frame: Locator, item: PackItem) {
  const correct = (item.options ?? []).filter((option) => option.correct);
  if (item.kind === "multiple_choice") {
    for (const option of correct)
      await frame.getByRole("checkbox", { name: option.label }).check();
    return;
  }
  await frame
    .getByRole("radio", { name: correct[0].label, exact: true })
    .click();
}

async function openStation(page: Page, position: number) {
  await page.goto(`/programs/${SLUG}/stations/${position}`);
  await expect(
    page.getByRole("heading", { level: 1, name: titleAt(position) }),
  ).toBeVisible();
}

/**
 * Completes the module of the open station. A module completed in an
 * earlier run shows its summary at once.
 */
async function completeModule(page: Page) {
  const complete = page.getByRole("button", { name: "Complete module" });
  const summary = page.getByRole("region", { name: "Module complete" });
  await expect(complete.or(summary)).toBeVisible();
  if (await complete.isVisible()) await complete.click();
  await expect(summary).toBeVisible();
}

/** `YYYY-MM-DD` plus `months`, clamped to the last day of the month. */
function addMonths(day: string, months: number): string {
  const [year, month, date] = day.split("-").map(Number);
  const target = new Date(Date.UTC(year, month - 1 + months, 1));
  const last = new Date(
    Date.UTC(target.getUTCFullYear(), target.getUTCMonth() + 1, 0),
  ).getUTCDate();
  target.setUTCDate(Math.min(date, last));
  return target.toISOString().slice(0, 10);
}

/** A date of the API as the SPA shows it in English. */
const shownDay = (day: string) =>
  new Intl.DateTimeFormat("en", {
    dateStyle: "medium",
    timeZone: "UTC",
  }).format(new Date(`${day}T00:00:00Z`));

async function expectNoAxeViolations(page: Page, label: string) {
  const results = await new AxeBuilder({ page }).withTags(WCAG_TAGS).analyze();
  expect(results.violations, label).toEqual([]);
}

test("the demo user earns the credential basics and opens it", async ({
  page,
}, testInfo) => {
  test.setTimeout(180_000);
  await signInAsDemo(page, SLOT);

  // Module 1: the exam passes with every answer correct, then the module
  // completes.
  await openStation(page, MODULE_POSITIONS[0]);
  const exam = page.getByRole("region", { name: EXAM.title });
  for (const item of EXAM_ITEMS)
    await answerCorrectly(itemFrame(exam, item), item);
  await exam.getByRole("button", { name: "Submit the exam" }).click();
  await expect(exam.locator("[data-outcome]")).toHaveAttribute(
    "data-outcome",
    "passed",
  );
  await completeModule(page);

  // Module 2.
  await openStation(page, MODULE_POSITIONS[1]);
  await completeModule(page);

  // The policy, reached through the main navigation.
  await page
    .getByRole("navigation", { name: "Main" })
    .getByRole("link", { name: "Policies" })
    .click();
  await expect(page).toHaveURL("/policies");
  const policy = page.locator(`[data-policy-key="${POLICY_KEY}"]`);
  await expect(policy).toBeVisible();
  const acknowledge = policy.getByRole("button", {
    name: "I have read this version",
  });
  const acknowledged = policy.getByText(/^You acknowledged this version on /);
  await expect(acknowledge.or(acknowledged)).toBeVisible();
  if (await acknowledge.isVisible()) await acknowledge.click();
  await expect(acknowledged).toBeVisible();
  await expect(acknowledge).toHaveCount(0);
  await expect(
    page.getByRole("table", { name: "Approved tools" }).getByRole("row"),
  ).not.toHaveCount(0);
  await expectNoAxeViolations(page, "/policies");

  // At phone width the tool table scrolls sideways inside a group that
  // takes the keyboard focus.
  const viewport = page.viewportSize();
  await page.setViewportSize({ width: 360, height: 800 });
  await expect(
    page.getByRole("group", { name: "Approved tools" }),
  ).toBeVisible();
  await expectNoAxeViolations(page, "/policies at a width of 360 px");
  if (viewport !== null) await page.setViewportSize(viewport);

  // The credential station: every requirement of basics is met, and the
  // credential is active.
  await openStation(page, CREDENTIAL_POSITION);
  const qualification = page.getByRole("region", {
    name: BASICS.title,
    exact: true,
  });
  await expect(qualification).toBeVisible();
  await expect(
    qualification.getByRole("list", { name: "Open requirements" }),
  ).toHaveCount(0);
  await expect(
    qualification
      .getByRole("list", { name: "Met requirements" })
      .getByRole("listitem"),
  ).toHaveCount(BASICS.requirements.length);
  await expect(qualification.locator("[data-status]")).toHaveAttribute(
    "data-status",
    "active",
  );
  await expectNoAxeViolations(page, "the credential station");

  // The credential page.
  await qualification
    .getByRole("link", { name: "View the credential" })
    .click();
  await expect(page).toHaveURL(/\/me\/credentials\/[0-9a-f-]{36}$/);
  const id = new URL(page.url()).pathname.split("/").pop()!;
  const heading = page.getByRole("heading", {
    level: 1,
    name: BASICS.title,
    exact: true,
  });
  await expect(heading).toBeVisible();

  const answer = await page.request.get(`/api/me/credentials/${id}`);
  expect(answer.ok()).toBe(true);
  const credential = (await answer.json()) as {
    qualification_code: string;
    status: string;
    issued_at: string;
    valid_until: string | null;
    unlocks_snapshot: string[];
  };
  expect(credential.qualification_code).toBe(BASICS.code);
  expect(credential.status).toBe("active");
  expect(credential.unlocks_snapshot).toEqual(BASICS.unlocks);

  // `valid_until` lies twelve months after the issue date, which is today
  // on the first run and an earlier day on a later run.
  expect(BASICS.validity_kind).toBe("months");
  expect(BASICS.validity_months).toBe(12);
  const validUntil = credential.valid_until!;
  const issuedOn = credential.issued_at.slice(0, 10);
  const today = new Date().toISOString().slice(0, 10);
  expect(issuedOn <= today).toBe(true);
  expect(validUntil >= addMonths(issuedOn, 12)).toBe(true);
  expect(validUntil <= addMonths(today, 12)).toBe(true);

  const details = page.locator("article dl");
  const detail = (term: string) =>
    details
      .locator("dt", { hasText: term })
      .locator("xpath=following-sibling::dd[1]");
  await expect(detail("Holder")).toHaveText(DISPLAY_NAME);
  await expect(detail("Status")).toHaveText("Active");
  await expect(detail("Valid until")).toHaveText(shownDay(validUntil));
  await expect(
    page
      .getByRole("region", { name: "The holder may carry out these tasks" })
      .getByRole("listitem"),
  ).toHaveText(BASICS.unlocks);
  await expect(page.locator("main")).not.toContainText("%");
  await expectNoAxeViolations(page, "/me/credentials/:id");

  // The print view on A4 leaves out the navigation and the print button.
  await page.emulateMedia({ media: "print" });
  await expect(page.getByRole("button", { name: "Print" })).toBeHidden();
  await expect(
    page.getByRole("navigation", { name: "Breadcrumb" }),
  ).toBeHidden();
  await expect(heading).toBeVisible();
  const path = testInfo.outputPath("credential.pdf");
  await page.pdf({ path, format: "A4" });
  expect(statSync(path).size).toBeGreaterThan(0);
  await page.emulateMedia({ media: "screen" });

  // The list of the user's credentials links to the same page.
  await page.goto("/me/credentials");
  await expect(
    page.getByRole("link", { name: BASICS.title, exact: true }),
  ).toHaveAttribute("href", `/me/credentials/${id}`);
});
