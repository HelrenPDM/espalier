import { screen, waitFor, within } from "@testing-library/react";
import { Route, Routes } from "react-router";
import { describe, expect, test } from "vitest";
import type { Handbook } from "../api/programs";
import { PlayerProvider } from "../player/PlayerProvider";
import { RuntimeContext } from "../player/RuntimeContext";
import {
  emptyResumeState,
  type ProgramView,
  type ResumeState,
} from "../player/runtime";
import { expectNoAxeViolations } from "../test/axe";
import {
  fakeRuntime,
  programFixture,
  renderPlayer,
  SLUG,
} from "../test/player";
import { renderWithProviders } from "../test/render";
import { signedInPayload } from "../test/session";
import { GlossaryPage } from "./GlossaryPage";
import { HandbookPage } from "./HandbookPage";
import { ProgramPage } from "./ProgramPage";
import { ProgramShell } from "./ProgramShell";
import { StationPage } from "./StationPage";

/**
 * The program shell of the platform routes: the breadcrumbs from the
 * program list to the current page, the program navigation with the
 * overview, the step list, the glossary and the handbook, and the pages
 * without their own step list and back link. Without the shell, as in the
 * admin preview and the SCORM package, the pages keep both.
 */
const TITLE = "AI assistant basics (demo)";
const BASE = `/programs/${SLUG}`;
const HANDBOOK: Handbook = { modules: [], placeholders: [] };

function renderShell(
  route: string,
  {
    program = programFixture(),
    state = emptyResumeState("full"),
  }: { program?: ProgramView; state?: ResumeState } = {},
) {
  const runtime = fakeRuntime({ program, state });
  return renderWithProviders(
    <RuntimeContext.Provider value={runtime}>
      <PlayerProvider slug={SLUG}>
        <Routes>
          <Route element={<ProgramShell />}>
            <Route index element={<ProgramPage />} />
            <Route path="stations/:position" element={<StationPage />} />
            <Route path="glossary" element={<GlossaryPage />} />
            <Route path="handbook" element={<HandbookPage />} />
          </Route>
        </Routes>
      </PlayerProvider>
    </RuntimeContext.Provider>,
    {
      route,
      path: "/programs/:slug/*",
      session: signedInPayload("mfa"),
      responses: {
        [`GET /api/programs/${SLUG}/handbook`]: { status: 200, body: HANDBOOK },
      },
    },
  );
}

const trail = () => screen.getByRole("navigation", { name: "Breadcrumb" });
const sidebar = () => screen.getByRole("navigation", { name: "Program" });
const trailItems = () =>
  within(trail())
    .getAllByRole("listitem")
    .map((item) => item.textContent);
const stationLink = (position: number) => {
  const link = within(sidebar())
    .getAllByRole("link")
    .find(
      (entry) => entry.getAttribute("href") === `${BASE}/stations/${position}`,
    );
  expect(link, `station ${position}`).toBeDefined();
  return link as HTMLElement;
};
const backLink = () => screen.queryByRole("link", { name: /^Back to/ });

