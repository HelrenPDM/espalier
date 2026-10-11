import { screen, waitFor, within } from "@testing-library/react";
import { describe, expect, test } from "vitest";
import {
  AssessmentsOpenError,
  emptyResumeState,
  type ProgramView,
  type ResumeState,
} from "../player/runtime";
import { expectNoAxeViolations } from "../test/axe";
import {
  fakeRuntime,
  IDS,
  programFixture,
  renderPlayer,
  type FakeRuntime,
} from "../test/player";
import { ModuleStation } from "./ModuleStation";

/** The statements of the five objectives of module 1 of the fixture. */
const STATEMENTS = {
  evidenced: "Learners can explain how a model continues text.",
  exam: "Learners can explain why answers vary.",
  practice: "Learners can name the checks of a statement.",
  selfFormat: "Learners can judge which tasks they keep.",
  socialFormat: "Learners can agree with their team on transparency.",
} as const;

/**
 * One key in `evidencedObjectives`, a passed exam that holds the evidence
 * items of `m1-subject-exam`, an answered practice item of
 * `m1-method-practice`; `m1-self-format` and `m1-social-format` have only
 * the workshop format as evidence.
 */
const summaryState = (): ResumeState => ({
  ...emptyResumeState("full"),
  evidencedObjectives: ["m1-subject-evidenced"],
  examOutcomes: { [IDS.exam]: "passed" },
  answeredItems: [IDS.multipleChoice],
});

function renderStation({
  program = programFixture(),
  state = summaryState(),
  runtime = fakeRuntime({ program, state }),
}: {
  program?: ProgramView;
  state?: ResumeState;
  runtime?: FakeRuntime;
} = {}) {
  return renderPlayer(<ModuleStation station={program.stations[1]} />, {
    runtime,
  });
}

/** Waits for the loaded station: its "Complete module" button. */
const completeButton = () =>
  screen.findByRole("button", { name: "Complete module" });

/** The completion summary, a region named by its heading. */
const findSummary = () =>
  screen.findByRole("region", { name: "Module complete" });

/** The summary entry of the objective with `statement`. */
function entryOf(summary: HTMLElement, statement: string): HTMLElement {
  const entry = within(summary).getByText(statement).closest("li");
  expect(entry).not.toBeNull();
  return entry as HTMLElement;
}

/** The status span of a summary entry. */
function statusOf(entry: HTMLElement): HTMLElement {
  const status = entry.querySelector<HTMLElement>("[data-status]");
  expect(status).not.toBeNull();
  return status as HTMLElement;
}

/** The status region of the station, whose text starts "Module complete.". */
const completionStatus = () =>
  screen
    .getAllByRole("status")
    .find((region) => region.textContent?.startsWith("Module complete."));

/** A promise with its resolve function, to hold a mock on it. */
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => {
    resolve = done;
  });
  return { promise, resolve };
}

