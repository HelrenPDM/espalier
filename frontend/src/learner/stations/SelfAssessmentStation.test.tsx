import { screen, waitFor, within } from "@testing-library/react";
import { describe, expect, test } from "vitest";
import type { Participation } from "../../api/insights";
import type { components } from "../../api/schema";
import { PlayerProvider } from "../../player/PlayerProvider";
import { RuntimeContext } from "../../player/RuntimeContext";
import {
  emptyResumeState,
  type ProgramView,
  type Runtime,
  type Segment,
  type Station,
} from "../../player/runtime";
import { PlatformRuntime } from "../../runtimes/platform";
import { expectNoAxeViolations } from "../../test/axe";
import {
  fakeRuntime,
  id,
  programFixture,
  SLUG,
  type FakeRuntime,
} from "../../test/player";
import {
  renderWithProviders,
  requestsTo,
  type StubResponses,
} from "../../test/render";
import { signedInPayload } from "../../test/session";
import { SelfAssessmentStation } from "./SelfAssessmentStation";

/**
 * Task 0014 step 5: the self-assessment station shows the question, one
 * card per segment, the note that the answer is stored without the name
 * and only preselects the path, and a skip link. Choosing a segment posts
 * the self-assessment and shows the path that the server set with the path
 * switch, which the player takes over through `refreshPath()` without a
 * manual path change. The station states whether the default path was
 * preselected or the path chosen by hand stayed, and when the path cannot
 * be loaded after one more try, that it appears after a reload; a second
 * visit states that the answer was recorded.
 */
type Progress = components["schemas"]["Progress"];

const SEGMENTS: Segment[] = [
  {
    key: "newsroom",
    label: "Newsroom",
    description: "You write and edit texts every day.",
    default_path: "short",
  },
  {
    key: "office",
    label: "Office",
    description: "You use texts now and then.",
    default_path: "full",
  },
];

const station: Station = {
  kind: "self_assessment",
  position: 5,
  title: "Where do you start?",
  intro: "One question before you start.",
  module_id: null,
  question: "Which describes your work best?",
  questions: [],
};

const feedbackStation: Station = {
  kind: "feedback",
  position: 6,
  title: "Your feedback",
  intro: null,
  module_id: null,
  question: null,
  questions: [],
};

/** The fixture program with segments and the stations 5 and 6. */
function program(): ProgramView {
  const fixture = programFixture();
  return {
    ...fixture,
    segments: SEGMENTS,
    stations: [...fixture.stations, station, feedbackStation],
  };
}

const participation = (
  overrides: Partial<Participation> = {},
): Participation => ({
  self_assessment: false,
  feedback: false,
  format_votes: [],
  ...overrides,
});

const PARTICIPATION = "GET /api/me/participation";
const POST_PATH = "/api/self-assessments";

function renderStation({
  runtime = fakeRuntime({ program: program() }),
  responses = {},
}: { runtime?: FakeRuntime | Runtime; responses?: StubResponses } = {}) {
  return renderWithProviders(
    <RuntimeContext.Provider value={runtime}>
      <PlayerProvider slug={SLUG}>
        <SelfAssessmentStation station={station} />
      </PlayerProvider>
    </RuntimeContext.Provider>,
    {
      route: `/programs/${SLUG}/stations/${station.position}`,
      session: signedInPayload("mfa"),
      responses: {
        [PARTICIPATION]: [
          { status: 200, body: participation() },
          { status: 200, body: participation({ self_assessment: true }) },
        ],
        [`POST ${POST_PATH}`]: {
          status: 200,
          body: { path: "short", already_recorded: false },
        },
        ...responses,
      },
    },
  );
}

const segmentButton = (name: string) => screen.findByRole("button", { name });

