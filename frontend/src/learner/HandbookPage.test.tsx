import { screen, within } from "@testing-library/react";
import { expect, test } from "vitest";
import type { Handbook } from "../api/programs";
import { PlayerProvider } from "../player/PlayerProvider";
import { RuntimeContext } from "../player/RuntimeContext";
import { fakeRuntime, id, programFixture, SLUG } from "../test/player";
import { renderWithProviders } from "../test/render";
import { signedInPayload } from "../test/session";
import { HandbookPage } from "./HandbookPage";

/**
 * Task 0013 step 21: the handbook renders the current version of each
 * policy that a placeholder names, and a note for a policy that the
 * organization has not published yet. The rules are pack text in the
 * language of the program; the policy text inherits the language of the
 * document.
 */
const handbook: Handbook = {
  modules: [
    {
      id: id(1),
      number: 1,
      title: "How language models work",
      rules: [
        {
          number: 1,
          statement: "Generated text carries no check of its own.",
          action: "Treat every generated statement as a draft.",
        },
      ],
    },
  ],
  placeholders: [
    {
      key: "input-rules",
      policy: null,
    },
    {
      key: "usage-policy",
      policy: {
        key: "usage-policy",
        number: 2,
        effective_from: "2026-10-01",
        body: "Enter **no** personal data into an assistant.",
      },
    },
  ],
};

function renderHandbook(locale = "en") {
  const runtime = fakeRuntime({ program: { ...programFixture(), locale } });
  return renderWithProviders(
    <RuntimeContext.Provider value={runtime}>
      <PlayerProvider slug={SLUG}>
        <HandbookPage />
      </PlayerProvider>
    </RuntimeContext.Provider>,
    {
      route: `/programs/${SLUG}/handbook`,
      session: signedInPayload("mfa"),
      responses: {
        [`GET /api/programs/${SLUG}/handbook`]: {
          status: 200,
          body: handbook,
        },
      },
    },
  );
}

test("each placeholder shows its policy text with the version, or a note without a published version", async () => {
  renderHandbook();

  const published = await screen.findByRole("region", {
    name: "usage-policy",
  });
  expect(published).toHaveTextContent(
    "Enter no personal data into an assistant.",
  );
  expect(within(published).getByText("no", { selector: "strong" }));
  expect(published).toHaveTextContent("Version 2, in effect from Oct 1, 2026.");

  const missing = screen.getByRole("region", { name: "input-rules" });
  expect(missing).toHaveTextContent(
    "Your organization has not published this policy yet.",
  );
});

test("the rules carry the language of the program, the policy text carries no lang", async () => {
  renderHandbook("de");

  const published = await screen.findByRole("region", {
    name: "usage-policy",
  });
  expect(
    screen
      .getByText("Generated text carries no check of its own.")
      .closest("[lang]"),
  ).toHaveAttribute("lang", "de");

  const policyText = within(published).getByText("no", { selector: "strong" });
  expect(policyText.closest("[lang]")).toBe(document.documentElement);
});
