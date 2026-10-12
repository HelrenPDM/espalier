import type { Answer, ExamOutcome, ItemFeedback, ItemView } from "./runtime";

/**
 * The evaluation of answers in the browser: a port of
 * `Espalier.Learning.Evaluator` and `Espalier.Learning.PassRule` (task 0009)
 * for the runtimes that work without the server, `StandaloneRuntime` of the
 * admin preview (task 0015) and the SCORM runtimes (task 0016). The module
 * holds no UI code.
 *
 * It reads items in the shape of the normalized payload of a content pack
 * (task 0008, step 9): `options` with `correct` and `feedback`, the free
 * `config` of a slot builder, a classification or a checklist drill, the
 * rule numbers of `rules` and the lesson keys of `reveals`. Answers have the
 * shape `Answer` of the API. The shared fixture
 * `test/fixtures/evaluator_cases.json` holds cases that this module and the
 * Elixir modules both pass.
 *
 * | Kind | Members | Correct when |
 * |---|---|---|
 * | `single_choice`, `multiple_choice` | `options` | the chosen set equals the set of correct options |
 * | `slot_builder` | `slots` | every slot has an option flagged correct |
 * | `classification` | `cases` | the mapping equals the expected mapping |
 * | `checklist_drill` | `checks`, `initials` | every required check is set and the trimmed initials have 2 to 5 characters |
 * | `poll` | `options` | never; `correct` is `null` |
 */

export type ItemKind = ItemView["kind"];

/** An option of a choice item, a poll or a slot, with its answer key. */
export interface PayloadOption {
  key: string;
  label?: string;
  correct: boolean | null;
  feedback: string | null;
}

/** The members of a payload item that the evaluation reads. */
export interface EvaluableItem {
  key: string;
  kind: ItemKind;
  /** A wrong core item fails an exam attempt. */
  core?: boolean | null;
  /** The numbers of the rules of the item's module that the item names. */
  rules?: number[];
  /** The keys of the lessons of the item's module that a wrong answer reveals. */
  reveals?: string[];
  options?: PayloadOption[];
  /** The free map of a slot builder, a classification or a checklist drill. */
  config?: unknown;
}

/** A rule of the item's module, as the result names it. */
export interface RuleEntry {
  id: string;
  number: number;
  statement: string;
  action: string;
}

/** A lesson of the item's module, by key, with the id that the result names. */
export interface LessonEntry {
  id: string;
  key: string;
  position: number;
}

/**
 * The module of an item: its rules and its lessons, which resolve the rule
 * numbers and the lesson keys of the item into the entries of the result.
 */
export interface EvaluationContext {
  rules: readonly RuleEntry[];
  lessons: readonly LessonEntry[];
}

export type OptionFeedback = ItemFeedback["option_feedback"][number];

/** The result of `evaluate`: an `ItemFeedback` without `item_id`. */
export interface Evaluation {
  correct: boolean | null;
  option_feedback: OptionFeedback[];
  rules: RuleEntry[];
  reveals: string[];
}

const EMPTY_CONTEXT: EvaluationContext = { rules: [], lessons: [] };

type AnswerMember = keyof Answer;

const MEMBERS: readonly AnswerMember[] = [
  "options",
  "slots",
  "cases",
  "checks",
  "initials",
];

const KIND_MEMBERS: Record<ItemKind, readonly AnswerMember[]> = {
  single_choice: ["options"],
  multiple_choice: ["options"],
  poll: ["options"],
  slot_builder: ["slots"],
  classification: ["cases"],
  checklist_drill: ["checks", "initials"],
};

type Entry = Record<string, unknown>;

const isRecord = (value: unknown): value is Entry =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/** The map entries of the list `key` of `map`; anything else is empty. */
function listAt(map: unknown, key: string): Entry[] {
  if (!isRecord(map)) return [];
  const value = map[key];
  return Array.isArray(value) ? value.filter(isRecord) : [];
}

/** The member `key` of a map, without the members of its prototype. */
function own(map: unknown, key: unknown): unknown {
  if (!isRecord(map) || typeof key !== "string" || !Object.hasOwn(map, key))
    return undefined;
  return map[key];
}

const absent = (value: unknown) => value === undefined || value === null;

/** `undefined` as `null`, as Elixir reads a missing member as `nil`. */
const orNull = <T>(value: T | undefined): T | null =>
  value === undefined ? null : value;

/**
 * True when every member of `chosen` is one of `keys` and no member repeats
 * (`distinct_subset?/2` of the evaluator).
 */
function distinctSubset(chosen: unknown, keys: ReadonlySet<unknown>): boolean {
  if (!Array.isArray(chosen)) return false;
  return (
    chosen.every((key) => keys.has(key)) &&
    new Set(chosen).size === chosen.length
  );
}

