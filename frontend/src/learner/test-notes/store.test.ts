import { screen, waitFor, within } from "@testing-library/react";
import { createElement } from "react";
import { Route, Routes } from "react-router";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import type { components } from "../../api/schema";
import type { TestNoteEvent } from "../../player/testNotes";
import { id, IDS, programFixture, SLUG } from "../../test/player";
import {
  renderWithProviders,
  type RecordedRequest,
  type StubResponses,
} from "../../test/render";
import { signedInPayload, TEST_USER } from "../../test/session";
import { ProgramRoute } from "../ProgramRoute";
import { StationPage } from "../StationPage";
import {
  resetTestNotes,
  TEST_NOTES_KEY,
  testNotesLog,
  type TestNote,
} from "./store";

/**
 * Task 0014 step 11 and ASVS 14.3.3: the store of the test session notes
 * is the only module that reads or writes `espalier.test_notes`, in
 * `sessionStorage`, and wraps every access in `try/catch`. While
 * `flags.testNotes` is false it touches no storage; with the flag it writes
 * that key and no other. After a recorded walk-through through the platform
 * runtime, the stored value holds none of the user id, the display name,
 * the e-mail address and the CSRF token of the session, and no request
 * carries the log. `resetTestNotes`, which a sign-out and a sign-in call
 * (see `src/auth/sessionEvents.test.ts`), empties the log, removes the key
 * and restarts the clock.
 */
type Progress = components["schemas"]["Progress"];

const CSRF_TOKEN = "csrf-token-of-the-test-session";
const ENROLLMENT_ID = id(500);
const PLAYER_KEY = `espalier.player.${SLUG}`;
const EVENT_NAMES = [
  "station_opened",
  "path_switched",
  "item_answered",
  "explanation_revealed",
  "exam_submitted",
  "format_voted",
];

const stationOpened = (station: number): TestNoteEvent => ({
  event: "station_opened",
  station,
});

/** The raw stored entry of the notes. */
const storedEntry = () => sessionStorage.getItem(TEST_NOTES_KEY);

/** The keys of `storage`. */
const keysOf = (storage: Storage) =>
  Array.from({ length: storage.length }, (_, index) => storage.key(index));

beforeEach(() => {
  testNotesLog(true).clear();
});

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
  testNotesLog(true).clear();
  localStorage.removeItem(PLAYER_KEY);
});