describe("ModuleStation completion", () => {
  test("after Complete module, the summary shows evidenced, evidenced, practised and open, and a format entry names the format with a link to the formats station", async () => {
    const { user, runtime } = renderStation();

    await user.click(await completeButton());
    const summary = await findSummary();

    expect(runtime.completeModule).toHaveBeenCalledWith(IDS.module1);
    const expected = [
      [
        STATEMENTS.evidenced,
        "m1-subject-evidenced",
        "evidenced",
        "Evidence shown",
      ],
      [STATEMENTS.exam, "m1-subject-exam", "evidenced", "Evidence shown"],
      [STATEMENTS.practice, "m1-method-practice", "practised", "Practised"],
      [STATEMENTS.selfFormat, "m1-self-format", "open", "Open"],
      [STATEMENTS.socialFormat, "m1-social-format", "open", "Open"],
    ] as const;
    for (const [statement, key, status, label] of expected) {
      const entry = entryOf(summary, statement);
      expect(entry).toHaveAttribute("data-objective-key", key);
      expect(statusOf(entry)).toHaveAttribute("data-status", status);
      expect(statusOf(entry)).toHaveTextContent(label);
    }

    // The format-only entries name the workshop and link to the station of
    // kind `companion_formats` (position 4).
    for (const statement of [STATEMENTS.selfFormat, STATEMENTS.socialFormat]) {
      const entry = entryOf(summary, statement);
      expect(entry).toHaveTextContent("Team workshop");
      expect(within(entry).getByRole("link")).toHaveAttribute(
        "href",
        "/programs/demo/stations/4",
      );
    }
    // An entry with evidence names no format.
    expect(entryOf(summary, STATEMENTS.exam)).not.toHaveTextContent(
      "Team workshop",
    );
  });

  test("without a companion formats station, the format note carries no link", async () => {
    const { user } = renderStation({
      program: programFixture({ withFormatStation: false }),
    });

    await user.click(await completeButton());
    const summary = await findSummary();

    const entry = entryOf(summary, STATEMENTS.selfFormat);
    expect(statusOf(entry)).toHaveAttribute("data-status", "open");
    expect(entry).toHaveTextContent("Team workshop");
    expect(within(entry).queryByRole("link")).toBeNull();
    expect(within(summary).queryAllByRole("link")).toHaveLength(0);
  });

  test("the refresh runs loadState again, takes a new evidenced key and calls saveState no time", async () => {
    const state = summaryState();
    const runtime = fakeRuntime({ state });
    const refresh = deferred<ResumeState | null>();
    runtime.loadState
      .mockResolvedValueOnce(structuredClone(state))
      .mockReturnValueOnce(refresh.promise);
    const { user } = renderStation({ runtime });

    await user.click(await completeButton());
    await waitFor(() => expect(runtime.loadState).toHaveBeenCalledTimes(2));

    // The completion added the module to `completedModules` through one
    // `saveState` call before the refresh.
    const savesBefore = runtime.saveState.mock.calls.length;
    expect(runtime.saveState).toHaveBeenLastCalledWith(
      expect.objectContaining({ completedModules: [IDS.module1] }),
    );

    refresh.resolve({
      ...state,
      completedModules: [IDS.module1],
      evidencedObjectives: ["m1-subject-evidenced", "m1-social-format"],
    });

    const summary = await findSummary();
    await waitFor(() =>
      expect(
        statusOf(entryOf(summary, STATEMENTS.socialFormat)),
      ).toHaveAttribute("data-status", "evidenced"),
    );
    expect(
      statusOf(entryOf(summary, STATEMENTS.socialFormat)),
    ).toHaveTextContent("Evidence shown");
    // An evidenced objective names no format.
    expect(entryOf(summary, STATEMENTS.socialFormat)).not.toHaveTextContent(
      "Team workshop",
    );
    expect(statusOf(entryOf(summary, STATEMENTS.selfFormat))).toHaveAttribute(
      "data-status",
      "open",
    );
    expect(runtime.saveState.mock.calls.length).toBe(savesBefore);
    expect(runtime.loadState).toHaveBeenCalledTimes(2);
  });

  test("focus lands on the summary heading, and the status region holds the completion text with the counts", async () => {
    const { user } = renderStation();

    await user.click(await completeButton());
    const heading = await screen.findByRole("heading", {
      name: "Module complete",
    });

    await waitFor(() => expect(heading).toHaveFocus());
    expect(completionStatus()).toHaveTextContent(
      "Module complete. Of its objectives, 2 show evidence, 1 is practised and 2 are open.",
    );
  });

  test("the summary text holds no percent sign", async () => {
    const { user } = renderStation();

    await user.click(await completeButton());
    const summary = await findSummary();

    expect(summary.textContent).not.toContain("%");
    expect(summary).toHaveTextContent(
      "Of the objectives of this topic, 2 show evidence, 1 is practised and 2 are open.",
    );
    expect(completionStatus()?.textContent).not.toContain("%");
  });

  test("on AssessmentsOpenError, no summary appears and the open exam is listed by title", async () => {
    const runtime = fakeRuntime({ state: emptyResumeState("full") });
    runtime.completeModule.mockRejectedValueOnce(
      new AssessmentsOpenError([
        { id: IDS.exam, key: "module-1-exam", title: "Exam of module 1" },
      ]),
    );
    const { user } = renderStation({ runtime });

    await user.click(await completeButton());
    const alert = await screen.findByRole("alert");

    expect(alert).toHaveTextContent(
      "Pass these exams before you complete the module:",
    );
    expect(within(alert).getByRole("listitem")).toHaveTextContent(
      "Exam of module 1",
    );
    expect(
      screen.queryByRole("region", { name: "Module complete" }),
    ).toBeNull();
    expect(
      screen.queryByRole("heading", { name: "Module complete" }),
    ).toBeNull();
    expect(completionStatus()).toBeUndefined();
    // The module did not join `completedModules`.
    for (const [saved] of runtime.saveState.mock.calls)
      expect(saved.completedModules).not.toContain(IDS.module1);
    expect(
      screen.getByRole("button", { name: "Complete module" }),
    ).toBeEnabled();
  });

  test("a module in completedModules shows the summary when the station opens", async () => {
    const { runtime } = renderStation({
      state: { ...summaryState(), completedModules: [IDS.module1] },
    });

    const summary = await findSummary();

    expect(statusOf(entryOf(summary, STATEMENTS.practice))).toHaveAttribute(
      "data-status",
      "practised",
    );
    expect(
      screen.queryByRole("button", { name: "Complete module" }),
    ).toBeNull();
    expect(runtime.completeModule).not.toHaveBeenCalled();
  });

  test("the station has no axe violations in light and dark mode, before and after the completion", async () => {
    const { user, container } = renderStation();

    const button = await completeButton();
    await expectNoAxeViolations(container);

    await user.click(button);
    await findSummary();
    await expectNoAxeViolations(container);
  }, 30_000);
});

