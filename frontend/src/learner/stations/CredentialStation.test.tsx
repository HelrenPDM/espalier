import { screen, within } from "@testing-library/react";
import { describe, expect, test } from "vitest";
import type { QualificationRequirements } from "../../api/credentials";
import type { CurrentPolicy } from "../../api/policies";
import { PlayerProvider } from "../../player/PlayerProvider";
import { RuntimeContext } from "../../player/RuntimeContext";
import type { ProgramView, Station } from "../../player/runtime";
import { expectNoAxeViolations } from "../../test/axe";
import { fakeRuntime, programFixture, SLUG } from "../../test/player";
import { renderWithProviders, type StubResponses } from "../../test/render";
import { signedInPayload } from "../../test/session";
import { CredentialStation } from "./CredentialStation";

/**
 * Task 0013 step 23: the credential station shows the met and open
 * requirements per qualification, links each open requirement to the
 * station or page that satisfies it, names every target by its title and
 * lists the issued credentials with status and a link to their page.
 */
const CREDENTIAL_ID = "3c5e7a9b-1d2f-4a6b-8c0d-2e4f6a8b0c1d";
const REQUIREMENTS_PATH = "/api/me/requirements";

const station: Station = {
  kind: "credential",
  position: 5,
  title: "Your credential",
  intro: "Complete both modules to receive the credential.",
  module_id: null,
  question: null,
  questions: [],
};

/** The fixture program with the credential station at position 5. */
function program(): ProgramView {
  const fixture = programFixture();
  return { ...fixture, stations: [...fixture.stations, station] };
}

const usagePolicy: CurrentPolicy = {
  id: "6f1c2b3a-4d5e-4f60-8a7b-9c0d1e2f3a4b",
  key: "usage-policy",
  title: "Usage policy",
  number: 1,
  effective_from: "2026-10-01",
  body: "Use only approved assistants.",
  acknowledged_at: null,
};

const UNLOCKS = [
  "Draft internal texts with an approved AI writing assistant",
  "Summarize non-confidential documents with an approved AI writing assistant",
];

const basics = (
  overrides: Partial<QualificationRequirements> = {},
): QualificationRequirements => ({
  code: "basics",
  title: "AI assistant basics",
  add_on: false,
  unlocks: UNLOCKS,
  credential: null,
  met: [
    { kind: "module_completed", target_key: "1", station_position: 2 },
    {
      kind: "assessment_passed",
      target_key: "module-1-exam",
      station_position: 2,
    },
  ],
  open: [
    { kind: "module_completed", target_key: "2", station_position: 3 },
    {
      kind: "policy_acknowledged",
      target_key: "usage-policy",
      station_position: null,
    },
  ],
  ...overrides,
});

const workshop: QualificationRequirements = {
  code: "workshop",
  title: "AI assistants in the team",
  add_on: true,
  unlocks: [
    "Coordinate how a team marks the use of an AI writing assistant in shared documents",
  ],
  credential: null,
  met: [],
  open: [
    { kind: "attendance", target_key: "workshop", station_position: 4 },
    {
      kind: "qualification_held",
      target_key: "basics",
      station_position: null,
    },
  ],
};

function renderStation(
  qualifications: QualificationRequirements[] = [basics(), workshop],
  responses: StubResponses = {},
) {
  const fixture = program();
  return renderWithProviders(
    <RuntimeContext.Provider value={fakeRuntime({ program: fixture })}>
      <PlayerProvider slug={SLUG}>
        <CredentialStation station={station} />
      </PlayerProvider>
    </RuntimeContext.Provider>,
    {
      route: `/programs/${SLUG}/stations/${station.position}`,
      session: signedInPayload("mfa"),
      responses: {
        [`GET ${REQUIREMENTS_PATH}`]: {
          status: 200,
          body: { qualifications },
        },
        "GET /api/policies": {
          status: 200,
          body: { policies: [usagePolicy] },
        },
        ...responses,
      },
    },
  );
}

const section = (name: string) => screen.findByRole("region", { name });

/** The entries of the list named `name` inside `scope`. */
const entries = (scope: HTMLElement, name: string) =>
  within(within(scope).getByRole("list", { name })).getAllByRole("listitem");