describe("the program shell", () => {
  test("on the program page the breadcrumbs end with the program title and the sidebar marks the overview", async () => {
    renderShell(BASE);

    await screen.findByRole("heading", { level: 1, name: TITLE });
    expect(trailItems()).toEqual(["Programs", TITLE]);
    expect(within(trail()).getByRole("link")).toHaveAttribute("href", "/");
    expect(within(trail()).getByText(TITLE)).toHaveAttribute(
      "aria-current",
      "page",
    );

    expect(
      within(sidebar()).getByRole("link", { name: "Program overview" }),
    ).toHaveAttribute("aria-current", "page");
    expect(
      within(sidebar()).getByRole("link", { name: "Program overview" }),
    ).toHaveAttribute("href", BASE);
    const steps = within(sidebar()).getByRole("list", { name: "Stations" });
    expect(within(steps).getAllByRole("link")).toHaveLength(4);
    expect(
      within(sidebar()).getByRole("link", { name: "Glossary" }),
    ).toHaveAttribute("href", `${BASE}/glossary`);
    expect(
      within(sidebar()).getByRole("link", { name: "Handbook" }),
    ).toHaveAttribute("href", `${BASE}/handbook`);
    // The program page keeps its own step list as the content of the
    // overview; every navigation has a name of its own.
    expect(
      screen
        .getAllByRole("navigation")
        .map((navigation) => navigation.getAttribute("aria-label")),
    ).toEqual(["Breadcrumb", "Program", "Stations", "More on this program"]);
  });

  test("on a station page the sidebar marks the station, and the page leaves out its own step list and back link", async () => {
    renderShell(`${BASE}/stations/2`, {
      state: { ...emptyResumeState("full"), visitedStations: [1] },
    });

    await screen.findByRole("heading", {
      level: 1,
      name: "How language models work",
    });
    expect(trailItems()).toEqual([
      "Programs",
      TITLE,
      "How language models work",
    ]);
    expect(within(trail()).getByRole("link", { name: TITLE })).toHaveAttribute(
      "href",
      BASE,
    );
    expect(
      within(trail()).getByText("How language models work"),
    ).toHaveAttribute("aria-current", "page");

    expect(stationLink(2)).toHaveAttribute("aria-current", "step");
    expect(stationLink(1)).not.toHaveAttribute("aria-current");
    expect(stationLink(1)).toHaveTextContent("Visited");
    expect(
      within(sidebar()).getByRole("link", { name: "Program overview" }),
    ).not.toHaveAttribute("aria-current");

    expect(
      screen.queryByRole("navigation", { name: "Stations" }),
    ).not.toBeInTheDocument();
    expect(screen.queryByRole("complementary")).not.toBeInTheDocument();
    expect(backLink()).not.toBeInTheDocument();
    expect(
      screen.getByRole("navigation", { name: "Previous and next station" }),
    ).toBeInTheDocument();
  });

  test("an unknown station ends the breadcrumbs with the not-found title and shows no back link", async () => {
    renderShell(`${BASE}/stations/99`);

    await screen.findByRole("heading", { level: 1, name: "Station not found" });
    expect(trailItems()).toEqual(["Programs", TITLE, "Station not found"]);
    expect(backLink()).not.toBeInTheDocument();
    expect(
      within(sidebar()).getByRole("link", { name: "Program overview" }),
    ).toHaveAttribute("href", BASE);
  });

  test.each([
    ["glossary", "Glossary"],
    ["handbook", "Handbook"],
  ])(
    "on the %s the breadcrumbs end with its title, the sidebar marks it, and no back link appears",
    async (path, title) => {
      renderShell(`${BASE}/${path}`);

      await screen.findByRole("heading", { level: 1, name: title });
      expect(trailItems()).toEqual(["Programs", TITLE, title]);
      expect(within(trail()).getByText(title)).toHaveAttribute(
        "aria-current",
        "page",
      );
      expect(
        within(sidebar()).getByRole("link", { name: title }),
      ).toHaveAttribute("aria-current", "page");
      expect(backLink()).not.toBeInTheDocument();
    },
  );

  test("pack text in the breadcrumbs and the sidebar carries the language of the program", async () => {
    renderShell(`${BASE}/stations/2`, {
      program: { ...programFixture(), locale: "de" },
    });

    await screen.findByRole("heading", {
      level: 1,
      name: "How language models work",
    });
    expect(within(trail()).getByRole("link", { name: TITLE })).toHaveAttribute(
      "lang",
      "de",
    );
    expect(
      within(trail()).getByText("How language models work"),
    ).toHaveAttribute("lang", "de");
    expect(
      within(trail()).getByRole("link", { name: "Programs" }).closest("[lang]"),
    ).toBe(document.documentElement);

    expect(within(sidebar()).getByText(TITLE)).toHaveAttribute("lang", "de");
    expect(
      within(stationLink(2)).getByText("How language models work"),
    ).toHaveAttribute("lang", "de");
    for (const label of ["Program overview", "Glossary", "Handbook"])
      expect(
        within(sidebar()).getByRole("link", { name: label }).closest("[lang]"),
      ).toBe(document.documentElement);
  });

  test("a link of the sidebar opens its page, and the mark follows", async () => {
    const { user, location } = renderShell(`${BASE}/stations/1`);

    await screen.findByRole("heading", { level: 1, name: "Overview" });
    await user.click(within(sidebar()).getByRole("link", { name: "Glossary" }));

    expect(
      await screen.findByRole("heading", { level: 1, name: "Glossary" }),
    ).toBeInTheDocument();
    expect(location()).toBe(`${BASE}/glossary`);
    expect(
      within(sidebar()).getByRole("link", { name: "Glossary" }),
    ).toHaveAttribute("aria-current", "page");
    expect(stationLink(1)).not.toHaveAttribute("aria-current");
  });

  test("the program menu button opens the sidebar on a narrow screen and closes it after a navigation and on Escape", async () => {
    const { user, location } = renderShell(`${BASE}/stations/1`);

    await screen.findByRole("heading", { level: 1, name: "Overview" });
    const button = screen.getByRole("button", { name: "Program menu" });
    // Headless UI sets aria-controls once the panel has registered.
    await waitFor(() => expect(button).toHaveAttribute("aria-controls"));
    const panel = document.getElementById(
      button.getAttribute("aria-controls") ?? "",
    );
    expect(panel).not.toBeNull();
    expect(panel).toContainElement(sidebar());
    expect(button).toHaveAttribute("aria-expanded", "false");
    expect(panel).toHaveClass("hidden", "lg:block");

    await user.click(button);
    expect(button).toHaveAttribute("aria-expanded", "true");
    expect(panel).not.toHaveClass("hidden");

    await user.click(within(sidebar()).getByRole("link", { name: "Glossary" }));
    expect(
      await screen.findByRole("heading", { level: 1, name: "Glossary" }),
    ).toBeInTheDocument();
    expect(location()).toBe(`${BASE}/glossary`);
    expect(button).toHaveAttribute("aria-expanded", "false");
    expect(panel).toHaveClass("hidden");
    expect(button).toHaveFocus();

    await user.click(button);
    expect(button).toHaveAttribute("aria-expanded", "true");
    await user.keyboard("{Escape}");
    expect(button).toHaveAttribute("aria-expanded", "false");
  });

  test.each([
    ["the program page", BASE, TITLE],
    ["a station page", `${BASE}/stations/1`, "Overview"],
    ["the glossary", `${BASE}/glossary`, "Glossary"],
  ])("has no axe violations on %s", async (_name, route, heading) => {
    const { container, user } = renderShell(route, {
      state: { ...emptyResumeState("full"), visitedStations: [1] },
    });

    await screen.findByRole("heading", { level: 1, name: heading });
    await expectNoAxeViolations(container);
    await user.click(screen.getByRole("button", { name: "Program menu" }));
    await expectNoAxeViolations(container);
  });
});