function keysValid(item: EvaluableItem, answer: Answer): boolean {
  switch (item.kind) {
    case "single_choice":
    case "multiple_choice":
    case "poll":
      return distinctSubset(
        answer.options,
        new Set((item.options ?? []).map((option) => option.key)),
      );
    case "slot_builder": {
      const chosen: unknown = answer.slots;
      if (!isRecord(chosen)) return false;
      const slots = new Map<unknown, Set<unknown>>();
      for (const slot of listAt(item.config, "slots"))
        slots.set(
          slot.key,
          new Set(listAt(slot, "options").map((option) => option.key)),
        );
      return Object.entries(chosen).every(
        ([slot, option]) =>
          typeof option === "string" && (slots.get(slot)?.has(option) ?? false),
      );
    }
    case "classification": {
      const chosen: unknown = answer.cases;
      if (!isRecord(chosen)) return false;
      const cases = new Set(
        listAt(item.config, "cases").map((entry) => entry.key),
      );
      const categories = new Set(
        listAt(item.config, "categories").map((entry) => entry.key),
      );
      return Object.entries(chosen).every(
        ([caseKey, category]) => cases.has(caseKey) && categories.has(category),
      );
    }
    case "checklist_drill":
      return (
        distinctSubset(
          answer.checks,
          new Set(listAt(item.config, "checks").map((check) => check.key)),
        ) && typeof answer.initials === "string"
      );
  }
}

/**
 * True when `answer` uses exactly the members of the item's kind and names
 * only keys of the item (`Evaluator.validate/2`). The platform answers an
 * answer that fails this check with 422 `invalid_answer`.
 */
export function validateAnswer(item: EvaluableItem, answer: Answer): boolean {
  if (!isRecord(answer)) return false;
  const allowed = KIND_MEMBERS[item.kind];
  const extra = MEMBERS.some(
    (member) => !allowed.includes(member) && !absent(answer[member]),
  );
  const missing = allowed.some((member) => absent(answer[member]));
  return !extra && !missing && keysValid(item, answer);
}

// The code points of the Unicode property White_Space, which Elixir's
// `String.trim/1` removes. The `trim()` of JavaScript differs: it keeps
// U+0085 and removes U+FEFF.
const WHITE_SPACE = new Set([
  0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x20, 0x85, 0xa0, 0x1680, 0x2000, 0x2001,
  0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200a,
  0x2028, 0x2029, 0x202f, 0x205f, 0x3000,
]);

/** `value` without leading and trailing White_Space, as `String.trim/1` gives it. */
function trimWhiteSpace(value: string): string {
  let start = 0;
  let end = value.length;
  while (start < end && WHITE_SPACE.has(value.charCodeAt(start))) start += 1;
  while (end > start && WHITE_SPACE.has(value.charCodeAt(end - 1))) end -= 1;
  return value.slice(start, end);
}

/** The number of grapheme clusters, as Elixir's `String.length/1` counts. */
function graphemeLength(value: string): number {
  if (typeof Intl !== "undefined" && "Segmenter" in Intl)
    return Array.from(
      new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(value),
    ).length;
  return [...value].length;
}

/** The initials of a checklist drill count with 2 to 5 characters after trimming. */
function initialsValid(initials: unknown): boolean {
  if (typeof initials !== "string") return false;
  const length = graphemeLength(trimWhiteSpace(initials));
  return length >= 2 && length <= 5;
}

function grade(
  item: EvaluableItem,
  answer: Answer,
): { correct: boolean | null; feedback: OptionFeedback[] } {
  switch (item.kind) {
    case "poll":
      return { correct: null, feedback: [] };
    case "single_choice":
    case "multiple_choice": {
      const chosen = new Set<unknown>(
        Array.isArray(answer.options)
          ? answer.options
          : absent(answer.options)
            ? []
            : [answer.options],
      );
      const options = item.options ?? [];
      const correctKeys = new Set(
        options.filter((option) => option.correct).map((option) => option.key),
      );
      const feedback = options.map((option) => ({
        key: option.key,
        selected: chosen.has(option.key),
        correct: option.correct === true,
        feedback: orNull(option.feedback),
      }));
      const correct =
        chosen.size === correctKeys.size &&
        [...chosen].every((key) => correctKeys.has(key as string));
      return { correct, feedback };
    }
    case "slot_builder": {
      const chosen: unknown = answer.slots ?? {};
      const feedback = listAt(item.config, "slots").map((slot) => {
        const choice = orNull(own(chosen, slot.key));
        const option = listAt(slot, "options").find(
          (entry) => orNull(entry.key) === choice,
        );
        return {
          key: orNull(slot.key) as string,
          choice: choice as string | null,
          correct: option !== undefined && option.correct === true,
          feedback:
            option === undefined
              ? null
              : (orNull(option.feedback) as string | null),
        };
      });
      return {
        correct:
          feedback.length > 0 && feedback.every((entry) => entry.correct),
        feedback,
      };
    }
    case "classification": {
      const chosen: unknown = answer.cases ?? {};
      const expectedMap = isRecord(item.config)
        ? (item.config.expected ?? {})
        : {};
      const feedback = listAt(item.config, "cases").map((entry) => {
        const choice = orNull(own(chosen, entry.key));
        const expected = orNull(own(expectedMap, entry.key));
        return {
          key: orNull(entry.key) as string,
          choice: choice as string | null,
          expected: expected as string | null,
          correct: choice !== null && choice === expected,
          feedback: orNull(entry.feedback) as string | null,
        };
      });
      return {
        correct:
          feedback.length > 0 && feedback.every((entry) => entry.correct),
        feedback,
      };
    }
    case "checklist_drill": {
      const chosen = new Set<unknown>(
        Array.isArray(answer.checks)
          ? answer.checks
          : absent(answer.checks)
            ? []
            : [answer.checks],
      );
      const feedback = listAt(item.config, "checks").map((check) => {
        const selected = chosen.has(check.key);
        const required = check.required === true;
        return {
          key: orNull(check.key) as string,
          selected,
          required,
          correct: selected || !required,
        };
      });
      return {
        correct:
          feedback.every((entry) => entry.correct) &&
          initialsValid(answer.initials),
        feedback,
      };
    }
  }
}

