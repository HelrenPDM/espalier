import {
  expect,
  test,
  type FrameLocator,
  type Locator,
  type Page,
} from "@playwright/test";
import { readdirSync, readFileSync } from "node:fs";
import {
  copyFile,
  mkdir,
  mkdtemp,
  readFile,
  rm,
  writeFile,
} from "node:fs/promises";
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { tmpdir } from "node:os";
import { dirname, extname, join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { unzipSync } from "fflate";
import { parse } from "yaml";
import {
  expectImageLoaded,
  expectVideoPlaysWithCaptions,
} from "../support/media.ts";
import { createStaffUser, type StaffUser } from "../support/staff.ts";

// An author exports modules 1 and 2 of the demo pack as SCORM 1.2 and SCORM
// 2004 4th edition packages on the export page, and each package runs in
// lms.html, a stand-in LMS on the run-time API of the npm package
// scorm-again (task 0016, step 14). The tests share the downloaded packages
// and the saved CMI data of the first session, so they run in order.
test.describe.configure({ mode: "serial" });

// The demo pack (0008 step 12) is the source of the titles and of the
// objective keys in position order.
const pack = (path: string) =>
  readFileSync(
    new URL(`../../../content/demo/${path}`, import.meta.url),
    "utf8",
  );
const PACK: { key: string; title: string } = parse(pack("pack.yaml"));
const MODULE_DIRS: Record<number, string> = {
  1: "modules/01-basics",
  2: "modules/02-checking",
};
const moduleTitle = (number: number): string =>
  parse(pack(`${MODULE_DIRS[number]}/module.yaml`)).title;
const objectiveKeys = (number: number): string[] =>
  (
    parse(pack(`${MODULE_DIRS[number]}/objectives.yaml`)) as { key: string }[]
  ).map((objective) => objective.key);

/**
 * The `media/` paths that the lessons of module `number` reference (task
 * 0018, step 20): the `src` of a figure or video and each file of
 * `captions`. Module 1 holds the demo video and its captions, module 2 the
 * SVG figure.
 */
const mediaPaths = (number: number): string[] => {
  const dir = `${MODULE_DIRS[number]}/lessons`;
  const files = readdirSync(
    new URL(`../../../content/demo/${dir}`, import.meta.url),
  );
  const paths = files.flatMap((file) =>
    [
      ...pack(`${dir}/${file}`).matchAll(
        /\b(?:src|captions)="?(media\/[a-z0-9/-]+\.[a-z0-9]+)/g,
      ),
    ].map((match) => match[1]),
  );
  return [...new Set(paths)].sort();
};

// The objectives of module 1 that the exam items name, and those whose only
// evidence is the companion format `workshop`.
const EXAM_OBJECTIVES = [
  "m1-subject-next-word",
  "m1-subject-varying-answers",
  "m1-method-check-claims",
];
const WORKSHOP_OBJECTIVES = [
  "m1-self-own-responsibility",
  "m1-social-team-transparency",
];

/** The harness page and the scorm-again bundle that it loads. */
const LMS_PAGE = fileURLToPath(new URL("lms.html", import.meta.url));
const SCORM_AGAIN = fileURLToPath(
  new URL(
    "../../node_modules/scorm-again/dist/scorm-again.js",
    import.meta.url,
  ),
);

interface Version {
  /** `scorm_version` of the export and the end of the file name. */
  key: "scorm12" | "scorm2004";
  /** The radio button of the export page and the version in its list. */
  label: string;
  /** The `version` parameter of lms.html. */
  lms: "1.2" | "2004";
  initialize: string;
  commit: string;
  terminate: string;
}

const VERSIONS: Version[] = [
  {
    key: "scorm12",
    label: "SCORM 1.2",
    lms: "1.2",
    initialize: "LMSInitialize",
    commit: "LMSCommit",
    terminate: "LMSFinish",
  },
  {
    key: "scorm2004",
    label: "SCORM 2004 4th edition",
    lms: "2004",
    initialize: "Initialize",
    commit: "Commit",
    terminate: "Terminate",
  },
];

type ObjectiveState = "passed" | "failed" | "incomplete";

/**
 * The elements of an entry of `cmi.objectives` per objective state, as
 * docs/guides/scorm-export.md lists them.
 */
const OBJECTIVE_VALUES: Record<
  Version["lms"],
  Record<ObjectiveState, Record<string, string>>
> = {
  "1.2": {
    passed: { status: "passed" },
    failed: { status: "failed" },
    incomplete: { status: "incomplete" },
  },
  "2004": {
    passed: { success_status: "passed", completion_status: "completed" },
    failed: { success_status: "failed", completion_status: "completed" },
    incomplete: { success_status: "unknown", completion_status: "incomplete" },
  },
};

// The members of `content.json` that the spec reads.
interface ContentOption {
  key: string;
  label: string;
  correct: boolean | null;
}
interface ContentItem {
  key: string;
  kind: string;
  stem: string;
  core: boolean;
  objectives: string[];
  options: ContentOption[];
  config: unknown;
}
interface SlotBuilderConfig {
  slots: { key: string; label: string; options: ContentOption[] }[];
}
interface ClassificationConfig {
  categories: { key: string; label: string }[];
  cases: { key: string; text: string }[];
  expected: Record<string, string>;
}
interface ChecklistDrillConfig {
  checks: { key: string; label: string; required: boolean }[];
}
/** A media file of a package: its delivery file below `media/`. */
interface ContentMedia {
  kind: "image" | "svg" | "video" | "captions";
  url: string;
  mime: string;
  poster_url: string | null;
}
interface Content {
  media: Record<string, ContentMedia>;
  module: {
    number: number;
    title: string;
    lessons: { key: string; title: string; position: number }[];
    objectives: { key: string }[];
    items: ContentItem[];
    assessments: {
      key: string;
      title: string;
      kind: string;
      max_wrong: number;
      items: string[];
    }[];
  };
}

/** An extracted package: its directory below `root` and its content. */
interface Package {
  dir: string;
  content: Content;
}

/** A call that lms.html recorded. */
interface LmsCall {
  name: string;
  element?: string;
  value?: string;
  result: string;
  error: string;
}

/** One launch of a package in lms.html. */
interface Session {
  page: Page;
  sco: FrameLocator;
  content: Content;
  version: Version;
}

/** The values that the package set, as [element, value] in call order. */
type Values = [element: string, value: string][];

let author: StaffUser;
/** The served directory: lms.html, the bundle and the extracted packages. */
let root = "";
let server: Server | undefined;
let lmsOrigin: string;
const packages = new Map<string, Package>();
/** The saved CMI data and the objective entries of the first session. */
const firstSessions = new Map<
  Version["key"],
  { saved: unknown; entries: Record<string, string>[] }
>();

const CONTENT_TYPES: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json",
  ".xml": "application/xml",
  ".xsd": "application/xml",
  ".webp": "image/webp",
  ".svg": "image/svg+xml; charset=utf-8",
  ".webm": "video/webm",
  ".vtt": "text/vtt; charset=utf-8",
};

