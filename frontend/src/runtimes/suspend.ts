import type { ExamOutcome, Path } from "../player/runtime";
import type { AssessmentProgress, EvidenceState } from "./objectives";
import { payloadIds, type PayloadModule } from "./standalone";

/**
 * The resume state of a SCORM package in `cmi.suspend_data` (task 0016,
 * step 4): the path, the opened explanations, the module completion and the
 * evidence state of `deriveObjectiveStates`.
 */
export interface SuspendState extends EvidenceState {
  path: Path;
  /** Block ids (`payloadIds.block`) of the opened explanations. */
  readonly openedExplanations: readonly string[];
  /**
   * The learner completed the module. A SCORM 1.2 module whose exams give
   * an outcome reports `passed` or `failed` in `cmi.core.lesson_status`,
   * so its completion cannot be read back from the LMS.
   */
  completed: boolean;
}

/** The limit of `cmi.suspend_data` in SCORM 1.2 (README section 11). */
export const SUSPEND_DATA_LIMIT = 4096;

const VERSION = "2";
const SEPARATOR = ".";
/** The fields before the assessments. */
const HEAD_FIELDS = 7;
/** Six bits per character, in the order of base64url (RFC 4648 section 5). */
const DIGITS =
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
/** The offset basis and the prime of the 32-bit FNV-1a hash. */
const FNV_OFFSET = 0x811c9dc5;
const FNV_PRIME = 0x01000193;
const PATHS: Record<Path, string> = { full: "f", short: "s" };
const OUTCOMES: Record<ExamOutcome, string> = {
  passed: "p",
  failed_core: "c",
  failed_errors: "e",
};

const byKey = (a: { key: string }, b: { key: string }) =>
  a.key < b.key ? -1 : a.key > b.key ? 1 : 0;

/**
 * The block ids of the explanations of `module`, in the order of their bits:
 * lessons by position (then key, as the module view orders them), and the
 * blocks of a lesson in order.
 */
export function explanationBlockIds(module: PayloadModule): string[] {
  return [...module.lessons]
    .sort((a, b) =>
      a.position !== b.position ? a.position - b.position : byKey(a, b),
    )
    .flatMap((lesson) =>
      lesson.blocks.flatMap((block, index) =>
        block.kind === "explanation"
          ? [payloadIds.block(module.number, lesson.key, index)]
          : [],
      ),
    );
}

/**
 * The layout fingerprint of `module`, which binds the suspend data to the
 * lists that its bitsets and assessment fields refer to: the 32-bit FNV-1a
 * hash of the UTF-8 bytes of the item keys, the explanation block ids
 * (`explanationBlockIds`) and the assessment keys, each list in order with
 * its members joined by `,` and the three lists joined by `;`. The hash is
 * written as six base64url digits, the most significant first.
 */
function fingerprint(module: PayloadModule): string {
  const layout = [
    module.items.map((item) => item.key),
    explanationBlockIds(module),
    module.assessments.map((assessment) => assessment.key),
  ]
    .map((list) => list.join(","))
    .join(";");
  let hash = FNV_OFFSET;
  for (const byte of new TextEncoder().encode(layout))
    hash = Math.imul(hash ^ byte, FNV_PRIME);
  return [30, 24, 18, 12, 6, 0]
    .map((shift) => DIGITS[(hash >>> shift) & 63])
    .join("");
}

/** The bits of the members of `names` that `chosen` holds, trailing zeros cut. */
function encodeBits(
  names: readonly string[],
  chosen: readonly string[],
): string {
  const set = new Set(chosen);
  const values: number[] = [];
  names.forEach((name, index) => {
    const digit = Math.floor(index / 6);
    values[digit] ??= 0;
    if (set.has(name)) values[digit] |= 1 << (index % 6);
  });
  while (values.length > 0 && values[values.length - 1] === 0) values.pop();
  return values.map((value) => DIGITS[value]).join("");
}

/**
 * The members of `names` whose bits `field` sets, in the order of `names`,
 * or `null` for a character outside the alphabet and for a set bit beyond
 * `names`.
 */
function decodeBits(names: readonly string[], field: string): string[] | null {
  if (field.length > Math.ceil(names.length / 6)) return null;
  const chosen: string[] = [];
  for (let digit = 0; digit < field.length; digit += 1) {
    const value = DIGITS.indexOf(field[digit]);
    if (value === -1) return null;
    for (let bit = 0; bit < 6; bit += 1) {
      if ((value & (1 << bit)) === 0) continue;
      const name = names[digit * 6 + bit];
      if (name === undefined) return null;
      chosen.push(name);
    }
  }
  return chosen;
}