/**
 * Evaluates an answer that passes `validateAnswer` (`Evaluator.evaluate/2`).
 *
 * The result holds `correct` (`null` for a poll), `option_feedback` (for a
 * choice item every option in order with `key`, `selected`, `correct` and
 * `feedback`; for a slot builder every slot with `key`, `choice`, `correct`
 * and the `feedback` of the chosen option; for a classification every case
 * with `key`, `choice`, `expected`, `correct` and its `feedback`; for a
 * checklist drill every check with `key`, `selected`, `required` and
 * `correct`; for a poll nothing), `rules` (the rules of `context` that the
 * item names, by number) and `reveals` (the ids of the lessons of `context`
 * that the item names in `reveals`, by position and key, only when
 * `correct` is `false`).
 */
export function evaluate(
  item: EvaluableItem,
  answer: Answer,
  context: EvaluationContext = EMPTY_CONTEXT,
): Evaluation {
  const { correct, feedback } = grade(item, answer);
  const numbers = new Set(item.rules ?? []);
  const rules = context.rules
    .filter((rule) => numbers.has(rule.number))
    .sort((a, b) => a.number - b.number)
    .map(({ id, number, statement, action }) => ({
      id,
      number,
      statement,
      action,
    }));
  const revealKeys = new Set(item.reveals ?? []);
  const reveals =
    correct === false
      ? context.lessons
          .filter((lesson) => revealKeys.has(lesson.key))
          .sort((a, b) =>
            a.position !== b.position
              ? a.position - b.position
              : a.key < b.key
                ? -1
                : a.key > b.key
                  ? 1
                  : 0,
          )
          .map((lesson) => lesson.id)
      : [];
  return { correct, option_feedback: feedback, rules, reveals };
}

/** The members of an item result that the pass rule reads. */
export interface GradedResult {
  core?: boolean | null;
  correct: boolean | null;
}

/** The number of wrong answers; only `false` counts as wrong. */
export function wrongCount(results: readonly GradedResult[]): number {
  return results.filter((result) => result.correct === false).length;
}

/** True when a core item is wrong. */
export function coreFailed(results: readonly GradedResult[]): boolean {
  return results.some(
    (result) => result.core === true && result.correct === false,
  );
}

/**
 * The pass rule of an exam attempt (`PassRule.evaluate/2`, README section
 * 7, rule 5): `failed_core` when a core item is wrong, whatever
 * `core_required` says, `failed_errors` when more than `max_wrong` answers
 * are wrong, and `passed` otherwise. A `max_wrong` that is not an integer
 * throws instead of letting every attempt pass.
 */
export function passRule(
  results: readonly GradedResult[],
  assessment: { max_wrong: number },
): ExamOutcome {
  if (!Number.isInteger(assessment.max_wrong))
    throw new TypeError("max_wrong must be an integer");
  if (coreFailed(results)) return "failed_core";
  if (wrongCount(results) > assessment.max_wrong) return "failed_errors";
  return "passed";
}

/** An exam item with its answer and its module. */
export interface AttemptEntry {
  item: EvaluableItem;
  answer: Answer;
  context?: EvaluationContext;
}

/** The evaluation of an exam attempt, as `Espalier.Learning.submit_attempt/3` computes it. */
export interface AttemptGrade {
  results: Evaluation[];
  wrong_count: number;
  core_failed: boolean;
  outcome: ExamOutcome;
}

/**
 * Evaluates every item of an attempt in exam order and applies the pass
 * rule, with `core` of each item.
 */
export function gradeAttempt(
  entries: readonly AttemptEntry[],
  assessment: { max_wrong: number },
): AttemptGrade {
  const results = entries.map(({ item, answer, context }) =>
    evaluate(item, answer, context),
  );
  const graded = entries.map(({ item }, index) => ({
    core: item.core === true,
    correct: results[index].correct,
  }));
  return {
    results,
    wrong_count: wrongCount(graded),
    core_failed: coreFailed(graded),
    outcome: passRule(graded, assessment),
  };
}
