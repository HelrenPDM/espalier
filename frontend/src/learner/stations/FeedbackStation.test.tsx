import { screen, waitFor, within } from "@testing-library/react";
import { describe, expect, test } from "vitest";
import type { Participation } from "../../api/insights";
import type { SessionPayload } from "../../api/session";
import { PlayerProvider } from "../../player/PlayerProvider";
import { RuntimeContext } from "../../player/RuntimeContext";
import type { ProgramView, Station } from "../../player/runtime";
import { expectNoAxeViolations } from "../../test/axe";
import { fakeRuntime, programFixture, SLUG } from "../../test/player";
import {
  renderWithProviders,
  requestsTo,
  type StubResponses,
} from "../../test/render";
import { signedInPayload } from "../../test/session";
import { FeedbackStation } from "./FeedbackStation";

/**
 * Task 0014 step 7: the feedback station renders the questions of the
 * station, single choice and the scale from 1 to 5 as radio groups and free
 * text as a text area of at most 2,000 characters that appears only with
 * `flags.feedbackFreeText`. It sends the answered questions once and then
 * thanks the learner, also on a later visit; an answer of the server that
 * the feedback was recorded before says so, and a failed post shows an
 * error.
 */
const station: Station = {
  kind: "feedback",
  position: 5,
  title: "Your feedback",
  intro: "Tell us how the program worked for you.",
  module_id: null,
  question: null,
  questions: [
    {
      key: "useful",
      kind: "scale",
      label: "How useful was the program?",
      options: [],
    },
    {
      key: "length",
      kind: "single_choice",
      label: "How was the length?",
      options: [
        { key: "too-short", label: "Too short" },
        { key: "right", label: "Just right" },
        { key: "too-long", label: "Too long" },
      ],
    },
    {
      key: "remarks",
      kind: "free_text",
      label: "What should we change?",
      options: [],
    },
  ],
};

/** The fixture program with the feedback station at position 5. */
function program(): ProgramView {
  const fixture = programFixture();
  return { ...fixture, stations: [...fixture.stations, station] };
}

const participation = (
  overrides: Partial<Participation> = {},
): Participation => ({
  self_assessment: false,
  feedback: false,
  format_votes: [],
  ...overrides,
});

const POST_PATH = "/api/feedback";

function renderStation({
  freeText = false,
  responses = {},
}: { freeText?: boolean; responses?: StubResponses } = {}) {
  const session: SessionPayload = signedInPayload("mfa", {
    flags: { feedback_free_text: freeText },
  });
  return renderWithProviders(
    <RuntimeContext.Provider value={fakeRuntime({ program: program() })}>
      <PlayerProvider slug={SLUG}>
        <FeedbackStation station={station} />
      </PlayerProvider>
    </RuntimeContext.Provider>,
    {
      route: `/programs/${SLUG}/stations/${station.position}`,
      session,
      responses: {
        "GET /api/me/participation": [
          { status: 200, body: participation() },
          { status: 200, body: participation({ feedback: true }) },
        ],
        [`POST ${POST_PATH}`]: {
          status: 200,
          body: { already_recorded: false },
        },
        ...responses,
      },
    },
  );
}

const group = (name: string) => screen.findByRole("radiogroup", { name });
const submitButton = () =>
  screen.getByRole("button", { name: "Send feedback" });

