import { describe, expect, test } from "vitest";
import fixtureData from "../../../test/fixtures/evaluator_cases.json";
import {
  evaluate,
  gradeAttempt,
  passRule,
  validateAnswer,
  type EvaluableItem,
  type EvaluationContext,
} from "./evaluate";
import type { Answer } from "./runtime";

/**
 * Task 0015 step 9: the TypeScript port of `Espalier.Learning.Evaluator`
 * and `Espalier.Learning.PassRule` passes the shared fixture
 * `test/fixtures/evaluator_cases.json`, which
 * `test/espalier/learning/evaluator_parity_test.exs` also reads, so both
 * implementations return the same results. Results are compared after a
 * JSON round trip, as the ExUnit test compares them.
 */
interface ItemCase {
  name: string;
  item: string;
  answer: Answer;
  valid: boolean;
  expected?: unknown;
}

interface AttemptCase {
  name: string;
  assessment: { max_wrong: number; core_required: boolean };
  items: string[];
  answers: Record<string, Answer>;
  expected: unknown;
}

interface Fixture {
  context: EvaluationContext;
  items: Record<string, EvaluableItem>;
  cases: ItemCase[];
  attempts: AttemptCase[];
}

const fixture = fixtureData as unknown as Fixture;

const json = (value: unknown): unknown => JSON.parse(JSON.stringify(value));

const itemOf = (key: string): EvaluableItem => {
  const item = fixture.items[key];
  if (item === undefined) throw new Error(`fixture lacks item ${key}`);
  return item;
};

describe("the shared fixture", () => {
  test("holds at least 30 item cases over every item kind and the pass rule", () => {
    expect(fixture.cases.length).toBeGreaterThanOrEqual(30);
    expect(
      new Set(fixture.cases.map((entry) => itemOf(entry.item).kind)),
    ).toEqual(
      new Set([
        "single_choice",
        "multiple_choice",
        "slot_builder",
        "classification",
        "checklist_drill",
        "poll",
      ]),
    );
    expect(
      new Set(
        fixture.attempts.map(
          (attempt) => (attempt.expected as { outcome: string }).outcome,
        ),
      ),
    ).toEqual(new Set(["passed", "failed_core", "failed_errors"]));
  });
});

describe("evaluate and validateAnswer", () => {
  test.each(fixture.cases.map((entry, index) => [index + 1, entry] as const))(
    "case %i",
    (_index, entry) => {
      const item = itemOf(entry.item);
      expect(validateAnswer(item, entry.answer), entry.name).toBe(entry.valid);
      if (entry.valid)
        expect(
          json(evaluate(item, entry.answer, fixture.context)),
          entry.name,
        ).toEqual(entry.expected);
    },
  );
});

describe("gradeAttempt and passRule", () => {
  test.each(
    fixture.attempts.map((attempt, index) => [index + 1, attempt] as const),
  )("attempt %i", (_index, attempt) => {
    const entries = attempt.items.map((key) => ({
      item: itemOf(key),
      answer: attempt.answers[key],
      context: fixture.context,
    }));
    for (const { item, answer } of entries)
      expect(validateAnswer(item, answer), attempt.name).toBe(true);

    const graded = gradeAttempt(entries, attempt.assessment);
    expect(
      json({
        correct: graded.results.map((result) => result.correct),
        wrong_count: graded.wrong_count,
        core_failed: graded.core_failed,
        outcome: graded.outcome,
      }),
      attempt.name,
    ).toEqual(attempt.expected);
  });

  test("a max_wrong that is not an integer throws", () => {
    expect(() => passRule([], { max_wrong: Number.NaN })).toThrow(TypeError);
    expect(() => passRule([], { max_wrong: 1.5 })).toThrow(TypeError);
  });
});

describe("evaluate without the module", () => {
  test("names no rules and reveals no lessons", () => {
    const result = evaluate(itemOf("sc-capital"), { options: ["a"] });
    expect(result.correct).toBe(false);
    expect(result.rules).toEqual([]);
    expect(result.reveals).toEqual([]);
  });

  test("reads no member of the prototype of an answer map", () => {
    const item: EvaluableItem = {
      key: "slots",
      kind: "slot_builder",
      config: {
        slots: [
          {
            key: "constructor",
            label: "Constructor",
            options: [{ key: "a", label: "A", correct: true, feedback: null }],
          },
        ],
      },
    };
    expect(validateAnswer(item, { slots: {} })).toBe(true);
    expect(evaluate(item, { slots: {} }).option_feedback).toEqual([
      { key: "constructor", choice: null, correct: false, feedback: null },
    ]);
  });
});
