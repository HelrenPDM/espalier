import { describe, expect, test } from "vitest";
import { ApiError } from "../api/errors";
import { objectiveStatus } from "../player/objectives/status";
import {
  AssessmentsOpenError,
  emptyResumeState,
  type ObjectiveView,
  type ProgramView,
} from "../player/runtime";
import {
  StandaloneRuntime,
  isPackPayload,
  payloadIds,
  payloadToProgramView,
  type PackPayload,
  type PayloadItem,
} from "./standalone";

/**
 * Task 0015 step 9: `StandaloneRuntime` on a hand-written payload with one
 * module, three objectives, an exam item, a poll, a checklist drill, a
 * format with `attendance_counts: true` and one with `false`. The mapping
 * fills `lesson_ids` (teaching lessons in position order), `evidence` (the
 * rule of 0008 step 13: no poll that no assessment lists, no format whose
 * attendance does not count) and `objective_keys`. `loadState` returns the
 * last saved state with an empty `evidencedObjectives`, and a passed exam
 * still shows `evidenced` through `objectiveStatus`.
 */
const item = (
  overrides: Partial<PayloadItem> & Pick<PayloadItem, "key" | "kind">,
): PayloadItem => ({
  lesson: null,
  stem: `Stem of ${overrides.key}`,
  core: false,
  provenance: "invented",
  objectives: [],
  rules: [],
  reveals: [],
  cite: [],
  options: [],
  config: {},
  ...overrides,
});

function payload(): PackPayload {
  return {
    key: "preview-pack",
    title: "Preview pack",
    locale: "en",
    version: "1.2.0",
    alignment: "strict",
    sources: [
      {
        key: "guide",
        title: "A guide",
        publisher: "A publisher",
        url: null,
        edition_date: "2026-01-01",
        retrieved_on: "2026-02-01",
        kind: "guidance",
      },
    ],
    glossary: [
      { slug: "zeta", label: "Zeta", short_text: "The last term." },
      { slug: "alpha", label: "Alpha", short_text: "The first term." },
    ],
    segments: [],
    stations: [
      {
        kind: "overview",
        title: "Overview",
        module: null,
        config: { intro: "Welcome." },
      },
      { kind: "module", title: "Basics", module: 1, config: {} },
    ],
    formats: [
      {
        key: "workshop",
        title: "Workshop",
        description: "A workshop.",
        phases: ["anchor"],
        attendance_counts: true,
        objectives: ["m1-social-judge"],
      },
      {
        key: "newsletter",
        title: "Newsletter",
        description: "A newsletter.",
        phases: ["update"],
        attendance_counts: false,
        objectives: ["m1-method-apply", "m1-social-judge"],
      },
    ],
    modules: [
      {
        number: 1,
        title: "Basics",
        summary: "The basics.",
        phases: ["understand"],
        single_path: false,
        // `a-practice` sorts first by key and comes second by position.
        lessons: [
          {
            key: "b-intro",
            title: "Introduction",
            position: 1,
            blocks: [
              {
                kind: "text",
                body: "Text.",
                provenance: "sourced",
                collapsed_on: [],
                placeholder_key: null,
                cite: ["guide#p. 2"],
                media: null,
              },
            ],
          },
          {
            key: "a-practice",
            title: "Practice",
            position: 2,
            blocks: [
              {
                kind: "explanation",
                body: "Explanation.",
                provenance: "invented",
                collapsed_on: ["short"],
                placeholder_key: null,
                cite: [],
                media: null,
              },
            ],
          },
        ],
        objectives: [
          {
            key: "m1-subject-know",
            statement: "Name the parts of a request.",
            area: "subject",
            depth: "know",
            phase: "understand",
            domain: null,
            taught_in: ["a-practice", "b-intro"],
          },
          {
            key: "m1-method-apply",
            statement: "Check a text before its release.",
            area: "method",
            depth: "apply",
            phase: "apply",
            domain: null,
            taught_in: ["a-practice"],
          },
          {
            key: "m1-social-judge",
            statement: "Judge a case with the team.",
            area: "social",
            depth: "judge",
            phase: "anchor",
            domain: null,
            taught_in: ["b-intro"],
          },
        ],
        rules: [
          { number: 1, statement: "Check first.", action: "Check.", cite: [] },
        ],
        items: [
          item({
            key: "poll-usage",
            kind: "poll",
            lesson: "b-intro",
            objectives: ["m1-social-judge"],
            options: [
              { key: "often", label: "Often", correct: false, feedback: null },
              { key: "never", label: "Never", correct: false, feedback: null },
            ],
          }),
          item({
            key: "drill-release",
            kind: "checklist_drill",
            lesson: "a-practice",
            objectives: ["m1-subject-know", "m1-method-apply"],
            rules: [1],
            reveals: ["b-intro"],
            config: {
              checks: [
                { key: "facts", label: "Facts checked", required: true },
                { key: "reader", label: "Second reader", required: false },
              ],
            },
          }),
          item({
            key: "exam-know",
            kind: "single_choice",
            core: true,
            objectives: ["m1-subject-know"],
            options: [
              { key: "yes", label: "Yes", correct: true, feedback: "Right." },
              { key: "no", label: "No", correct: false, feedback: "Wrong." },
            ],
          }),
        ],
        assessments: [
          {
            key: "exam-1",
            title: "Exam of module 1",
            kind: "exam",
            counts_for_credential: true,
            max_wrong: 0,
            core_required: true,
            items: ["exam-know"],
          },
        ],
      },
    ],
  };
}

