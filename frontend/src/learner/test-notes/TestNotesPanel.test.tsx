import { screen, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { useTestNote } from "../../player/testNotes";
import { expectNoAxeViolations } from "../../test/axe";
import { IDS } from "../../test/player";
import { renderWithProviders } from "../../test/render";
import { signedInPayload } from "../../test/session";
import { testNotesLog } from "./store";
import { TestNotesProvider } from "./TestNotesProvider";

/**
 * Task 0014 step 11: with `flags.testNotes`, the provider passes the
 * store's record function to the player and shows the "Test notes" panel
 * with the log as text, one line per event with its time since the log
 * started, and buttons that copy and clear the log. Without the flag, the
 * player records into nothing and no panel appears.
 */
function Recorder() {
  const note = useTestNote();
  return (
    <button
      type="button"
      onClick={() =>
        note({ event: "item_answered", item: IDS.poll, correct: null })
      }
    >
      Answer the poll
    </button>
  );
}

function renderPanel(testNotes = true) {
  return renderWithProviders(
    <TestNotesProvider>
      <Recorder />
    </TestNotesProvider>,
    {
      session: signedInPayload("mfa", { flags: { test_notes: testNotes } }),
    },
  );
}

const panel = () => screen.getByRole("region", { name: "Test notes" });
const logText = () =>
  within(panel()).getByRole("textbox", { name: "Recorded events" });

beforeEach(() => {
  const log = testNotesLog(true);
  log.clear();
  const now = vi.spyOn(Date, "now");
  now.mockReturnValue(100_000);
  log.record({ event: "station_opened", station: 2 });
  now.mockReturnValue(165_400);
  log.record({ event: "path_switched", path: "full" });
  now.mockReturnValue(170_000);
  log.record({
    event: "exam_submitted",
    assessment: IDS.exam,
    outcome: "failed_errors",
  });
});

afterEach(() => {
  vi.restoreAllMocks();
  testNotesLog(true).clear();
});

describe("TestNotesPanel", () => {
  test("shows the log as text with the time of each event", async () => {
    const { container } = renderPanel();

    expect(logText()).toHaveValue(
      [
        "+0:00 Station 2 opened",
        "+1:05 Path switched: Full path",
        `+1:10 Exam ${IDS.exam} failed: too many wrong answers`,
      ].join("\n"),
    );
    expect(logText()).toHaveAttribute("readonly");
    expect(panel()).toHaveTextContent(
      "It stays in this browser tab until the next sign-out or sign-in, holds no personal data and is never sent to the server.",
    );
    await expectNoAxeViolations(container);
  });

  test("an event of the player appears in the panel at once", async () => {
    const { user } = renderPanel();
    vi.spyOn(Date, "now").mockReturnValue(172_000);

    await user.click(screen.getByRole("button", { name: "Answer the poll" }));

    expect((logText() as HTMLTextAreaElement).value.split("\n").at(-1)).toBe(
      `+1:12 Poll ${IDS.poll} answered`,
    );
  });

  test("copy writes the text to the clipboard", async () => {
    const { user } = renderPanel();

    await user.click(within(panel()).getByRole("button", { name: "Copy" }));

    expect(await navigator.clipboard.readText()).toBe(
      (logText() as HTMLTextAreaElement).value,
    );
    expect(within(panel()).getByRole("status")).toHaveTextContent(
      "The notes were copied.",
    );
  });

  test("a failed copy says how to copy by hand", async () => {
    const { user } = renderPanel();
    vi.spyOn(navigator.clipboard, "writeText").mockRejectedValue(
      new Error("denied"),
    );

    await user.click(within(panel()).getByRole("button", { name: "Copy" }));

    expect(await within(panel()).findByRole("status")).toHaveTextContent(
      "The notes could not be copied. Select the text and copy it by hand.",
    );
  });

  test("clear empties the log and disables the buttons", async () => {
    const { user } = renderPanel();

    await user.click(within(panel()).getByRole("button", { name: "Clear" }));

    expect(logText()).toHaveValue("");
    expect(logText()).toHaveAttribute("placeholder", "No events recorded yet.");
    expect(testNotesLog(true).notes()).toEqual([]);
    expect(
      within(panel()).getByRole("button", { name: "Copy" }),
    ).toBeDisabled();
    expect(
      within(panel()).getByRole("button", { name: "Clear" }),
    ).toBeDisabled();
    expect(within(panel()).getByRole("status")).toHaveTextContent(
      "The notes were cleared.",
    );
  });

  test("without the flag there is no panel and the player records nothing", async () => {
    const { user } = renderPanel(false);

    await user.click(screen.getByRole("button", { name: "Answer the poll" }));

    expect(screen.queryByRole("region", { name: "Test notes" })).toBeNull();
    expect(testNotesLog(true).notes()).toHaveLength(3);
  });
});
