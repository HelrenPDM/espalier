import { render, type RenderResult } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import type { ReactNode } from "react";
import { createMemoryRouter, RouterProvider } from "react-router";
import { vi, type Mock } from "vitest";
import "../i18n";
import { PlayerProvider } from "../player/PlayerProvider";
import { RuntimeContext } from "../player/RuntimeContext";
import {
  emptyResumeState,
  type Block,
  type ItemView,
  type ModuleView,
  type ObjectiveView,
  type ProgramView,
  type ResumeState,
  type Runtime,
} from "../player/runtime";

/** A readable UUID for fixtures: `id(101)` is `00000000-0000-4000-8000-000000000101`. */
export const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;

export const SLUG = "demo";

/** The ids of the fixture program. */
export const IDS = {
  module1: id(1),
  module2: id(2),
  lesson1: id(11),
  lesson2: id(12),
  lesson3: id(13),
  lesson4: id(14),
  textBlock: id(21),
  explanationShort: id(22),
  placeholderBlock: id(23),
  explanationPlain: id(24),
  caseBlock: id(25),
  quoteBlock: id(26),
  singleChoice: id(31),
  multipleChoice: id(32),
  poll: id(33),
  slotBuilder: id(34),
  classification: id(35),
  checklist: id(36),
  noObjectives: id(37),
  examItem1: id(41),
  examItem2: id(42),
  exam: id(51),
  workshop: id(61),
  rule1: id(71),
  rule2: id(72),
} as const;

const block = (
  overrides: Partial<Block> & Pick<Block, "id" | "kind">,
): Block => ({
  body: "Body text.",
  provenance: "invented",
  collapsed_on: [],
  placeholder_key: null,
  citations: [],
  ...overrides,
});

export const item = (
  overrides: Partial<ItemView> & Pick<ItemView, "id" | "key" | "kind">,
): ItemView => ({
  stem: `Stem of ${overrides.key}`,
  provenance: "invented",
  lesson_id: null,
  objective_keys: [],
  options: [],
  slots: [],
  cases: [],
  categories: [],
  checks: [],
  ...overrides,
});

const objective = (
  overrides: Partial<ObjectiveView> & Pick<ObjectiveView, "key" | "area">,
): ObjectiveView => ({
  statement: `Learners can ${overrides.key}.`,
  depth: "know",
  phase: "understand",
  domain: null,
  lesson_ids: [],
  evidence: [],
  ...overrides,
});

const choices = (...labels: string[]) =>
  labels.map((label, index) => ({ key: `option-${index + 1}`, label }));

/**
 * Module 1 of the fixture: three lessons, five objectives in the four areas
 * (two in `subject`), a practice item of every choice kind and an exam.
 *
 * - `m1-subject-evidenced`: evidence item `singleChoice` (practice).
 * - `m1-subject-exam`: evidence items `examItem1` and `examItem2` of the exam.
 * - `m1-method-practice`: evidence item `multipleChoice` (practice).
 * - `m1-self-format`: evidence only the workshop format.
 * - `m1-social-format`: evidence only the workshop format.
 */