describe("the store", () => {
  test("touches no storage while flags.testNotes is false", () => {
    const getItem = vi.spyOn(Storage.prototype, "getItem");
    const setItem = vi.spyOn(Storage.prototype, "setItem");
    const removeItem = vi.spyOn(Storage.prototype, "removeItem");
    const log = testNotesLog(false);

    log.record(stationOpened(1));
    log.record({
      event: "item_answered",
      item: IDS.singleChoice,
      correct: true,
    });
    log.clear();

    expect(log.enabled).toBe(false);
    expect(log.notes()).toEqual([]);
    expect(getItem).not.toHaveBeenCalled();
    expect(setItem).not.toHaveBeenCalled();
    expect(removeItem).not.toHaveBeenCalled();
    expect(keysOf(sessionStorage)).toEqual([]);
  });

  test("with the flag set, writes the key espalier.test_notes and no other key", () => {
    const setItem = vi.spyOn(Storage.prototype, "setItem");
    const localKeys = keysOf(localStorage);
    const log = testNotesLog(true);

    log.record(stationOpened(1));
    log.record({ event: "path_switched", path: "short" });
    log.record({
      event: "exam_submitted",
      assessment: IDS.exam,
      outcome: "failed_core",
    });

    expect(setItem).toHaveBeenCalledTimes(3);
    for (const [key] of setItem.mock.calls) expect(key).toBe(TEST_NOTES_KEY);
    for (const storage of setItem.mock.contexts)
      expect(storage).toBe(sessionStorage);
    expect(keysOf(sessionStorage)).toEqual([TEST_NOTES_KEY]);
    expect(keysOf(localStorage)).toEqual(localKeys);
    expect(log.notes().map(({ event }) => event)).toEqual([
      "station_opened",
      "path_switched",
      "exam_submitted",
    ]);
  });

  test("stores each event with the milliseconds since the log started", () => {
    const now = vi.spyOn(Date, "now");
    const log = testNotesLog(true);

    now.mockReturnValue(1_760_000_000_000);
    log.record(stationOpened(2));
    now.mockReturnValue(1_760_000_002_500);
    log.record({
      event: "item_answered",
      item: IDS.singleChoice,
      correct: false,
    });
    now.mockReturnValue(1_760_000_004_000);
    log.record({ event: "explanation_revealed", item: IDS.singleChoice });

    expect(JSON.parse(storedEntry() ?? "null")).toEqual({
      v: 1,
      notes: [
        { event: "station_opened", station: 2, at: 0 },
        {
          event: "item_answered",
          item: IDS.singleChoice,
          correct: false,
          at: 2500,
        },
        { event: "explanation_revealed", item: IDS.singleChoice, at: 4000 },
      ],
    });
    // The entry holds no clock time.
    expect(storedEntry()).not.toContain("1760000");
  });

  test("clear removes the entry and restarts the clock", () => {
    const now = vi.spyOn(Date, "now");
    const log = testNotesLog(true);
    now.mockReturnValue(10_000);
    log.record(stationOpened(1));
    now.mockReturnValue(15_000);
    log.record(stationOpened(2));
    const listener = vi.fn();
    const unsubscribe = log.subscribe(listener);

    log.clear();
    now.mockReturnValue(20_000);
    log.record(stationOpened(3));
    unsubscribe();
    log.record(stationOpened(4));

    expect(listener).toHaveBeenCalledTimes(2);
    expect(log.notes().map(({ at }) => at)).toEqual([0, 0]);
    expect(keysOf(sessionStorage)).toEqual([TEST_NOTES_KEY]);
  });

  test("resetTestNotes empties the log, removes the entry, notifies the listeners and restarts the clock", () => {
    const now = vi.spyOn(Date, "now");
    const log = testNotesLog(true);
    now.mockReturnValue(10_000);
    log.record(stationOpened(1));
    now.mockReturnValue(15_000);
    log.record({
      event: "item_answered",
      item: IDS.singleChoice,
      correct: true,
    });
    const listener = vi.fn();
    const unsubscribe = log.subscribe(listener);

    resetTestNotes();

    expect(listener).toHaveBeenCalledTimes(1);
    expect(log.notes()).toEqual([]);
    expect(storedEntry()).toBeNull();
    expect(keysOf(sessionStorage)).toEqual([]);

    // The clock starts again with the first note after the reset.
    now.mockReturnValue(90_000);
    log.record(stationOpened(2));
    expect(log.notes()).toEqual([{ ...stationOpened(2), at: 0 }]);
    unsubscribe();
  });

  test("resetTestNotes removes the entry of an earlier page also while flags.testNotes is false", async () => {
    sessionStorage.setItem(
      TEST_NOTES_KEY,
      JSON.stringify({
        v: 1,
        notes: [
          { event: "station_opened", station: 1, at: 1000 },
          {
            event: "exam_submitted",
            assessment: IDS.exam,
            outcome: "passed",
            at: 4000,
          },
        ],
      }),
    );
    vi.resetModules();
    const fresh = await import("./store");
    const setItem = vi.spyOn(Storage.prototype, "setItem");

    fresh.resetTestNotes();

    expect(storedEntry()).toBeNull();
    expect(setItem).not.toHaveBeenCalled();
    expect(fresh.testNotesLog(false).notes()).toEqual([]);
    const log = fresh.testNotesLog(true);
    expect(log.notes()).toEqual([]);
    // A reload would continue the clock at 4000; the reset starts it again.
    vi.spyOn(Date, "now").mockReturnValue(50_000);
    log.record(stationOpened(3));
    expect(log.notes()).toEqual([{ ...stationOpened(3), at: 0 }]);
    log.clear();
  });

  test("a reload reads the stored notes, drops malformed ones and continues the clock", async () => {
    sessionStorage.setItem(
      TEST_NOTES_KEY,
      JSON.stringify({
        v: 1,
        notes: [
          { event: "station_opened", station: 1, at: 1000 },
          { event: "unknown", at: 1500 },
          { event: "station_opened", station: "2", at: 1600 },
          {
            event: "item_answered",
            item: IDS.poll,
            correct: null,
            at: 4000,
            user_id: TEST_USER.id,
          },
        ],
      }),
    );
    vi.resetModules();
    const fresh = await import("./store");
    vi.spyOn(Date, "now").mockReturnValue(50_000);
    const log = fresh.testNotesLog(true);

    expect(log.notes()).toEqual([
      { event: "station_opened", station: 1, at: 1000 },
      { event: "item_answered", item: IDS.poll, correct: null, at: 4000 },
    ]);
    log.record({ event: "format_voted", station: 4 });

    expect(log.notes().at(-1)).toEqual({
      event: "format_voted",
      station: 4,
      at: 4000,
    });
    expect(storedEntry()).not.toContain(TEST_USER.id);
    log.clear();
  });

  test("an entry of another version or of no JSON yields no notes", async () => {
    for (const raw of ['{"v":2,"notes":[]}', "not json", "[]"]) {
      sessionStorage.setItem(TEST_NOTES_KEY, raw);
      vi.resetModules();
      const fresh = await import("./store");
      expect(fresh.testNotesLog(true).notes()).toEqual([]);
    }
  });

  test("wraps every access in try/catch and keeps the notes in memory when storage throws", async () => {
    const blocked = () => {
      throw new DOMException("The operation is insecure.", "SecurityError");
    };
    vi.spyOn(Storage.prototype, "getItem").mockImplementation(blocked);
    vi.spyOn(Storage.prototype, "setItem").mockImplementation(blocked);
    vi.spyOn(Storage.prototype, "removeItem").mockImplementation(blocked);
    vi.resetModules();
    const fresh = await import("./store");
    const log = fresh.testNotesLog(true);

    expect(() => log.record(stationOpened(1))).not.toThrow();
    expect(log.notes()).toMatchObject([stationOpened(1)]);
    expect(() => log.clear()).not.toThrow();
    expect(log.notes()).toEqual([]);
  });
});

