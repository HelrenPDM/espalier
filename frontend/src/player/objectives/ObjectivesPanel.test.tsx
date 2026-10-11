import { render, screen, within } from "@testing-library/react";
import { afterEach, describe, expect, test, vi } from "vitest";
import i18n from "../../i18n";
import de from "../../i18n/de.json";
import en from "../../i18n/en.json";
import { ModuleStation } from "../../learner/ModuleStation";
import { expectNoAxeViolations } from "../../test/axe";
import {
  IDS,
  module1,
  module2,
  programFixture,
  renderPlayer,
} from "../../test/player";
import type { ModuleView } from "../runtime";
import { ObjectivesPanel } from "./ObjectivesPanel";

afterEach(async () => {
  await i18n.changeLanguage("en");
});

const AREA_HEADINGS = {
  en: [
    en.objectives.area.subject,
    en.objectives.area.method,
    en.objectives.area.self,
    en.objectives.area.social,
  ],
  de: [
    de.objectives.area.subject,
    de.objectives.area.method,
    de.objectives.area.self,
    de.objectives.area.social,
  ],
};

const panel = (name = en.objectives.panelTitle) =>
  screen.getByRole("region", { name });

const areaHeadings = (container: HTMLElement) =>
  within(container)
    .getAllByRole("heading", { level: 3 })
    .map((heading) => heading.textContent);

describe("ObjectivesPanel", () => {
  test("groups five objectives of four areas under four h3 headings in the order of AREAS", () => {
    expect(module1().objectives).toHaveLength(5);
    render(<ObjectivesPanel module={module1()} />);

    expect(
      within(panel()).getByRole("heading", {
        level: 2,
        name: "Objectives of this topic",
      }),
    ).toBeInTheDocument();
    expect(areaHeadings(panel())).toEqual([
      "Subject competence",
      "Method competence",
      "Self competence",
      "Social competence",
    ]);
    expect(areaHeadings(panel())).toEqual(AREA_HEADINGS.en);
  });

  test("shows the four area headings in German", async () => {
    await i18n.changeLanguage("de");
    render(<ObjectivesPanel module={module1()} />);

    const region = panel("Ziele dieses Themas");
    expect(areaHeadings(region)).toEqual([
      "Fachkompetenz",
      "Methodenkompetenz",
      "Selbstkompetenz",
      "Sozialkompetenz",
    ]);
    expect(areaHeadings(region)).toEqual(AREA_HEADINGS.de);
  });

  test("orders the groups by AREAS and the entries by the module view", () => {
    const base = module1();
    const reversed: ModuleView = {
      ...base,
      objectives: [...base.objectives].reverse(),
    };
    render(<ObjectivesPanel module={reversed} />);

    expect(areaHeadings(panel())).toEqual(AREA_HEADINGS.en);
    const subject = screen
      .getByRole("heading", { level: 3, name: "Subject competence" })
      .closest("div");
    expect(
      within(subject as HTMLElement)
        .getAllByRole("listitem")
        .map((entry) => entry.id),
    ).toEqual(["objective-m1-subject-exam", "objective-m1-subject-evidenced"]);
  });

  test("a module with objectives in subject and method only shows two groups", () => {
    render(<ObjectivesPanel module={module2()} />);

    expect(areaHeadings(panel())).toEqual([
      "Subject competence",
      "Method competence",
    ]);
    const method = screen
      .getByRole("heading", { level: 3, name: "Method competence" })
      .closest("div");
    expect(within(method as HTMLElement).getAllByRole("listitem")).toHaveLength(
      2,
    );
  });

  test("a module without objectives renders no panel", () => {
    const { container } = render(
      <ObjectivesPanel module={{ ...module1(), objectives: [] }} />,
    );

    expect(container).toBeEmptyDOMElement();
    expect(screen.queryByRole("region")).toBeNull();
    expect(screen.queryByRole("heading")).toBeNull();
  });

  test.each([
    ["en", en],
    ["de", de],
  ] as const)(
    "each entry carries its id, tabIndex -1, the statement and its depth label as text (%s)",
    async (language, catalog) => {
      await i18n.changeLanguage(language);
      const module = module1();
      render(<ObjectivesPanel module={module} />);

      const entries = within(panel(catalog.objectives.panelTitle)).getAllByRole(
        "listitem",
      );
      expect(entries.map((entry) => entry.id)).toEqual(
        module.objectives.map((objective) => `objective-${objective.key}`),
      );
      entries.forEach((entry, index) => {
        const objective = module.objectives[index];
        expect(entry).toHaveAttribute("tabindex", "-1");
        expect(entry.tabIndex).toBe(-1);
        expect(entry).toHaveTextContent(objective.statement);
        expect(entry).toHaveTextContent(
          catalog.objectives.depth[objective.depth],
        );
      });
      expect(entries[0]).toHaveTextContent(
        language === "en" ? "Depth: Know." : "Tiefe: Wissen.",
      );
      expect(entries[3]).toHaveTextContent(
        language === "en" ? "Depth: Judge." : "Tiefe: Beurteilen.",
      );
    },
  );

  test("shows the domain only when the objective names one", () => {
    render(<ObjectivesPanel module={module1()} />);

    const [withDomain, withoutDomain] =
      within(panel()).getAllByRole("listitem");
    expect(withDomain).toHaveTextContent("Domain: research.");
    expect(withoutDomain).not.toHaveTextContent("Domain:");
  });

  test("lists the lessons of each objective as links with their titles", () => {
    render(<ObjectivesPanel module={module1()} />);

    const entry = document.getElementById("objective-m1-method-practice");
    const links = within(entry as HTMLElement).getAllByRole("link");
    expect(links.map((link) => link.textContent)).toEqual([
      "Why answers vary",
      "Checking and sharing",
    ]);
    expect(links.map((link) => link.getAttribute("href"))).toEqual([
      `#lesson-${IDS.lesson2}`,
      `#lesson-${IDS.lesson3}`,
    ]);
  });

  test("shows no status", () => {
    render(<ObjectivesPanel module={module1()} />);

    for (const label of Object.values(en.objectives.status))
      expect(panel()).not.toHaveTextContent(label);
  });

  test("has no axe violations", async () => {
    const { container } = render(<ObjectivesPanel module={module1()} />);

    await expectNoAxeViolations(container);
  });
});

