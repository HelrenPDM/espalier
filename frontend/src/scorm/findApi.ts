import type { Scorm12Api, Scorm2004Api } from "../runtimes/lms";

/** The LMS API that the discovery found, with the SCORM version it serves. */
export type LmsApi =
  { version: "2004"; api: Scorm2004Api } | { version: "1.2"; api: Scorm12Api };

/**
 * The members of a window that the discovery reads. `Window` has them; the
 * tests pass plain objects.
 */
export interface ApiWindow {
  readonly parent: ApiWindow | null;
  readonly opener?: ApiWindow | null;
}

/**
 * The most parent steps of one walk for `API_1484_11`: `maxTries` of the
 * API discovery algorithm in the SCORM 2004 4th edition run-time environment
 * (IEEE 1484.11.2).
 */
export const SCORM_2004_MAX_TRIES = 500;

/**
 * The most parent steps of one walk for `API`: the limit of `findAPI` in the
 * SCORM 1.2 run-time environment ("7 is an arbitrary number, but should be
 * more than sufficient").
 */
export const SCORM_12_MAX_TRIES = 7;

interface Search {
  name: "API_1484_11" | "API";
  maxTries: number;
  /** The function that every API object of the version has. */
  initialize: "Initialize" | "LMSInitialize";
}

const SCORM_2004: Search = {
  name: "API_1484_11",
  maxTries: SCORM_2004_MAX_TRIES,
  initialize: "Initialize",
};

const SCORM_12: Search = {
  name: "API",
  maxTries: SCORM_12_MAX_TRIES,
  initialize: "LMSInitialize",
};

/**
 * The member `name` of `target`, or `undefined`. A window of another origin
 * throws a `SecurityError` on every member except a few such as `parent`
 * and `opener`, which counts as not found for that window.
 */
function memberOf(target: object, name: string): unknown {
  try {
    return (target as Record<string, unknown>)[name];
  } catch {
    return undefined;
  }
}

/** The parent of `win`, or `null` for a top window. */
function parentOf(win: ApiWindow): ApiWindow | null {
  const parent = memberOf(win, "parent") as ApiWindow | null | undefined;
  return parent != null && parent !== win ? parent : null;
}

/** The API object of `search` on `win`, when it has the initialize function. */
function apiOn(win: ApiWindow, search: Search): object | null {
  const api = memberOf(win, search.name);
  if ((typeof api !== "object" && typeof api !== "function") || api === null)
    return null;
  return typeof memberOf(api, search.initialize) === "function" ? api : null;
}

/**
 * `ScanForAPI` (2004) and `findAPI` (1.2): looks at `start` and walks up its
 * parents until a window holds the API, the top window is reached or the
 * walk has taken `maxTries` parent steps.
 */
function scan(start: ApiWindow, search: Search): object | null {
  let win = start;
  for (let tries = 0; ; tries += 1) {
    const api = apiOn(win, search);
    if (api !== null) return api;
    const parent = parentOf(win);
    if (parent === null || tries >= search.maxTries) return null;
    win = parent;
  }
}

/** The parent chain of `win`, then the opener of `win` and its parents. */
function discover(win: ApiWindow, search: Search): object | null {
  const found = scan(win, search);
  if (found !== null) return found;
  const opener = memberOf(win, "opener") as ApiWindow | null | undefined;
  return opener == null ? null : scan(opener, search);
}

/**
 * Finds the run-time API of the LMS with the discovery algorithms of the
 * standards: from `win` up the chain of `window.parent`, then from
 * `window.opener` up its chain, each walk within the attempt limit of its
 * version. It looks for `API_1484_11` first and for `API` only when no
 * window offers it, so an LMS that offers both serves the package as
 * SCORM 2004. An object without the initialize function of its version is
 * no API. Returns `null` when neither API is found.
 */
export function findApi(win: ApiWindow): LmsApi | null {
  const api2004 = discover(win, SCORM_2004);
  if (api2004 !== null)
    return { version: "2004", api: api2004 as Scorm2004Api };
  const api12 = discover(win, SCORM_12);
  if (api12 !== null) return { version: "1.2", api: api12 as Scorm12Api };
  return null;
}
