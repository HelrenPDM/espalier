import { afterEach, describe, expect, test, vi } from "vitest";
import { fakeScorm12, fakeScorm2004 } from "../runtimes/fakeLms";
import type { Scorm12Api, Scorm2004Api } from "../runtimes/lms";
import { ScormRuntime } from "../runtimes/scorm";
import { Scorm12Runtime } from "../runtimes/scorm12";
import { Scorm2004Runtime } from "../runtimes/scorm2004";
import {
  CONTENT_FILE,
  createRuntime,
  loadContent,
  onRestoredFromCache,
  startRuntime,
  uiLanguage,
} from "./boot";
import type { ApiWindow } from "./findApi";
import { scormContent } from "./fixture";

/** Task 0016 step 2: the start of the SCORM entry before the first render. */

const answer = (status: number, body: string) =>
  vi.fn<typeof fetch>(async () => new Response(body, { status }));

describe("loadContent", () => {
  test("fetches content.json relative to the page and returns it", async () => {
    const fetchImpl = answer(200, JSON.stringify(scormContent()));

    await expect(loadContent(fetchImpl)).resolves.toEqual(scormContent());
    expect(fetchImpl).toHaveBeenCalledWith(CONTENT_FILE);
    expect(CONTENT_FILE).toBe("content.json");
  });

  test("returns null for a missing file, invalid JSON or another shape", async () => {
    await expect(loadContent(answer(404, "Not found"))).resolves.toBeNull();
    await expect(loadContent(answer(200, "{"))).resolves.toBeNull();
    await expect(
      loadContent(
        answer(200, JSON.stringify({ ...scormContent(), schema: 2 })),
      ),
    ).resolves.toBeNull();
    await expect(
      loadContent(
        vi.fn<typeof fetch>(async () => {
          throw new TypeError("offline");
        }),
      ),
    ).resolves.toBeNull();
  });
});

describe("uiLanguage", () => {
  test("takes the primary subtag when the i18n files hold it", () => {
    expect(uiLanguage("de")).toBe("de");
    expect(uiLanguage("de-AT")).toBe("de");
    expect(uiLanguage("DE_ch")).toBe("de");
    expect(uiLanguage("en-GB")).toBe("en");
  });

  test("falls back to English for a locale without UI strings", () => {
    expect(uiLanguage("fr")).toBe("en");
    expect(uiLanguage("")).toBe("en");
  });
});

describe("createRuntime", () => {
  test("picks the runtime of the version that the discovery found", () => {
    const content = scormContent();
    const api2004 = {} as Scorm2004Api;
    const api12 = {} as Scorm12Api;

    expect(
      createRuntime({ version: "2004", api: api2004 }, content),
    ).toBeInstanceOf(Scorm2004Runtime);
    expect(
      createRuntime({ version: "1.2", api: api12 }, content),
    ).toBeInstanceOf(Scorm12Runtime);
  });
});

describe("startRuntime", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  /** A top window with `members`: its parent is itself, as in a browser. */
  function topWindow(members: Record<string, unknown> = {}): ApiWindow {
    const win: Record<string, unknown> = { opener: null, ...members };
    win.parent = win;
    return win as unknown as ApiWindow;
  }

  test("starts the runtime of the API that the discovery found", () => {
    const { api, lms } = fakeScorm2004();

    const result = startRuntime(
      topWindow({ API_1484_11: api }),
      scormContent(),
    );

    expect(result.kind).toBe("started");
    if (result.kind !== "started") return;
    expect(result.runtime).toBeInstanceOf(Scorm2004Runtime);
    expect(lms.names()[0]).toBe("Initialize");
    // Ends the session, which also removes the `pagehide` listener.
    result.runtime.finish();
  });

  test("gives the notice noLms when no window offers an API", () => {
    expect(startRuntime(topWindow(), scormContent())).toEqual({
      kind: "notice",
      reason: "noLms",
    });
  });

  test("gives the notice startFailed when the LMS refuses the initialization", () => {
    const scorm12 = fakeScorm12();
    scorm12.lms.fail("LMSInitialize");
    const scorm2004 = fakeScorm2004();
    scorm2004.lms.fail("Initialize");

    for (const win of [
      topWindow({ API: scorm12.api }),
      topWindow({ API_1484_11: scorm2004.api }),
    ])
      expect(startRuntime(win, scormContent())).toEqual({
        kind: "notice",
        reason: "startFailed",
      });
  });

  test("gives the notice startFailed when the start throws", () => {
    const start = vi
      .spyOn(ScormRuntime.prototype, "start")
      .mockImplementation(() => {
        throw new Error("The LMS refused the initialization.");
      });
    const { api } = fakeScorm12();

    expect(startRuntime(topWindow({ API: api }), scormContent())).toEqual({
      kind: "notice",
      reason: "startFailed",
    });
    expect(start).toHaveBeenCalledOnce();
  });
});

describe("onRestoredFromCache", () => {
  /** A `pageshow` event; jsdom may lack `PageTransitionEvent`. */
  function pageshow(persisted: boolean): Event {
    const event = new Event("pageshow");
    Object.defineProperty(event, "persisted", { value: persisted });
    return event;
  }

  test("calls back for a page from the back/forward cache until it is removed", () => {
    const onRestore = vi.fn();
    const stop = onRestoredFromCache(window, onRestore);

    window.dispatchEvent(pageshow(false));
    expect(onRestore).not.toHaveBeenCalled();

    window.dispatchEvent(pageshow(true));
    expect(onRestore).toHaveBeenCalledOnce();

    stop();
    window.dispatchEvent(pageshow(true));
    expect(onRestore).toHaveBeenCalledOnce();
  });
});