/** Serves the files below `dir` on a free port of 127.0.0.1. */
async function serve(dir: string): Promise<Server> {
  const created = createServer((request, response) => {
    const { pathname } = new URL(request.url ?? "/", "http://127.0.0.1");
    const path = resolve(dir, `.${decodeURIComponent(pathname)}`);
    if (!path.startsWith(dir + sep)) {
      response.writeHead(404).end();
      return;
    }
    readFile(path).then(
      (body) =>
        response
          .writeHead(200, {
            "content-type":
              CONTENT_TYPES[extname(path)] ?? "application/octet-stream",
          })
          .end(body),
      () => response.writeHead(404).end(),
    );
  });
  await new Promise<void>((listening) =>
    created.listen(0, "127.0.0.1", listening),
  );
  return created;
}

/**
 * Extracts `zip` into `target` and returns the entry names. An entry that
 * would leave `target` fails the spec.
 */
async function extract(zip: Buffer, target: string): Promise<string[]> {
  const entries = unzipSync(new Uint8Array(zip));
  for (const [name, data] of Object.entries(entries)) {
    if (name.endsWith("/")) continue;
    const path = resolve(target, name);
    if (!path.startsWith(target + sep))
      throw new Error(`The zip entry ${name} lies outside the package.`);
    await mkdir(dirname(path), { recursive: true });
    await writeFile(path, data);
  }
  return Object.keys(entries);
}