export function module1(): ModuleView {
  return {
    id: IDS.module1,
    number: 1,
    title: "How language models work",
    summary: "Summary of module 1.",
    phases: ["orient", "understand"],
    single_path: false,
    program_slug: SLUG,
    lessons: [
      {
        id: IDS.lesson1,
        key: "01-first-lesson",
        position: 1,
        title: "What a language model does",
        blocks: [
          block({
            id: IDS.textBlock,
            kind: "text",
            body: "A [[term:llm|language model]] continues text.",
          }),
          block({
            id: IDS.explanationShort,
            kind: "explanation",
            body: "The next word follows from probabilities.",
            collapsed_on: ["short"],
            provenance: "sourced",
            citations: [
              {
                locator: "Overview",
                source: {
                  key: "vendor-guide",
                  title: "User guide",
                  publisher: "Example Vendor",
                  url: "https://example.org/guide",
                  edition_date: "2026-03-01",
                  retrieved_on: "2026-09-15",
                  kind: "vendor",
                },
              },
            ],
          }),
          block({
            id: IDS.placeholderBlock,
            kind: "placeholder",
            body: "Your organization adds its rules for inputs here.",
            provenance: "placeholder",
            placeholder_key: "input-rules",
          }),
        ],
      },
      {
        id: IDS.lesson2,
        key: "02-second-lesson",
        position: 2,
        title: "Why answers vary",
        blocks: [
          block({
            id: IDS.explanationPlain,
            kind: "explanation",
            body: "Sampling adds chance.",
          }),
        ],
      },
      {
        id: IDS.lesson3,
        key: "03-third-lesson",
        position: 3,
        title: "Checking and sharing",
        blocks: [
          block({
            id: IDS.quoteBlock,
            kind: "quote",
            body: "I read every paragraph as if a new colleague wrote it.",
            provenance: "sourced",
          }),
        ],
      },
    ],
    rules: [
      {
        id: IDS.rule1,
        number: 1,
        statement: "Generated text carries no check of its own.",
        action: "Treat every generated statement as a draft.",
        citations: [],
      },
      {
        id: IDS.rule2,
        number: 2,
        statement: "The same request can produce different answers.",
        action: "Keep the version you have checked.",
        citations: [],
      },
    ],
    practice_items: [
      item({
        id: IDS.singleChoice,
        key: "m1-single",
        kind: "single_choice",
        stem: "How does a language model write?",
        lesson_id: IDS.lesson1,
        objective_keys: ["m1-subject-evidenced"],
        options: choices(
          "It continues the text with likely words.",
          "It looks up a database of facts.",
        ),
      }),
      item({
        id: IDS.multipleChoice,
        key: "m1-multiple",
        kind: "multiple_choice",
        stem: "Why can answers vary?",
        lesson_id: IDS.lesson2,
        objective_keys: ["m1-method-practice"],
        options: choices(
          "Chance at each step.",
          "Earlier turns.",
          "A person edits them.",
        ),
      }),
      item({
        id: IDS.poll,
        key: "m1-poll",
        kind: "poll",
        stem: "Which task first?",
        lesson_id: IDS.lesson3,
        options: choices("Emails", "Summaries"),
      }),
    ],
    exams: [
      {
        id: IDS.exam,
        key: "module-1-exam",
        title: "Exam of module 1",
        max_wrong: 1,
        counts_for_credential: true,
        items: [
          item({
            id: IDS.examItem1,
            key: "m1-exam-1",
            kind: "single_choice",
            stem: "What does a model do when it writes?",
            objective_keys: ["m1-subject-exam"],
            options: choices("It continues text.", "It retrieves facts."),
          }),
          item({
            id: IDS.examItem2,
            key: "m1-exam-2",
            kind: "single_choice",
            stem: "Which parts need a check?",
            objective_keys: ["m1-subject-exam"],
            options: choices("Every name and number.", "Nothing."),
          }),
        ],
      },
    ],
    objectives: [
      objective({
        key: "m1-subject-evidenced",
        area: "subject",
        domain: "research",
        statement: "Learners can explain how a model continues text.",
        lesson_ids: [IDS.lesson1],
        evidence: [{ kind: "item", id: IDS.singleChoice }],
      }),
      objective({
        key: "m1-subject-exam",
        area: "subject",
        statement: "Learners can explain why answers vary.",
        lesson_ids: [IDS.lesson2],
        evidence: [
          { kind: "item", id: IDS.examItem1 },
          { kind: "item", id: IDS.examItem2 },
        ],
      }),
      objective({
        key: "m1-method-practice",
        area: "method",
        statement: "Learners can name the checks of a statement.",
        lesson_ids: [IDS.lesson2, IDS.lesson3],
        evidence: [{ kind: "item", id: IDS.multipleChoice }],
      }),
      objective({
        key: "m1-self-format",
        area: "self",
        depth: "judge",
        statement: "Learners can judge which tasks they keep.",
        lesson_ids: [IDS.lesson3],
        evidence: [{ kind: "format", id: IDS.workshop }],
      }),
      objective({
        key: "m1-social-format",
        area: "social",
        depth: "judge",
        statement: "Learners can agree with their team on transparency.",
        lesson_ids: [IDS.lesson3],
        evidence: [{ kind: "format", id: IDS.workshop }],
      }),
    ],
  };
}

