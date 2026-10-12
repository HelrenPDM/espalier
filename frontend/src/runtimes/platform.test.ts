import { QueryClient } from "@tanstack/react-query";
import { beforeEach, describe, expect, test, vi } from "vitest";
import { createApiClient } from "../api/client";
import type { components } from "../api/schema";
import { sessionQueryKey, toSession } from "../api/session";
import {
  AssessmentsOpenError,
  emptyResumeState,
  type ResumeState,
} from "../player/runtime";
import { id, IDS, module1, module2, programFixture } from "../test/player";
import { requestsTo, stubFetch, type StubResponses } from "../test/render";
import { signedInPayload } from "../test/session";
import {
  entryOwner,
  PlatformRuntime,
  playerStorageKey,
  type PlayerStorage,
} from "./platform";

type Progress = components["schemas"]["Progress"];
type EnrollmentView = components["schemas"]["EnrollmentView"];

const SLUG = "demo";
const KEY = "espalier.player.demo";
const ENROLLMENT_ID = id(500);
// The owner tag of the entry of ENROLLMENT_ID and of another person's
// enrollment in the same program.
const OWNER = (await entryOwner(ENROLLMENT_ID)) as string;
const OTHER_OWNER = (await entryOwner(id(501))) as string;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/** A progress answer with an enrollment on the full path and no records. */
const progress = (overrides: Partial<Progress> = {}): Progress => ({
  enrollment: {
    id: ENROLLMENT_ID,
    path: "full",
    path_chosen_manually: false,
  },
  completed_module_ids: [],
  exams: [],
  objectives: [],
  ...overrides,
});

const enrollmentView = (
  path: EnrollmentView["path"],
  overrides: Partial<EnrollmentView> = {},
): EnrollmentView => ({
  id: ENROLLMENT_ID,
  path,
  path_chosen_manually: false,
  program_id: id(100),
  started_at: "2026-10-11T09:00:00Z",
  ...overrides,
});

/** A storage object in memory, with `getItem` and `setItem` as mocks. */
function memoryStorage(initial: Record<string, string> = {}) {
  const values = new Map(Object.entries(initial));
  return {
    values,
    getItem: vi.fn((key: string) => values.get(key) ?? null),
    setItem: vi.fn((key: string, value: string) => {
      values.set(key, value);
    }),
  };
}

type Storage = ReturnType<typeof memoryStorage>;

let queryClient: QueryClient;

beforeEach(() => {
  queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });
  // Mutating requests carry the CSRF token of the cached session.
  queryClient.setQueryData(
    sessionQueryKey,
    toSession(signedInPayload("mfa", { csrf_token: "csrf-1" })),
  );
});

/** A runtime of the program `slug` over `stubFetch(responses)` and `storage`. */
function setup(
  responses: StubResponses,
  {
    storage = memoryStorage(),
    slug = SLUG,
  }: { storage?: PlayerStorage; slug?: string } = {},
) {
  const { fetchImpl, requests } = stubFetch(responses);
  const client = createApiClient(queryClient, fetchImpl);
  const runtime = new PlatformRuntime(slug, { client, storage });
  return { runtime, requests, fetchImpl };
}

/** The parsed entry that the runtime wrote under `KEY`. */
function writtenEntry(storage: Storage): Record<string, unknown> {
  const raw = storage.values.get(KEY);
  expect(raw).toBeDefined();
  return JSON.parse(raw as string) as Record<string, unknown>;
}

/** A state that holds every member, the server-side ones included. */
function fullState(overrides: Partial<ResumeState> = {}): ResumeState {
  return {
    ...emptyResumeState("full"),
    openedExplanations: [IDS.explanationShort],
    visitedStations: [1, 2],
    answeredItems: [IDS.multipleChoice, IDS.singleChoice],
    completedModules: [IDS.module1],
    examOutcomes: { [IDS.exam]: "passed" },
    evidencedObjectives: ["m1-subject-evidenced", "m1-subject-exam"],
    ...overrides,
  };
}