/** The program of the platform runtime: the fixture with module summaries. */
function platformResponses(): StubResponses {
  const { modules, glossary, ...program } = programFixture();
  let path: "short" | "full" = "full";
  const progress = (): Progress => ({
    enrollment: { id: ENROLLMENT_ID, path, path_chosen_manually: false },
    completed_module_ids: [],
    exams: [],
    objectives: [],
  });
  return {
    [`GET /api/programs/${SLUG}`]: {
      status: 200,
      body: {
        ...program,
        modules: modules.map(
          ({ id, number, phases, single_path, summary, title }) => ({
            id,
            number,
            phases,
            single_path,
            summary,
            title,
          }),
        ),
      },
    },
    ...Object.fromEntries(
      modules.map((module) => [
        `GET /api/modules/${module.id}`,
        { status: 200, body: module },
      ]),
    ),
    [`GET /api/programs/${SLUG}/glossary`]: {
      status: 200,
      body: { terms: glossary },
    },
    "GET /api/me/progress": () => ({ status: 200, body: progress() }),
    [`PATCH /api/enrollments/${ENROLLMENT_ID}`]: (request) => {
      path = (request.body as { path: "short" | "full" }).path;
      return {
        status: 200,
        body: {
          id: ENROLLMENT_ID,
          path,
          path_chosen_manually: true,
          program_id: id(100),
          started_at: "2026-10-11T09:00:00Z",
        },
      };
    },
    [`POST /api/items/${IDS.singleChoice}/responses`]: {
      status: 200,
      body: {
        item_id: IDS.singleChoice,
        correct: false,
        option_feedback: [],
        rules: [],
        reveals: [IDS.lesson1],
      },
    },
    [`POST /api/assessments/${IDS.exam}/attempts`]: {
      status: 201,
      body: {
        id: id(900),
        assessment_id: IDS.exam,
        number: 1,
        outcome: "passed",
        core_failed: false,
        wrong_count: 0,
        submitted_at: "2026-10-11T10:00:00Z",
        results: [],
      },
    },
    "GET /api/me/participation": {
      status: 200,
      body: { self_assessment: false, feedback: false, format_votes: [] },
    },
    [`POST /api/formats/${IDS.workshop}/votes`]: {
      status: 200,
      body: { already_recorded: false },
    },
  };
}

/**
 * Renders the program routes with the platform runtime for `TEST_USER`
 * with the test notes flag `testNotes`, and records the URL of every
 * request, query included.
 */
function renderProgram(testNotes: boolean) {
  const urls: string[] = [];
  const BaseRequest = globalThis.Request;
  vi.stubGlobal(
    "Request",
    class RecordingRequest extends BaseRequest {
      constructor(input: RequestInfo | URL, init?: RequestInit) {
        super(input, init);
        urls.push(this.url);
      }
    },
  );
  const rendered = renderWithProviders(
    createElement(
      Routes,
      null,
      createElement(
        Route,
        { path: "programs/:slug", element: createElement(ProgramRoute) },
        createElement(Route, {
          path: "stations/:position",
          element: createElement(StationPage),
        }),
      ),
    ),
    {
      route: `/programs/${SLUG}/stations/1`,
      path: "/*",
      session: signedInPayload("mfa", {
        csrf_token: CSRF_TOKEN,
        flags: { test_notes: testNotes },
      }),
      responses: platformResponses(),
    },
  );
  return { ...rendered, urls };
}

const heading = (name: string) =>
  screen.findByRole("heading", { level: 1, name });

/**
 * Walks through the program: the overview, module 1 with a path switch, a
 * wrong practice answer that reveals explanations and a passed exam, module
 * 2 and the companion formats station with a vote.
 */