describe("ModuleStation reveal and path", () => {
  const lessonOne = () => {
    const section = document.getElementById(`lesson-${IDS.lesson1}`);
    expect(section).not.toBeNull();
    return section as HTMLElement;
  };
  const explanationButton = () =>
    within(lessonOne()).getByRole("button", { name: "Explanation" });
  const singleChoice = () =>
    screen.getByRole("group", { name: "How does a language model write?" });

  /** Answers the single choice item with the wrong option. */
  async function answerWrong(user: ReturnType<typeof renderStation>["user"]) {
    const item = singleChoice();
    await user.click(
      within(item).getByRole("radio", {
        name: "It looks up a database of facts.",
      }),
    );
    await user.click(
      within(item).getByRole("button", { name: "Check answer" }),
    );
  }

  function revealingRuntime(path: ResumeState["path"]) {
    const runtime = fakeRuntime({ state: emptyResumeState(path) });
    runtime.submitItem.mockResolvedValueOnce({
      item_id: IDS.singleChoice,
      correct: false,
      option_feedback: [],
      rules: [],
      reveals: [IDS.lesson1],
    });
    return runtime;
  }

  test("on the short path, a wrong answer opens the collapsed explanation of the lesson it reveals", async () => {
    const runtime = revealingRuntime("short");
    const { user } = renderStation({ runtime });
    await completeButton();

    expect(explanationButton()).toHaveAttribute("aria-expanded", "false");

    await answerWrong(user);

    await waitFor(() =>
      expect(explanationButton()).toHaveAttribute("aria-expanded", "true"),
    );
    expect(runtime.submitItem).toHaveBeenCalledWith(IDS.singleChoice, {
      options: ["option-2"],
    });
    expect(runtime.saveState).toHaveBeenLastCalledWith(
      expect.objectContaining({
        openedExplanations: [IDS.explanationShort],
        answeredItems: [IDS.singleChoice],
      }),
    );
    const status = within(singleChoice()).getByRole("status");
    expect(status).toHaveTextContent("Not correct.");
    expect(
      within(status).getByRole("link", { name: "What a language model does" }),
    ).toHaveAttribute("href", `#lesson-${IDS.lesson1}`);
  });

  test("on the full path, the same answer opens nothing new", async () => {
    const runtime = revealingRuntime("full");
    const { user } = renderStation({ runtime });
    await completeButton();

    // On the full path, the explanation starts open.
    expect(explanationButton()).toHaveAttribute("aria-expanded", "true");

    await answerWrong(user);

    await waitFor(() =>
      expect(runtime.saveState).toHaveBeenLastCalledWith(
        expect.objectContaining({ answeredItems: [IDS.singleChoice] }),
      ),
    );
    for (const [saved] of runtime.saveState.mock.calls)
      expect(saved.openedExplanations).toEqual([]);
    const status = within(singleChoice()).getByRole("status");
    expect(status).toHaveTextContent("Not correct.");
    expect(status).not.toHaveTextContent("What a language model does");
    expect(within(status).queryByRole("link")).toBeNull();
    expect(explanationButton()).toHaveAttribute("aria-expanded", "true");
  });

  test("the path switch passes the new path to saveState", async () => {
    const runtime = fakeRuntime({ state: emptyResumeState("full") });
    const { user } = renderStation({ runtime });
    await completeButton();

    const short = screen.getByRole("radio", { name: "Short path" });
    expect(short).toHaveAttribute("aria-checked", "false");
    await user.click(short);

    await waitFor(() =>
      expect(runtime.saveState).toHaveBeenLastCalledWith(
        expect.objectContaining({ path: "short" }),
      ),
    );
    expect(screen.getByRole("radio", { name: "Short path" })).toHaveAttribute(
      "aria-checked",
      "true",
    );
    // On the short path, the explanation of lesson 1 starts collapsed.
    expect(explanationButton()).toHaveAttribute("aria-expanded", "false");

    await user.click(screen.getByRole("radio", { name: "Full path" }));
    await waitFor(() =>
      expect(runtime.saveState).toHaveBeenLastCalledWith(
        expect.objectContaining({ path: "full" }),
      ),
    );
  });
});
