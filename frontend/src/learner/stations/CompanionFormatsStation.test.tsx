import { screen, waitFor, within } from "@testing-library/react";
import { describe, expect, test } from "vitest";
import type { Participation } from "../../api/insights";
import { PlayerProvider } from "../../player/PlayerProvider";
import { RuntimeContext } from "../../player/RuntimeContext";
import type {
  CompanionFormat,
  ProgramView,
  Station,
} from "../../player/runtime";
import { expectNoAxeViolations } from "../../test/axe";
import { fakeRuntime, id, IDS, programFixture, SLUG } from "../../test/player";
import {
  renderWithProviders,
  requestsTo,
  type StubResponses,
} from "../../test/render";
import { signedInPayload } from "../../test/session";
import { CompanionFormatsStation } from "./CompanionFormatsStation";

/**
 * Task 0014 step 6: the companion formats station shows one card per
 * format with its phases, its description and a "Would use" toggle. The
 * toggle posts the vote once and then stays pressed and disabled, the
 * station states that the choice is anonymous and cannot be changed, and a
 * second visit reads the earlier votes from the participation.
 */
const MENTORING = id(62);

const mentoring: CompanionFormat = {
  id: MENTORING,
  key: "mentoring",
  title: "Peer mentoring",
  description: "Two colleagues meet once a month.",
  phases: ["update"],
  attendance_counts: false,
};

/** The fixture program with the workshop and a second format. */
function program(): ProgramView {
  const fixture = programFixture();
  return {
    ...fixture,
    companion_formats: [...fixture.companion_formats, mentoring],
  };
}

const station = programFixture().stations[3];

const participation = (
  overrides: Partial<Participation> = {},
): Participation => ({
  self_assessment: false,
  feedback: false,
  format_votes: [],
  ...overrides,
});

const votePath = (formatId: string) => `/api/formats/${formatId}/votes`;

function renderStation(
  responses: StubResponses = {},
  fixture: ProgramView = program(),
  shown: Station = station,
) {
  return renderWithProviders(
    <RuntimeContext.Provider value={fakeRuntime({ program: fixture })}>
      <PlayerProvider slug={SLUG}>
        <CompanionFormatsStation station={shown} />
      </PlayerProvider>
    </RuntimeContext.Provider>,
    {
      route: `/programs/${SLUG}/stations/${shown.position}`,
      session: signedInPayload("mfa"),
      responses: {
        "GET /api/me/participation": [
          { status: 200, body: participation() },
          {
            status: 200,
            body: participation({ format_votes: [IDS.workshop] }),
          },
        ],
        [`POST ${votePath(IDS.workshop)}`]: {
          status: 200,
          body: { already_recorded: false },
        },
        ...responses,
      },
    },
  );
}

const card = (name: string) => screen.findByRole("article", { name });
const toggle = (scope: HTMLElement) =>
  within(scope).getByRole("button", { name: "Would use" });

describe("CompanionFormatsStation", () => {
  test("shows the intro, the anonymity note and one card per format with phases and description", async () => {
    const { container } = renderStation();

    const workshop = await card("Team workshop");
    expect(
      screen.getByText("Formats outside the platform."),
    ).toBeInTheDocument();
    expect(
      screen.getByText(
        "Your choice is anonymous: it is stored without your name and cannot be changed afterwards.",
      ),
    ).toBeInTheDocument();
    expect(
      screen.getAllByRole("article").map((article) => article.dataset.format),
    ).toEqual(["workshop", "mentoring"]);
    expect(workshop).toHaveTextContent("Phases: Apply, Anchor");
    expect(within(workshop).getByText("A two-hour session.")).toHaveAttribute(
      "lang",
      "en",
    );
    expect(
      within(workshop).getByRole("heading", { name: "Team workshop" }),
    ).toHaveAttribute("lang", "en");
    expect(await card("Peer mentoring")).toHaveTextContent("Phases: Update");
    expect(toggle(workshop)).toHaveAttribute("aria-pressed", "false");
    expect(toggle(workshop)).toBeEnabled();
    expect(toggle(workshop)).toHaveAccessibleDescription("Team workshop");
    await expectNoAxeViolations(container);
  });

  test("the toggle posts the vote once and then stays pressed and disabled", async () => {
    const { requests, user, container } = renderStation();
    const workshop = await card("Team workshop");

    await user.click(toggle(workshop));

    await waitFor(() =>
      expect(toggle(workshop)).toHaveAttribute("aria-pressed", "true"),
    );
    expect(toggle(workshop)).toBeDisabled();
    expect(within(workshop).getByRole("status")).toHaveTextContent(
      "Your vote is recorded.",
    );
    expect(requestsTo(requests, "POST", votePath(IDS.workshop))).toHaveLength(
      1,
    );
    expect(
      requestsTo(requests, "POST", votePath(IDS.workshop))[0].body,
    ).toEqual({ choice: "would_use" });

    await user.click(toggle(workshop));
    expect(requestsTo(requests, "POST", votePath(IDS.workshop))).toHaveLength(
      1,
    );
    // The other format stays open for a vote.
    const other = await card("Peer mentoring");
    expect(toggle(other)).toHaveAttribute("aria-pressed", "false");
    expect(toggle(other)).toBeEnabled();
    await expectNoAxeViolations(container);
  });

  test("a second visit shows the earlier vote pressed and disabled without a post", async () => {
    const { requests } = renderStation({
      "GET /api/me/participation": {
        status: 200,
        body: participation({ format_votes: [MENTORING] }),
      },
    });

    const other = await card("Peer mentoring");
    expect(toggle(other)).toHaveAttribute("aria-pressed", "true");
    expect(toggle(other)).toBeDisabled();
    expect(toggle(await card("Team workshop"))).toHaveAttribute(
      "aria-pressed",
      "false",
    );
    expect(
      requests.filter((request) => request.method === "POST"),
    ).toHaveLength(0);
  });

  test("a failed vote shows an error and leaves the toggle open", async () => {
    const { user } = renderStation({
      [`POST ${votePath(IDS.workshop)}`]: {
        status: 500,
        body: { error: "internal" },
      },
    });
    const workshop = await card("Team workshop");

    await user.click(toggle(workshop));

    expect(await within(workshop).findByRole("alert")).toHaveTextContent(
      "Your vote could not be saved. Please try again.",
    );
    expect(toggle(workshop)).toHaveAttribute("aria-pressed", "false");
    expect(toggle(workshop)).toBeEnabled();
  });

  test("a program without formats says so and offers no toggle", async () => {
    const fixture = { ...programFixture(), companion_formats: [] };
    const { requests } = renderStation({}, fixture);

    expect(
      await screen.findByText("This program has no companion formats."),
    ).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Would use" })).toBeNull();
    expect(
      requests.filter((request) => request.method === "POST"),
    ).toHaveLength(0);
  });
});
