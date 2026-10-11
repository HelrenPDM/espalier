import type { Answer, ItemFeedback, ItemView } from "../runtime";

/**
 * The user-perceived characters of `value`: grapheme clusters, as Elixir's
 * `String.length/1` counts them, so "é" counts once in composed and in
 * decomposed form. Without `Intl.Segmenter` it counts code points.
 */
export function graphemeCount(value: string): number {
  if (typeof Intl.Segmenter !== "function") return [...value].length;
  const segmenter = new Intl.Segmenter(undefined, { granularity: "grapheme" });
  return [...segmenter.segment(value)].length;
}

/**
 * The initials of a checklist drill count after trimming, 2 to 5 grapheme
 * clusters, as the evaluator of 0009 step 10 checks them.
 */
export function initialsValid(initials: string | undefined): boolean {
  const length = graphemeCount((initials ?? "").trim());
  return length >= 2 && length <= 5;
}

/**
 * Whether `answer` is complete for `item`: one option of a single choice or
 * a poll, at least one of a multiple choice, an option for every slot, a
 * category for every case, and for a checklist drill every required check
 * with initials of 2 to 5 characters.
 */
export function answerComplete(
  item: ItemView,
  answer: Answer | undefined,
): boolean {
  if (answer === undefined) return false;
  switch (item.kind) {
    case "single_choice":
    case "poll":
      return answer.options?.length === 1;
    case "multiple_choice":
      return (answer.options?.length ?? 0) > 0;
    case "slot_builder":
      return item.slots.every((slot) => Boolean(answer.slots?.[slot.key]));
    case "classification":
      return item.cases.every((entry) => Boolean(answer.cases?.[entry.key]));
    case "checklist_drill":
      return (
        item.checks.every(
          (check) => !check.required || answer.checks?.includes(check.key),
        ) && initialsValid(answer.initials)
      );
  }
}

/** The feedback entry of an option, slot, case or check. */
export function feedbackFor(
  feedback: ItemFeedback | null,
  key: string,
): ItemFeedback["option_feedback"][number] | undefined {
  return feedback?.option_feedback.find((entry) => entry.key === key);
}
