import { screen, waitFor, within } from "@testing-library/react";
import { describe, expect, test } from "vitest";
import {
  emptyResumeState,
  type AttemptResult,
  type ExamOutcome,
  type ItemFeedback,
  type ResumeState,
} from "../player/runtime";
import { expectNoAxeViolations } from "../test/axe";
import {
  fakeRuntime,
  id,
  IDS,
  module1,
  renderPlayer,
  type FakeRuntime,
} from "../test/player";
import { ExamSection } from "./ExamSection";

const STEM_1 = "What does a model do when it writes?";
const STEM_2 = "Which parts need a check?";

function renderExam({
  state = emptyResumeState("full"),
  runtime = fakeRuntime({ state }),
}: { state?: ResumeState; runtime?: FakeRuntime } = {}) {
  const module = module1();
  return renderPlayer(<ExamSection exam={module.exams[0]} module={module} />, {
    runtime,
  });
}

const itemGroup = (stem: string) => screen.getByRole("group", { name: stem });
const submitButton = () =>
  screen.getByRole("button", { name: "Submit the exam" });

/** Chooses the option `label` of the exam item `stem`. */
async function choose(
  user: ReturnType<typeof renderExam>["user"],
  stem: string,
  label: string,
) {
  await user.click(within(itemGroup(stem)).getByRole("radio", { name: label }));
}

/** Answers both items: item 1 right (option 1), item 2 wrong (option 2). */
async function answerAll(user: ReturnType<typeof renderExam>["user"]) {
  await choose(user, STEM_1, "It continues text.");
  await choose(user, STEM_2, "Nothing.");
}

const result = (
  itemId: string,
  correct: boolean,
  selected: string,
  feedback: Record<string, string>,
): ItemFeedback => ({
  item_id: itemId,
  correct,
  option_feedback: ["option-1", "option-2"].map((key) => ({
    key,
    selected: key === selected,
    // Option 1 is the right answer of both exam items.
    correct: key === "option-1",
    feedback: feedback[key] ?? null,
  })),
  rules: [],
  reveals: [],
});

function attempt(
  outcome: ExamOutcome,
  overrides: Partial<AttemptResult> = {},
): AttemptResult {
  return {
    id: id(900),
    assessment_id: IDS.exam,
    number: 1,
    outcome,
    core_failed: outcome === "failed_core",
    wrong_count: 1,
    submitted_at: "2026-10-11T10:00:00Z",
    results: [
      result(IDS.examItem1, true, "option-1", {
        "option-1": "A model continues text with likely words.",
        "option-2": "No database lies behind the answer.",
      }),
      result(IDS.examItem2, false, "option-2", {
        "option-1": "Names and numbers need a check against a source.",
      }),
    ],
    ...overrides,
  };
}

/** The outcome paragraph of the result. */
const outcome = () => document.querySelector<HTMLElement>("[data-outcome]");