const packageOf = (number: number, version: Version): Package => {
  const found = packages.get(`${number}-${version.key}`);
  if (found === undefined)
    throw new Error(`The package of module ${number} is missing.`);
  return found;
};

/**
 * Opens lms.html with the package of module `number` for `version` in a
 * new document, with the CMI data of an earlier session when `saved` is
 * given, and waits for the module station of the package.
 */
async function launch(
  page: Page,
  number: number,
  version: Version,
  saved?: unknown,
): Promise<Session> {
  const { dir, content } = packageOf(number, version);
  const query = new URLSearchParams({ version: version.lms, package: dir });
  const hash =
    saved === undefined ? "" : `#${encodeURIComponent(JSON.stringify(saved))}`;
  // Without the blank page, a URL that differs only in its hash would not
  // load a new document.
  await page.goto("about:blank");
  await page.goto(`${lmsOrigin}/lms.html?${query}${hash}`);
  const sco = page.frameLocator("iframe[title='SCORM package']");
  await expect(
    sco.getByRole("heading", { level: 1, name: content.module.title }),
  ).toBeVisible();
  return { page, sco, content, version };
}

const lmsCalls = (session: Session) =>
  session.page.evaluate<LmsCall[]>("lms.calls");

/** The values that the package set so far, in order; the LMS rejected none. */
async function setValues(session: Session): Promise<Values> {
  const sets = (await lmsCalls(session)).filter(
    (call) => call.element !== undefined,
  );
  expect(
    sets.filter((call) => call.result !== "true"),
    "values the LMS rejected",
  ).toEqual([]);
  return sets.map((call) => [call.element ?? "", call.value ?? ""]);
}

const last = (values: Values, element: string) =>
  values.findLast(([name]) => name === element)?.[1];

/** The writes of `cmi.objectives.n.id` in order. */
const objectiveIds = (values: Values) =>
  values.filter(([element]) => /^cmi\.objectives\.\d+\.id$/.test(element));

/** Per index of `cmi.objectives`, the last value of each of its elements. */
function objectiveEntries(values: Values): Record<string, string>[] {
  const entries: Record<string, string>[] = [];
  for (const [element, value] of values) {
    const match = /^cmi\.objectives\.(\d+)\.(\w+)$/.exec(element);
    if (match === null) continue;
    (entries[Number(match[1])] ??= {})[match[2]] = value;
  }
  return entries;
}

/** The entries of `keys` in index order, by default `incomplete`. */
const expectedEntries = (
  version: Version,
  keys: string[],
  states: Record<string, ObjectiveState> = {},
) =>
  keys.map((key) => ({
    id: key,
    ...OBJECTIVE_VALUES[version.lms][states[key] ?? "incomplete"],
  }));

/**
 * The start of a session: the id of every objective in position order, each
 * written before the other elements of its index (SCORM 2004 accepts a
 * status only after the id), and every objective `incomplete`.
 */
function expectObjectivesAtStart(
  values: Values,
  version: Version,
  keys: string[],
) {
  expect(objectiveIds(values)).toEqual(
    keys.map((key, index) => [`cmi.objectives.${index}.id`, key]),
  );
  expect(
    keys.map(
      (_key, index) =>
        values.find(([element]) =>
          element.startsWith(`cmi.objectives.${index}.`),
        )?.[0],
    ),
  ).toEqual(keys.map((_key, index) => `cmi.objectives.${index}.id`));
  expect(objectiveEntries(values)).toEqual(expectedEntries(version, keys));
}

/**
 * Leaves the package as an LMS does: the session ends with a commit and
 * `LMSFinish` or `Terminate`. Returns the CMI data for the next session.
 */
async function endSession(session: Session): Promise<unknown> {
  const { page, version } = session;
  await page.evaluate("lms.unload()");
  await expect
    .poll(async () => (await lmsCalls(session)).map((call) => call.name))
    .toEqual(expect.arrayContaining([version.initialize, version.terminate]));
  const names = (await lmsCalls(session)).map((call) => call.name);
  expect(names[0]).toBe(version.initialize);
  expect(names.slice(-2)).toEqual([version.commit, version.terminate]);
  await setValues(session);
  return page.evaluate<unknown>("lms.state()");
}

const itemOf = (content: Content, key: string): ContentItem => {
  const found = content.module.items.find((item) => item.key === key);
  if (found === undefined) throw new Error(`The item ${key} is missing.`);
  return found;
};