describe("loadState", () => {
  test("creates the enrollment on the full path when the progress holds none", async () => {
    const { runtime, requests, fetchImpl } = setup({
      "GET /api/me/progress": {
        status: 200,
        body: progress({ enrollment: null }),
      },
      "POST /api/enrollments": { status: 201, body: enrollmentView("full") },
    });

    const state = await runtime.loadState();

    const posts = requestsTo(requests, "POST", "/api/enrollments");
    expect(posts).toHaveLength(1);
    expect(posts[0].body).toEqual({ program_slug: SLUG, path: "full" });
    expect(posts[0].headers.get("x-csrf-token")).toBe("csrf-1");
    expect(state.path).toBe("full");
    // The progress is read for the program of the runtime.
    const progressUrl = new URL((fetchImpl.mock.calls[0][0] as Request).url);
    expect(progressUrl.pathname).toBe("/api/me/progress");
    expect(progressUrl.searchParams.get("program")).toBe(SLUG);
  });

  test("creates no enrollment when the progress holds one", async () => {
    const { runtime, requests } = setup({
      "GET /api/me/progress": {
        status: 200,
        body: progress({
          enrollment: {
            id: ENROLLMENT_ID,
            path: "short",
            path_chosen_manually: true,
          },
        }),
      },
    });

    const state = await runtime.loadState();

    expect(requestsTo(requests, "POST", "/api/enrollments")).toHaveLength(0);
    expect(state.path).toBe("short");
  });

  test("takes the completed modules and the exam outcomes from the server", async () => {
    const { runtime } = setup({
      "GET /api/me/progress": {
        status: 200,
        body: progress({
          completed_module_ids: [IDS.module1],
          exams: [{ assessment_id: IDS.exam, outcome: "failed_core" }],
        }),
      },
    });

    const state = await runtime.loadState();

    expect(state.completedModules).toEqual([IDS.module1]);
    expect(state.examOutcomes).toEqual({ [IDS.exam]: "failed_core" });
  });

  test.each([
    ["standard", { answered_item_ids: [IDS.singleChoice] }],
    ["minimal", {}],
  ])(
    "gives evidencedObjectives with the evidenced keys only (%s)",
    async (_setting, tracking) => {
      const { runtime } = setup({
        "GET /api/me/progress": {
          status: 200,
          body: progress({
            ...tracking,
            objectives: [
              { key: "m1-subject-evidenced", status: "evidenced" },
              { key: "m1-subject-exam", status: "open" },
              { key: "m1-method-practice", status: "evidenced" },
              { key: "m1-self-format", status: "open" },
            ],
          }),
        },
      });

      const state = await runtime.loadState();

      expect(state.evidencedObjectives).toEqual([
        "m1-subject-evidenced",
        "m1-method-practice",
      ]);
    },
  );

  test("reads the entry under espalier.player.<slug>", async () => {
    const storage = memoryStorage({
      "espalier.player.ai-basics": JSON.stringify({
        v: 2,
        o: OWNER,
        openedExplanations: [IDS.explanationShort],
        visitedStations: [2],
      }),
    });
    const { runtime } = setup(
      { "GET /api/me/progress": { status: 200, body: progress() } },
      { storage, slug: "ai-basics" },
    );

    const state = await runtime.loadState();

    expect(playerStorageKey("ai-basics")).toBe("espalier.player.ai-basics");
    expect(storage.getItem).toHaveBeenCalledWith("espalier.player.ai-basics");
    expect(state.openedExplanations).toEqual([IDS.explanationShort]);
    expect(state.visitedStations).toEqual([2]);
  });

  test.each([
    ["a missing entry", undefined],
    ["invalid JSON", "{not json"],
    ["a JSON value that is no object", "[1,2]"],
    ["JSON null", "null"],
    [
      "another version",
      JSON.stringify({
        v: 3,
        o: OWNER,
        openedExplanations: [IDS.explanationShort],
        visitedStations: [2],
        answeredItems: [IDS.singleChoice],
      }),
    ],
    [
      "an entry of version 1, which has no owner",
      JSON.stringify({
        v: 1,
        openedExplanations: [IDS.explanationShort],
        visitedStations: [2],
        answeredItems: [IDS.singleChoice],
      }),
    ],
    [
      "an entry without an owner",
      JSON.stringify({
        v: 2,
        openedExplanations: [IDS.explanationShort],
        visitedStations: [2],
        answeredItems: [IDS.singleChoice],
      }),
    ],
    [
      "an entry of another person",
      JSON.stringify({
        v: 2,
        o: OTHER_OWNER,
        openedExplanations: [IDS.explanationShort],
        visitedStations: [2],
        answeredItems: [IDS.singleChoice],
      }),
    ],
    [
      "an entry without a version",
      JSON.stringify({
        openedExplanations: [IDS.explanationShort],
        visitedStations: [2],
        answeredItems: [IDS.singleChoice],
      }),
    ],
    [
      "members of the wrong type",
      JSON.stringify({
        v: 2,
        o: OWNER,
        openedExplanations: IDS.explanationShort,
        visitedStations: { 2: true },
        answeredItems: 5,
      }),
    ],
    [
      "list entries of the wrong type",
      JSON.stringify({
        v: 2,
        o: OWNER,
        openedExplanations: [1, null, { id: IDS.explanationShort }],
        visitedStations: ["2", 1.5, null],
        answeredItems: [false, [IDS.singleChoice]],
      }),
    ],
  ])("yields empty lists for %s", async (_case, raw) => {
    const storage = memoryStorage(raw === undefined ? {} : { [KEY]: raw });
    // Without the ids of answered items, `answeredItems` comes from the entry.
    const { runtime } = setup(
      { "GET /api/me/progress": { status: 200, body: progress() } },
      { storage },
    );

    const state = await runtime.loadState();

    expect(state.openedExplanations).toEqual([]);
    expect(state.visitedStations).toEqual([]);
    expect(state.answeredItems).toEqual([]);
  });

  test("works with a storage whose getItem and setItem throw", async () => {
    const storage = {
      getItem: vi.fn(() => {
        throw new DOMException("Blocked", "SecurityError");
      }),
      setItem: vi.fn(() => {
        throw new DOMException("Full", "QuotaExceededError");
      }),
    };
    const { runtime, requests } = setup(
      {
        "GET /api/me/progress": { status: 200, body: progress() },
        "PATCH /api/enrollments/00000000-0000-4000-8000-000000000500": {
          status: 200,
          body: enrollmentView("short", { path_chosen_manually: true }),
        },
      },
      { storage },
    );

    const state = await runtime.loadState();
    expect(state.openedExplanations).toEqual([]);
    expect(state.visitedStations).toEqual([]);
    expect(state.answeredItems).toEqual([]);

    await expect(
      runtime.saveState({ ...state, path: "short" }),
    ).resolves.toBeUndefined();
    expect(storage.getItem).toHaveBeenCalled();
    expect(storage.setItem).toHaveBeenCalled();
    // The path still reaches the server.
    expect(
      requestsTo(requests, "PATCH", `/api/enrollments/${ENROLLMENT_ID}`),
    ).toHaveLength(1);
  });
});

