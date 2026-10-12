import type { ScormContent } from "./content";
import type { Scorm12Api } from "./lms";
import { ScormRuntime, type ScormDialect } from "./scorm";

const LESSON_STATUS = "cmi.core.lesson_status";
const EXIT = "cmi.core.exit";
/** The largest value of the score elements of SCORM 1.2. */
const SCORE_LIMIT = 100;

const pad = (value: number, length = 2) => String(value).padStart(length, "0");

/**
 * A duration as `CMITimespan` of SCORM 1.2 (`HH:MM:SS.SS`, hours with up to
 * four digits), capped at `9999:59:59.99`.
 */
export function cmiTimespan(milliseconds: number): string {
  const limit = 9999 * 360000 + 359999;
  const centiseconds = Math.min(
    limit,
    Math.max(0, Math.round(milliseconds / 10)),
  );
  const hours = Math.floor(centiseconds / 360000);
  const minutes = Math.floor(centiseconds / 6000) % 60;
  const seconds = Math.floor(centiseconds / 100) % 60;
  return `${pad(hours)}:${pad(minutes)}:${pad(seconds)}.${pad(centiseconds % 100)}`;
}

/** The SCORM 1.2 calls and data model elements of `ScormRuntime`. */
function scorm12Dialect(api: Scorm12Api): ScormDialect {
  return {
    initialize: () => api.LMSInitialize(""),
    // SCORM 1.2 reports a second initialization with the general error 101
    // only, which does not tell it apart from other failures.
    alreadyInitialized: () => false,
    terminate: () => api.LMSFinish(""),
    getValue: (element) => api.LMSGetValue(element),
    setValue: (element, value) => api.LMSSetValue(element, value),
    commit: () => api.LMSCommit(""),
    statusElements: [LESSON_STATUS],
    completedIn: (read) => read(LESSON_STATUS) === "completed",
    status({ success, completed }, read) {
      const current = read(LESSON_STATUS);
      const status =
        success ??
        (completed
          ? "completed"
          : current === "not attempted"
            ? "incomplete"
            : current);
      return [
        [LESSON_STATUS, status],
        [EXIT, status === "passed" || status === "completed" ? "" : "suspend"],
      ];
    },
    objective: (index, state) => [[`cmi.objectives.${index}.status`, state]],
    // The score elements hold 0 to 100, so a larger exam reports the
    // percentage of correct answers, rounded to two decimal places.
    score(raw, max) {
      const [value, limit] =
        max <= SCORE_LIMIT
          ? [raw, max]
          : [Math.round((raw / max) * 10000) / 100, SCORE_LIMIT];
      return [
        ["cmi.core.score.raw", String(value)],
        ["cmi.core.score.min", "0"],
        ["cmi.core.score.max", String(limit)],
      ];
    },
    sessionTime: (milliseconds) => [
      "cmi.core.session_time",
      cmiTimespan(milliseconds),
    ],
  };
}

/**
 * The runtime of a SCORM 1.2 package (task 0016, step 4), `ScormRuntime`
 * with the data model of SCORM 1.2:
 *
 * - `start()` calls `LMSInitialize("")` and sets `cmi.core.lesson_status`
 *   to `incomplete` when the LMS reports `not attempted`. It throws when
 *   `LMSInitialize` does not answer `"true"`.
 * - After an exam attempt it sets `cmi.core.score.raw`, `cmi.core.score.min`
 *   (0), `cmi.core.score.max` and `cmi.core.lesson_status` to `passed` or
 *   `failed`. The score is the number of correct answers of the number of
 *   exam items, and for an exam of more than 100 items the percentage of
 *   correct answers (two decimal places) of 100, because the score
 *   elements of SCORM 1.2 hold 0 to 100.
 * - The completion of the module sets `completed` while no exam of the
 *   module gives the status `passed` or `failed`, so a module without exam
 *   and a module whose exam has no attempt report `completed`. An exam
 *   outcome takes precedence; the suspend data then records the
 *   completion, which `cmi.core.lesson_status` does not show.
 * - `cmi.core.exit` is `suspend` while the status is `incomplete` or
 *   `failed`, and `""` once it is `passed` or `completed`.
 * - `cmi.objectives.n.status` holds the state of the objective: `passed`,
 *   `failed` or `incomplete`.
 * - `finish()`, which `pagehide` calls, sets `cmi.core.session_time`,
 *   commits and calls `LMSFinish("")`.
 *
 * Contract of the SCORM entry: `new Scorm12Runtime(content, api)`, then
 * `start()` before the player renders.
 */
export class Scorm12Runtime extends ScormRuntime {
  constructor(content: ScormContent, api: Scorm12Api) {
    super(content, scorm12Dialect(api));
  }
}