const examOf = (content: Content) => {
  const exam = content.module.assessments.find(
    (assessment) => assessment.kind === "exam",
  );
  if (exam === undefined) throw new Error("The module has no exam.");
  return { exam, items: exam.items.map((key) => itemOf(content, key)) };
};

/** The lessons of the module in position order. */
const lessonsOf = (content: Content) =>
  [...content.module.lessons].sort((a, b) => a.position - b.position);

/** The frame of an item, located by its stem. */
const itemFrame = (scope: FrameLocator | Locator, item: ContentItem) =>
  scope.getByRole("group", { name: item.stem, exact: true });

/** The explanation button of a lesson, which has one explanation. */
const explanationOf = (sco: FrameLocator, lesson: { title: string }) =>
  sco
    .getByRole("region", { name: lesson.title, exact: true })
    .getByRole("button", { name: "Explanation", exact: true });

/** Chooses the correct options of a choice item, or adds one wrong option. */
async function answerChoice(
  frame: Locator,
  item: ContentItem,
  correct: boolean,
) {
  const options = (value: boolean) =>
    item.options.filter((option) => option.correct === value);
  if (item.kind === "multiple_choice") {
    for (const option of options(true))
      await frame
        .getByRole("checkbox", { name: option.label, exact: true })
        .check();
    if (!correct)
      await frame
        .getByRole("checkbox", { name: options(false)[0].label, exact: true })
        .check();
    return;
  }
  await frame
    .getByRole("radio", { name: options(correct)[0].label, exact: true })
    .click();
}

/**
 * Takes the exam of module 1 with a correct answer to every item except
 * those in `wrong`, and returns the region of the exam.
 */
async function takeExam(
  sco: FrameLocator,
  content: Content,
  wrong: ContentItem[],
): Promise<Locator> {
  const { exam, items } = examOf(content);
  const region = sco.getByRole("region", { name: exam.title, exact: true });
  for (const item of items)
    await answerChoice(itemFrame(region, item), item, !wrong.includes(item));
  await region.getByRole("button", { name: "Submit the exam" }).click();
  return region;
}

/** Answers a slot builder, a classification or a checklist drill correctly. */
async function answerPracticeItem(sco: FrameLocator, item: ContentItem) {
  const frame = itemFrame(sco, item);
  switch (item.kind) {
    case "slot_builder": {
      for (const slot of (item.config as SlotBuilderConfig).slots) {
        const option = slot.options.find((entry) => entry.correct === true);
        await frame
          .getByLabel(slot.label, { exact: true })
          .selectOption({ label: option?.label ?? "" });
      }
      await frame.getByRole("button", { name: "Check answer" }).click();
      break;
    }
    case "classification": {
      const { categories, cases, expected } =
        item.config as ClassificationConfig;
      for (const entry of cases) {
        const category = categories.find(
          (candidate) => candidate.key === expected[entry.key],
        );
        await frame
          .getByLabel(entry.text, { exact: true })
          .selectOption({ label: category?.label ?? "" });
      }
      await frame.getByRole("button", { name: "Check answer" }).click();
      break;
    }
    case "checklist_drill": {
      for (const check of (item.config as ChecklistDrillConfig).checks)
        if (check.required)
          await frame.getByRole("checkbox", { name: check.label }).check();
      await frame.getByLabel("Your initials").fill("AB");
      await frame.getByRole("button", { name: "Release" }).click();
      break;
    }
    default:
      throw new Error(`No correct answer for the kind ${item.kind}.`);
  }
  await expect(frame.getByRole("status")).toContainText("Correct.");
}

test.beforeAll(async ({ browser }) => {
  author = await createStaffUser(browser, "author");
  // The harness, the bundle and the extracted packages share one fresh
  // directory, served over HTTP from one origin, so that the package can
  // fetch its content.json and reach the API in the window of lms.html.
  root = await mkdtemp(join(tmpdir(), "espalier-scorm-"));
  await copyFile(LMS_PAGE, join(root, "lms.html"));
  await copyFile(SCORM_AGAIN, join(root, "scorm-again.js"));
  server = await serve(root);
  lmsOrigin = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});