describe("saveState", () => {
  const patchPath = `/api/enrollments/${ENROLLMENT_ID}`;

  test("sends PATCH /api/enrollments/:id with the path only when the path changes", async () => {
    const { runtime, requests } = setup({
      "GET /api/me/progress": { status: 200, body: progress() },
      [`PATCH ${patchPath}`]: {
        status: 200,
        body: enrollmentView("short", { path_chosen_manually: true }),
      },
    });
    const state = await runtime.loadState();

    await runtime.saveState({ ...state, visitedStations: [1] });
    expect(requestsTo(requests, "PATCH", patchPath)).toHaveLength(0);

    await runtime.saveState({ ...state, path: "short" });
    const patches = requestsTo(requests, "PATCH", patchPath);
    expect(patches).toHaveLength(1);
    expect(patches[0].body).toEqual({ path: "short" });
    expect(patches[0].headers.get("x-csrf-token")).toBe("csrf-1");

    // The enrollment is on the short path now, so the same path sends nothing.
    await runtime.saveState({
      ...state,
      path: "short",
      openedExplanations: [IDS.explanationShort],
    });
    expect(requestsTo(requests, "PATCH", patchPath)).toHaveLength(1);
  });

  test("writes the entry under espalier.player.<slug>", async () => {
    const storage = memoryStorage();
    const { runtime } = setup(
      { "GET /api/me/progress": { status: 200, body: progress() } },
      { storage },
    );
    const state = await runtime.loadState();

    await runtime.saveState(state);

    expect(storage.setItem).toHaveBeenCalledWith(KEY, expect.any(String));
    expect([...storage.values.keys()]).toEqual([KEY]);
  });

  test("two path changes in quick succession end with the last path on the server", async () => {
    let serverPath: EnrollmentView["path"] = "full";
    const { runtime, requests } = setup({
      "GET /api/me/progress": { status: 200, body: progress() },
      // The first change answers later than the second would.
      [`PATCH ${patchPath}`]: async (request) => {
        const { path } = request.body as { path: EnrollmentView["path"] };
        await new Promise((resolve) =>
          setTimeout(resolve, path === "short" ? 30 : 0),
        );
        serverPath = path;
        return {
          status: 200,
          body: enrollmentView(path, { path_chosen_manually: true }),
        };
      },
    });
    const state = await runtime.loadState();

    await Promise.all([
      runtime.saveState({ ...state, path: "short" }),
      runtime.saveState({ ...state, path: "full" }),
    ]);

    expect(
      requestsTo(requests, "PATCH", patchPath).map((request) => request.body),
    ).toEqual([{ path: "short" }, { path: "full" }]);
    expect(serverPath).toBe("full");
  });

  test("a failed save does not block the next one", async () => {
    const { runtime, requests } = setup({
      "GET /api/me/progress": { status: 200, body: progress() },
      [`PATCH ${patchPath}`]: [
        { status: 500, body: { error: "internal" } },
        {
          status: 200,
          body: enrollmentView("short", { path_chosen_manually: true }),
        },
      ],
    });
    const state = await runtime.loadState();

    await expect(
      runtime.saveState({ ...state, path: "short" }),
    ).rejects.toMatchObject({ status: 500 });
    await expect(
      runtime.saveState({ ...state, path: "short" }),
    ).resolves.toBeUndefined();
    expect(requestsTo(requests, "PATCH", patchPath)).toHaveLength(2);
  });
});

