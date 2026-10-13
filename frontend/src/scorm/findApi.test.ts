import { describe, expect, test } from "vitest";
import {
  SCORM_12_MAX_TRIES,
  SCORM_2004_MAX_TRIES,
  findApi,
  type ApiWindow,
} from "./findApi";

/**
 * Task 0016 step 2: the API discovery of the SCORM entry on plain window
 * objects. A window of another origin throws a `SecurityError` on every
 * member except `parent` and `opener`.
 */

type FakeWindow = ApiWindow & Record<string, unknown>;

/** A top window: its parent is itself, as in a browser. */
function topWindow(members: Record<string, unknown> = {}): FakeWindow {
  const win = { opener: null, ...members } as Record<string, unknown>;
  win.parent = win;
  return win as FakeWindow;
}

const frame = (
  parent: ApiWindow,
  members: Record<string, unknown> = {},
): FakeWindow => ({ parent, opener: null, ...members });

/** A chain of `depth` frames below `top`; returns the innermost frame. */
function nested(top: ApiWindow, depth: number): FakeWindow {
  let win = top as FakeWindow;
  for (let level = 0; level < depth; level += 1) win = frame(win);
  return win;
}

/** A frame of another origin below `parent`. */
function foreignFrame(parent: ApiWindow): ApiWindow {
  const win = { parent, opener: null };
  for (const name of ["API", "API_1484_11"])
    Object.defineProperty(win, name, {
      get() {
        throw new DOMException("Blocked a frame", "SecurityError");
      },
    });
  return win;
}

const api12 = () => ({ LMSInitialize: () => "true" });
const api2004 = () => ({ Initialize: () => "true" });

describe("findApi", () => {
  test("finds API_1484_11 in the parent as SCORM 2004", () => {
    const api = api2004();
    const sco = frame(topWindow({ API_1484_11: api }));

    expect(findApi(sco)).toEqual({ version: "2004", api });
    expect(findApi(sco)?.api).toBe(api);
  });

  test("finds API in an ancestor as SCORM 1.2", () => {
    const api = api12();
    const sco = nested(topWindow({ API: api }), 3);

    expect(findApi(sco)).toEqual({ version: "1.2", api });
  });

  test("looks at the window itself first", () => {
    const api = api12();

    expect(findApi(topWindow({ API: api }))).toEqual({ version: "1.2", api });
  });

  test("prefers API_1484_11 when an LMS offers both", () => {
    const api = api2004();
    const sco = frame(topWindow({ API: api12(), API_1484_11: api }));

    expect(findApi(sco)).toEqual({ version: "2004", api });
  });

  test("prefers API_1484_11 of an ancestor over API of a nearer window", () => {
    const api = api2004();
    const middle = frame(topWindow({ API_1484_11: api }), { API: api12() });

    expect(findApi(frame(middle))?.version).toBe("2004");
  });

  test("walks up at most 7 parents for API", () => {
    const api = api12();

    expect(
      findApi(nested(topWindow({ API: api }), SCORM_12_MAX_TRIES)),
    ).toEqual({ version: "1.2", api });
    expect(
      findApi(nested(topWindow({ API: api }), SCORM_12_MAX_TRIES + 1)),
    ).toBeNull();
  });

  test("walks up at most 500 parents for API_1484_11", () => {
    const api = api2004();

    expect(
      findApi(nested(topWindow({ API_1484_11: api }), SCORM_2004_MAX_TRIES)),
    ).toEqual({ version: "2004", api });
    expect(
      findApi(
        nested(topWindow({ API_1484_11: api }), SCORM_2004_MAX_TRIES + 1),
      ),
    ).toBeNull();
  });

  test("passes a frame of another origin and finds the API above it", () => {
    const api = api12();
    const sco = frame(foreignFrame(topWindow({ API: api })));

    expect(findApi(sco)).toEqual({ version: "1.2", api });
  });

  test("treats a window of another origin as one without an API", () => {
    const sco = frame(foreignFrame(foreignFrame(topWindow())));

    expect(findApi(sco)).toBeNull();
  });

  test("searches the opener and its parents when the parents have no API", () => {
    const api = api2004();
    const opener = frame(topWindow({ API_1484_11: api }));
    const sco = topWindow({ opener });

    expect(findApi(sco)).toEqual({ version: "2004", api });
  });

  test("searches the opener of the window, not of its parents", () => {
    const parent = topWindow({ opener: topWindow({ API: api12() }) });

    expect(findApi(frame(parent))).toBeNull();
  });

  test("skips an object without the initialize function of its version", () => {
    const api = api12();
    const sco = frame(frame(topWindow({ API: api }), { API: {} }), {
      API_1484_11: api12(),
    });

    expect(findApi(sco)).toEqual({ version: "1.2", api });
  });

  test("returns null without an API", () => {
    expect(findApi(nested(topWindow(), 2))).toBeNull();
    expect(findApi(topWindow())).toBeNull();
  });
});