const ID = {
  module: payloadIds.module(1),
  intro: payloadIds.lesson(1, "b-intro"),
  practice: payloadIds.lesson(1, "a-practice"),
  poll: payloadIds.item("poll-usage"),
  drill: payloadIds.item("drill-release"),
  examItem: payloadIds.item("exam-know"),
  exam: payloadIds.assessment("exam-1"),
  workshop: payloadIds.format("workshop"),
  newsletter: payloadIds.format("newsletter"),
};

function objectiveOf(program: ProgramView, key: string): ObjectiveView {
  const objective = program.modules[0].objectives.find(
    (entry) => entry.key === key,
  );
  if (objective === undefined) throw new Error(`no objective ${key}`);
  return objective;
}

describe("the payload-to-view mapping", () => {
  test("gives every objective its teaching lessons in position order", () => {
    const program = payloadToProgramView(payload());

    expect(
      program.modules[0].objectives.map(({ key, lesson_ids }) => ({
        key,
        lesson_ids,
      })),
    ).toEqual([
      { key: "m1-subject-know", lesson_ids: [ID.intro, ID.practice] },
      { key: "m1-method-apply", lesson_ids: [ID.practice] },
      { key: "m1-social-judge", lesson_ids: [ID.intro] },
    ]);
    expect(program.modules[0].lessons.map((lesson) => lesson.id)).toEqual([
      ID.intro,
      ID.practice,
    ]);
  });

  test("gives every objective its evidence: items by key, then formats whose attendance counts", () => {
    const program = payloadToProgramView(payload());

    expect(objectiveOf(program, "m1-subject-know").evidence).toEqual([
      { kind: "item", id: ID.drill },
      { kind: "item", id: ID.examItem },
    ]);
    expect(objectiveOf(program, "m1-method-apply").evidence).toEqual([
      { kind: "item", id: ID.drill },
    ]);
    expect(objectiveOf(program, "m1-social-judge").evidence).toEqual([
      { kind: "format", id: ID.workshop },
    ]);

    const evidence = program.modules[0].objectives.flatMap(
      (objective) => objective.evidence,
    );
    expect(evidence.map((entry) => entry.id)).not.toContain(ID.poll);
    expect(evidence.map((entry) => entry.id)).not.toContain(ID.newsletter);
  });

  test("gives every item view its sorted objective keys", () => {
    const [module] = payloadToProgramView(payload()).modules;

    expect(
      module.practice_items.map(({ id, objective_keys, lesson_id }) => ({
        id,
        objective_keys,
        lesson_id,
      })),
    ).toEqual([
      { id: ID.poll, objective_keys: ["m1-social-judge"], lesson_id: ID.intro },
      {
        id: ID.drill,
        objective_keys: ["m1-method-apply", "m1-subject-know"],
        lesson_id: ID.practice,
      },
    ]);
    expect(module.exams).toHaveLength(1);
    expect(module.exams[0]).toMatchObject({
      id: ID.exam,
      key: "exam-1",
      max_wrong: 0,
      counts_for_credential: true,
    });
    expect(
      module.exams[0].items.map(({ id, objective_keys, lesson_id }) => ({
        id,
        objective_keys,
        lesson_id,
      })),
    ).toEqual([
      { id: ID.examItem, objective_keys: ["m1-subject-know"], lesson_id: null },
    ]);
  });

  test("maps the views without answer keys, with stations, formats, citations and the glossary", () => {
    const program = payloadToProgramView(payload());
    const [module] = program.modules;

    expect(program).toMatchObject({
      slug: "preview-pack",
      title: "Preview pack",
      locale: "en",
      pack_version: "1.2.0",
    });
    expect(program.stations).toEqual([
      expect.objectContaining({
        position: 1,
        kind: "overview",
        module_id: null,
        intro: "Welcome.",
      }),
      expect.objectContaining({
        position: 2,
        kind: "module",
        module_id: ID.module,
      }),
    ]);
    expect(program.companion_formats.map((format) => format.id)).toEqual([
      ID.workshop,
      ID.newsletter,
    ]);
    expect(program.glossary.map((term) => term.slug)).toEqual([
      "alpha",
      "zeta",
    ]);
    expect(module.lessons[0].blocks[0].citations).toEqual([
      { locator: "p. 2", source: payload().sources[0] },
    ]);
    expect(module.lessons[0].blocks[0].policy).toBeNull();
    expect(module.exams[0].items[0].options).toEqual([
      { key: "yes", label: "Yes" },
      { key: "no", label: "No" },
    ]);
    expect(JSON.stringify(program)).not.toMatch(/"(correct|feedback)"/);
  });
});

