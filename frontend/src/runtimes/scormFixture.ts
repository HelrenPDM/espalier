import type { Answer } from "../player/runtime";
import type { ScormContent } from "./content";
import {
  payloadIds,
  type PayloadBlock,
  type PayloadItem,
  type PayloadObjective,
} from "./standalone";

/**
 * A small `content.json` for the tests of the SCORM runtimes (task 0016,
 * step 5): one module with five objectives, practice items of several
 * kinds, a poll, an exam with two items, a format with
 * `attendance_counts: true`, a placeholder block with a published policy
 * and one without, and an item that also names an objective of another
 * module.
 *
 * | Objective | Evidence |
 * |---|---|
 * | `m1-subject-exam` | the exam item `exam-a` |
 * | `m1-method-mixed` | the practice item `choice-practice` and the exam item `exam-b` |
 * | `m1-method-practice` | the practice items `slots-practice`, `drill-practice` and `classify-other` |
 * | `m1-social-poll` | none (named by the poll `poll-usage` only) |
 * | `m1-self-format` | none (named by the format `workshop` only) |
 *
 * `classify-other` also names `m2-other-topic`, an objective of module 2.
 * The exam `exam-1` counts for the credential and allows one wrong answer.
 * With `{ exam: false }` the module has neither the exam nor its items, and
 * with `{ countsForCredential: false }` the exam does not count for the
 * credential.
 */
export function scormContent({
  exam = true,
  countsForCredential = true,
} = {}): ScormContent {
  const items = [
    item("choice-practice", "single_choice", "intro", ["m1-method-mixed"], {
      rules: [1],
      reveals: ["intro"],
      options: [option("yes", true), option("no", false)],
    }),
    item("slots-practice", "slot_builder", "practice", ["m1-method-practice"], {
      config: {
        slots: [
          {
            key: "tone",
            label: "Tone",
            options: [option("plain", true), option("loud", false)],
          },
        ],
      },
    }),
    item(
      "drill-practice",
      "checklist_drill",
      "practice",
      ["m1-method-practice"],
      {
        config: {
          checks: [{ key: "facts", label: "Facts checked", required: true }],
        },
      },
    ),
    item(
      "classify-other",
      "classification",
      "practice",
      ["m1-method-practice", "m2-other-topic"],
      {
        config: {
          cases: [{ key: "memo", text: "An internal memo.", feedback: null }],
          categories: [
            { key: "internal", label: "Internal" },
            { key: "public", label: "Public" },
          ],
          expected: { memo: "internal" },
        },
      },
    ),
    item("poll-usage", "poll", "intro", ["m1-social-poll"], {
      options: [option("often", false), option("never", false)],
    }),
    item("exam-a", "single_choice", null, ["m1-subject-exam"], {
      options: [option("yes", true), option("no", false)],
    }),
    item("exam-b", "multiple_choice", null, ["m1-method-mixed"], {
      options: [option("a", true), option("b", true), option("c", false)],
    }),
  ];

  return {
    schema: 1,
    program: { slug: "scorm-pack", title: "SCORM pack", locale: "en" },
    module: {
      number: 1,
      title: "Basics",
      summary: "The basics.",
      phases: ["understand"],
      single_path: false,
      areas_elsewhere: {},
      // `practice` comes first in the payload and second by position.
      lessons: [
        {
          key: "practice",
          title: "Practice",
          position: 2,
          blocks: [
            block("explanation"),
            block("example"),
            block("explanation"),
          ],
        },
        {
          key: "intro",
          title: "Introduction",
          position: 1,
          blocks: [
            block("text"),
            block("explanation"),
            block("placeholder", "input-rules"),
            block("placeholder", "tool-list"),
          ],
        },
      ],
      objectives: [
        objective("m1-subject-exam", "subject", ["intro"]),
        objective("m1-method-mixed", "method", ["intro", "practice"]),
        objective("m1-method-practice", "method", ["practice"]),
        objective("m1-social-poll", "social", ["intro"]),
        objective("m1-self-format", "self", ["practice"]),
      ],
      rules: [
        { number: 1, statement: "Check first.", action: "Check.", cite: [] },
      ],
      items: exam ? items : items.filter((entry) => entry.lesson !== null),
      assessments: exam
        ? [
            {
              key: "exam-1",
              title: "Exam of module 1",
              kind: "exam",
              counts_for_credential: countsForCredential,
              max_wrong: 1,
              core_required: false,
              items: ["exam-a", "exam-b"],
            },
          ]
        : [],
    },
    glossary: [],
    sources: [],
    formats: [
      {
        key: "workshop",
        title: "Workshop",
        description: "A workshop.",
        phases: ["anchor"],
        attendance_counts: true,
        objectives: ["m1-self-format"],
      },
    ],
    policies: {
      "input-rules": {
        key: "input-rules",
        number: 2,
        effective_from: "2026-03-01",
        body: "Inputs follow the rules of the house.",
      },
    },
  };
}