describe("without the program shell (admin preview, SCORM package)", () => {
  test("the station page keeps its step list and its back link", async () => {
    renderPlayer(<StationPage />, {
      route: `${BASE}/stations/2`,
      path: "/programs/:slug/stations/:position",
    });

    await screen.findByRole("heading", {
      level: 1,
      name: "How language models work",
    });
    const steps = screen.getByRole("navigation", { name: "Stations" });
    expect(steps.closest("aside")).not.toBeNull();
    expect(
      within(steps)
        .getAllByRole("link")
        .find((link) => link.getAttribute("aria-current") === "step"),
    ).toHaveAttribute("href", `${BASE}/stations/2`);
    expect(
      screen.getByRole("link", { name: `Back to ${TITLE}` }),
    ).toHaveAttribute("href", BASE);
    expect(
      screen.queryByRole("navigation", { name: "Breadcrumb" }),
    ).not.toBeInTheDocument();
  });

  test("the glossary keeps its back link", async () => {
    renderPlayer(<GlossaryPage />, { route: `${BASE}/glossary` });

    await screen.findByRole("heading", { level: 1, name: "Glossary" });
    expect(
      screen.getByRole("link", { name: `Back to ${TITLE}` }),
    ).toHaveAttribute("href", BASE);
  });

  test("the handbook keeps its back link", async () => {
    renderWithProviders(
      <RuntimeContext.Provider value={fakeRuntime()}>
        <PlayerProvider slug={SLUG}>
          <HandbookPage />
        </PlayerProvider>
      </RuntimeContext.Provider>,
      {
        route: `${BASE}/handbook`,
        session: signedInPayload("mfa"),
        responses: {
          [`GET /api/programs/${SLUG}/handbook`]: {
            status: 200,
            body: HANDBOOK,
          },
        },
      },
    );

    await screen.findByRole("heading", { level: 1, name: "Handbook" });
    expect(
      screen.getByRole("link", { name: `Back to ${TITLE}` }),
    ).toHaveAttribute("href", BASE);
  });
});
