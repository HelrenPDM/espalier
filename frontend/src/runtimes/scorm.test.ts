import { afterEach, describe, expect, test } from "vitest";
import { AssessmentsOpenError, emptyResumeState } from "../player/runtime";
import { fakeScorm12 } from "./fakeLms";
import { Scorm12Runtime } from "./scorm12";
import { ANSWERS, IDS, examAnswers, scormContent } from "./scormFixture";
import { payloadIds } from "./standalone";
import { decodeSuspendData } from "./suspend";

/**
 * Task 0016 step 4: the behaviour that `Scorm12Runtime` and
 * `Scorm2004Runtime` share through `ScormRuntime`, tested on the SCORM 1.2
 * dialect: the policies of placeholder blocks, the completion rule with
 * exams passed in an earlier session, the resume state, the merge of
 * `saveState`, an LMS that fails, the calls before `start()` and after
 * `finish()`, and the save after `pagehide` on a page that the browser
 * keeps in its back/forward cache.
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

/** The values that an LMS returns to the next session of `lms`. */
const resumed = (lms: { values: Map<string, string> }) => ({
  "cmi.suspend_data": lms.values.get("cmi.suspend_data") ?? "",
  "cmi.core.lesson_status": lms.values.get("cmi.core.lesson_status") ?? "",
});

const EXPLANATION = payloadIds.block(1, "intro", 1);