async function walkThrough({
  user,
  requests,
}: ReturnType<typeof renderProgram>) {
  await heading("Overview");
  await user.click(
    screen.getByRole("link", { name: "Next: How language models work" }),
  );
  await heading("How language models work");

  await user.click(await screen.findByRole("radio", { name: "Short path" }));
  await waitFor(() =>
    expect(
      requests.filter((request) => request.method === "PATCH"),
    ).toHaveLength(1),
  );

  const item = screen.getByRole("group", {
    name: "How does a language model write?",
  });
  await user.click(
    within(item).getByRole("radio", {
      name: "It looks up a database of facts.",
    }),
  );
  await user.click(within(item).getByRole("button", { name: "Check answer" }));
  await within(item).findByText(/The explanation in this lesson is open now/);

  const exam = (stem: string, label: string) =>
    user.click(
      within(screen.getByRole("group", { name: stem })).getByRole("radio", {
        name: label,
      }),
    );
  await exam("What does a model do when it writes?", "It continues text.");
  await exam("Which parts need a check?", "Every name and number.");
  await user.click(screen.getByRole("button", { name: "Submit the exam" }));
  await screen.findByText(/^Passed:/);

  await user.click(
    screen.getByRole("link", { name: "Next: Checking the output" }),
  );
  await heading("Checking the output");
  await user.click(
    screen.getByRole("link", { name: "Next: Beyond the platform" }),
  );
  await heading("Beyond the platform");
  await user.click(await screen.findByRole("button", { name: "Would use" }));
  await waitFor(() =>
    expect(screen.getByRole("button", { name: "Would use" })).toBeDisabled(),
  );
}

/** Every part of `request` that leaves the browser, as text. */
const sentText = (request: RecordedRequest) =>
  [
    request.method,
    request.path,
    JSON.stringify(request.body),
    ...Array.from(request.headers.entries()).flat(),
  ].join("\n");

describe("a recorded walk-through", () => {
  test("stores the events without personal data, shows them in the panel and sends none of them", async () => {
    const rendered = renderProgram(true);
    const setItem = vi.spyOn(Storage.prototype, "setItem");

    await walkThrough(rendered);

    const raw = storedEntry();
    expect(raw).not.toBeNull();
    const notes = (JSON.parse(raw ?? "null") as { notes: TestNote[] }).notes;
    expect(notes.map(({ at: _at, ...event }) => event)).toEqual([
      stationOpened(1),
      stationOpened(2),
      { event: "path_switched", path: "short" },
      { event: "item_answered", item: IDS.singleChoice, correct: false },
      { event: "explanation_revealed", item: IDS.singleChoice },
      { event: "exam_submitted", assessment: IDS.exam, outcome: "passed" },
      stationOpened(3),
      stationOpened(4),
      { event: "format_voted", station: 4 },
    ]);
    for (const secret of [
      TEST_USER.id,
      TEST_USER.display_name,
      TEST_USER.email,
      CSRF_TOKEN,
    ])
      expect(raw).not.toContain(secret);
    expect(keysOf(sessionStorage)).toEqual([TEST_NOTES_KEY]);
    for (const [index, storage] of setItem.mock.contexts.entries())
      if (storage === sessionStorage)
        expect(setItem.mock.calls[index][0]).toBe(TEST_NOTES_KEY);

    const panel = screen.getByRole("region", { name: "Test notes" });
    const log = within(panel).getByRole("textbox", {
      name: "Recorded events",
    }) as HTMLTextAreaElement;
    expect(log.value.split("\n")).toHaveLength(9);
    expect(log.value).toMatch(/^\+0:00 Station 1 opened$/m);
    expect(log.value).toContain("Path switched: Short path");
    expect(log.value).toContain(`Item ${IDS.singleChoice} answered wrongly`);
    expect(log.value).toContain(`Exam ${IDS.exam} passed`);
    expect(log.value).toContain("Vote for a format at station 4");

    // No request carries the log, its key or one of its events.
    const { requests, urls } = rendered;
    expect(requests.length).toBeGreaterThan(0);
    expect(urls.length).toBeGreaterThanOrEqual(requests.length);
    for (const text of [...requests.map(sentText), ...urls]) {
      expect(text).not.toContain(raw);
      expect(text).not.toContain(TEST_NOTES_KEY);
      expect(text).not.toContain(log.value.split("\n")[0]);
      for (const name of EVENT_NAMES) expect(text).not.toContain(name);
    }
  });

  test("records nothing and shows no panel while flags.testNotes is false", async () => {
    const rendered = renderProgram(false);
    const setItem = vi.spyOn(Storage.prototype, "setItem");

    await walkThrough(rendered);

    expect(setItem.mock.contexts).not.toContain(sessionStorage);
    expect(keysOf(sessionStorage)).toEqual([]);
    expect(screen.queryByRole("region", { name: "Test notes" })).toBeNull();
  });
});