function encodeAssessment(progress: AssessmentProgress | undefined): string {
  if (
    progress === undefined ||
    progress.outcome === null ||
    !Number.isSafeInteger(progress.attempts) ||
    progress.attempts < 1
  )
    return "0";
  return `${progress.attempts}${OUTCOMES[progress.outcome]}`;
}

function decodeAssessment(field: string): AssessmentProgress | null {
  if (field === "0") return { attempts: 0, outcome: null };
  const match = /^([1-9][0-9]*)([pce])$/.exec(field);
  if (match === null) return null;
  const attempts = Number(match[1]);
  if (!Number.isSafeInteger(attempts)) return null;
  const outcome = (Object.keys(OUTCOMES) as ExamOutcome[]).find(
    (key) => OUTCOMES[key] === match[2],
  );
  return outcome === undefined ? null : { attempts, outcome };
}

/**
 * Encodes `state` for `cmi.suspend_data` of a package of `module`.
 *
 * The string holds fields separated by `.`: the version `2`, the layout
 * fingerprint of `module` (`fingerprint`, six characters), the path letter
 * (`f` full, `s` short), `1` or `0` for the completed module, the bitsets
 * of the opened explanations (`explanationBlockIds`), the answered items
 * and the items with a correct answer (both by position in
 * `module.items`), and one field per assessment of `module` in payload
 * order: `0` before the first attempt, otherwise the attempt count followed
 * by the outcome letter (`p` passed, `c` failed_core, `e` failed_errors). A
 * bitset holds six bits per character in the base64url alphabet, the first
 * member in the lowest bit of the first character, without trailing zero
 * characters. Every character belongs to the unreserved characters of RFC
 * 3986, so no LMS escapes or mangles the string.
 *
 * Ids and keys that `module` does not hold are left out. Throws a
 * `RangeError` when the result is longer than `SUSPEND_DATA_LIMIT`.
 */
export function encodeSuspendData(
  module: PayloadModule,
  state: SuspendState,
): string {
  const items = module.items.map((item) => item.key);
  const fields = [
    VERSION,
    fingerprint(module),
    PATHS[state.path],
    state.completed ? "1" : "0",
    encodeBits(explanationBlockIds(module), state.openedExplanations),
    encodeBits(items, state.answeredItems),
    encodeBits(items, state.correctItems),
    ...module.assessments.map((assessment) =>
      encodeAssessment(
        Object.hasOwn(state.assessments, assessment.key)
          ? state.assessments[assessment.key]
          : undefined,
      ),
    ),
  ];
  const data = fields.join(SEPARATOR);
  if (data.length > SUSPEND_DATA_LIMIT)
    throw new RangeError(
      `suspend data of ${data.length} characters exceeds ${SUSPEND_DATA_LIMIT}`,
    );
  return data;
}

/**
 * Decodes the suspend data of a package of `module`. Returns `null`, and
 * never throws, for a value that is not a string, an empty or malformed
 * string, another version (version `1` included), and a string that does
 * not fit `module`: another layout fingerprint, another number of
 * assessments, a bitset longer than its list, or a correct item that is
 * not answered. The lists come in the order of `module`, and `assessments`
 * holds every assessment of `module`.
 */
export function decodeSuspendData(
  module: PayloadModule,
  data: unknown,
): SuspendState | null {
  if (typeof data !== "string" || data === "") return null;
  const fields = data.split(SEPARATOR);
  if (
    fields[0] !== VERSION ||
    fields.length !== HEAD_FIELDS + module.assessments.length ||
    fields[1] !== fingerprint(module)
  )
    return null;
  const [, , pathLetter, completed, opened, answered, correct] = fields;
  const path = (Object.keys(PATHS) as Path[]).find(
    (key) => PATHS[key] === pathLetter,
  );
  if (path === undefined || (completed !== "0" && completed !== "1"))
    return null;

  const items = module.items.map((item) => item.key);
  const openedExplanations = decodeBits(explanationBlockIds(module), opened);
  const answeredItems = decodeBits(items, answered);
  const correctItems = decodeBits(items, correct);
  if (
    openedExplanations === null ||
    answeredItems === null ||
    correctItems === null ||
    !correctItems.every((key) => answeredItems.includes(key))
  )
    return null;

  const progress = module.assessments.map((_, index) =>
    decodeAssessment(fields[HEAD_FIELDS + index]),
  );
  if (progress.some((entry) => entry === null)) return null;
  return {
    path,
    completed: completed === "1",
    openedExplanations,
    answeredItems,
    correctItems,
    assessments: Object.fromEntries(
      module.assessments.map((assessment, index) => [
        assessment.key,
        progress[index] as AssessmentProgress,
      ]),
    ),
  };
}