describe("FeedbackStation", () => {
  test("renders the choice and scale questions as radio groups and hides free text without the flag", async () => {
    const { container } = renderStation();

    const scale = await group("How useful was the program?");
    expect(
      screen.getByText("Tell us how the program worked for you."),
    ).toBeInTheDocument();
    expect(
      screen.getByText(
        "Your feedback is stored without your name. You can send it once.",
      ),
    ).toBeInTheDocument();
    expect(
      within(scale)
        .getAllByRole("radio")
        .map((radio) => radio.textContent),
    ).toEqual(["1", "2", "3", "4", "5"]);
    expect(scale).toHaveAccessibleDescription(
      "From 1 (not at all) to 5 (completely).",
    );
    const length = await group("How was the length?");
    expect(
      within(length)
        .getAllByRole("radio")
        .map((radio) => radio.textContent),
    ).toEqual(["Too short", "Just right", "Too long"]);
    expect(within(length).getByText("Just right")).toHaveAttribute(
      "lang",
      "en",
    );
    expect(screen.getByText("How was the length?")).toHaveAttribute(
      "lang",
      "en",
    );
    expect(screen.queryByRole("textbox")).toBeNull();
    expect(screen.queryByText("What should we change?")).toBeNull();
    expect(submitButton()).toBeDisabled();
    await expectNoAxeViolations(container);
  });

  test("shows free text with a limit of 2,000 characters when the flag is set", async () => {
    const { container } = renderStation({ freeText: true });

    const text = await screen.findByRole("textbox", {
      name: "What should we change?",
    });
    expect(text).toHaveAttribute("maxlength", "2000");
    expect(text).toHaveAccessibleDescription(
      "At most 2,000 characters. Please leave out names and other personal details.",
    );
    await expectNoAxeViolations(container);
  });

  test("sends the answered questions only, with trimmed free text, and then thanks the learner", async () => {
    const { requests, user, container } = renderStation({ freeText: true });
    const scale = await group("How useful was the program?");

    await user.click(within(scale).getByRole("radio", { name: "4" }));
    expect(submitButton()).toBeEnabled();
    await user.type(
      screen.getByRole("textbox", { name: "What should we change?" }),
      "  Shorter videos.  ",
    );
    await user.click(submitButton());

    const thanks = await screen.findByText(
      "Thank you. Your feedback is recorded.",
    );
    expect(requestsTo(requests, "POST", POST_PATH)).toHaveLength(1);
    expect(requestsTo(requests, "POST", POST_PATH)[0].body).toEqual({
      program_slug: SLUG,
      answers: { useful: 4, remarks: "Shorter videos." },
    });
    await waitFor(() => expect(thanks).toHaveFocus());
    expect(screen.queryByRole("radiogroup")).toBeNull();
    expect(screen.queryByRole("button", { name: "Send feedback" })).toBeNull();
    await expectNoAxeViolations(container);
  });

  test("sends a single choice by its option key, and free text of spaces enables nothing", async () => {
    const { requests, user } = renderStation({ freeText: true });
    const length = await group("How was the length?");

    await user.type(
      screen.getByRole("textbox", { name: "What should we change?" }),
      "   ",
    );
    expect(submitButton()).toBeDisabled();
    await user.click(within(length).getByRole("radio", { name: "Too long" }));
    await user.click(submitButton());

    await screen.findByText("Thank you. Your feedback is recorded.");
    expect(requestsTo(requests, "POST", POST_PATH)[0].body).toEqual({
      program_slug: SLUG,
      answers: { length: "too-long" },
    });
  });

  test("a second visit thanks the learner without the form", async () => {
    const { requests } = renderStation({
      responses: {
        "GET /api/me/participation": {
          status: 200,
          body: participation({ feedback: true }),
        },
      },
    });

    expect(
      await screen.findByText(
        "You have already sent your feedback. Thank you.",
      ),
    ).toBeInTheDocument();
    expect(screen.queryByRole("radiogroup")).toBeNull();
    expect(requestsTo(requests, "POST", POST_PATH)).toHaveLength(0);
  });

  test.each([
    [
      "a participation that failed to load",
      { status: 500, body: { error: "internal" } },
    ],
    [
      "a stale participation",
      { status: 200, body: participation({ feedback: false }) },
    ],
  ])(
    "after %s, an answer already_recorded says that the feedback was sent before",
    async (_name, loaded) => {
      const { requests, user } = renderStation({
        responses: {
          "GET /api/me/participation": [
            loaded,
            { status: 200, body: participation({ feedback: true }) },
          ],
          [`POST ${POST_PATH}`]: {
            status: 200,
            body: { already_recorded: true },
          },
        },
      });
      const scale = await group("How useful was the program?");

      await user.click(within(scale).getByRole("radio", { name: "3" }));
      await user.click(submitButton());

      const sent = await screen.findByText(
        "You have already sent your feedback. Thank you.",
      );
      await waitFor(() => expect(sent).toHaveFocus());
      expect(
        screen.queryByText("Thank you. Your feedback is recorded."),
      ).toBeNull();
      expect(screen.queryByRole("radiogroup")).toBeNull();
      expect(requestsTo(requests, "POST", POST_PATH)).toHaveLength(1);
    },
  );

  test("a failed post shows an error and keeps the answers", async () => {
    const { requests, user } = renderStation({
      responses: {
        [`POST ${POST_PATH}`]: [
          { status: 422, body: { error: "validation_failed" } },
          { status: 200, body: { already_recorded: false } },
        ],
      },
    });
    const scale = await group("How useful was the program?");

    await user.click(within(scale).getByRole("radio", { name: "2" }));
    await user.click(submitButton());

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Your feedback could not be sent. Please try again.",
    );
    expect(within(scale).getByRole("radio", { name: "2" })).toBeChecked();

    await user.click(submitButton());
    await screen.findByText("Thank you. Your feedback is recorded.");
    expect(requestsTo(requests, "POST", POST_PATH)).toHaveLength(2);
  });
});