describe("SelfAssessmentStation", () => {
  test("shows the question, one card per segment, the privacy note and a skip link", async () => {
    const { container } = renderStation();

    const newsroom = await segmentButton("Newsroom");
    expect(
      screen.getByRole("heading", { name: "Which describes your work best?" }),
    ).toHaveAttribute("lang", "en");
    expect(
      screen.getByText("One question before you start."),
    ).toBeInTheDocument();
    expect(
      screen.getByText(
        "Your answer is stored without your name. It only preselects your path, and you can switch the path at any time.",
      ),
    ).toBeInTheDocument();
    const list = screen.getByRole("list", {
      name: "Which describes your work best?",
    });
    expect(
      within(list)
        .getAllByRole("button")
        .map((button) => button.getAttribute("data-segment")),
    ).toEqual(["newsroom", "office"]);
    expect(newsroom).toHaveAccessibleDescription(
      "You write and edit texts every day. Suggested: Short path",
    );
    expect(
      screen.getByRole("button", { name: "Office" }),
    ).toHaveAccessibleDescription(
      "You use texts now and then. Suggested: Full path",
    );
    expect(screen.getByText("Newsroom")).toHaveAttribute("lang", "en");
    expect(
      screen.getByRole("link", { name: "Skip this question" }),
    ).toHaveAttribute("href", `/programs/${SLUG}/stations/6`);
    await expectNoAxeViolations(container);
  });

  test("choosing a segment posts it and shows the path that the server set without a manual change", async () => {
    const runtime = fakeRuntime({ program: program() });
    const { requests, user } = renderStation({ runtime });
    const newsroom = await segmentButton("Newsroom");
    // The server applies the default path of the segment.
    runtime.loadState.mockResolvedValue(emptyResumeState("short"));
    const savesBefore = runtime.saveState.mock.calls.length;

    await user.click(newsroom);

    expect(
      await screen.findByText(
        "Your answer is recorded. It preselected the path below, and you can switch it.",
      ),
    ).toBeInTheDocument();
    expect(requestsTo(requests, "POST", POST_PATH)).toHaveLength(1);
    expect(requestsTo(requests, "POST", POST_PATH)[0].body).toEqual({
      program_slug: SLUG,
      segment_key: "newsroom",
    });
    expect(screen.getByRole("radio", { name: "Short path" })).toBeChecked();
    expect(screen.getByRole("radio", { name: "Full path" })).not.toBeChecked();
    // The path came from loadState; no save sent it as a manual choice.
    expect(runtime.saveState.mock.calls.length).toBe(savesBefore);
    expect(screen.queryByRole("button", { name: "Newsroom" })).toBeNull();
    // The participation reloads after the post.
    expect(requestsTo(requests, "GET", "/api/me/participation")).toHaveLength(
      2,
    );
  });

  test("a path that the learner chose by hand stays, and the station says so", async () => {
    const runtime = fakeRuntime({ program: program() });
    const { requests, user } = renderStation({
      runtime,
      responses: {
        // The learner had switched to the full path by hand, so the server
        // keeps it instead of the default path of the segment.
        [`POST ${POST_PATH}`]: {
          status: 200,
          body: { path: "full", already_recorded: false },
        },
      },
    });
    const newsroom = await segmentButton("Newsroom");
    runtime.loadState.mockResolvedValue(emptyResumeState("full"));
    const savesBefore = runtime.saveState.mock.calls.length;

    await user.click(newsroom);

    const kept = await screen.findByText(
      "Your answer is recorded. You chose your path yourself before, so the path below stays as it was, and you can switch it.",
    );
    expect(kept).toHaveAttribute("data-outcome", "kept");
    expect(screen.queryByText(/It preselected the path below/)).toBeNull();
    expect(screen.getByRole("radio", { name: "Full path" })).toBeChecked();
    expect(runtime.saveState.mock.calls.length).toBe(savesBefore);
    expect(requestsTo(requests, "POST", POST_PATH)).toHaveLength(1);
  });

  test("a failed load of the path is tried once more", async () => {
    const runtime = fakeRuntime({ program: program() });
    const { user } = renderStation({ runtime });
    const newsroom = await segmentButton("Newsroom");
    const loadsBefore = runtime.loadState.mock.calls.length;
    runtime.loadState
      .mockRejectedValueOnce(new Error("offline"))
      .mockResolvedValueOnce(emptyResumeState("short"));
    const savesBefore = runtime.saveState.mock.calls.length;

    await user.click(newsroom);

    expect(
      await screen.findByText(
        "Your answer is recorded. It preselected the path below, and you can switch it.",
      ),
    ).toHaveAttribute("data-outcome", "recorded");
    expect(runtime.loadState.mock.calls.length - loadsBefore).toBe(2);
    expect(screen.getByRole("radio", { name: "Short path" })).toBeChecked();
    expect(runtime.saveState.mock.calls.length).toBe(savesBefore);
  });

  test("when the path cannot be loaded twice, the station says that it appears after a reload", async () => {
    const runtime = fakeRuntime({ program: program() });
    const { container, user } = renderStation({ runtime });
    const newsroom = await segmentButton("Newsroom");
    const loadsBefore = runtime.loadState.mock.calls.length;
    runtime.loadState
      .mockRejectedValueOnce(new Error("offline"))
      .mockRejectedValueOnce(new Error("offline"));
    const savesBefore = runtime.saveState.mock.calls.length;

    await user.click(newsroom);

    expect(
      await screen.findByText(
        "Your answer is recorded. The path that applies now appears below after you reload the page.",
      ),
    ).toHaveAttribute("data-outcome", "reload");
    expect(screen.queryByText(/It preselected the path below/)).toBeNull();
    expect(runtime.loadState.mock.calls.length - loadsBefore).toBe(2);
    // The station does not put the returned path into the player, which
    // would send it as a manual choice.
    expect(runtime.saveState.mock.calls.length).toBe(savesBefore);
    expect(screen.getByRole("radio", { name: "Full path" })).toBeChecked();
    await expectNoAxeViolations(container);
  });

  test("with the platform runtime, the server's path reaches the path switch without a PATCH of the enrollment", async () => {
    const enrollmentId = id(500);
    let serverPath: "short" | "full" = "full";
    const progress = (): Progress => ({
      enrollment: {
        id: enrollmentId,
        path: serverPath,
        path_chosen_manually: false,
      },
      completed_module_ids: [],
      exams: [],
      objectives: [],
    });
    const { modules, glossary, ...rest } = program();
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
    const responses: StubResponses = {
      [`GET /api/programs/${SLUG}`]: {
        status: 200,
        body: { ...rest, modules: summaries },
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
      [`POST ${POST_PATH}`]: () => {
        serverPath = "short";
        return {
          status: 200,
          body: { path: "short", already_recorded: false },
        };
      },
      [`PATCH /api/enrollments/${enrollmentId}`]: (request) => ({
        status: 200,
        body: {
          id: enrollmentId,
          path: (request.body as { path: "short" | "full" }).path,
          path_chosen_manually: true,
          program_id: id(100),
          started_at: "2026-10-11T09:00:00Z",
        },
      }),
    };
    // The runtime needs the API client of the render, so every call waits
    // until the render has created it.
    let created: (runtime: PlatformRuntime) => void = () => {};
    const ready = new Promise<PlatformRuntime>((resolve) => {
      created = resolve;
    });
    const lazy: Runtime = {
      loadProgram: async (slug) => (await ready).loadProgram(slug),
      submitItem: async (itemId, answer) =>
        (await ready).submitItem(itemId, answer),
      submitAssessment: async (assessmentId, answers) =>
        (await ready).submitAssessment(assessmentId, answers),
      completeModule: async (moduleId) =>
        (await ready).completeModule(moduleId),
      loadState: async () => (await ready).loadState(),
      saveState: async (state) => (await ready).saveState(state),
    };
    const memory = new Map<string, string>();
    const storage = {
      getItem: (key: string) => memory.get(key) ?? null,
      setItem: (key: string, value: string) => void memory.set(key, value),
    };
    const rendered = renderStation({ runtime: lazy, responses });
    const platform = new PlatformRuntime(SLUG, {
      client: rendered.client,
      storage,
    });
    created(platform);
    const { requests, user } = rendered;

    await user.click(await segmentButton("Newsroom"));

    await waitFor(() =>
      expect(screen.getByRole("radio", { name: "Short path" })).toBeChecked(),
    );
    expect(
      requestsTo(requests, "PATCH", `/api/enrollments/${enrollmentId}`),
    ).toHaveLength(0);
    // A later save with the adopted path sends no PATCH either.
    await platform.saveState(emptyResumeState("short"));
    expect(
      requestsTo(requests, "PATCH", `/api/enrollments/${enrollmentId}`),
    ).toHaveLength(0);

    // Switching by hand sends the path as a manual choice.
    await user.click(screen.getByRole("radio", { name: "Full path" }));
    await waitFor(() =>
      expect(
        requestsTo(requests, "PATCH", `/api/enrollments/${enrollmentId}`),
      ).toHaveLength(1),
    );
    expect(
      requestsTo(requests, "PATCH", `/api/enrollments/${enrollmentId}`)[0].body,
    ).toEqual({ path: "full" });
  });

  test("a second visit shows the current path and states that the answer was recorded", async () => {
    const runtime = fakeRuntime({
      program: program(),
      state: emptyResumeState("short"),
    });
    const { container, requests } = renderStation({
      runtime,
      responses: {
        [PARTICIPATION]: {
          status: 200,
          body: participation({ self_assessment: true }),
        },
      },
    });

    expect(
      await screen.findByText(
        "Your answer was already recorded. The path below is your current path, and you can switch it.",
      ),
    ).toBeInTheDocument();
    expect(screen.getByRole("radio", { name: "Short path" })).toBeChecked();
    expect(screen.queryByRole("button", { name: "Newsroom" })).toBeNull();
    expect(
      screen.queryByRole("link", { name: "Skip this question" }),
    ).toBeNull();
    expect(requestsTo(requests, "POST", POST_PATH)).toHaveLength(0);
    await expectNoAxeViolations(container);
  });

  test("an answer that the server had recorded before is stated as such", async () => {
    const { user } = renderStation({
      responses: {
        [`POST ${POST_PATH}`]: {
          status: 200,
          body: { path: "full", already_recorded: true },
        },
      },
    });

    await user.click(await segmentButton("Office"));

    expect(
      await screen.findByText(
        "Your answer was already recorded. The path below is your current path, and you can switch it.",
      ),
    ).toBeInTheDocument();
  });

  test("the skip link leads to the next station and sends nothing", async () => {
    const runtime = fakeRuntime({ program: program() });
    const { requests, user, location } = renderStation({ runtime });
    await segmentButton("Newsroom");
    const savesBefore = runtime.saveState.mock.calls.length;

    await user.click(screen.getByRole("link", { name: "Skip this question" }));

    expect(location()).toBe(`/programs/${SLUG}/stations/6`);
    expect(requestsTo(requests, "POST", POST_PATH)).toHaveLength(0);
    expect(runtime.saveState.mock.calls.length).toBe(savesBefore);
  });

  test("a failed post shows an error and keeps the segments", async () => {
    const { user } = renderStation({
      responses: {
        [`POST ${POST_PATH}`]: [
          { status: 500, body: { error: "internal" } },
          {
            status: 429,
            body: { error: "rate_limited" },
            headers: { "retry-after": "120" },
          },
        ],
      },
    });

    await user.click(await segmentButton("Newsroom"));
    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Your answer could not be saved. Please try again.",
    );
    expect(screen.getByRole("button", { name: "Newsroom" })).toBeEnabled();

    await user.click(screen.getByRole("button", { name: "Newsroom" }));
    await waitFor(() =>
      expect(screen.getByRole("alert")).toHaveTextContent(
        "Too many attempts. Try again in 2 minutes.",
      ),
    );
  });
});