describe("StandaloneRuntime", () => {
  test("loadState returns null before the first save and then the saved state with empty evidencedObjectives", async () => {
    const runtime = new StandaloneRuntime(payload());
    expect(await runtime.loadState()).toBeNull();

    const saved = {
      ...emptyResumeState("short"),
      answeredItems: [ID.drill],
      examOutcomes: { [ID.exam]: "passed" as const },
      evidencedObjectives: ["m1-subject-know"],
    };
    await runtime.saveState(saved);
    saved.answeredItems.push("changed later");

    expect(await runtime.loadState()).toEqual({
      ...emptyResumeState("short"),
      answeredItems: [ID.drill],
      examOutcomes: { [ID.exam]: "passed" },
      evidencedObjectives: [],
    });
  });

  test("after a passed exam, objectiveStatus gives evidenced for the objective of the exam item", async () => {
    const runtime = new StandaloneRuntime(payload());
    const program = await runtime.loadProgram("preview-pack");
    await runtime.saveState({
      ...emptyResumeState("full"),
      examOutcomes: { [ID.exam]: "passed" },
    });

    const state = await runtime.loadState();
    expect(state).not.toBeNull();
    if (state === null) return;
    expect(state.evidencedObjectives).toEqual([]);
    expect(
      objectiveStatus(objectiveOf(program, "m1-subject-know"), program, state),
    ).toBe("evidenced");
    expect(
      objectiveStatus(objectiveOf(program, "m1-method-apply"), program, state),
    ).toBe("open");

    await runtime.saveState({ ...state, answeredItems: [ID.drill] });
    const practised = await runtime.loadState();
    if (practised === null) throw new Error("no state");
    expect(
      objectiveStatus(
        objectiveOf(program, "m1-method-apply"),
        program,
        practised,
      ),
    ).toBe("practised");
  });

  test("loadProgram answers 404 for another slug", async () => {
    const runtime = new StandaloneRuntime(payload());
    await expect(runtime.loadProgram("other")).rejects.toMatchObject({
      status: 404,
      code: "not_found",
    });
  });

  test("submitItem evaluates a practice item with its rules and reveals", async () => {
    const runtime = new StandaloneRuntime(payload());

    expect(
      await runtime.submitItem(ID.drill, { checks: ["facts"], initials: "AB" }),
    ).toEqual({
      item_id: ID.drill,
      correct: true,
      option_feedback: [
        { key: "facts", selected: true, required: true, correct: true },
        { key: "reader", selected: false, required: false, correct: true },
      ],
      rules: [
        {
          id: payloadIds.rule(1, 1),
          number: 1,
          statement: "Check first.",
          action: "Check.",
        },
      ],
      reveals: [],
    });
    expect(
      (await runtime.submitItem(ID.drill, { checks: [], initials: "AB" }))
        .reveals,
    ).toEqual([ID.intro]);
    expect(await runtime.submitItem(ID.poll, { options: ["often"] })).toEqual(
      expect.objectContaining({ correct: null, option_feedback: [] }),
    );
  });

  test("submitItem rejects an exam item and an unknown id with 404 and an unfitting answer with 422", async () => {
    const runtime = new StandaloneRuntime(payload());

    await expect(
      runtime.submitItem(ID.examItem, { options: ["yes"] }),
    ).rejects.toMatchObject({ status: 404, code: "not_found" });
    await expect(
      runtime.submitItem("item-unknown", { options: [] }),
    ).rejects.toBeInstanceOf(ApiError);
    await expect(
      runtime.submitItem(ID.drill, { options: ["facts"] }),
    ).rejects.toMatchObject({ status: 422, code: "invalid_answer" });
  });

  test("submitAssessment applies the pass rule and numbers the attempts", async () => {
    const runtime = new StandaloneRuntime(payload());

    const failed = await runtime.submitAssessment(ID.exam, {
      [ID.examItem]: { options: ["no"] },
    });
    expect(failed).toMatchObject({
      assessment_id: ID.exam,
      number: 1,
      outcome: "failed_core",
      core_failed: true,
      wrong_count: 1,
    });
    expect(failed.results).toEqual([
      expect.objectContaining({ item_id: ID.examItem, correct: false }),
    ]);

    const passed = await runtime.submitAssessment(ID.exam, {
      [ID.examItem]: { options: ["yes"] },
    });
    expect(passed).toMatchObject({ number: 2, outcome: "passed" });
    expect(passed.submitted_at).toMatch(
      /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/,
    );
  });

  test("submitAssessment answers 422 for a missing answer and 404 for an unknown exam", async () => {
    const runtime = new StandaloneRuntime(payload());

    await expect(runtime.submitAssessment(ID.exam, {})).rejects.toMatchObject({
      status: 422,
      code: "validation_failed",
    });
    await expect(
      runtime.submitAssessment(ID.exam, {
        [ID.examItem]: { options: ["maybe"] },
      }),
    ).rejects.toMatchObject({ status: 422, code: "validation_failed" });
    await expect(
      runtime.submitAssessment("assessment-unknown", {}),
    ).rejects.toMatchObject({ status: 404 });
  });

  test("completeModule rejects with AssessmentsOpenError until the credential exam is passed", async () => {
    const runtime = new StandaloneRuntime(payload());

    const open = await runtime
      .completeModule(ID.module)
      .catch((error) => error);
    expect(open).toBeInstanceOf(AssessmentsOpenError);
    expect((open as AssessmentsOpenError).assessments).toEqual([
      { id: ID.exam, key: "exam-1", title: "Exam of module 1" },
    ]);

    await runtime.submitAssessment(ID.exam, {
      [ID.examItem]: { options: ["yes"] },
    });
    await expect(runtime.completeModule(ID.module)).resolves.toBeUndefined();
    await expect(runtime.completeModule("module-9")).rejects.toMatchObject({
      status: 404,
    });
  });

  test("isPackPayload accepts a payload and rejects other values", () => {
    expect(isPackPayload(payload())).toBe(true);
    expect(isPackPayload(null)).toBe(false);
    expect(isPackPayload({ key: "x" })).toBe(false);
  });
});
