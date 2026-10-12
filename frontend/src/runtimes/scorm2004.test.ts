import { afterEach, describe, expect, test } from "vitest";
import { emptyResumeState } from "../player/runtime";
import { fakeScorm2004 } from "./fakeLms";
import {
  OBJECTIVE_STATUS_2004,
  Scorm2004Runtime,
  timeInterval,
} from "./scorm2004";
import {
  ANSWERS,
  IDS,
  OBJECTIVE_KEYS,
  examAnswers,
  scormContent,
} from "./scormFixture";

/**
 * Task 0016 step 5: `Scorm2004Runtime` against a fake SCORM 2004 LMS that
 * records every call. On start it writes the id of every objective in
 * position order and the status of an index after its id; an answer writes
 * the status of the objective whose state changed and commits once;
 * `loadState` reports the objectives in the state `passed`; a second
 * runtime on the suspend data of the first writes the same entries; and
 * each objective state has its pair of `success_status` and
 * `completion_status`. The further tests cover the status, score and exit
 * values of step 4 and a failed `Initialize`.
 */
const runtimes: Scorm2004Runtime[] = [];

afterEach(() => {
  for (const runtime of runtimes.splice(0)) runtime.finish();
});

function started(
  preloaded: Record<string, string> = {},
  content = scormContent(),
) {
  const { api, lms } = fakeScorm2004(preloaded);
  const runtime = new Scorm2004Runtime(content, api);
  runtimes.push(runtime);
  runtime.start();
  return { runtime, lms };
}

const success = (index: number) => `cmi.objectives.${index}.success_status`;
const completion = (index: number) =>
  `cmi.objectives.${index}.completion_status`;

/** The pair of the entry `index` in the LMS. */
const pair = (lms: { values: Map<string, string> }, index: number) => ({
  success_status: lms.values.get(success(index)),
  completion_status: lms.values.get(completion(index)),
});