describe("CredentialStation", () => {
  test("shows the intro and one section per qualification", async () => {
    const { requests } = renderStation();

    await section("AI assistant basics");
    expect(
      screen.getByText("Complete both modules to receive the credential."),
    ).toBeInTheDocument();
    expect(
      screen.getAllByRole("heading", { level: 2 }).map((h) => h.textContent),
    ).toEqual(["AI assistant basics", "AI assistants in the team"]);
    expect(
      requests.filter((request) => request.path === REQUIREMENTS_PATH),
    ).toHaveLength(1);
  });

  test("shows met and open requirements with the titles of their targets, and links each open requirement", async () => {
    renderStation();
    const qualification = await section("AI assistant basics");

    const open = entries(qualification, "Open requirements");
    expect(open.map((entry) => entry.textContent)).toEqual([
      "Complete the module: Checking the output",
      "Acknowledge the policy: Usage policy",
    ]);
    expect(
      within(open[0]).getByRole("link", {
        name: "Complete the module: Checking the output",
      }),
    ).toHaveAttribute("href", `/programs/${SLUG}/stations/3`);
    expect(
      within(open[1]).getByRole("link", {
        name: "Acknowledge the policy: Usage policy",
      }),
    ).toHaveAttribute("href", "/policies");

    const met = entries(qualification, "Met requirements");
    expect(met.map((entry) => entry.textContent)).toEqual([
      "Module completed: How language models work",
      "Exam passed: Exam of module 1",
    ]);
    for (const entry of met)
      expect(within(entry).queryByRole("link")).toBeNull();

    expect(
      entries(qualification, "The credential permits these tasks").map(
        (entry) => entry.textContent,
      ),
    ).toEqual(UNLOCKS);
    expect(qualification).toHaveTextContent(
      "Not issued yet. The credential is issued once every requirement is met.",
    );
  });

  test("links attendance to the companion formats station and leaves a prerequisite credential without link", async () => {
    renderStation();
    const addOn = await section("AI assistants in the team");

    expect(addOn).toHaveTextContent("An add-on to another credential.");
    const open = entries(addOn, "Open requirements");
    expect(
      within(open[0]).getByRole("link", {
        name: "Obtain the format certificate: Team workshop",
      }),
    ).toHaveAttribute("href", `/programs/${SLUG}/stations/4`);
    expect(open[1]).toHaveTextContent(
      "Hold the credential: AI assistant basics",
    );
    expect(within(open[1]).queryByRole("link")).toBeNull();
    expect(
      within(addOn).queryByRole("list", { name: "Met requirements" }),
    ).toBeNull();
  });

  test("pack titles carry the content language in their own element", async () => {
    renderStation();
    const qualification = await section("AI assistant basics");

    expect(
      within(qualification).getByRole("heading", {
        level: 2,
        name: "AI assistant basics",
      }),
    ).toHaveAttribute("lang", "en");
    const [moduleEntry] = entries(qualification, "Met requirements");
    expect(
      within(moduleEntry).getByText("How language models work"),
    ).toHaveAttribute("lang", "en");
    // A policy title belongs to the organization, not to the pack.
    const [, policyEntry] = entries(qualification, "Open requirements");
    expect(within(policyEntry).getByText("Usage policy")).not.toHaveAttribute(
      "lang",
    );
  });

  test("lists an issued credential with its status and a link to its page", async () => {
    renderStation([
      basics({
        credential: {
          id: CREDENTIAL_ID,
          status: "active",
          issued_at: "2026-10-11T09:30:00Z",
          valid_until: "2027-10-11",
        },
        met: [
          ...basics().met,
          { kind: "module_completed", target_key: "2", station_position: 3 },
          {
            kind: "policy_acknowledged",
            target_key: "usage-policy",
            station_position: null,
          },
        ],
        open: [],
      }),
    ]);
    const qualification = await section("AI assistant basics");

    expect(qualification).toHaveTextContent("Your credential:");
    expect(qualification).toHaveTextContent("Active");
    expect(qualification).toHaveTextContent("valid until Oct 11, 2027");
    expect(
      within(qualification).getByRole("link", { name: "View the credential" }),
    ).toHaveAttribute("href", `/me/credentials/${CREDENTIAL_ID}`);
    expect(
      within(qualification).queryByRole("list", { name: "Open requirements" }),
    ).toBeNull();
    expect(entries(qualification, "Met requirements")).toHaveLength(4);
    expect(qualification.textContent ?? "").not.toMatch(/%|score/i);
  });

  test("a failed load shows an alert", async () => {
    renderStation([], {
      [`GET ${REQUIREMENTS_PATH}`]: { status: 500, body: { error: "server" } },
    });

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "The requirements could not be loaded. Please try again later.",
    );
  });

  test("has no axe violations", async () => {
    const { container } = renderStation();

    await section("AI assistants in the team");
    await expectNoAxeViolations(container);
  });
});
