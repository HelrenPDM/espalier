import type { ScormContent } from "./content";
import type { Scorm2004Api } from "./lms";
import type { ObjectiveState } from "./objectives";
import { ScormRuntime, type ScormDialect } from "./scorm";

const COMPLETION_STATUS = "cmi.completion_status";
const SUCCESS_STATUS = "cmi.success_status";
const EXIT = "cmi.exit";
/** The error code of SCORM 2004 for an `Initialize` of an initialized session. */
const ALREADY_INITIALIZED = "103";

/**
 * The `success_status` and `completion_status` of an entry of
 * `cmi.objectives` for each objective state.
 */
export const OBJECTIVE_STATUS_2004: Record<
  ObjectiveState,
  { success_status: string; completion_status: string }
> = {
  passed: { success_status: "passed", completion_status: "completed" },
  failed: { success_status: "failed", completion_status: "completed" },
  incomplete: { success_status: "unknown", completion_status: "incomplete" },
};

/**
 * A duration as `timeinterval (second,10,2)` of SCORM 2004, an ISO 8601
 * duration with hours, minutes and seconds to the hundredth, such as
 * `PT1H2M3.5S`.
 */
export function timeInterval(milliseconds: number): string {
  const centiseconds = Math.max(0, Math.round(milliseconds / 10));
  const hours = Math.floor(centiseconds / 360000);
  const minutes = Math.floor(centiseconds / 6000) % 60;
  const seconds = (centiseconds % 6000) / 100;
  return `PT${hours}H${minutes}M${seconds}S`;
}

/**
 * The value of `cmi.score.scaled`: `raw / max` with at most seven decimal
 * places, in [0, 1].
 */
function scaled(raw: number, max: number): string {
  return String(Math.round((raw / max) * 1e7) / 1e7);
}

/** The SCORM 2004 calls and data model elements of `ScormRuntime`. */
function scorm2004Dialect(api: Scorm2004Api): ScormDialect {
  return {
    initialize: () => api.Initialize(""),
    alreadyInitialized: () =>
      String(api.GetLastError()) === ALREADY_INITIALIZED,
    terminate: () => api.Terminate(""),
    getValue: (element) => api.GetValue(element),
    setValue: (element, value) => api.SetValue(element, value),
    commit: () => api.Commit(""),
    statusElements: [COMPLETION_STATUS, SUCCESS_STATUS],
    completedIn: (read) => read(COMPLETION_STATUS) === "completed",
    status({ success, completed }, read) {
      const current = read(COMPLETION_STATUS);
      const completion = completed
        ? "completed"
        : current === "not attempted" || current === "unknown"
          ? "incomplete"
          : current;
      return [
        [COMPLETION_STATUS, completion],
        [SUCCESS_STATUS, success ?? read(SUCCESS_STATUS)],
        [EXIT, completion === "completed" ? "normal" : "suspend"],
      ];
    },
    objective: (index, state) => [
      [
        `cmi.objectives.${index}.success_status`,
        OBJECTIVE_STATUS_2004[state].success_status,
      ],
      [
        `cmi.objectives.${index}.completion_status`,
        OBJECTIVE_STATUS_2004[state].completion_status,
      ],
    ],
    // An exam without items has no scaled score.
    score: (raw, max) => [
      ["cmi.score.raw", String(raw)],
      ["cmi.score.min", "0"],
      ["cmi.score.max", String(max)],
      ...(max > 0 ? [["cmi.score.scaled", scaled(raw, max)] as const] : []),
    ],
    sessionTime: (milliseconds) => [
      "cmi.session_time",
      timeInterval(milliseconds),
    ],
  };
}

/**
 * The runtime of a SCORM 2004 4th edition package (task 0016, step 4),
 * `ScormRuntime` with the data model of SCORM 2004:
 *
 * - `start()` calls `Initialize("")` and sets `cmi.completion_status` to
 *   `incomplete` when the LMS reports `not attempted` or `unknown`. It
 *   throws when `Initialize` does not answer `"true"`, unless
 *   `GetLastError()` then reports 103 (already initialized).
 * - After an exam attempt it sets `cmi.score.raw`, `cmi.score.min` (0),
 *   `cmi.score.max`, `cmi.score.scaled` (raw divided by max) and
 *   `cmi.success_status` to `passed` or `failed`. A module without exam
 *   leaves `cmi.success_status` `unknown`. The completion of the module
 *   sets `cmi.completion_status` to `completed`, with or without exam.
 * - `cmi.exit` is `suspend` until the completion status is `completed`,
 *   and `normal` afterwards.
 * - `cmi.objectives.n.success_status` and
 *   `cmi.objectives.n.completion_status` hold the state of the objective
 *   (`OBJECTIVE_STATUS_2004`).
 * - `finish()`, which `pagehide` calls, sets `cmi.session_time`, commits
 *   and calls `Terminate("")`.
 *
 * Contract of the SCORM entry: `new Scorm2004Runtime(content, api)`, then
 * `start()` before the player renders.
 */
export class Scorm2004Runtime extends ScormRuntime {
  constructor(content: ScormContent, api: Scorm2004Api) {
    super(content, scorm2004Dialect(api));
  }
}