/** The objective keys of `scormContent()` in position order. */
export const OBJECTIVE_KEYS = [
  "m1-subject-exam",
  "m1-method-mixed",
  "m1-method-practice",
  "m1-social-poll",
  "m1-self-format",
];

/** The ids of the views of `scormContent()`. */
export const IDS = {
  program: "scorm-pack",
  module: payloadIds.module(1),
  choice: payloadIds.item("choice-practice"),
  slots: payloadIds.item("slots-practice"),
  drill: payloadIds.item("drill-practice"),
  classify: payloadIds.item("classify-other"),
  poll: payloadIds.item("poll-usage"),
  examA: payloadIds.item("exam-a"),
  examB: payloadIds.item("exam-b"),
  exam: payloadIds.assessment("exam-1"),
};

/** A correct and a wrong answer per item id; the poll has no correct one. */
export const ANSWERS: Record<string, { right: Answer; wrong: Answer }> = {
  [IDS.choice]: { right: { options: ["yes"] }, wrong: { options: ["no"] } },
  [IDS.slots]: {
    right: { slots: { tone: "plain" } },
    wrong: { slots: { tone: "loud" } },
  },
  [IDS.drill]: {
    right: { checks: ["facts"], initials: "AB" },
    wrong: { checks: [], initials: "AB" },
  },
  [IDS.classify]: {
    right: { cases: { memo: "internal" } },
    wrong: { cases: { memo: "public" } },
  },
  [IDS.poll]: { right: { options: ["often"] }, wrong: { options: ["never"] } },
  [IDS.examA]: { right: { options: ["yes"] }, wrong: { options: ["no"] } },
  [IDS.examB]: {
    right: { options: ["a", "b"] },
    wrong: { options: ["c"] },
  },
};

/** The answers of an exam attempt with the items of `wrong` answered wrongly. */
export function examAnswers(...wrong: string[]): Record<string, Answer> {
  return Object.fromEntries(
    [IDS.examA, IDS.examB].map((id) => [
      id,
      wrong.includes(id) ? ANSWERS[id].wrong : ANSWERS[id].right,
    ]),
  );
}

function option(key: string, correct: boolean) {
  return { key, label: key, correct, feedback: null };
}

function block(
  kind: PayloadBlock["kind"],
  placeholderKey: string | null = null,
): PayloadBlock {
  return {
    kind,
    body: `A ${kind} block.`,
    provenance: kind === "placeholder" ? "placeholder" : "invented",
    collapsed_on: kind === "explanation" ? ["short"] : [],
    placeholder_key: placeholderKey,
    cite: [],
  };
}

function objective(
  key: string,
  area: PayloadObjective["area"],
  taughtIn: string[],
): PayloadObjective {
  return {
    key,
    statement: `The statement of ${key}.`,
    area,
    depth: "know",
    phase: "understand",
    domain: null,
    taught_in: taughtIn,
  };
}

function item(
  key: string,
  kind: PayloadItem["kind"],
  lesson: string | null,
  objectives: string[],
  overrides: Partial<PayloadItem> = {},
): PayloadItem {
  return {
    key,
    kind,
    lesson,
    stem: `The stem of ${key}.`,
    core: false,
    provenance: "invented",
    objectives,
    rules: [],
    reveals: [],
    cite: [],
    options: [],
    config: {},
    ...overrides,
  };
}
