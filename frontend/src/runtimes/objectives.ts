import type { ExamOutcome } from "../player/runtime";
import type { ScormContent } from "./content";
import type { PayloadAssessment, PayloadItem } from "./standalone";

/**
 * The state of a learning objective in `cmi.objectives` of a SCORM package
 * (task 0016, step 4). The runtimes map it to the status values of SCORM
 * 1.2 and SCORM 2004.
 */
export type ObjectiveState = "passed" | "failed" | "incomplete";

/** An objective of the module with its state. */
export interface ObjectiveEntry {
  key: string;
  state: ObjectiveState;
}

/** The attempts of one assessment of the module. */
export interface AssessmentProgress {
  /** The number of attempts, 0 before the first. */
  attempts: number;
  /**
   * The outcome in the form of `GET /api/me/progress`: `passed` when any
   * attempt passed, otherwise the outcome of the latest attempt, and `null`
   * before the first attempt.
   */
  outcome: ExamOutcome | null;
}

/**
 * The progress of a learner in the module of a package that the objective
 * states derive from: the answers of this session and of the sessions that
 * the suspend data restores.
 */
export interface EvidenceState {
  /** The keys of the practice items with a submitted answer. */
  readonly answeredItems: readonly string[];
  /**
   * The keys of the practice items with a correct answer. An item stays in
   * the list once any of its answers was correct.
   */
  readonly correctItems: readonly string[];
  /**
   * The attempts per assessment key. A missing key counts as an assessment
   * without an attempt.
   */
  readonly assessments: Readonly<Record<string, AssessmentProgress>>;
}

/** The progress of `key` in `assessments`, without the members of its prototype. */
function progressOf(
  assessments: EvidenceState["assessments"],
  key: string,
): AssessmentProgress | undefined {
  return Object.hasOwn(assessments, key) ? assessments[key] : undefined;
}

/**
 * The state of every objective of `content.module` in position order (task
 * 0016, step 4). It reads only its arguments.
 *
 * The evidence items of an objective follow the evidence rule of 0008 step
 * 13, limited to the items of the module: every item that names the
 * objective and is listed by an assessment, and every other item that names
 * it and whose kind has a correct answer (every kind except `poll`).
 * Companion formats provide no evidence in a package, because attendance is
 * recorded on the platform only. An exam item is an item that an assessment
 * of kind `exam` lists; every other item of the module is a practice item.
 *
 * - `passed`: an assessment that lists an evidence item has a passed
 *   attempt, or a practice evidence item has a correct answer. This is the
 *   rule of `Espalier.Learning.ObjectiveStatus.derive/2` for `evidenced`
 *   with an empty set of attended formats, so a passed attempt also counts
 *   for an objective whose item was answered wrongly within `max_wrong`.
 * - `failed`: not `passed`, at least one evidence item, and every evidence
 *   item has an answer. A practice item has an answer once the learner
 *   submitted one, and an exam item once an assessment that lists it has an
 *   attempt.
 * - `incomplete`: every other objective, also one without an evidence item
 *   in the module.
 *
 * An item that names an objective of another module adds no entry, because
 * the result holds the objectives of `content.module` only.
 */
export function deriveObjectiveStates(
  content: Pick<ScormContent, "module">,
  state: EvidenceState,
): ObjectiveEntry[] {
  const { module } = content;
  const listing = new Map<string, PayloadAssessment[]>();
  for (const assessment of module.assessments)
    for (const key of assessment.items)
      listing.set(key, [...(listing.get(key) ?? []), assessment]);
  const examItems = new Set(
    module.assessments
      .filter((assessment) => assessment.kind === "exam")
      .flatMap((assessment) => assessment.items),
  );
  const answered = new Set(state.answeredItems);
  const correct = new Set(state.correctItems);

  const listedBy = (item: PayloadItem) => listing.get(item.key) ?? [];
  const passed = (item: PayloadItem) =>
    listedBy(item).some(
      (assessment) =>
        progressOf(state.assessments, assessment.key)?.outcome === "passed",
    ) ||
    (!examItems.has(item.key) && correct.has(item.key));
  const hasAnswer = (item: PayloadItem) =>
    examItems.has(item.key)
      ? listedBy(item).some(
          (assessment) =>
            (progressOf(state.assessments, assessment.key)?.attempts ?? 0) > 0,
        )
      : answered.has(item.key);

  return module.objectives.map(({ key }): ObjectiveEntry => {
    const evidence = module.items.filter(
      (item) =>
        item.objectives.includes(key) &&
        (listing.has(item.key) || item.kind !== "poll"),
    );
    if (evidence.some(passed)) return { key, state: "passed" };
    if (evidence.length > 0 && evidence.every(hasAnswer))
      return { key, state: "failed" };
    return { key, state: "incomplete" };
  });
}