test.afterAll(async () => {
  await author?.context.close();
  const running = server;
  if (running !== undefined) {
    running.closeAllConnections();
    await new Promise((closed) => running.close(closed));
  }
  if (root !== "") await rm(root, { recursive: true, force: true });
});

test("an author exports modules 1 and 2 in both versions and downloads the packages", async () => {
  test.setTimeout(120_000);
  const { page } = author;
  await page.goto("/admin/exports");
  await expect(
    page.getByRole("heading", { level: 1, name: "SCORM export" }),
  ).toBeVisible();
  await page
    .getByLabel("Program", { exact: true })
    .selectOption({ label: PACK.title });

  // Four requests: module 1 and module 2, each in both versions.
  const list = page.getByRole("status", { name: "Requested exports" });
  const requested: { number: number; version: Version }[] = [];
  for (const number of [1, 2]) {
    await page
      .getByLabel("Module", { exact: true })
      .selectOption({ label: `${number}. ${moduleTitle(number)}` });
    for (const version of VERSIONS) {
      await page
        .getByRole("radio", { name: version.label, exact: true })
        .check();
      await page.getByRole("button", { name: "Request the export" }).click();
      requested.push({ number, version });
      await expect(list.getByRole("listitem")).toHaveCount(requested.length);
    }
  }

  // The list shows the newest export first. Each one reaches "Ready for
  // download", and its link downloads the zip under the name of step 10.
  const entries = list.getByRole("listitem");
  for (const [index, { number, version }] of [...requested]
    .reverse()
    .entries()) {
    const entry = entries.nth(index);
    await expect(entry).toContainText(
      `Module ${number}: ${moduleTitle(number)}`,
    );
    await expect(entry).toContainText(version.label);
    await expect(entry).toContainText("Ready for download", {
      timeout: 60_000,
    });
    const downloaded = page.waitForEvent("download");
    await entry.getByRole("link", { name: /^Download the package/ }).click();
    const download = await downloaded;
    expect(download.suggestedFilename()).toBe(
      `${PACK.key}-module-${number}-${version.key}.zip`,
    );

    const dir = `module-${number}-${version.key}`;
    const names = await extract(
      await readFile(await download.path()),
      join(root, dir),
    );
    expect(names).toEqual(
      expect.arrayContaining([
        "imsmanifest.xml",
        "index.html",
        "LICENSE",
        "NOTICE",
        "content.json",
        "assets/player.js",
        "assets/player.css",
      ]),
    );
    const content = JSON.parse(
      await readFile(join(root, dir, "content.json"), "utf8"),
    ) as Content;
    expect(content.module.number).toBe(number);
    // The media of the lessons (task 0018, step 17): every `media/` path
    // of the module maps to a delivery file of the package, named after
    // its digest, and the package holds that file and the poster of a
    // video.
    expect(Object.keys(content.media).sort()).toEqual(mediaPaths(number));
    for (const [path, entry] of Object.entries(content.media)) {
      const ext = { image: "webp", svg: "svg", video: "webm", captions: "vtt" }[
        entry.kind
      ];
      expect(entry.url, path).toMatch(
        new RegExp(`^media/[0-9a-f]{64}\\.${ext}$`),
      );
      expect(names, path).toContain(entry.url);
      if (entry.kind === "video") {
        expect(entry.poster_url, path).toMatch(/^media\/[0-9a-f]{64}\.webp$/);
        expect(names, `${path} poster`).toContain(entry.poster_url);
      }
    }
    expect(
      Object.values(content.media)
        .map((entry) => entry.kind)
        .sort(),
    ).toEqual(number === 1 ? ["captions", "video"] : ["svg"]);
    // The objectives of the module in position order.
    expect(content.module.objectives.map((objective) => objective.key)).toEqual(
      objectiveKeys(number),
    );
    packages.set(`${number}-${version.key}`, { dir, content });
  }
});