describe("ScormRuntime", () => {
  test("loadProgram gives each placeholder block the policy of content.json, or null without a published version", async () => {
    const content = scormContent();
    const { runtime } = started({}, content);

    const program = await runtime.loadProgram(IDS.program);
    const blocks = program.modules[0].lessons.flatMap(
      (lesson) => lesson.blocks,
    );

    expect(
      blocks
        .filter((block) => block.kind === "placeholder")
        .map((block) => [block.placeholder_key, block.policy]),
    ).toEqual([
      ["input-rules", content.policies["input-rules"]],
      ["tool-list", null],
    ]);
    expect(
      blocks
        .filter((block) => block.kind !== "placeholder")
        .every((block) => block.policy === null),
    ).toBe(true);
    expect(program.stations).toEqual([
      expect.objectContaining({
        position: 1,
        kind: "module",
        module_id: IDS.module,
      }),
    ]);
    await expect(runtime.loadProgram("other")).rejects.toMatchObject({
      status: 404,
    });
  });

  test("completeModule rejects with AssessmentsOpenError until the exam passed, also in an earlier session", async () => {
    const first = started();

    await first.runtime.submitAssessment(
      IDS.exam,
      examAnswers(IDS.examA, IDS.examB),
    );
    const open = await first.runtime
      .completeModule(IDS.module)
      .catch((error: unknown) => error);
    expect(open).toBeInstanceOf(AssessmentsOpenError);
    expect((open as AssessmentsOpenError).assessments).toEqual([
      { id: IDS.exam, key: "exam-1", title: "Exam of module 1" },
    ]);

    await first.runtime.submitAssessment(IDS.exam, examAnswers());
    first.runtime.finish();

    const second = started(resumed(first.lms));
    await expect(
      second.runtime.completeModule(IDS.module),
    ).resolves.toBeUndefined();
    await expect(
      second.runtime.completeModule("module-9"),
    ).rejects.toMatchObject({ status: 404 });
  });

  test("loadState restores the progress of an earlier session, and attempts count on", async () => {
    const first = started();
    await first.runtime.saveState({
      ...emptyResumeState("short"),
      openedExplanations: [EXPLANATION],
    });
    await first.runtime.submitItem(IDS.choice, ANSWERS[IDS.choice].right);
    await first.runtime.submitAssessment(
      IDS.exam,
      examAnswers(IDS.examA, IDS.examB),
    );
    await first.runtime.submitAssessment(IDS.exam, examAnswers());
    await first.runtime.completeModule(IDS.module);
    first.runtime.finish();

    const second = started(resumed(first.lms));

    expect(await second.runtime.loadState()).toEqual({
      path: "short",
      openedExplanations: [EXPLANATION],
      visitedStations: [1],
      answeredItems: [IDS.choice],
      completedModules: [IDS.module],
      examOutcomes: { [IDS.exam]: "passed" },
      evidencedObjectives: ["m1-subject-exam", "m1-method-mixed"],
    });
    const attempt = await second.runtime.submitAssessment(
      IDS.exam,
      examAnswers(IDS.examA, IDS.examB),
    );
    expect(attempt).toMatchObject({ number: 3, outcome: "failed_errors" });
    expect((await second.runtime.loadState()).examOutcomes).toEqual({
      [IDS.exam]: "passed",
    });
  });

  test("saveState writes the path, explanations and completion of the player with the answers of the runtime, and nothing when they did not change", async () => {
    const { runtime, lms } = started();
    await runtime.submitItem(IDS.choice, ANSWERS[IDS.choice].right);
    lms.clear();

    const state = {
      ...emptyResumeState("short"),
      openedExplanations: [EXPLANATION, "block-unknown"],
    };
    await runtime.saveState(state);

    expect(lms.names()).toEqual(["LMSSetValue", "LMSCommit"]);
    expect(lms.calls.at(-1)?.args).toEqual([""]);
    expect(
      decodeSuspendData(
        scormContent().module,
        lms.values.get("cmi.suspend_data"),
      ),
    ).toMatchObject({
      path: "short",
      openedExplanations: [EXPLANATION],
      answeredItems: ["choice-practice"],
      correctItems: ["choice-practice"],
      completed: false,
    });

    lms.clear();
    await runtime.saveState(state);
    expect(lms.calls).toEqual([]);
  });

  test("a failing LMS leaves answers and attempts working, saveState rejects, and the next operation writes what was not stored", async () => {
    const { runtime, lms } = started();

    lms.fail("LMSSetValue");
    expect(
      await runtime.submitItem(IDS.choice, ANSWERS[IDS.choice].right),
    ).toMatchObject({ item_id: IDS.choice, correct: true });
    expect(
      await runtime.submitAssessment(IDS.exam, examAnswers(IDS.examB)),
    ).toMatchObject({ outcome: "passed" });
    await expect(runtime.saveState(emptyResumeState("full"))).rejects.toThrow();
    lms.fail("LMSSetValue", false);

    lms.fail("LMSCommit");
    await expect(
      runtime.saveState(emptyResumeState("short")),
    ).rejects.toThrow();
    lms.fail("LMSCommit", false);

    lms.clear();
    await runtime.submitItem(IDS.poll, ANSWERS[IDS.poll].right);
    expect(lms.values.get("cmi.objectives.0.status")).toBe("passed");
    expect(lms.values.get("cmi.objectives.1.status")).toBe("passed");
    expect(lms.values.get("cmi.core.lesson_status")).toBe("passed");
    expect(lms.values.get("cmi.core.score.raw")).toBe("1");
    expect(lms.names().at(-1)).toBe("LMSCommit");
  });

  test("an LMS call that throws counts as a failed call", async () => {
    const { api } = fakeScorm12();
    const runtime = new Scorm12Runtime(scormContent(), {
      ...api,
      LMSSetValue: () => {
        throw new Error("broken LMS");
      },
    });
    runtimes.push(runtime);
    runtime.start();

    await expect(
      runtime.submitItem(IDS.choice, ANSWERS[IDS.choice].right),
    ).resolves.toMatchObject({ correct: true });
    await expect(runtime.saveState(emptyResumeState("full"))).rejects.toThrow();
  });

  test("LMS calls before start() and after finish() are skipped, and saveState rejects after finish()", async () => {
    const { api, lms } = fakeScorm12();
    const runtime = new Scorm12Runtime(scormContent(), api);

    await runtime.submitItem(IDS.choice, ANSWERS[IDS.choice].right);
    await expect(
      runtime.saveState(emptyResumeState("short")),
    ).resolves.toBeUndefined();
    await runtime.completeModule(IDS.module).catch(() => undefined);
    runtime.finish();
    expect(lms.calls).toEqual([]);

    runtime.start();
    runtime.finish();
    lms.clear();

    await runtime.submitItem(IDS.slots, ANSWERS[IDS.slots].right);
    await runtime.submitAssessment(IDS.exam, examAnswers());
    await expect(runtime.saveState(emptyResumeState("full"))).rejects.toThrow();
    runtime.start();
    runtime.finish();
    expect(lms.calls).toEqual([]);
    expect((await runtime.loadState()).answeredItems).toEqual([
      IDS.choice,
      IDS.slots,
    ]);
  });

  test("after pagehide of a page that the browser keeps in its back/forward cache, saveState rejects without an LMS call", async () => {
    const { runtime, lms } = started();

    window.dispatchEvent(
      new PageTransitionEvent("pagehide", { persisted: true }),
    );
    expect(lms.names().at(-1)).toBe("LMSFinish");
    lms.clear();

    await expect(
      runtime.saveState({
        ...emptyResumeState("short"),
        openedExplanations: [EXPLANATION],
      }),
    ).rejects.toThrow();
    expect(lms.calls).toEqual([]);
  });
});