/**
 * Module 2 of the fixture: `single_path: true`, one lesson with a case
 * comparison, a slot builder, a classification, a checklist drill and an
 * item without objectives, and objectives in `subject` and `method` only.
 */
export function module2(): ModuleView {
  return {
    id: IDS.module2,
    number: 2,
    title: "Checking the output",
    summary: "Summary of module 2.",
    phases: ["apply"],
    single_path: true,
    program_slug: SLUG,
    lessons: [
      {
        id: IDS.lesson4,
        key: "01-first-lesson",
        position: 1,
        title: "Building a prompt",
        blocks: [
          block({
            id: IDS.caseBlock,
            kind: "case_comparison",
            body: "**Draft A**\n\nA states a figure.\n\n**Draft B**\n\nB states a goal.\n\nA needs a check.",
          }),
        ],
      },
    ],
    rules: [],
    practice_items: [
      item({
        id: IDS.slotBuilder,
        key: "m2-slots",
        kind: "slot_builder",
        stem: "Build a prompt.",
        lesson_id: IDS.lesson4,
        objective_keys: ["m2-subject-prompt"],
        slots: [
          {
            key: "task",
            label: "Task",
            options: [
              { key: "task-clear", label: "Write a notice to my team." },
              { key: "task-vague", label: "Write something." },
            ],
          },
          {
            key: "format",
            label: "Format",
            options: [
              { key: "format-short", label: "Three sentences." },
              { key: "format-open", label: "Any length." },
            ],
          },
        ],
      }),
      item({
        id: IDS.classification,
        key: "m2-classify",
        kind: "classification",
        stem: "Sort each statement.",
        lesson_id: IDS.lesson4,
        objective_keys: ["m2-method-judge"],
        categories: [
          { key: "needs-source", label: "Check against a source" },
          { key: "ready", label: "Ready to use" },
        ],
        cases: [
          { key: "case-figure", text: "The process saves 40 percent." },
          { key: "case-thanks", text: "Thank you for reading." },
        ],
      }),
      item({
        id: IDS.checklist,
        key: "m2-release",
        kind: "checklist_drill",
        stem: "Run the release checks.",
        lesson_id: IDS.lesson4,
        objective_keys: ["m2-method-release"],
        checks: [
          {
            key: "facts-checked",
            label: "Every fact is checked.",
            required: true,
          },
          {
            key: "second-reader",
            label: "A colleague has read it.",
            required: false,
          },
        ],
      }),
      item({
        id: IDS.noObjectives,
        key: "m2-plain",
        kind: "single_choice",
        stem: "A question without objectives.",
        lesson_id: IDS.lesson4,
        options: choices("Yes", "No"),
      }),
    ],
    exams: [],
    objectives: [
      objective({
        key: "m2-subject-prompt",
        area: "subject",
        depth: "apply",
        statement: "Learners can build a prompt from four parts.",
        lesson_ids: [IDS.lesson4],
        evidence: [{ kind: "item", id: IDS.slotBuilder }],
      }),
      objective({
        key: "m2-method-judge",
        area: "method",
        depth: "judge",
        statement: "Learners can judge two compared drafts.",
        lesson_ids: [IDS.lesson4],
        evidence: [{ kind: "item", id: IDS.classification }],
      }),
      objective({
        key: "m2-method-release",
        area: "method",
        depth: "apply",
        statement: "Learners can run the release checks.",
        lesson_ids: [IDS.lesson4],
        evidence: [{ kind: "item", id: IDS.checklist }],
      }),
    ],
  };
}

/**
 * The fixture program: an overview (position 1), module 1 (2), module 2
 * (3) and, unless `withFormatStation` is false, a companion formats station
 * (4); the workshop format and a glossary of two terms.
 */