test("the packages play the demo video with captions and show the SVG figure", async ({
  page,
}) => {
  test.setTimeout(60_000);
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  const version = VERSIONS[1];

  // Module 1: the video of lesson 1 with its English captions, served by
  // the stand-in LMS from the files of the package.
  const first = await launch(page, 1, version);
  const video = first.sco.locator("video");
  await expect(video.locator("source")).toHaveAttribute(
    "src",
    /^media\/[0-9a-f]{64}\.webm$/,
  );
  await expect(video.locator("track")).toHaveAttribute(
    "src",
    /^media\/[0-9a-f]{64}\.vtt$/,
  );
  await expectVideoPlaysWithCaptions(video);
  await endSession(first);

  // Module 2: the SVG figure of lesson 2 through an <img>.
  const second = await launch(page, 2, version);
  const image = second.sco.locator("figure img");
  await expect(image).toHaveCount(1);
  await expect(image).toHaveAttribute("src", /^media\/[0-9a-f]{64}\.svg$/);
  await expectImageLoaded(image);
  await endSession(second);
  expect(errors).toEqual([]);
});

for (const version of VERSIONS) {
  test(`${version.label}: module 1 reports the passed exam, its score and the objective states`, async ({
    page,
  }) => {
    test.setTimeout(60_000);
    const session = await launch(page, 1, version);
    const { sco, content } = session;
    const keys = objectiveKeys(1);

    // Start: the five objective keys in position order, all incomplete.
    let values = await setValues(session);
    expectObjectivesAtStart(values, version, keys);
    if (version.lms === "1.2") {
      expect(last(values, "cmi.core.lesson_status")).toBe("incomplete");
      expect(last(values, "cmi.core.exit")).toBe("suspend");
    } else {
      expect(last(values, "cmi.completion_status")).toBe("incomplete");
      expect(last(values, "cmi.exit")).toBe("suspend");
    }

    // The short path and one opened explanation, which the next session
    // restores. On the short path the explanations start collapsed.
    const shortPath = sco.getByRole("radio", { name: "Short path" });
    await shortPath.click();
    await expect(shortPath).toBeChecked();
    const explanation = explanationOf(sco, lessonsOf(content)[1]);
    await expect(explanation).toHaveAttribute("aria-expanded", "false");
    await explanation.click();
    await expect(explanation).toHaveAttribute("aria-expanded", "true");

    // The exam admits one wrong answer (`max_wrong`), so a wrong answer to
    // its multiple-choice item passes with one correct answer less. The
    // objective of that item counts as passed through the passed attempt.
    const { exam, items } = examOf(content);
    expect(exam.max_wrong).toBeGreaterThanOrEqual(1);
    const wrong = items.filter(
      (item) => !item.core && item.kind === "multiple_choice",
    );
    expect(wrong).toHaveLength(1);
    const region = await takeExam(sco, content, wrong);
    await expect(region.locator("[data-outcome]")).toHaveAttribute(
      "data-outcome",
      "passed",
    );

    await sco.getByRole("button", { name: "Complete module" }).click();
    await expect(
      sco.getByRole("region", { name: "Module complete" }),
    ).toBeVisible();

    // Status and score: raw holds the correct answers, max the exam items.
    values = await setValues(session);
    const raw = items.length - wrong.length;
    if (version.lms === "1.2") {
      expect(last(values, "cmi.core.lesson_status")).toBe("passed");
      expect(last(values, "cmi.core.score.raw")).toBe(String(raw));
      expect(last(values, "cmi.core.score.min")).toBe("0");
      expect(last(values, "cmi.core.score.max")).toBe(String(items.length));
      expect(last(values, "cmi.core.exit")).toBe("");
    } else {
      expect(last(values, "cmi.completion_status")).toBe("completed");
      expect(last(values, "cmi.success_status")).toBe("passed");
      expect(last(values, "cmi.score.raw")).toBe(String(raw));
      expect(last(values, "cmi.score.max")).toBe(String(items.length));
      const scaled = Number(last(values, "cmi.score.scaled"));
      expect(scaled).toBeGreaterThan(0);
      expect(scaled).toBeLessThan(1);
      expect(scaled).toBeCloseTo(raw / items.length, 7);
      expect(last(values, "cmi.exit")).toBe("normal");
    }

    // Objectives: the three that the exam items name are passed, the two
    // whose only evidence is the workshop stay incomplete.
    expect(objectiveIds(values)).toHaveLength(keys.length);
    const entries = objectiveEntries(values);
    expect(entries).toEqual(
      expectedEntries(
        version,
        keys,
        Object.fromEntries(EXAM_OBJECTIVES.map((key) => [key, "passed"])),
      ),
    );
    expect(
      WORKSHOP_OBJECTIVES.map((key) => entries[keys.indexOf(key)]),
    ).toEqual(
      WORKSHOP_OBJECTIVES.map((key) => ({
        id: key,
        ...OBJECTIVE_VALUES[version.lms].incomplete,
      })),
    );

    firstSessions.set(version.key, {
      saved: await endSession(session),
      entries,
    });
  });

  test(`${version.label}: a second session restores the path, the opened explanation and the objective entries`, async ({
    page,
  }) => {
    const first = firstSessions.get(version.key);
    if (first === undefined) throw new Error("The first session is missing.");
    const session = await launch(page, 1, version, first.saved);
    const { sco, content } = session;

    await expect(sco.getByRole("radio", { name: "Short path" })).toBeChecked();
    const lessons = lessonsOf(content);
    for (const [index, lesson] of lessons.entries())
      await expect(explanationOf(sco, lesson)).toHaveAttribute(
        "aria-expanded",
        index === 1 ? "true" : "false",
      );
    await expect(
      sco.getByRole("region", { name: "Module complete" }),
    ).toBeVisible();

    // Each objective key at the index of the first session, with its state.
    const values = await setValues(session);
    const keys = objectiveKeys(1);
    expect(objectiveIds(values)).toEqual(
      keys.map((key, index) => [`cmi.objectives.${index}.id`, key]),
    );
    expect(objectiveEntries(values)).toEqual(first.entries);
  });

  test(`${version.label}: a failing exam attempt reports failed`, async ({
    page,
  }) => {
    // A fresh session, so that the pass of the first session does not keep
    // the status.
    const session = await launch(page, 1, version);
    const { sco, content } = session;
    const { items } = examOf(content);
    const region = await takeExam(
      sco,
      content,
      items.filter((item) => item.core),
    );
    await expect(region.locator("[data-outcome]")).toHaveAttribute(
      "data-outcome",
      "failed_core",
    );

    const values = await setValues(session);
    if (version.lms === "1.2") {
      expect(last(values, "cmi.core.lesson_status")).toBe("failed");
      expect(last(values, "cmi.core.exit")).toBe("suspend");
    } else {
      expect(last(values, "cmi.success_status")).toBe("failed");
      expect(last(values, "cmi.completion_status")).toBe("incomplete");
      expect(last(values, "cmi.exit")).toBe("suspend");
    }
  });

  test(`${version.label}: module 2 without exam reports completed and passes each objective with its item`, async ({
    page,
  }) => {
    const session = await launch(page, 2, version);
    const { sco, content } = session;
    const keys = objectiveKeys(2);

    let values = await setValues(session);
    expectObjectivesAtStart(values, version, keys);

    // The slot builder, the classification and the checklist drill, each
    // answered correctly, pass the objective that they name.
    const states: Record<string, ObjectiveState> = {};
    expect(content.module.items.map((item) => item.kind).sort()).toEqual([
      "checklist_drill",
      "classification",
      "slot_builder",
    ]);
    for (const item of content.module.items) {
      await answerPracticeItem(sco, item);
      for (const key of item.objectives) states[key] = "passed";
      values = await setValues(session);
      expect(objectiveEntries(values), item.key).toEqual(
        expectedEntries(version, keys, states),
      );
    }
    expect(Object.keys(states).sort()).toEqual([...keys].sort());

    await sco.getByRole("button", { name: "Complete module" }).click();
    await expect(
      sco.getByRole("region", { name: "Module complete" }),
    ).toBeVisible();

    values = await setValues(session);
    if (version.lms === "1.2") {
      expect(last(values, "cmi.core.lesson_status")).toBe("completed");
      expect(last(values, "cmi.core.exit")).toBe("");
    } else {
      expect(last(values, "cmi.completion_status")).toBe("completed");
      expect(last(values, "cmi.exit")).toBe("normal");
      // The package leaves the success status of the LMS, `unknown`.
      expect(
        values.filter(
          ([element, value]) =>
            element === "cmi.success_status" && value !== "unknown",
        ),
      ).toEqual([]);
      const state = await page.evaluate<{ success_status: string }>(
        "lms.state()",
      );
      expect(state.success_status).toBe("unknown");
    }
    expect(values.filter(([element]) => element.includes(".score."))).toEqual(
      [],
    );
  });
}
