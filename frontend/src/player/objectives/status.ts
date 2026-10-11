import type {
  ObjectiveStatus,
  ObjectiveView,
  ProgramView,
  ResumeState,
} from "../runtime";

/**
 * The status of `objective` in the current view (README section 7, rule
 * 15). It reads only its arguments.
 *
 * - `evidenced`: `state.evidencedObjectives` holds the key, or
 *   `state.examOutcomes` maps an exam of `program` to `passed` and that
 *   exam holds an item that the `evidence` of the objective names. The
 *   second condition shows a pass of the current visit before the runtime
 *   reports it, as 0009 step 13 counts a passed attempt.
 * - `practised`: `state.answeredItems` holds a practice item of `program`
 *   whose `objective_keys` hold the key. It records only that the learner
 *   answered such an item, because `answeredItems` holds no correctness.
 * - `open`: neither applies.
 */
export function objectiveStatus(
  objective: ObjectiveView,
  program: Pick<ProgramView, "modules">,
  state: Pick<
    ResumeState,
    "evidencedObjectives" | "examOutcomes" | "answeredItems"
  >,
): ObjectiveStatus {
  if (state.evidencedObjectives.includes(objective.key)) return "evidenced";

  const evidenceItems = new Set(
    objective.evidence
      .filter((entry) => entry.kind === "item")
      .map((entry) => entry.id),
  );
  const passedExamShows = program.modules.some((module) =>
    module.exams.some(
      (exam) =>
        Object.hasOwn(state.examOutcomes, exam.id) &&
        state.examOutcomes[exam.id] === "passed" &&
        exam.items.some((item) => evidenceItems.has(item.id)),
    ),
  );
  if (passedExamShows) return "evidenced";

  const answered = new Set(state.answeredItems);
  const practised = program.modules.some((module) =>
    module.practice_items.some(
      (item) =>
        answered.has(item.id) && item.objective_keys.includes(objective.key),
    ),
  );
  return practised ? "practised" : "open";
}

/** The number of `objectives` per status. */
export function statusCounts(
  objectives: ObjectiveView[],
  program: Pick<ProgramView, "modules">,
  state: Pick<
    ResumeState,
    "evidencedObjectives" | "examOutcomes" | "answeredItems"
  >,
): Record<ObjectiveStatus, number> {
  const counts: Record<ObjectiveStatus, number> = {
    evidenced: 0,
    practised: 0,
    open: 0,
  };
  for (const objective of objectives)
    counts[objectiveStatus(objective, program, state)] += 1;
  return counts;
}
