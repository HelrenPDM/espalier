import type { Scorm12Api, Scorm2004Api } from "./lms";

/** A call of the LMS API: the function name and its arguments. */
export interface LmsCall {
  name: string;
  args: string[];
}

/** The error functions, which leave the error code of the last call as it is. */
const ERROR_FUNCTIONS = /Get(LastError|ErrorString|Diagnostic)$/;

/**
 * The store and the call record of a fake LMS for the tests of the SCORM
 * runtimes (task 0016, step 5). `values` holds the data model, preloaded
 * with the values of an earlier session; every call goes to `calls`. A
 * function named in `fail` answers `"false"` (`""` for a get) without
 * effect, and the error functions then report its error code.
 */
export class FakeLms {
  readonly calls: LmsCall[] = [];
  readonly values: Map<string, string>;
  /** The error code of the last call that is not an error function. */
  lastError = "0";
  /** The failing functions with their error codes. */
  readonly #failing = new Map<string, string>();

  constructor(values: Record<string, string>) {
    this.values = new Map(Object.entries(values));
  }

  /**
   * Makes the function `name` fail from now on with the error code
   * `error` (101, the general exception of both versions, by default), or
   * work again with `failing` false.
   */
  fail(name: string, failing = true, error = "101"): void {
    if (failing) this.#failing.set(name, error);
    else this.#failing.delete(name);
  }

  /** Records a call and runs `effect` unless the function fails. */
  call(name: string, args: string[], effect: () => string): string {
    this.calls.push({ name, args });
    if (ERROR_FUNCTIONS.test(name)) return effect();
    const error = this.#failing.get(name);
    this.lastError = error ?? "0";
    if (error !== undefined) return name.endsWith("GetValue") ? "" : "false";
    return effect();
  }

  /** The set calls in order, as `[element, value]`. */
  sets(): [string, string][] {
    return this.calls
      .filter((call) => call.name.endsWith("SetValue"))
      .map((call) => [call.args[0], call.args[1]]);
  }

  /** The set calls of elements of `cmi.objectives`. */
  objectiveSets(): [string, string][] {
    return this.sets().filter(([element]) =>
      element.startsWith("cmi.objectives."),
    );
  }

  /** The names of the calls in order. */
  names(): string[] {
    return this.calls.map((call) => call.name);
  }

  /** The values of the entries of `cmi.objectives`, as an LMS keeps them. */
  objectives(): Record<string, string> {
    return Object.fromEntries(
      [...this.values].filter(([element]) =>
        element.startsWith("cmi.objectives."),
      ),
    );
  }

  /** Forgets the recorded calls. */
  clear(): void {
    this.calls.length = 0;
  }
}

/**
 * A fake SCORM 1.2 LMS whose `cmi.core.lesson_status` starts as
 * `not attempted` unless `preloaded` sets it.
 */
export function fakeScorm12(preloaded: Record<string, string> = {}): {
  api: Scorm12Api;
  lms: FakeLms;
} {
  const lms = new FakeLms({
    "cmi.core.lesson_status": "not attempted",
    "cmi.suspend_data": "",
    ...preloaded,
  });
  const api: Scorm12Api = {
    LMSInitialize: (parameter) =>
      lms.call("LMSInitialize", [parameter], () => "true"),
    LMSFinish: (parameter) => lms.call("LMSFinish", [parameter], () => "true"),
    LMSGetValue: (element) =>
      lms.call("LMSGetValue", [element], () => lms.values.get(element) ?? ""),
    LMSSetValue: (element, value) =>
      lms.call("LMSSetValue", [element, value], () => {
        lms.values.set(element, value);
        return "true";
      }),
    LMSCommit: (parameter) => lms.call("LMSCommit", [parameter], () => "true"),
    LMSGetLastError: () => lms.call("LMSGetLastError", [], () => lms.lastError),
    LMSGetErrorString: (code) =>
      lms.call("LMSGetErrorString", [code], () => ""),
    LMSGetDiagnostic: (code) => lms.call("LMSGetDiagnostic", [code], () => ""),
  };
  return { api, lms };
}

/**
 * A fake SCORM 2004 LMS whose `cmi.completion_status` and
 * `cmi.success_status` start as `unknown` unless `preloaded` sets them.
 */
export function fakeScorm2004(preloaded: Record<string, string> = {}): {
  api: Scorm2004Api;
  lms: FakeLms;
} {
  const lms = new FakeLms({
    "cmi.completion_status": "unknown",
    "cmi.success_status": "unknown",
    "cmi.suspend_data": "",
    ...preloaded,
  });
  const api: Scorm2004Api = {
    Initialize: (parameter) =>
      lms.call("Initialize", [parameter], () => "true"),
    Terminate: (parameter) => lms.call("Terminate", [parameter], () => "true"),
    GetValue: (element) =>
      lms.call("GetValue", [element], () => lms.values.get(element) ?? ""),
    SetValue: (element, value) =>
      lms.call("SetValue", [element, value], () => {
        lms.values.set(element, value);
        return "true";
      }),
    Commit: (parameter) => lms.call("Commit", [parameter], () => "true"),
    GetLastError: () => lms.call("GetLastError", [], () => lms.lastError),
    GetErrorString: (code) => lms.call("GetErrorString", [code], () => ""),
    GetDiagnostic: (code) => lms.call("GetDiagnostic", [code], () => ""),
  };
  return { api, lms };
}
