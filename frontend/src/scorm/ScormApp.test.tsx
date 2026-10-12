import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, onTestFinished, test, vi } from "vitest";
import i18n from "../i18n";
import { contentPayload, type ScormContent } from "../runtimes/content";
import { StandaloneRuntime } from "../runtimes/standalone";
import { applyPackLanguage, onRestoredFromCache } from "./boot";
import { scormContent } from "./fixture";
import { ScormNotice, ScormPlayer } from "./ScormApp";

/**
 * Task 0016 step 2: the player of the package in its memory router, on
 * `StandaloneRuntime` in place of a started SCORM runtime.
 */

afterEach(async () => {
  vi.unstubAllGlobals();
  await i18n.changeLanguage("en");
});

function renderPlayer(content: ScormContent = scormContent()) {
  const runtime = new StandaloneRuntime(contentPayload(content));
  const user = userEvent.setup();
  const view = render(<ScormPlayer content={content} runtime={runtime} />);
  return { user, ...view };
}

/** `scormContent` with a source link and a link in the block body. */
function contentWithLinks(): ScormContent {
  const content = scormContent();
  const [block] = content.module.lessons[0].blocks;
  block.body = "Read [the guide](https://example.org/guide) first.";
  block.cite = ["vendor-guide"];
  content.sources = [
    {
      key: "vendor-guide",
      title: "User guide",
      publisher: "Example Vendor",
      url: "https://example.org/guide",
      edition_date: "2026-03-01",
      retrieved_on: "2026-09-15",
      kind: "vendor",
    },
  ];
  return content;
}

/**
 * A `pageshow` event with `persisted`. jsdom may lack
 * `PageTransitionEvent`, so the member is set on a plain event.
 */
function pageshow(persisted: boolean): Event {
  const event = new Event("pageshow");
  Object.defineProperty(event, "persisted", { value: persisted });
  return event;
}

describe("ScormPlayer", () => {
  test("shows the module title and the module station without a request", async () => {
    const fetchSpy = vi.fn<typeof fetch>();
    vi.stubGlobal("fetch", fetchSpy);
    renderPlayer();

    expect(
      await screen.findByRole("heading", { level: 1, name: "Basics" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("heading", { level: 2, name: "Introduction" }),
    ).toBeInTheDocument();
    expect(screen.getByText("Which part names the task?")).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Complete module" }),
    ).toBeInTheDocument();
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  test("opens the glossary in the memory router and returns to the station", async () => {
    const before = window.location.href;
    const { user } = renderPlayer();

    await user.click(await screen.findByRole("button", { name: "Prompt" }));

    expect(
      await screen.findByRole("heading", { level: 1, name: "Glossary" }),
    ).toBeInTheDocument();
    expect(
      screen.getByText("The input to a model.", { selector: "dd" }),
    ).toBeInTheDocument();
    expect(window.location.href).toBe(before);

    await user.click(screen.getByRole("link", { name: "Back to Demo pack" }));

    expect(
      await screen.findByRole("heading", { level: 1, name: "Basics" }),
    ).toHaveFocus();
    expect(window.location.href).toBe(before);
  });

  test("opens a source link and a link of a block body in a new tab", async () => {
    renderPlayer(contentWithLinks());

    const source = await screen.findByRole("link", { name: "User guide" });
    const body = screen.getByRole("link", { name: "the guide" });
    for (const link of [source, body]) {
      expect(link).toHaveAttribute("href", "https://example.org/guide");
      expect(link).toHaveAttribute("target", "_blank");
      expect(link).toHaveAttribute("rel", "noopener noreferrer");
    }
  });

  test("a page restored from the back/forward cache shows sessionEnded in place of the player", async () => {
    const { rerender } = renderPlayer();
    await screen.findByRole("heading", { level: 1, name: "Basics" });
    onTestFinished(
      onRestoredFromCache(window, () =>
        rerender(<ScormNotice reason="sessionEnded" />),
      ),
    );

    window.dispatchEvent(pageshow(false));
    expect(
      screen.getByRole("heading", { level: 1, name: "Basics" }),
    ).toBeInTheDocument();

    window.dispatchEvent(pageshow(true));

    expect(
      await screen.findByRole("heading", { level: 1, name: "Session ended" }),
    ).toBeInTheDocument();
    expect(screen.getByRole("alert")).toHaveTextContent(
      /can no longer save anything/,
    );
    expect(screen.queryByRole("heading", { name: "Basics" })).toBeNull();
  });
});

describe("ScormNotice", () => {
  test("states that the package needs an LMS and shows nothing else", () => {
    const { container } = render(<ScormNotice reason="noLms" />);

    expect(
      screen.getByRole("heading", {
        level: 1,
        name: "Learning management system required",
      }),
    ).toBeInTheDocument();
    expect(screen.getByRole("alert")).toHaveTextContent(/inside a learning/);
    expect(container.querySelectorAll("main > *")).toHaveLength(2);
  });
});

describe("applyPackLanguage", () => {
  /** `scormContent` with the pack locale `locale`. */
  const withLocale = (locale: string): ScormContent => {
    const content = scormContent();
    content.program.locale = locale;
    return content;
  };

  test("the locale de-AT renders the notice in German", async () => {
    await applyPackLanguage(withLocale("de-AT"));
    render(<ScormNotice reason="sessionEnded" />);

    expect(
      screen.getByRole("heading", { level: 1, name: "Sitzung beendet" }),
    ).toBeInTheDocument();
    expect(screen.getByRole("alert")).toHaveTextContent(
      /aus der Lernplattform/,
    );
  });

  test("a locale without UI strings renders the notice in English", async () => {
    await i18n.changeLanguage("de");
    await applyPackLanguage(withLocale("fr"));
    render(<ScormNotice reason="sessionEnded" />);

    expect(
      screen.getByRole("heading", { level: 1, name: "Session ended" }),
    ).toBeInTheDocument();
  });
});