describe("the browser entry", () => {
  /** Strings that belong to the server-side members of `fullState()`. */
  const serverSide = [
    "completedModules",
    "examOutcomes",
    "evidencedObjectives",
    "m1-subject-evidenced",
    "m1-subject-exam",
    IDS.module1,
    IDS.exam,
    "passed",
  ];

  test("standard: answeredItems come from the server, and the entry holds v, o, openedExplanations and visitedStations only", async () => {
    const storage = memoryStorage({
      [KEY]: JSON.stringify({
        v: 2,
        o: OWNER,
        openedExplanations: [IDS.explanationShort],
        visitedStations: [2],
        answeredItems: [IDS.poll],
      }),
    });
    const { runtime, requests } = setup(
      {
        "GET /api/me/progress": {
          status: 200,
          body: progress({
            answered_item_ids: [IDS.singleChoice, IDS.multipleChoice],
          }),
        },
      },
      { storage },
    );

    const state = await runtime.loadState();
    expect(state.answeredItems).toEqual([IDS.singleChoice, IDS.multipleChoice]);
    expect(state.openedExplanations).toEqual([IDS.explanationShort]);
    expect(state.visitedStations).toEqual([2]);

    await runtime.saveState(fullState());

    const entry = writtenEntry(storage);
    expect(Object.keys(entry).sort()).toEqual(
      ["o", "openedExplanations", "v", "visitedStations"].sort(),
    );
    expect(entry).toEqual({
      v: 2,
      o: OWNER,
      openedExplanations: [IDS.explanationShort],
      visitedStations: [1, 2],
    });
    const raw = storage.values.get(KEY) as string;
    for (const value of [...serverSide, "answeredItems"])
      expect(raw).not.toContain(value);
    // The runtime sends nothing of the entry to the server.
    for (const request of requests)
      expect(JSON.stringify(request.body ?? null)).not.toContain(
        "openedExplanations",
      );
  });

  test("minimal: answeredItems come from the entry, and the entry adds answeredItems with item ids only", async () => {
    const storage = memoryStorage({
      [KEY]: JSON.stringify({
        v: 2,
        o: OWNER,
        openedExplanations: [],
        visitedStations: [2],
        answeredItems: [IDS.multipleChoice],
      }),
    });
    const { runtime, requests } = setup(
      { "GET /api/me/progress": { status: 200, body: progress() } },
      { storage },
    );

    const state = await runtime.loadState();
    expect(state.answeredItems).toEqual([IDS.multipleChoice]);

    await runtime.saveState(fullState());

    const entry = writtenEntry(storage);
    expect(Object.keys(entry).sort()).toEqual(
      [
        "answeredItems",
        "o",
        "openedExplanations",
        "v",
        "visitedStations",
      ].sort(),
    );
    expect(entry).toEqual({
      v: 2,
      o: OWNER,
      openedExplanations: [IDS.explanationShort],
      visitedStations: [1, 2],
      answeredItems: [IDS.multipleChoice, IDS.singleChoice],
    });
    const answered = entry.answeredItems as unknown[];
    for (const value of answered) {
      expect(typeof value).toBe("string");
      expect(value).toMatch(UUID);
    }
    const raw = storage.values.get(KEY) as string;
    for (const value of serverSide) expect(raw).not.toContain(value);
    for (const request of requests)
      expect(JSON.stringify(request.body ?? null)).not.toContain(
        "answeredItems",
      );
  });
});

