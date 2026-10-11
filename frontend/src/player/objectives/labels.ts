import type { ObjectiveStatus, ObjectiveView } from "../runtime";

export type Area = ObjectiveView["area"];
export type Depth = ObjectiveView["depth"];

/**
 * Returns `list` unchanged. The call compiles only when `list` names every
 * member of `All`, so `tsc` fails when the API schema gains an area, a
 * depth or a status that a list lacks.
 */
const complete =
  <All extends string>() =>
  <const List extends readonly All[]>(
    list: List & ([All] extends [List[number]] ? unknown : never),
  ): List =>
    list;

/** The four CORE competence areas, in the order of the panel and the summary. */
export const AREAS = complete<Area>()(["subject", "method", "self", "social"]);

/** The three depths of an objective. */
export const DEPTHS = complete<Depth>()(["know", "apply", "judge"]);

/** The three statuses of an objective in the player. */
export const STATUSES = complete<ObjectiveStatus>()([
  "evidenced",
  "practised",
  "open",
]);

export const areaKey = (area: Area) => `objectives.area.${area}` as const;
export const depthKey = (depth: Depth) => `objectives.depth.${depth}` as const;
export const statusKey = (status: ObjectiveStatus) =>
  `objectives.status.${status}` as const;