export function programFixture({
  withFormatStation = true,
}: { withFormatStation?: boolean } = {}): ProgramView {
  return {
    id: id(100),
    slug: SLUG,
    title: "AI assistant basics (demo)",
    locale: "en",
    pack_version: "1.0.0",
    segments: [],
    companion_formats: [
      {
        id: IDS.workshop,
        key: "workshop",
        title: "Team workshop",
        description: "A two-hour session.",
        phases: ["apply", "anchor"],
        attendance_counts: true,
      },
    ],
    stations: [
      {
        kind: "overview",
        position: 1,
        title: "Overview",
        intro: "This program is a demo.",
        module_id: null,
        question: null,
        questions: [],
      },
      {
        kind: "module",
        position: 2,
        title: "How language models work",
        intro: null,
        module_id: IDS.module1,
        question: null,
        questions: [],
      },
      {
        kind: "module",
        position: 3,
        title: "Checking the output",
        intro: null,
        module_id: IDS.module2,
        question: null,
        questions: [],
      },
      ...(withFormatStation
        ? [
            {
              kind: "companion_formats" as const,
              position: 4,
              title: "Beyond the platform",
              intro: "Formats outside the platform.",
              module_id: null,
              question: null,
              questions: [],
            },
          ]
        : []),
    ],
    modules: [module1(), module2()],
    glossary: [
      {
        slug: "llm",
        label: "language model",
        short_text: "A program that continues text with likely words.",
      },
      {
        slug: "sampling",
        label: "sampling",
        short_text: "The chance-based choice among likely next words.",
      },
    ],
  };
}

/** A `Runtime` whose methods are mocks. */
export type FakeRuntime = {
  [K in keyof Runtime]: Mock<Runtime[K]>;
};

/**
 * A fake runtime over `program` and `state`. `loadState` resolves a copy of
 * `state` (or `null`), and every write resolves; each method is a `vi.fn`
 * that a test can replace with `mockResolvedValueOnce` and the like.
 */
export function fakeRuntime({
  program = programFixture(),
  state = emptyResumeState("full"),
}: {
  program?: ProgramView;
  state?: ResumeState | null;
} = {}): FakeRuntime {
  return {
    loadProgram: vi.fn(async () => program),
    loadState: vi.fn(async () =>
      state === null ? null : structuredClone(state),
    ),
    saveState: vi.fn(async () => {}),
    submitItem: vi.fn(async (itemId: string) => ({
      item_id: itemId,
      correct: true,
      option_feedback: [],
      rules: [],
      reveals: [],
    })),
    submitAssessment: vi.fn(async (assessmentId: string) => ({
      id: id(900),
      assessment_id: assessmentId,
      number: 1,
      outcome: "passed" as const,
      core_failed: false,
      wrong_count: 0,
      submitted_at: "2026-10-11T10:00:00Z",
      results: [],
    })),
    completeModule: vi.fn(async () => {}),
  };
}

export interface RenderPlayerResult extends RenderResult {
  runtime: FakeRuntime;
  router: ReturnType<typeof createMemoryRouter>;
  user: ReturnType<typeof userEvent.setup>;
  /** The path, query and fragment of the memory router. */
  location: () => string;
}

/**
 * Renders `ui` inside the player of the fixture program: a memory router at
 * `route` (default `/programs/demo`), `RuntimeContext` with `runtime` and
 * `PlayerProvider`. The player loads asynchronously, so tests wait with
 * `findBy…`. Other paths render nothing, so a navigation shows in
 * `location()`.
 */
export function renderPlayer(
  ui: ReactNode,
  {
    runtime = fakeRuntime(),
    route = `/programs/${SLUG}`,
    path = route.split(/[?#]/)[0],
  }: { runtime?: FakeRuntime; route?: string; path?: string } = {},
): RenderPlayerResult {
  const router = createMemoryRouter(
    [
      {
        path,
        element: (
          <RuntimeContext.Provider value={runtime}>
            <PlayerProvider slug={SLUG}>{ui}</PlayerProvider>
          </RuntimeContext.Provider>
        ),
      },
      { path: "*", element: null },
    ],
    { initialEntries: [route] },
  );
  const user = userEvent.setup();
  const result = render(<RouterProvider router={router} />);
  const location = () =>
    router.state.location.pathname +
    router.state.location.search +
    router.state.location.hash;
  return { ...result, runtime, router, user, location };
}