describe("the owner of the entry", () => {
  test("entryOwner gives 16 hexadecimal digits that hold no part of the enrollment id", async () => {
    expect(OWNER).toMatch(/^[0-9a-f]{16}$/);
    expect(await entryOwner(ENROLLMENT_ID)).toBe(OWNER);
    expect(OTHER_OWNER).not.toBe(OWNER);
    for (const part of ENROLLMENT_ID.split("-"))
      if (part.length >= 4) expect(OWNER).not.toContain(part);
  });

  test("a second person on the same browser starts with empty lists and replaces the entry", async () => {
    // The first person visited stations 1 and 2 in this browser.
    const storage = memoryStorage({
      [KEY]: JSON.stringify({
        v: 2,
        o: OTHER_OWNER,
        openedExplanations: [IDS.explanationShort],
        visitedStations: [1, 2],
        answeredItems: [IDS.singleChoice],
      }),
    });
    const { runtime } = setup(
      { "GET /api/me/progress": { status: 200, body: progress() } },
      { storage },
    );

    const state = await runtime.loadState();
    expect(state.openedExplanations).toEqual([]);
    expect(state.visitedStations).toEqual([]);
    expect(state.answeredItems).toEqual([]);

    await runtime.saveState({ ...state, visitedStations: [3] });
    expect(writtenEntry(storage)).toEqual({
      v: 2,
      o: OWNER,
      openedExplanations: [],
      visitedStations: [3],
      answeredItems: [],
    });
  });

  test("the same person finds the entry again in a later visit", async () => {
    const storage = memoryStorage();
    const first = setup(
      { "GET /api/me/progress": { status: 200, body: progress() } },
      { storage },
    );
    const state = await first.runtime.loadState();
    await first.runtime.saveState({
      ...state,
      openedExplanations: [IDS.explanationShort],
      visitedStations: [1, 2],
      answeredItems: [IDS.singleChoice],
    });

    const later = setup(
      { "GET /api/me/progress": { status: 200, body: progress() } },
      { storage },
    );
    const restored = await later.runtime.loadState();

    expect(restored.openedExplanations).toEqual([IDS.explanationShort]);
    expect(restored.visitedStations).toEqual([1, 2]);
    expect(restored.answeredItems).toEqual([IDS.singleChoice]);
  });

  test("without a digest the runtime reads and writes no entry and still saves the path", async () => {
    const digest = vi
      .spyOn(crypto.subtle, "digest")
      .mockRejectedValue(new DOMException("Insecure", "NotSupportedError"));
    try {
      const storage = memoryStorage({
        [KEY]: JSON.stringify({
          v: 2,
          o: OWNER,
          openedExplanations: [IDS.explanationShort],
          visitedStations: [2],
        }),
      });
      const { runtime, requests } = setup(
        {
          "GET /api/me/progress": { status: 200, body: progress() },
          [`PATCH /api/enrollments/${ENROLLMENT_ID}`]: {
            status: 200,
            body: enrollmentView("short", { path_chosen_manually: true }),
          },
        },
        { storage },
      );

      const state = await runtime.loadState();
      expect(state.openedExplanations).toEqual([]);
      expect(state.visitedStations).toEqual([]);

      await runtime.saveState({ ...state, path: "short" });
      expect(storage.setItem).not.toHaveBeenCalled();
      expect(
        requestsTo(requests, "PATCH", `/api/enrollments/${ENROLLMENT_ID}`),
      ).toHaveLength(1);
    } finally {
      digest.mockRestore();
    }
  });
});