describe("Scorm2004Runtime", () => {
  test("on start, writes the id of every objective in position order and the status of an index only after its id", () => {
    const { lms } = started();

    expect(lms.calls[0]).toEqual({ name: "Initialize", args: [""] });
    expect(lms.objectiveSets()).toEqual(
      OBJECTIVE_KEYS.flatMap((key, index) => [
        [`cmi.objectives.${index}.id`, key],
        [success(index), "unknown"],
        [completion(index), "incomplete"],
      ]),
    );
    expect(lms.values.get("cmi.completion_status")).toBe("incomplete");
    expect(lms.values.get("cmi.success_status")).toBe("unknown");
    expect(lms.values.get("cmi.exit")).toBe("suspend");
    expect(lms.calls.at(-1)).toEqual({ name: "Commit", args: [""] });
    expect(lms.names().filter((name) => name === "Commit")).toHaveLength(1);
  });

  test("after an answer that changes the state of one objective, writes the status of that objective only and then commits", async () => {
    const { runtime, lms } = started();
    lms.clear();

    await runtime.submitItem(IDS.choice, ANSWERS[IDS.choice].right);

    expect(lms.objectiveSets()).toEqual([
      [success(1), "passed"],
      [completion(1), "completed"],
    ]);
    expect(lms.sets().map(([element]) => element)).toEqual([
      success(1),
      completion(1),
      "cmi.suspend_data",
    ]);
    expect(lms.calls.at(-1)).toEqual({ name: "Commit", args: [""] });
    expect(lms.names().filter((name) => name === "Commit")).toHaveLength(1);
  });

  test("loadState returns the keys of the objectives in the state passed as evidencedObjectives and no other key", async () => {
    const { runtime } = started();
    for (const id of [IDS.slots, IDS.drill, IDS.classify])
      await runtime.submitItem(id, ANSWERS[id].wrong);
    await runtime.submitItem(IDS.poll, ANSWERS[IDS.poll].right);
    await runtime.submitAssessment(IDS.exam, examAnswers(IDS.examB));

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
    const pairs = OBJECTIVE_KEYS.map((_, index) => pair(first.lms, index));

    const second = started({
      "cmi.suspend_data": first.lms.values.get("cmi.suspend_data") ?? "",
      "cmi.completion_status":
        first.lms.values.get("cmi.completion_status") ?? "",
      "cmi.success_status": first.lms.values.get("cmi.success_status") ?? "",
    });

    expect(second.lms.objectiveSets()).toEqual(
      OBJECTIVE_KEYS.flatMap((key, index) => [
        [`cmi.objectives.${index}.id`, key],
        [success(index), pairs[index].success_status],
        [completion(index), pairs[index].completion_status],
      ]),
    );
    expect((await second.runtime.loadState()).evidencedObjectives).toEqual([
      "m1-method-mixed",
    ]);
  });

  test("writes the pair of success_status and completion_status for each of the three states", async () => {
    const { runtime, lms } = started();
    await runtime.submitItem(IDS.choice, ANSWERS[IDS.choice].right);
    for (const id of [IDS.slots, IDS.drill, IDS.classify])
      await runtime.submitItem(id, ANSWERS[id].wrong);

    // m1-method-mixed is passed, m1-method-practice failed and
    // m1-social-poll incomplete.
    expect(pair(lms, 1)).toEqual({
      success_status: "passed",
      completion_status: "completed",
    });
    expect(pair(lms, 2)).toEqual({
      success_status: "failed",
      completion_status: "completed",
    });
    expect(pair(lms, 3)).toEqual({
      success_status: "unknown",
      completion_status: "incomplete",
    });
    expect(OBJECTIVE_STATUS_2004).toEqual({
      passed: pair(lms, 1),
      failed: pair(lms, 2),
      incomplete: pair(lms, 3),
    });
  });

  test("an exam attempt sets the score with its scaled value and the success status; completion sets completed and the exit normal", async () => {
    const { runtime, lms } = started();

    await runtime.submitAssessment(IDS.exam, examAnswers(IDS.examA, IDS.examB));
    expect(lms.values.get("cmi.success_status")).toBe("failed");
    expect(lms.values.get("cmi.score.scaled")).toBe("0");

    lms.clear();
    await runtime.submitAssessment(IDS.exam, examAnswers(IDS.examB));
    // The minimum and the maximum did not change, so they are not written.
    expect(
      lms.sets().filter(([element]) => !element.startsWith("cmi.objectives.")),
    ).toEqual([
      ["cmi.score.raw", "1"],
      ["cmi.score.scaled", "0.5"],
      ["cmi.success_status", "passed"],
      ["cmi.suspend_data", expect.any(String)],
    ]);
    expect(lms.values.get("cmi.score.min")).toBe("0");
    expect(lms.values.get("cmi.score.max")).toBe("2");
    expect(lms.values.get("cmi.completion_status")).toBe("incomplete");
    expect(lms.values.get("cmi.exit")).toBe("suspend");
    expect(lms.names().filter((name) => name === "Commit")).toHaveLength(1);

    await runtime.completeModule(IDS.module);
    expect(lms.values.get("cmi.completion_status")).toBe("completed");
    expect(lms.values.get("cmi.success_status")).toBe("passed");
    expect(lms.values.get("cmi.exit")).toBe("normal");
  });

  test("a module without exam reports completed and leaves the success status unknown", async () => {
    const { runtime, lms } = started({}, scormContent({ exam: false }));

    await runtime.completeModule(IDS.module);

    expect(lms.values.get("cmi.completion_status")).toBe("completed");
    expect(lms.values.get("cmi.success_status")).toBe("unknown");
    expect(lms.values.get("cmi.exit")).toBe("normal");
    expect(lms.sets().map(([element]) => element)).not.toContain(
      "cmi.success_status",
    );
  });

  test("a module whose exam does not count for the credential reports completed when the learner completes it without an attempt", async () => {
    const { runtime, lms } = started(
      {},
      scormContent({ countsForCredential: false }),
    );

    await runtime.completeModule(IDS.module);

    expect(lms.values.get("cmi.completion_status")).toBe("completed");
    expect(lms.values.get("cmi.success_status")).toBe("unknown");
    expect(lms.values.get("cmi.exit")).toBe("normal");
  });

  test("when Initialize fails, start() throws and no later call reaches the LMS, Terminate included", async () => {
    const { api, lms } = fakeScorm2004();
    lms.fail("Initialize");
    const runtime = new Scorm2004Runtime(scormContent(), api);

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

    // GetLastError tells a session that is already initialized apart.
    expect(lms.names()).toEqual(["Initialize", "GetLastError"]);
  });

  test("an Initialize that fails with error 103, already initialized, starts the session", () => {
    const { api, lms } = fakeScorm2004();
    lms.fail("Initialize", true, "103");
    const runtime = new Scorm2004Runtime(scormContent(), api);
    runtimes.push(runtime);

    runtime.start();
    runtime.finish();

    expect(lms.names().slice(0, 3)).toEqual([
      "Initialize",
      "GetLastError",
      "GetValue",
    ]);
    expect(lms.values.get("cmi.completion_status")).toBe("incomplete");
    expect(lms.calls.at(-1)).toEqual({ name: "Terminate", args: [""] });
  });

  test("pagehide sets the session time, commits and calls Terminate once", async () => {
    const { runtime, lms } = started();
    await runtime.saveState(await runtime.loadState());
    lms.clear();

    window.dispatchEvent(new Event("pagehide"));
    window.dispatchEvent(new Event("pagehide"));

    expect(lms.values.get("cmi.session_time")).toMatch(
      /^PT\d+H\d+M\d+(\.\d{1,2})?S$/,
    );
    expect(lms.names()).toEqual(["SetValue", "Commit", "Terminate"]);
    expect(lms.calls.at(-1)).toEqual({ name: "Terminate", args: [""] });
  });

  test("timeInterval writes an ISO 8601 duration to the hundredth of a second", () => {
    expect(timeInterval(0)).toBe("PT0H0M0S");
    expect(timeInterval(3_723_456)).toBe("PT1H2M3.46S");
  });
});