describe("ExamSection", () => {
  test("submit is disabled until every exam item has an answer", async () => {
    const { user } = renderExam();
    await screen.findByRole("heading", { name: "Exam of module 1" });

    expect(submitButton()).toBeDisabled();
    await choose(user, STEM_1, "It continues text.");
    expect(submitButton()).toBeDisabled();
    await choose(user, STEM_2, "Nothing.");
    expect(submitButton()).toBeEnabled();
  });

  test("submitAssessment gets the chosen option of every item", async () => {
    const { user, runtime } = renderExam();
    await screen.findByRole("heading", { name: "Exam of module 1" });

    await answerAll(user);
    await user.click(submitButton());

    await waitFor(() => expect(runtime.submitAssessment).toHaveBeenCalled());
    expect(runtime.submitAssessment).toHaveBeenCalledTimes(1);
    expect(runtime.submitAssessment).toHaveBeenCalledWith(IDS.exam, {
      [IDS.examItem1]: { options: ["option-1"] },
      [IDS.examItem2]: { options: ["option-2"] },
    });
  });

  test.each([
    [
      "failed_core",
      attempt("failed_core"),
      "Not passed: a core question is answered wrong.",
    ],
    [
      "failed_errors",
      attempt("failed_errors", { wrong_count: 2 }),
      "Not passed: 2 answers are wrong, more than the 1 this exam allows.",
    ],
    ["passed", attempt("passed"), "Passed: 1 of 2 answers are correct."],
  ] as const)(
    "the outcome %s renders with its reason and no percent sign",
    async (kind, answer, text) => {
      const runtime = fakeRuntime();
      runtime.submitAssessment.mockResolvedValueOnce(answer);
      const { user } = renderExam({ runtime });
      await screen.findByRole("heading", { name: "Exam of module 1" });

      await answerAll(user);
      await user.click(submitButton());

      await waitFor(() => expect(outcome()).not.toBeNull());
      expect(outcome()).toHaveAttribute("data-outcome", kind);
      expect(outcome()).toHaveTextContent(text);
      const section = screen.getByRole("region", { name: "Exam of module 1" });
      expect(section.textContent).not.toContain("%");
      // The outcome sits in the status region of the exam.
      const status = within(section)
        .getAllByRole("status")
        .find((region) => region.contains(outcome()));
      expect(status).toBeDefined();
    },
  );

  test("passed names the number of correct answers", async () => {
    const runtime = fakeRuntime();
    runtime.submitAssessment.mockResolvedValueOnce(
      attempt("passed", {
        wrong_count: 0,
        results: [
          result(IDS.examItem1, true, "option-1", {}),
          result(IDS.examItem2, true, "option-1", {}),
        ],
      }),
    );
    const { user } = renderExam({ runtime });
    await screen.findByRole("heading", { name: "Exam of module 1" });

    await choose(user, STEM_1, "It continues text.");
    await choose(user, STEM_2, "Every name and number.");
    await user.click(submitButton());

    await waitFor(() =>
      expect(outcome()).toHaveTextContent(
        "Passed: 2 of 2 answers are correct.",
      ),
    );
  });

  test("shows the feedback per item and locks the answers", async () => {
    const runtime = fakeRuntime();
    runtime.submitAssessment.mockResolvedValueOnce(attempt("passed"));
    const { user } = renderExam({ runtime });
    await screen.findByRole("heading", { name: "Exam of module 1" });

    await answerAll(user);
    await user.click(submitButton());
    await waitFor(() => expect(outcome()).not.toBeNull());

    const first = itemGroup(STEM_1);
    expect(first).toHaveTextContent("Correct.");
    expect(first).toHaveTextContent(
      "A model continues text with likely words.",
    );
    expect(first).toHaveTextContent("No database lies behind the answer.");

    const second = itemGroup(STEM_2);
    expect(second).toHaveTextContent("Not correct.");
    expect(second).toHaveTextContent("Your choice is not correct");
    expect(second).toHaveTextContent(
      "Names and numbers need a check against a source.",
    );

    for (const radio of within(first).getAllByRole("radio"))
      expect(radio).toHaveAttribute("aria-disabled", "true");
    expect(
      screen.queryByRole("button", { name: "Submit the exam" }),
    ).toBeNull();
  });

  test("New attempt clears the answers and the result", async () => {
    const runtime = fakeRuntime();
    runtime.submitAssessment.mockResolvedValueOnce(attempt("failed_core"));
    const { user } = renderExam({ runtime });
    await screen.findByRole("heading", { name: "Exam of module 1" });

    await answerAll(user);
    await user.click(submitButton());
    await waitFor(() => expect(outcome()).not.toBeNull());

    await user.click(screen.getByRole("button", { name: "New attempt" }));

    expect(outcome()).toBeNull();
    expect(submitButton()).toBeDisabled();
    for (const stem of [STEM_1, STEM_2]) {
      const group = itemGroup(stem);
      for (const radio of within(group).getAllByRole("radio")) {
        expect(radio).toHaveAttribute("aria-checked", "false");
        expect(radio).not.toHaveAttribute("aria-disabled", "true");
      }
      expect(group).not.toHaveTextContent("Correct.");
      expect(group).not.toHaveTextContent("Not correct.");
    }
  });

  test("the outcome reaches examOutcomes through saveState", async () => {
    const runtime = fakeRuntime();
    runtime.submitAssessment.mockResolvedValueOnce(attempt("failed_errors"));
    const { user } = renderExam({ runtime });
    await screen.findByRole("heading", { name: "Exam of module 1" });

    await answerAll(user);
    await user.click(submitButton());

    await waitFor(() =>
      expect(runtime.saveState).toHaveBeenLastCalledWith(
        expect.objectContaining({
          examOutcomes: { [IDS.exam]: "failed_errors" },
        }),
      ),
    );
  });

  test("a later failed_core after a passed attempt keeps passed", async () => {
    const runtime = fakeRuntime();
    runtime.submitAssessment
      .mockResolvedValueOnce(attempt("passed"))
      .mockResolvedValueOnce(attempt("failed_core", { number: 2 }));
    const { user } = renderExam({ runtime });
    await screen.findByRole("heading", { name: "Exam of module 1" });

    await answerAll(user);
    await user.click(submitButton());
    await waitFor(() =>
      expect(runtime.saveState).toHaveBeenLastCalledWith(
        expect.objectContaining({ examOutcomes: { [IDS.exam]: "passed" } }),
      ),
    );

    await user.click(screen.getByRole("button", { name: "New attempt" }));
    await answerAll(user);
    await user.click(submitButton());
    await waitFor(() =>
      expect(outcome()).toHaveAttribute("data-outcome", "failed_core"),
    );

    expect(runtime.submitAssessment).toHaveBeenCalledTimes(2);
    expect(runtime.saveState).toHaveBeenLastCalledWith(
      expect.objectContaining({ examOutcomes: { [IDS.exam]: "passed" } }),
    );
    for (const [saved] of runtime.saveState.mock.calls)
      expect(saved.examOutcomes[IDS.exam]).not.toBe("failed_core");
  });

  test("a passed outcome of the state stays passed after a failed attempt", async () => {
    const runtime = fakeRuntime({
      state: {
        ...emptyResumeState("full"),
        examOutcomes: { [IDS.exam]: "passed" },
      },
    });
    runtime.submitAssessment.mockResolvedValueOnce(attempt("failed_core"));
    const { user } = renderExam({ runtime });
    await screen.findByText(
      "You have passed this exam. A new attempt is possible at any time.",
    );
    const savesBefore = runtime.saveState.mock.calls.length;

    await answerAll(user);
    await user.click(submitButton());
    await waitFor(() =>
      expect(outcome()).toHaveAttribute("data-outcome", "failed_core"),
    );

    // The state is unchanged, so no save follows.
    expect(runtime.saveState.mock.calls.length).toBe(savesBefore);
  });

  test("has no axe violations before and after a submission", async () => {
    const runtime = fakeRuntime();
    runtime.submitAssessment.mockResolvedValueOnce(attempt("failed_core"));
    const { user, container } = renderExam({ runtime });
    await screen.findByRole("heading", { name: "Exam of module 1" });

    await expectNoAxeViolations(container);
    await answerAll(user);
    await user.click(submitButton());
    await waitFor(() => expect(outcome()).not.toBeNull());
    await expectNoAxeViolations(container);
  }, 30_000);
});