describe("completeModule", () => {
  const completionPath = `/api/modules/${IDS.module1}/completion`;

  test("resolves after a 200 answer", async () => {
    const { runtime, requests } = setup({
      [`POST ${completionPath}`]: {
        status: 200,
        body: { completed_at: "2026-10-11T10:00:00Z" },
      },
    });

    await expect(runtime.completeModule(IDS.module1)).resolves.toBeUndefined();
    expect(requestsTo(requests, "POST", completionPath)).toHaveLength(1);
  });

  test("rejects a 409 assessments_open with AssessmentsOpenError carrying the exams", async () => {
    const exams = [
      { id: IDS.exam, key: "module-1-exam", title: "Exam of module 1" },
    ];
    const { runtime } = setup({
      [`POST ${completionPath}`]: {
        status: 409,
        body: { error: "assessments_open", assessments: exams },
      },
    });

    const error: unknown = await runtime.completeModule(IDS.module1).then(
      () => null,
      (reason: unknown) => reason,
    );

    expect(error).toBeInstanceOf(AssessmentsOpenError);
    expect((error as AssessmentsOpenError).assessments).toEqual(exams);
  });

  test.each([
    [409, "not_enrolled"],
    [404, "not_found"],
    [429, "rate_limited"],
  ])(
    "rejects another error answer (%i %s) with an Error that carries the status and the code",
    async (status, code) => {
      const { runtime } = setup({
        [`POST ${completionPath}`]: { status, body: { error: code } },
      });

      const error: unknown = await runtime.completeModule(IDS.module1).then(
        () => null,
        (reason: unknown) => reason,
      );

      expect(error).toBeInstanceOf(Error);
      expect(error).not.toBeInstanceOf(AssessmentsOpenError);
      expect(error).toMatchObject({ status, code });
    },
  );
});

describe("submitItem and submitAssessment", () => {
  test("post the answer and the answers", async () => {
    const feedback = {
      item_id: IDS.singleChoice,
      correct: false,
      option_feedback: [],
      rules: [],
      reveals: [IDS.lesson1],
    };
    const attempt = {
      id: id(900),
      assessment_id: IDS.exam,
      number: 1,
      outcome: "passed",
      core_failed: false,
      wrong_count: 0,
      submitted_at: "2026-10-11T10:00:00Z",
      results: [],
    };
    const { runtime, requests } = setup({
      [`POST /api/items/${IDS.singleChoice}/responses`]: {
        status: 200,
        body: feedback,
      },
      [`POST /api/assessments/${IDS.exam}/attempts`]: {
        status: 201,
        body: attempt,
      },
    });

    await expect(
      runtime.submitItem(IDS.singleChoice, { options: ["option-2"] }),
    ).resolves.toEqual(feedback);
    const answers = {
      [IDS.examItem1]: { options: ["option-1"] },
      [IDS.examItem2]: { options: ["option-1"] },
    };
    await expect(runtime.submitAssessment(IDS.exam, answers)).resolves.toEqual(
      attempt,
    );

    expect(
      requestsTo(
        requests,
        "POST",
        `/api/items/${IDS.singleChoice}/responses`,
      )[0].body,
    ).toEqual({ answer: { options: ["option-2"] } });
    expect(
      requestsTo(requests, "POST", `/api/assessments/${IDS.exam}/attempts`)[0]
        .body,
    ).toEqual({ answers });
  });
});

describe("loadProgram", () => {
  test("reads the program, every module and the glossary and returns the modules in program order", async () => {
    const { modules, glossary, ...program } = programFixture();
    const summaries = modules.map(
      ({ id, number, phases, single_path, summary, title }) => ({
        id,
        number,
        phases,
        single_path,
        summary,
        title,
      }),
    );
    const delay = (ms: number) =>
      new Promise((resolve) => setTimeout(resolve, ms));
    const { runtime, requests } = setup({
      [`GET /api/programs/${SLUG}`]: {
        status: 200,
        body: { ...program, modules: summaries },
      },
      // Module 1 answers after module 2.
      [`GET /api/modules/${IDS.module1}`]: async () => {
        await delay(20);
        return { status: 200, body: module1() };
      },
      [`GET /api/modules/${IDS.module2}`]: { status: 200, body: module2() },
      [`GET /api/programs/${SLUG}/glossary`]: {
        status: 200,
        body: { terms: glossary },
      },
    });

    const loaded = await runtime.loadProgram(SLUG);

    expect(loaded.modules.map((module) => module.id)).toEqual([
      IDS.module1,
      IDS.module2,
    ]);
    expect(loaded).toEqual(programFixture());
    expect(loaded.glossary.map((term) => term.slug)).toEqual([
      "llm",
      "sampling",
    ]);
    for (const path of [
      `/api/programs/${SLUG}`,
      `/api/modules/${IDS.module1}`,
      `/api/modules/${IDS.module2}`,
      `/api/programs/${SLUG}/glossary`,
    ])
      expect(requestsTo(requests, "GET", path)).toHaveLength(1);
  });

  test("rejects with the status of a failed read", async () => {
    const { runtime } = setup({});

    await expect(runtime.loadProgram("missing")).rejects.toMatchObject({
      status: 404,
      code: "not_found",
    });
  });
});
