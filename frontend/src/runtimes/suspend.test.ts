import { describe, expect, test } from "vitest";
import { parse } from "yaml";
import type { ExamOutcome } from "../player/runtime";
import type { AssessmentProgress } from "./objectives";
import { scormContent } from "./scormFixture";
import type {
  PayloadAssessment,
  PayloadBlock,
  PayloadItem,
  PayloadLesson,
  PayloadModule,
} from "./standalone";
import {
  SUSPEND_DATA_LIMIT,
  decodeSuspendData,
  encodeSuspendData,
  explanationBlockIds,
  type SuspendState,
} from "./suspend";

/**
 * Task 0016 step 5: the suspend-data encoding is inverse to its decoding
 * for generated states, stays below 1,000 characters for the largest module
 * of the demo pack in `content/demo` with every explanation opened, every
 * item answered correctly and every exam passed, and throws above the
 * 4,096 characters of `cmi.suspend_data` in SCORM 1.2. The layout
 * fingerprint makes the decoding of a string of another layout of the
 * module return `null`.
 */

/** A deterministic generator of numbers in [0, 1) (mulberry32). */
function random(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const KINDS: PayloadBlock["kind"][] = ["text", "explanation", "example"];
const OUTCOMES: ExamOutcome[] = ["passed", "failed_core", "failed_errors"];

function block(kind: PayloadBlock["kind"]): PayloadBlock {
  return {
    kind,
    body: "",
    provenance: "invented",
    collapsed_on: [],
    placeholder_key: null,
    cite: [],
    media: null,
  };
}

function payloadItem(key: string, kind: PayloadItem["kind"]): PayloadItem {
  return {
    key,
    kind,
    lesson: null,
    stem: "",
    provenance: "invented",
    objectives: [],
    cite: [],
    options: [],
  };
}

function assessment(key: string, items: string[]): PayloadAssessment {
  return {
    key,
    title: key,
    kind: "exam",
    counts_for_credential: true,
    max_wrong: 0,
    core_required: false,
    items,
  };
}

function payloadModule(
  number: number,
  lessons: PayloadLesson[],
  items: PayloadItem[],
  assessments: PayloadAssessment[],
): PayloadModule {
  return {
    number,
    title: `Module ${number}`,
    summary: "",
    phases: [],
    single_path: false,
    lessons,
    objectives: [],
    rules: [],
    items,
    assessments,
  };
}

/** A module with random lessons, blocks, items and assessments. */
function generatedModule(next: () => number): PayloadModule {
  const pick = (count: number) => Math.floor(next() * count);
  const lessons = Array.from({ length: pick(5) }, (_, index) => ({
    key: `lesson-${index}`,
    title: `Lesson ${index}`,
    // Repeated positions order by key.
    position: pick(4),
    blocks: Array.from({ length: pick(7) }, () => block(KINDS[pick(3)])),
  }));
  const items = Array.from({ length: pick(40) }, (_, index) =>
    payloadItem(`item-${index}`, next() < 0.2 ? "poll" : "single_choice"),
  );
  const assessments = Array.from({ length: pick(4) }, (_, index) =>
    assessment(
      `exam-${index}`,
      items.filter(() => next() < 0.3).map((item) => item.key),
    ),
  );
  return payloadModule(1 + pick(9), lessons, items, assessments);
}

/** A state of `module` in the canonical form that decoding returns. */
function generatedState(
  module: PayloadModule,
  next: () => number,
): SuspendState {
  const some = <T>(list: T[]) => list.filter(() => next() < 0.5);
  const answeredItems = some(module.items.map((item) => item.key));
  return {
    path: next() < 0.5 ? "full" : "short",
    completed: next() < 0.5,
    openedExplanations: some(explanationBlockIds(module)),
    answeredItems,
    correctItems: some(answeredItems),
    assessments: Object.fromEntries(
      module.assessments.map((entry): [string, AssessmentProgress] => {
        if (next() < 0.3) return [entry.key, { attempts: 0, outcome: null }];
        const attempts = 1 + Math.floor(next() ** 4 * 5000);
        return [
          entry.key,
          { attempts, outcome: OUTCOMES[Math.floor(next() * 3)] },
        ];
      }),
    ),
  };
}

/**
 * The files of the demo modules by path below `content/demo/modules/`.
 * Vite reads them at build time, as in `src/test/boundaries.test.ts`, so
 * the test needs no file system access; `vite.config.ts` allows the
 * directory.
 */
const DEMO_FILES: Record<string, string> = Object.fromEntries(
  Object.entries(
    import.meta.glob<string>(
      [
        "../../../content/demo/modules/*/*.yaml",
        "../../../content/demo/modules/*/lessons/*.md",
      ],
      { query: "?raw", import: "default", eager: true },
    ),
  ).map(([key, text]) => [
    key.replace(/^.*\/content\/demo\/modules\//, ""),
    text,
  ]),
);

/** The module directories of the demo pack. */
const DEMO_MODULES = [
  ...new Set(Object.keys(DEMO_FILES).map((path) => path.split("/")[0])),
].sort();

/**
 * A module of the demo pack, read from its files: the items of
 * `items.yaml`, the assessments of `assessment.yaml` and one block per
 * container directive of each lesson file, with the lesson key from the
 * file name and the position from the front matter.
 */
function demoModule(directory: string): PayloadModule {
  const yaml = (name: string): unknown => {
    const text = DEMO_FILES[`${directory}/${name}`];
    return text === undefined ? null : parse(text);
  };
  const list = (name: string) => {
    const value = yaml(name);
    return Array.isArray(value) ? (value as Record<string, unknown>[]) : [];
  };

  const lessonPrefix = `${directory}/lessons/`;
  const lessons = Object.keys(DEMO_FILES)
    .filter((path) => path.startsWith(lessonPrefix) && path.endsWith(".md"))
    .sort()
    .map((path): PayloadLesson => {
      const file = path.slice(lessonPrefix.length);
      const text = DEMO_FILES[path];
      const front = parse(/^---\n([\s\S]*?)\n---/.exec(text)?.[1] ?? "") as {
        title: string;
        position: number;
      };
      return {
        key: file.replace(/\.md$/, ""),
        title: front.title,
        position: front.position,
        blocks: [...text.matchAll(/^:::([a-z_]+)(\{.*\})?\s*$/gm)].map(
          (match) => block(match[1] as PayloadBlock["kind"]),
        ),
      };
    });
  const items = list("items.yaml").map((entry) =>
    payloadItem(String(entry.key), entry.kind as PayloadItem["kind"]),
  );
  const assessments = list("assessment.yaml").map((entry) =>
    assessment(String(entry.key), (entry.items as string[]) ?? []),
  );
  const { number } = yaml("module.yaml") as { number: number };
  return payloadModule(number, lessons, items, assessments);
}

/** A state of `scormContent()` with one opened explanation and two answers. */
const STATE: SuspendState = {
  path: "short",
  completed: false,
  openedExplanations: ["block-1-intro-2"],
  answeredItems: ["choice-practice", "slots-practice"],
  correctItems: ["choice-practice"],
  assessments: { "exam-1": { attempts: 2, outcome: "failed_errors" } },
};

/** The state of a first launch. */
const EMPTY: SuspendState = {
  path: "full",
  completed: false,
  openedExplanations: [],
  answeredItems: [],
  correctItems: [],
  assessments: {},
};

/** The state with every explanation opened, every item correct and every exam passed. */
function fullState(module: PayloadModule): SuspendState {
  const items = module.items.map((item) => item.key);
  return {
    path: "full",
    completed: true,
    openedExplanations: explanationBlockIds(module),
    answeredItems: items,
    correctItems: items,
    assessments: Object.fromEntries(
      module.assessments.map((entry) => [
        entry.key,
        { attempts: 1, outcome: "passed" as const },
      ]),
    ),
  };
}

describe("the suspend data", () => {
  test("encode and decode are inverse for generated states", () => {
    const next = random(16);
    for (let run = 0; run < 500; run += 1) {
      const module = generatedModule(next);
      const state = generatedState(module, next);
      const data = encodeSuspendData(module, state);

      expect(data).toMatch(/^[A-Za-z0-9._-]+$/);
      expect(decodeSuspendData(module, data)).toEqual(state);
    }
  });

  test("the largest module of the demo pack encodes below 1,000 characters", () => {
    const modules = DEMO_MODULES.map(demoModule);
    const size = (module: PayloadModule) =>
      module.items.length +
      explanationBlockIds(module).length +
      module.assessments.length;
    const largest = modules.reduce((a, b) => (size(b) > size(a) ? b : a));
    expect(modules.length).toBeGreaterThan(1);
    expect(largest.items.length).toBeGreaterThan(0);
    expect(explanationBlockIds(largest).length).toBeGreaterThan(0);

    const state = fullState(largest);
    const data = encodeSuspendData(largest, state);

    expect(data.length).toBeLessThan(1000);
    expect(decodeSuspendData(largest, data)).toEqual(state);
  });

  test("encode throws for a result above 4,096 characters", () => {
    // Six items per character: 25,000 answered items need 4,167 characters.
    const items = Array.from({ length: 25000 }, (_, index) =>
      payloadItem(`item-${index}`, "single_choice"),
    );
    const module = payloadModule(1, [], items, []);
    const state = { ...fullState(module), correctItems: [] };

    expect(() => encodeSuspendData(module, state)).toThrow(RangeError);
    expect(
      encodeSuspendData(module, { ...state, answeredItems: [] }).length,
    ).toBeLessThanOrEqual(SUSPEND_DATA_LIMIT);
  });

  test("decode returns null for a string that is empty, malformed, of another version or does not fit the module", () => {
    const { module } = scormContent();
    // AUWWl7 is 0x1459697b, the 32-bit FNV-1a hash of
    // "choice-practice,slots-practice,drill-practice,classify-other,poll-usage,exam-a,exam-b;block-1-intro-2,block-1-practice-1,block-1-practice-3;exam-1".
    expect(encodeSuspendData(module, STATE)).toBe("2.AUWWl7.s.0.B.D.B.2e");
    expect(decodeSuspendData(module, "2.AUWWl7.s.0.B.D.B.2e")).toEqual(STATE);

    for (const data of [
      undefined,
      42,
      "",
      "garbage",
      "1.s.0.B.D.B.2e",
      "1.AUWWl7.s.0.B.D.B.2e",
      "3.AUWWl7.s.0.B.D.B.2e",
      "2.AUWWl8.s.0.B.D.B.2e",
      "2..s.0.B.D.B.2e",
      "2.AUWWl7.x.0.B.D.B.2e",
      "2.AUWWl7.s.2.B.D.B.2e",
      "2.AUWWl7.s.0.!.D.B.2e",
      "2.AUWWl7.s.0.BA.D.B.2e",
      "2.AUWWl7.s.0.I.D.B.2e",
      "2.AUWWl7.s.0.B.D.E.2e",
      "2.AUWWl7.s.0.B.D.B.2",
      "2.AUWWl7.s.0.B.D.B.0p",
      "2.AUWWl7.s.0.B.D.B.02e",
      "2.AUWWl7.s.0.B.D.B.2e.0",
      "2.AUWWl7.s.0.B.D.B",
    ])
      expect(decodeSuspendData(module, data)).toBeNull();
  });

  test("decode returns null for a string of another layout of the module, which it would otherwise decode onto shifted entries", () => {
    const { module } = scormContent();
    const data = encodeSuspendData(module, STATE);
    const changed: Record<string, PayloadModule> = {
      "an item inserted before the first item": {
        ...module,
        items: [{ ...module.items[0], key: "new-item" }, ...module.items],
      },
      "a renamed assessment key": {
        ...module,
        assessments: module.assessments.map((entry) => ({
          ...entry,
          key: "exam-renamed",
        })),
      },
      "a block inserted before an explanation": {
        ...module,
        lessons: module.lessons.map((lesson) =>
          lesson.key === "intro"
            ? { ...lesson, blocks: [block("text"), ...lesson.blocks] }
            : lesson,
        ),
      },
    };

    for (const [change, layout] of Object.entries(changed)) {
      expect(decodeSuspendData(layout, data), change).toBeNull();
      // The other fields fit the changed module, so only the fingerprint
      // keeps the progress from landing on other entries.
      const fields = data.split(".");
      fields[1] = encodeSuspendData(layout, EMPTY).split(".")[1];
      expect(
        decodeSuspendData(layout, fields.join(".")),
        change,
      ).not.toBeNull();
    }

    // A change outside the layout keeps the progress.
    const retitled = {
      ...module,
      title: "Another title",
      items: module.items.map((item) => ({ ...item, stem: "Another stem." })),
    };
    expect(decodeSuspendData(retitled, data)).toEqual(STATE);
  });
});
