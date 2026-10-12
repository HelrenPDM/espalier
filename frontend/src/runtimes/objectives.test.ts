import { describe, expect, test } from "vitest";
import { gradeAttempt } from "../player/evaluate";
import {
  deriveObjectiveStates,
  type EvidenceState,
  type ObjectiveState,
} from "./objectives";
import { OBJECTIVE_KEYS, scormContent } from "./scormFixture";

/**
 * Task 0016 step 5: `deriveObjectiveStates` on the fixture of
 * `scormFixture.ts`, with one exam, practice items of several kinds, a
 * poll, a format with `attendance_counts: true` and an item that names an
 * objective of another module. Each test covers a rule of step 4.
 */
const content = scormContent();

const EMPTY: EvidenceState = {
  answeredItems: [],
  correctItems: [],
  assessments: {},
};

/** The state per objective key for `state`. */
function states(state: Partial<EvidenceState>): Record<string, ObjectiveState> {
  return Object.fromEntries(
    deriveObjectiveStates(content, { ...EMPTY, ...state }).map((entry) => [
      entry.key,
      entry.state,
    ]),
  );
}

describe("deriveObjectiveStates", () => {
  test("every objective starts incomplete, in position order", () => {
    expect(deriveObjectiveStates(content, EMPTY)).toEqual(
      OBJECTIVE_KEYS.map((key) => ({ key, state: "incomplete" })),
    );
  });

  test("a correct answer to a practice evidence item gives passed", () => {
    expect(
      states({
        answeredItems: ["choice-practice", "slots-practice"],
        correctItems: ["choice-practice", "slots-practice"],
      }),
    ).toEqual({
      "m1-subject-exam": "incomplete",
      "m1-method-mixed": "passed",
      "m1-method-practice": "passed",
      "m1-social-poll": "incomplete",
      "m1-self-format": "incomplete",
    });
  });

  test("an answer to a poll that names an objective leaves the objective incomplete", () => {
    expect(states({ answeredItems: ["poll-usage"] })["m1-social-poll"]).toBe(
      "incomplete",
    );
  });

  test("a failed attempt gives failed to an objective whose evidence items all belong to the exam and leaves one with an unanswered practice evidence item incomplete", () => {
    const after = states({
      assessments: { "exam-1": { attempts: 1, outcome: "failed_errors" } },
    });

    expect(after["m1-subject-exam"]).toBe("failed");
    expect(after["m1-method-mixed"]).toBe("incomplete");
  });

  test("wrong answers to every evidence item give failed, and a later correct answer gives passed", () => {
    const wrong = {
      answeredItems: [
        "choice-practice",
        "slots-practice",
        "drill-practice",
        "classify-other",
      ],
      assessments: { "exam-1": { attempts: 1, outcome: "failed_core" } },
    } satisfies Partial<EvidenceState>;
    const failed = states(wrong);
    expect(failed["m1-method-practice"]).toBe("failed");
    expect(failed["m1-method-mixed"]).toBe("failed");

    const corrected = states({
      ...wrong,
      correctItems: ["drill-practice", "choice-practice"],
    });
    expect(corrected["m1-method-practice"]).toBe("passed");
    expect(corrected["m1-method-mixed"]).toBe("passed");
  });

  test("a passed attempt gives passed to every objective that an item of the exam names, also when that item was answered wrongly", () => {
    const items = new Map(content.module.items.map((item) => [item.key, item]));
    const [exam] = content.module.assessments;
    const attempt = gradeAttempt(
      [
        { item: items.get("exam-a")!, answer: { options: ["yes"] } },
        { item: items.get("exam-b")!, answer: { options: ["c"] } },
      ],
      exam,
    );
    expect(attempt.results.map((result) => result.correct)).toEqual([
      true,
      false,
    ]);
    expect(attempt.outcome).toBe("passed");

    const after = states({
      assessments: { "exam-1": { attempts: 1, outcome: attempt.outcome } },
    });
    expect(after["m1-subject-exam"]).toBe("passed");
    expect(after["m1-method-mixed"]).toBe("passed");
    expect(after["m1-method-practice"]).toBe("incomplete");
  });

  test("an objective whose only evidence is the format stays incomplete", () => {
    const keys = content.module.items.map((item) => item.key);
    expect(
      states({
        answeredItems: keys,
        correctItems: keys,
        assessments: { "exam-1": { attempts: 1, outcome: "passed" } },
      })["m1-self-format"],
    ).toBe("incomplete");
  });

  test("the item that names an objective of another module adds no entry", () => {
    const entries = deriveObjectiveStates(content, {
      ...EMPTY,
      answeredItems: ["classify-other"],
      correctItems: ["classify-other"],
    });

    expect(entries.map((entry) => entry.key)).toEqual(OBJECTIVE_KEYS);
    expect(entries).toContainEqual({
      key: "m1-method-practice",
      state: "passed",
    });
  });
});
