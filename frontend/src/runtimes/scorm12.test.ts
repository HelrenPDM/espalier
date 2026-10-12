import { Scorm12API } from "scorm-again";
import { afterEach, describe, expect, test } from "vitest";
import { emptyResumeState, type Answer } from "../player/runtime";
import type { ScormContent } from "./content";
import { fakeScorm12 } from "./fakeLms";
import { Scorm12Runtime, cmiTimespan } from "./scorm12";
import {
  ANSWERS,
  IDS,
  OBJECTIVE_KEYS,
  examAnswers,
  scormContent,
} from "./scormFixture";
import { payloadIds } from "./standalone";

/**
 * Task 0016 step 5: `Scorm12Runtime` against a fake SCORM 1.2 LMS that
 * records every call. On start it writes the id of every objective in
 * position order and the status of an index after its id; an answer writes
 * the status of the objective whose state changed and commits once;
 * `loadState` reports the objectives in the state `passed`; and a second
 * runtime on the suspend data of the first writes the same entries. The
 * further tests cover the status, score and exit values of step 4, a failed
 * `LMSInitialize`, and the score of an exam of more than 100 items against
 * the SCORM 1.2 API of scorm-again.
 */
const runtimes: Scorm12Runtime[] = [];

afterEach(() => {
  for (const runtime of runtimes.splice(0)) runtime.finish();
});

function started(
  preloaded: Record<string, string> = {},
  content = scormContent(),
) {
  const { api, lms } = fakeScorm12(preloaded);
  const runtime = new Scorm12Runtime(content, api);
  runtimes.push(runtime);
  runtime.start();
  return { runtime, lms };
}

const status = (index: number) => `cmi.objectives.${index}.status`;

/**
 * `scormContent()` with an exam of `count` single-choice items, each a copy
 * of `exam-a` with the correct option `yes`, in place of the items of
 * `exam-1`.
 */
function contentWithExamItems(count: number): ScormContent {
  const content = scormContent();
  const [exam] = content.module.assessments;
  const [template] = content.module.items.filter(
    (item) => item.key === "exam-a",
  );
  const keys = Array.from(
    { length: count },
    (_, index) => `exam-item-${index + 1}`,
  );
  return {
    ...content,
    module: {
      ...content.module,
      items: [
        ...content.module.items.filter(
          (item) => !exam.items.includes(item.key),
        ),
        ...keys.map((key) => ({ ...template, key })),
      ],
      assessments: [{ ...exam, items: keys }],
    },
  };
}