describe("ObjectivesPanel in the module station", () => {
  const station = () => {
    const found = programFixture().stations[1];
    expect(found.module_id).toBe(IDS.module1);
    return found;
  };

  test("a lesson link moves focus to the lesson heading and scrolls it into view", async () => {
    const scrollIntoView = vi.fn();
    const original = Object.getOwnPropertyDescriptor(
      HTMLElement.prototype,
      "scrollIntoView",
    );
    Object.defineProperty(HTMLElement.prototype, "scrollIntoView", {
      configurable: true,
      writable: true,
      value: scrollIntoView,
    });
    try {
      const { user, location } = renderPlayer(
        <ModuleStation station={station()} />,
      );
      const region = await screen.findByRole("region", {
        name: "Objectives of this topic",
      });
      const before = location();
      const hashBefore = window.location.hash;

      const entry = within(region)
        .getAllByRole("listitem")
        .find((item) => item.id === "objective-m1-method-practice");
      await user.click(
        within(entry as HTMLElement).getByRole("link", {
          name: "Checking and sharing",
        }),
      );

      const heading = screen.getByRole("heading", {
        level: 2,
        name: "Checking and sharing",
      });
      expect(heading.id).toBe(`lesson-${IDS.lesson3}-heading`);
      expect(heading.closest("section")).toHaveAttribute(
        "id",
        `lesson-${IDS.lesson3}`,
      );
      expect(heading).toHaveAttribute("tabindex", "-1");
      expect(heading).toHaveFocus();
      expect(scrollIntoView).toHaveBeenCalled();
      expect(scrollIntoView.mock.contexts.at(-1)).toBe(heading);
      // The handler prevents the default, so neither router changes.
      expect(location()).toBe(before);
      expect(window.location.hash).toBe(hashBefore);
    } finally {
      if (original === undefined)
        delete (HTMLElement.prototype as Partial<HTMLElement>).scrollIntoView;
      else
        Object.defineProperty(
          HTMLElement.prototype,
          "scrollIntoView",
          original,
        );
    }
  });

  test("a lesson link activated with the keyboard moves focus as well", async () => {
    const { user } = renderPlayer(<ModuleStation station={station()} />);
    const region = await screen.findByRole("region", {
      name: "Objectives of this topic",
    });

    within(region)
      .getByRole("link", { name: "What a language model does" })
      .focus();
    await user.keyboard("{Enter}");

    expect(
      screen.getByRole("heading", {
        level: 2,
        name: "What a language model does",
      }),
    ).toHaveFocus();
  });
});