describe("Scorm12Runtime", () => {
  test("on start, writes the id of every objective in position order and the status of an index only after its id", () => {
    const { lms } = started();

    expect(lms.calls[0]).toEqual({ name: "LMSInitialize", args: [""] });
    expect(lms.objectiveSets()).toEqual(
      OBJECTIVE_KEYS.flatMap((key, index) => [
        [`cmi.objectives.${index}.id`, key],
        [status(index), "incomplete"],
      ]),
    );
    expect(lms.values.get("cmi.core.lesson_status")).toBe("incomplete");
    expect(lms.values.get("cmi.core.exit")).toBe("suspend");
    expect(lms.calls.at(-1)).toEqual({ name: "LMSCommit", args: [""] });
    expect(lms.names().filter((name) => name === "LMSCommit")).toHaveLength(1);
  });

  test("after an answer that changes the state of one objective, writes the status of that objective only and then commits", async () => {
    const { runtime, lms } = started();
    lms.clear();

    await runtime.submitItem(IDS.choice, ANSWERS[IDS.choice].right);

    expect(lms.objectiveSets()).toEqual([[status(1), "passed"]]);
    expect(lms.sets().map(([element]) => element)).toEqual([
      status(1),
      "cmi.suspend_data",
    ]);
    expect(lms.calls.at(-1)).toEqual({ name: "LMSCommit", args: [""] });
    expect(lms.names().filter((name) => name === "LMSCommit")).toHaveLength(1);
  });

  test("loadState returns the keys of the objectives in the state passed as evidencedObjectives and no other key", async () => {
    const { runtime, lms } = started();
    for (const id of [IDS.slots, IDS.drill, IDS.classify])
      await runtime.submitItem(id, ANSWERS[id].wrong);
    await runtime.submitItem(IDS.poll, ANSWERS[IDS.poll].right);
    await runtime.submitAssessment(IDS.exam, examAnswers(IDS.examB));

    expect(
      [0, 1, 2, 3, 4].map((index) => lms.values.get(status(index))),
    ).toEqual(["passed", "passed", "failed", "incomplete", "incomplete"]);
    expect((await runtime.loadState()).evidencedObjectives).toEqual([
      "m1-subject-exam",
      "m1-method-mixed",
    ]);
  });

  test("a second runtime that decodes the suspend data of the first writes the same keys at the same indices with the states of the first", async () => {
    const first = started();
    await first.runtime.submitItem(IDS.choice, ANSWERS[IDS.choice].right);
    for (const id of [IDS.slots, IDS.drill, IDS.classify])
      await first.runtime.submitItem(id, ANSWERS[id].wrong);
    await first.runtime.submitAssessment(
      IDS.exam,
      examAnswers(IDS.examA, IDS.examB),
    );
    await first.runtime.saveState(await first.runtime.loadState());
    first.runtime.finish();
    const states = OBJECTIVE_KEYS.map((_, index) =>
      first.lms.values.get(status(index)),
    );
    expect(states).toEqual([
      "failed",
      "passed",
      "failed",
      "incomplete",
      "incomplete",
    ]);

    const second = started({
      "cmi.suspend_data": first.lms.values.get("cmi.suspend_data") ?? "",
      "cmi.core.lesson_status":
        first.lms.values.get("cmi.core.lesson_status") ?? "",
    });

    expect(second.lms.objectiveSets()).toEqual(
      OBJECTIVE_KEYS.flatMap((key, index) => [
        [`cmi.objectives.${index}.id`, key],
        [status(index), states[index]],
      ]),
    );
    expect((await second.runtime.loadState()).evidencedObjectives).toEqual([
      "m1-method-mixed",
    ]);
  });

  test("a passing exam sets the score of the attempt, the status passed and the exit to the empty string", async () => {
    const { runtime, lms } = started();
    lms.clear();

    await runtime.submitAssessment(IDS.exam, examAnswers(IDS.examB));

    expect(lms.sets()).toEqual(
      expect.arrayContaining([
        ["cmi.core.score.raw", "1"],
        ["cmi.core.score.min", "0"],
        ["cmi.core.score.max", "2"],
        ["cmi.core.lesson_status", "passed"],
        ["cmi.core.exit", ""],
      ]),
    );
    expect(lms.names().filter((name) => name === "LMSCommit")).toHaveLength(1);
  });

  test("a failing attempt sets the status failed and keeps the exit suspend; a later pass sets passed", async () => {
    const { runtime, lms } = started();

    await runtime.submitAssessment(IDS.exam, examAnswers(IDS.examA, IDS.examB));
    expect(lms.values.get("cmi.core.lesson_status")).toBe("failed");
    expect(lms.values.get("cmi.core.score.raw")).toBe("0");
    expect(lms.values.get("cmi.core.exit")).toBe("suspend");

    await runtime.submitAssessment(IDS.exam, examAnswers());
    expect(lms.values.get("cmi.core.lesson_status")).toBe("passed");
    expect(lms.values.get("cmi.core.score.raw")).toBe("2");
    expect(lms.values.get("cmi.core.exit")).toBe("");
  });

  test("a module without exam reports completed once the learner completes it", async () => {
    const { runtime, lms } = started({}, scormContent({ exam: false }));
    expect(lms.values.get("cmi.core.lesson_status")).toBe("incomplete");

    await runtime.completeModule(IDS.module);

    expect(lms.values.get("cmi.core.lesson_status")).toBe("completed");
    expect(lms.values.get("cmi.core.exit")).toBe("");
  });

  test("a module whose exam does not count for the credential reports completed when the learner completes it without an attempt, and a later attempt reports its outcome", async () => {
    const { runtime, lms } = started(
      {},
      scormContent({ countsForCredential: false }),
    );

    await runtime.completeModule(IDS.module);
    expect(lms.values.get("cmi.core.lesson_status")).toBe("completed");
    expect(lms.values.get("cmi.core.exit")).toBe("");

    await runtime.submitAssessment(IDS.exam, examAnswers(IDS.examA, IDS.examB));
    expect(lms.values.get("cmi.core.lesson_status")).toBe("failed");
    expect(lms.values.get("cmi.core.exit")).toBe("suspend");
  });

  test("an exam of more than 100 items writes the percentage with max 100, which the SCORM 1.2 API of scorm-again accepts", async () => {
    const content = contentWithExamItems(120);
    const [exam] = content.module.assessments;
    const answers: Record<string, Answer> = Object.fromEntries(
      exam.items.map((key, index) => [
        payloadIds.item(key),
        { options: [index < 110 ? "yes" : "no"] },
      ]),
    );
    const api = new Scorm12API({
      lmsCommitUrl: false,
      logLevel: "NONE",
    });
    const sets: { element: string; value: string; error: string }[] = [];
    const setValue = api.LMSSetValue.bind(api);
    api.LMSSetValue = (element: string, value: string) => {
      const result = setValue(element, value);
      sets.push({ element, value, error: String(api.LMSGetLastError()) });
      return result;
    };
    const runtime = new Scorm12Runtime(content, api);
    runtimes.push(runtime);
    runtime.start();

    await runtime.submitAssessment(payloadIds.assessment(exam.key), answers);

    expect(
      sets
        .filter(({ element }) => element.startsWith("cmi.core.score."))
        .map(({ element, value }) => [element, value]),
    ).toEqual([
      ["cmi.core.score.raw", "91.67"],
      ["cmi.core.score.min", "0"],
      ["cmi.core.score.max", "100"],
    ]);
    expect(sets.filter(({ error }) => error !== "0")).toEqual([]);
    expect(api.cmi.core.score.raw).toBe("91.67");
    expect(api.cmi.core.score.max).toBe("100");
    // The number of items, 120, lies outside the range of the element.
    expect(setValue("cmi.core.score.max", "120")).toBe("false");
    expect(String(api.LMSGetLastError())).toBe("405");
  });

  test("when LMSInitialize fails, start() throws and no later call reaches the LMS, LMSFinish included", async () => {
    const { api, lms } = fakeScorm12();
    lms.fail("LMSInitialize");
    const runtime = new Scorm12Runtime(scormContent(), api);

    expect(() => runtime.start()).toThrow(Error);
    await runtime.submitItem(IDS.choice, ANSWERS[IDS.choice].right);
    await runtime.submitAssessment(IDS.exam, examAnswers());
    await runtime.completeModule(IDS.module);
    await expect(
      runtime.saveState(emptyResumeState("short")),
    ).rejects.toThrow();
    window.dispatchEvent(new Event("pagehide"));
    runtime.finish();
    runtime.start();

    expect(lms.names()).toEqual(["LMSInitialize"]);
  });

  test("pagehide sets the session time, commits and calls LMSFinish once", async () => {
    const { runtime, lms } = started();
    await runtime.saveState(await runtime.loadState());
    lms.clear();

    window.dispatchEvent(new Event("pagehide"));
    window.dispatchEvent(new Event("pagehide"));

    const time = lms.values.get("cmi.core.session_time") ?? "";
    expect(time).toMatch(/^\d{2,4}:\d{2}:\d{2}\.\d{2}$/);
    expect(lms.names()).toEqual(["LMSSetValue", "LMSCommit", "LMSFinish"]);
    expect(lms.calls.at(-1)).toEqual({ name: "LMSFinish", args: [""] });
  });

  test("cmiTimespan writes hours, minutes and seconds to the hundredth", () => {
    expect(cmiTimespan(0)).toBe("00:00:00.00");
    expect(cmiTimespan(3_723_456)).toBe("01:02:03.46");
    expect(cmiTimespan(1e12)).toBe("9999:59:59.99");
  });
});
