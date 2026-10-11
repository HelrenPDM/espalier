import { act, screen, within } from "@testing-library/react";
import { describe, expect, test, vi, type Mock } from "vitest";
import { expectNoAxeViolations } from "../../test/axe";
import { IDS, programFixture, renderPlayer } from "../../test/player";
import type { ItemFeedback, ItemView, Lesson } from "../runtime";
import { PracticeItem } from "./PracticeItem";

const program = programFixture();

type OnAnswered = (item: ItemView, feedback: ItemFeedback) => Lesson[];

/** The practice item `itemId` of the fixture and the id of its module. */
function practiceItem(itemId: string): { item: ItemView; moduleId: string } {
  for (const module of program.modules) {
    const found = module.practice_items.find((entry) => entry.id === itemId);
    if (found) return { item: found, moduleId: module.id };
  }
  throw new Error(`The fixture has no practice item ${itemId}.`);
}

/**
 * Renders the practice item `itemId` of the fixture through `PracticeItem`
 * and waits for the player. `frame` is the group of the item, `status` its
 * status region.
 */
async function renderItem(
  itemId: string,
  onAnswered: Mock<OnAnswered> = vi.fn<OnAnswered>(() => []),
) {
  const { item, moduleId } = practiceItem(itemId);
  const view = renderPlayer(
    <PracticeItem item={item} moduleId={moduleId} onAnswered={onAnswered} />,
  );
  const frame = await screen.findByRole("group", { name: item.stem });
  return {
    ...view,
    item,
    onAnswered,
    frame,
    status: within(frame).getByRole("status"),
  };
}

/**
 * The element around the visible text `text` of an option, slot, case or
 * check: the label and the feedback below it share this parent.
 */
// The row of an option, slot, case or check: the nearest list item or box
// around its label text.
const rowOf = (frame: HTMLElement, text: string) =>
  within(within(frame).getByText(text).closest("li, div") as HTMLElement);

/**
 * Matches the innermost element whose text is `text`, also when the text
 * spans child elements, such as the content language span in "Expected:
 * <category>".
 */
const fullText =
  (text: string) => (_content: string, element: Element | null) =>
    element !== null &&
    element.textContent === text &&
    Array.from(element.children).every((child) => child.textContent !== text);

const RULE_1 = {
  id: IDS.rule1,
  number: 1,
  statement: "Generated text carries no check of its own.",
  action: "Treat every generated statement as a draft.",
};

const RULE_2 = {
  id: IDS.rule2,
  number: 2,
  statement: "The same request can produce different answers.",
  action: "Keep the version you have checked.",
};

const SINGLE_FIRST = "It continues the text with likely words.";
const SINGLE_SECOND = "It looks up a database of facts.";

const singleCorrect: ItemFeedback = {
  item_id: IDS.singleChoice,
  correct: true,
  option_feedback: [
    {
      key: "option-1",
      selected: true,
      correct: true,
      feedback: "The model predicts the next word.",
    },
    {
      key: "option-2",
      selected: false,
      correct: false,
      feedback: "A model has no table of facts.",
    },
  ],
  rules: [RULE_1],
  reveals: [],
};

const singleWrong: ItemFeedback = {
  item_id: IDS.singleChoice,
  correct: false,
  option_feedback: [
    {
      key: "option-1",
      selected: false,
      correct: true,
      feedback: "The model predicts the next word.",
    },
    {
      key: "option-2",
      selected: true,
      correct: false,
      feedback: "A model has no table of facts.",
    },
  ],
  rules: [RULE_1, RULE_2],
  reveals: [IDS.lesson1],
};

describe("SingleChoiceItem", () => {
  test("enables the check once an option is chosen and sends that option", async () => {
    const { user, runtime, frame } = await renderItem(IDS.singleChoice);
    const submit = within(frame).getByRole("button", { name: "Check answer" });
    const first = within(frame).getByRole("radio", { name: SINGLE_FIRST });
    const second = within(frame).getByRole("radio", { name: SINGLE_SECOND });
    expect(submit).toBeDisabled();
    expect(first).not.toBeChecked();

    await user.click(second);
    expect(second).toBeChecked();
    expect(submit).toBeEnabled();
    await user.click(first);
    expect(first).toBeChecked();
    expect(second).not.toBeChecked();

    runtime.submitItem.mockResolvedValueOnce(singleCorrect);
    await user.click(submit);
    expect(runtime.submitItem).toHaveBeenCalledTimes(1);
    expect(runtime.submitItem).toHaveBeenCalledWith(IDS.singleChoice, {
      options: ["option-1"],
    });
  });

  test("the radio group is labelled by the stem", async () => {
    const { frame, item } = await renderItem(IDS.singleChoice);
    // The editor receives the stem id to label the inputs as a group.
    expect(
      within(frame).getByRole("radiogroup", { name: item.stem }),
    ).toBeInTheDocument();
  });

  test("a correct answer shows the result, the feedback per option and the rule links, and locks the options", async () => {
    const { user, runtime, frame, status } = await renderItem(IDS.singleChoice);
    expect(status).toBeEmptyDOMElement();
    await user.click(within(frame).getByRole("radio", { name: SINGLE_FIRST }));
    runtime.submitItem.mockResolvedValueOnce(singleCorrect);
    await user.click(
      within(frame).getByRole("button", { name: "Check answer" }),
    );

    expect(await within(status).findByText("Correct.")).toBeInTheDocument();
    const rule = within(status).getByRole("link", {
      name: "Rule 1: Generated text carries no check of its own.",
    });
    expect(rule).toHaveAttribute("href", "#rule-1");
    expect(
      within(status).getByText("The rules behind this question:"),
    ).toBeInTheDocument();

    const first = rowOf(frame, SINGLE_FIRST);
    expect(first.getByText("Correct answer")).toBeInTheDocument();
    expect(
      first.getByText("The model predicts the next word."),
    ).toBeInTheDocument();
    const second = rowOf(frame, SINGLE_SECOND);
    expect(second.queryByText("Correct answer")).not.toBeInTheDocument();
    expect(
      second.queryByText("Your choice is not correct"),
    ).not.toBeInTheDocument();
    expect(
      second.getByText("A model has no table of facts."),
    ).toBeInTheDocument();

    // The options take no change after the submission.
    const radios = within(frame).getAllByRole("radio");
    for (const radio of radios)
      expect(radio).toHaveAttribute("aria-disabled", "true");
    await user.click(within(frame).getByRole("radio", { name: SINGLE_SECOND }));
    expect(
      within(frame).getByRole("radio", { name: SINGLE_FIRST }),
    ).toBeChecked();
    expect(
      within(frame).queryByRole("button", { name: "Check answer" }),
    ).not.toBeInTheDocument();
  });

  test("a wrong answer marks the chosen option and the correct one", async () => {
    const { user, runtime, frame, status } = await renderItem(IDS.singleChoice);
    await user.click(within(frame).getByRole("radio", { name: SINGLE_SECOND }));
    runtime.submitItem.mockResolvedValueOnce(singleWrong);
    await user.click(
      within(frame).getByRole("button", { name: "Check answer" }),
    );

    expect(await within(status).findByText("Not correct.")).toBeInTheDocument();
    expect(
      rowOf(frame, SINGLE_SECOND).getByText("Your choice is not correct"),
    ).toBeInTheDocument();
    expect(
      rowOf(frame, SINGLE_FIRST).getByText("Correct answer"),
    ).toBeInTheDocument();
    expect(
      within(status)
        .getAllByRole("link")
        .map((link) => link.getAttribute("href")),
    ).toEqual(["#rule-1", "#rule-2"]);
  });

  test("Try again clears the answer and the feedback", async () => {
    const { user, runtime, frame, status } = await renderItem(IDS.singleChoice);
    await user.click(within(frame).getByRole("radio", { name: SINGLE_FIRST }));
    runtime.submitItem.mockResolvedValueOnce(singleCorrect);
    await user.click(
      within(frame).getByRole("button", { name: "Check answer" }),
    );
    await within(status).findByText("Correct.");

    await user.click(within(frame).getByRole("button", { name: "Try again" }));
    expect(status).toBeEmptyDOMElement();
    for (const radio of within(frame).getAllByRole("radio")) {
      expect(radio).not.toBeChecked();
      expect(radio).not.toHaveAttribute("aria-disabled", "true");
    }
    expect(within(frame).queryByText("Correct answer")).not.toBeInTheDocument();
    expect(
      within(frame).getByRole("button", { name: "Check answer" }),
    ).toBeDisabled();
    expect(
      within(frame).queryByRole("button", { name: "Try again" }),
    ).not.toBeInTheDocument();
  });

  test("has no axe violations before and after the submission", async () => {
    const { user, runtime, frame, status, container } = await renderItem(
      IDS.singleChoice,
    );
    await expectNoAxeViolations(container);
    await user.click(within(frame).getByRole("radio", { name: SINGLE_SECOND }));
    runtime.submitItem.mockResolvedValueOnce(singleWrong);
    await user.click(
      within(frame).getByRole("button", { name: "Check answer" }),
    );
    await within(status).findByText("Not correct.");
    await expectNoAxeViolations(container);
  });
});

const MULTI = [
  "Chance at each step.",
  "Earlier turns.",
  "A person edits them.",
];

const multiWrong: ItemFeedback = {
  item_id: IDS.multipleChoice,
  correct: false,
  option_feedback: [
    {
      key: "option-1",
      selected: true,
      correct: true,
      feedback: "Sampling picks among likely words.",
    },
    {
      key: "option-2",
      selected: false,
      correct: true,
      feedback: "The model reads the whole conversation.",
    },
    {
      key: "option-3",
      selected: true,
      correct: false,
      feedback: "Nobody edits an answer in between.",
    },
  ],
  rules: [RULE_2],
  reveals: [IDS.lesson2],
};

describe("MultipleChoiceItem", () => {
  test("enables the check with at least one option and sends every chosen option", async () => {
    const { user, runtime, frame } = await renderItem(IDS.multipleChoice);
    const submit = within(frame).getByRole("button", { name: "Check answer" });
    const boxes = MULTI.map((label) =>
      within(frame).getByRole("checkbox", { name: label }),
    );
    expect(submit).toBeDisabled();

    await user.click(boxes[0]);
    expect(boxes[0]).toBeChecked();
    expect(submit).toBeEnabled();
    await user.click(boxes[0]);
    expect(boxes[0]).not.toBeChecked();
    expect(submit).toBeDisabled();

    await user.click(boxes[0]);
    await user.click(boxes[2]);
    expect(submit).toBeEnabled();
    runtime.submitItem.mockResolvedValueOnce(multiWrong);
    await user.click(submit);
    expect(runtime.submitItem).toHaveBeenCalledTimes(1);
    expect(runtime.submitItem).toHaveBeenCalledWith(IDS.multipleChoice, {
      options: ["option-1", "option-3"],
    });
  });

  test("locks the options and the button while the answer is sent", async () => {
    const { user, runtime, frame, status } = await renderItem(
      IDS.multipleChoice,
    );
    await user.click(within(frame).getByRole("checkbox", { name: MULTI[0] }));
    let resolve!: (feedback: ItemFeedback) => void;
    runtime.submitItem.mockReturnValueOnce(
      new Promise<ItemFeedback>((done) => {
        resolve = done;
      }),
    );
    await user.click(
      within(frame).getByRole("button", { name: "Check answer" }),
    );

    expect(
      within(frame).getByRole("button", { name: "Checking…" }),
    ).toBeDisabled();
    for (const box of within(frame).getAllByRole("checkbox"))
      expect(box).toBeDisabled();

    await act(async () => resolve({ ...multiWrong, correct: true }));
    expect(await within(status).findByText("Correct.")).toBeInTheDocument();
    expect(
      within(frame).queryByRole("button", { name: "Checking…" }),
    ).not.toBeInTheDocument();
  });

  test("shows the feedback per option and keeps the options disabled after the submission", async () => {
    const { user, runtime, frame, status } = await renderItem(
      IDS.multipleChoice,
    );
    await user.click(within(frame).getByRole("checkbox", { name: MULTI[0] }));
    await user.click(within(frame).getByRole("checkbox", { name: MULTI[2] }));
    runtime.submitItem.mockResolvedValueOnce(multiWrong);
    await user.click(
      within(frame).getByRole("button", { name: "Check answer" }),
    );

    expect(await within(status).findByText("Not correct.")).toBeInTheDocument();
    expect(
      within(status).getByRole("link", {
        name: "Rule 2: The same request can produce different answers.",
      }),
    ).toHaveAttribute("href", "#rule-2");

    const chosenCorrect = rowOf(frame, MULTI[0]);
    expect(chosenCorrect.getByText("Correct answer")).toBeInTheDocument();
    expect(
      chosenCorrect.getByText("Sampling picks among likely words."),
    ).toBeInTheDocument();
    const missed = rowOf(frame, MULTI[1]);
    expect(missed.getByText("Correct answer")).toBeInTheDocument();
    expect(
      missed.getByText("The model reads the whole conversation."),
    ).toBeInTheDocument();
    const chosenWrong = rowOf(frame, MULTI[2]);
    expect(
      chosenWrong.getByText("Your choice is not correct"),
    ).toBeInTheDocument();
    expect(chosenWrong.queryByText("Correct answer")).not.toBeInTheDocument();
    expect(
      chosenWrong.getByText("Nobody edits an answer in between."),
    ).toBeInTheDocument();

    for (const box of within(frame).getAllByRole("checkbox"))
      expect(box).toBeDisabled();
    expect(
      within(frame).getByRole("checkbox", { name: MULTI[0] }),
    ).toBeChecked();
    expect(
      within(frame).getByRole("checkbox", { name: MULTI[1] }),
    ).not.toBeChecked();
  });

  test("Try again clears the chosen options", async () => {
    const { user, runtime, frame, status } = await renderItem(
      IDS.multipleChoice,
    );
    await user.click(within(frame).getByRole("checkbox", { name: MULTI[0] }));
    runtime.submitItem.mockResolvedValueOnce(multiWrong);
    await user.click(
      within(frame).getByRole("button", { name: "Check answer" }),
    );
    await within(status).findByText("Not correct.");

    await user.click(within(frame).getByRole("button", { name: "Try again" }));
    for (const box of within(frame).getAllByRole("checkbox")) {
      expect(box).not.toBeChecked();
      expect(box).toBeEnabled();
    }
    expect(status).toBeEmptyDOMElement();
    expect(within(frame).queryByText("Correct answer")).not.toBeInTheDocument();
    expect(
      within(frame).getByRole("button", { name: "Check answer" }),
    ).toBeDisabled();
  });

  test("has no axe violations before and after the submission", async () => {
    const { user, runtime, frame, status, container } = await renderItem(
      IDS.multipleChoice,
    );
    await expectNoAxeViolations(container);
    await user.click(within(frame).getByRole("checkbox", { name: MULTI[0] }));
    await user.click(within(frame).getByRole("checkbox", { name: MULTI[2] }));
    runtime.submitItem.mockResolvedValueOnce(multiWrong);
    await user.click(
      within(frame).getByRole("button", { name: "Check answer" }),
    );
    await within(status).findByText("Not correct.");
    await expectNoAxeViolations(container);
  });
});

const TASK_CLEAR = "Write a notice to my team.";
const FORMAT_SHORT = "Three sentences.";
const FORMAT_OPEN = "Any length.";

const slotFeedback: ItemFeedback = {
  item_id: IDS.slotBuilder,
  correct: false,
  option_feedback: [
    {
      key: "task",
      choice: "task-clear",
      correct: true,
      feedback: "The task names the reader.",
    },
    {
      key: "format",
      choice: "format-open",
      correct: false,
      feedback: "Without a length the answer grows.",
    },
  ],
  rules: [],
  reveals: [],
};

/** The lines of the live preview of a slot builder, in order. */
function previewLines(frame: HTMLElement): string[] {
  const preview = within(frame).getByText("Preview")
    .nextElementSibling as HTMLElement;
  return [...preview.querySelectorAll("p")].map(
    (line) => line.textContent ?? "",
  );
}

describe("SlotBuilderItem", () => {
  test("enables the check once every slot has an option and sends the slots", async () => {
    const { user, runtime, frame } = await renderItem(IDS.slotBuilder);
    const submit = within(frame).getByRole("button", { name: "Check answer" });
    const task = within(frame).getByRole("combobox", { name: "Task" });
    const format = within(frame).getByRole("combobox", { name: "Format" });
    expect(submit).toBeDisabled();

    await user.selectOptions(format, FORMAT_OPEN);
    expect(submit).toBeDisabled();
    await user.selectOptions(task, TASK_CLEAR);
    expect(submit).toBeEnabled();
    // Back to "Choose…" leaves a slot without an option.
    await user.selectOptions(task, "Choose…");
    expect(submit).toBeDisabled();
    await user.selectOptions(task, TASK_CLEAR);

    runtime.submitItem.mockResolvedValueOnce(slotFeedback);
    await user.click(submit);
    expect(runtime.submitItem).toHaveBeenCalledTimes(1);
    expect(runtime.submitItem).toHaveBeenCalledWith(IDS.slotBuilder, {
      slots: { task: "task-clear", format: "format-open" },
    });
  });

  test("the preview assembles the chosen lines in slot order", async () => {
    const { user, frame } = await renderItem(IDS.slotBuilder);
    expect(previewLines(frame)).toEqual([
      "Choose an option for each part to see the result.",
    ]);
    await user.selectOptions(
      within(frame).getByRole("combobox", { name: "Format" }),
      FORMAT_SHORT,
    );
    expect(previewLines(frame)).toEqual([FORMAT_SHORT]);
    await user.selectOptions(
      within(frame).getByRole("combobox", { name: "Task" }),
      TASK_CLEAR,
    );
    // The format was chosen first, the task slot comes first.
    expect(previewLines(frame)).toEqual([TASK_CLEAR, FORMAT_SHORT]);
    await user.selectOptions(
      within(frame).getByRole("combobox", { name: "Format" }),
      FORMAT_OPEN,
    );
    expect(previewLines(frame)).toEqual([TASK_CLEAR, FORMAT_OPEN]);
  });

  test("shows the feedback per slot and disables the selects after the submission", async () => {
    const { user, runtime, frame, status } = await renderItem(IDS.slotBuilder);
    await user.selectOptions(
      within(frame).getByRole("combobox", { name: "Task" }),
      TASK_CLEAR,
    );
    await user.selectOptions(
      within(frame).getByRole("combobox", { name: "Format" }),
      FORMAT_OPEN,
    );
    runtime.submitItem.mockResolvedValueOnce(slotFeedback);
    await user.click(
      within(frame).getByRole("button", { name: "Check answer" }),
    );

    expect(await within(status).findByText("Not correct.")).toBeInTheDocument();
    const task = rowOf(frame, "Task");
    expect(task.getByText("Fits")).toBeInTheDocument();
    expect(task.getByText("The task names the reader.")).toBeInTheDocument();
    const format = rowOf(frame, "Format");
    expect(format.getByText("Does not fit")).toBeInTheDocument();
    expect(
      format.getByText("Without a length the answer grows."),
    ).toBeInTheDocument();
    for (const select of within(frame).getAllByRole("combobox"))
      expect(select).toBeDisabled();
    expect(previewLines(frame)).toEqual([TASK_CLEAR, FORMAT_OPEN]);
  });

  test("Try again clears the slots and the preview", async () => {
    const { user, runtime, frame, status } = await renderItem(IDS.slotBuilder);
    await user.selectOptions(
      within(frame).getByRole("combobox", { name: "Task" }),
      TASK_CLEAR,
    );
    await user.selectOptions(
      within(frame).getByRole("combobox", { name: "Format" }),
      FORMAT_OPEN,
    );
    runtime.submitItem.mockResolvedValueOnce(slotFeedback);
    await user.click(
      within(frame).getByRole("button", { name: "Check answer" }),
    );
    await within(status).findByText("Not correct.");

    await user.click(within(frame).getByRole("button", { name: "Try again" }));
    for (const select of within(frame).getAllByRole("combobox")) {
      expect(select).toHaveValue("");
      expect(select).toBeEnabled();
    }
    expect(previewLines(frame)).toEqual([
      "Choose an option for each part to see the result.",
    ]);
    expect(within(frame).queryByText("Fits")).not.toBeInTheDocument();
    expect(status).toBeEmptyDOMElement();
    expect(
      within(frame).getByRole("button", { name: "Check answer" }),
    ).toBeDisabled();
  });

  test("has no axe violations before and after the submission", async () => {
    const { user, runtime, frame, status, container } = await renderItem(
      IDS.slotBuilder,
    );
    await expectNoAxeViolations(container);
    await user.selectOptions(
      within(frame).getByRole("combobox", { name: "Task" }),
      TASK_CLEAR,
    );
    await user.selectOptions(
      within(frame).getByRole("combobox", { name: "Format" }),
      FORMAT_OPEN,
    );
    runtime.submitItem.mockResolvedValueOnce(slotFeedback);
    await user.click(
      within(frame).getByRole("button", { name: "Check answer" }),
    );
    await within(status).findByText("Not correct.");
    await expectNoAxeViolations(container);
  });
});

const CASE_FIGURE = "The process saves 40 percent.";
const CASE_THANKS = "Thank you for reading.";
const NEEDS_SOURCE = "Check against a source";
const READY = "Ready to use";

const classificationFeedback: ItemFeedback = {
  item_id: IDS.classification,
  correct: false,
  option_feedback: [
    {
      key: "case-figure",
      choice: "needs-source",
      expected: "needs-source",
      correct: true,
      feedback: "A figure needs its source.",
    },
    {
      key: "case-thanks",
      choice: "needs-source",
      expected: "ready",
      correct: false,
      feedback: "A greeting states no fact.",
    },
  ],
  rules: [RULE_1],
  reveals: [],
};

describe("ClassificationItem", () => {
  test("enables the check once every case has a category and sends the cases", async () => {
    const { user, runtime, frame } = await renderItem(IDS.classification);
    const submit = within(frame).getByRole("button", { name: "Check answer" });
    const figure = within(frame).getByRole("combobox", { name: CASE_FIGURE });
    const thanks = within(frame).getByRole("combobox", { name: CASE_THANKS });
    expect(submit).toBeDisabled();

    await user.selectOptions(figure, NEEDS_SOURCE);
    expect(submit).toBeDisabled();
    await user.selectOptions(thanks, NEEDS_SOURCE);
    expect(submit).toBeEnabled();
    await user.selectOptions(figure, "Choose…");
    expect(submit).toBeDisabled();
    await user.selectOptions(figure, NEEDS_SOURCE);

    runtime.submitItem.mockResolvedValueOnce(classificationFeedback);
    await user.click(submit);
    expect(runtime.submitItem).toHaveBeenCalledTimes(1);
    expect(runtime.submitItem).toHaveBeenCalledWith(IDS.classification, {
      cases: { "case-figure": "needs-source", "case-thanks": "needs-source" },
    });
  });

  test("shows the feedback per case with the expected category and disables the selects", async () => {
    const { user, runtime, frame, status } = await renderItem(
      IDS.classification,
    );
    await user.selectOptions(
      within(frame).getByRole("combobox", { name: CASE_FIGURE }),
      NEEDS_SOURCE,
    );
    await user.selectOptions(
      within(frame).getByRole("combobox", { name: CASE_THANKS }),
      NEEDS_SOURCE,
    );
    runtime.submitItem.mockResolvedValueOnce(classificationFeedback);
    await user.click(
      within(frame).getByRole("button", { name: "Check answer" }),
    );

    expect(await within(status).findByText("Not correct.")).toBeInTheDocument();
    expect(
      within(status).getByRole("link", {
        name: "Rule 1: Generated text carries no check of its own.",
      }),
    ).toHaveAttribute("href", "#rule-1");
    const figure = rowOf(frame, CASE_FIGURE);
    expect(figure.getByText("Correct")).toBeInTheDocument();
    expect(figure.getByText("A figure needs its source.")).toBeInTheDocument();
    const thanks = rowOf(frame, CASE_THANKS);
    expect(
      thanks.getByText(fullText(`Expected: ${READY}`)),
    ).toBeInTheDocument();
    expect(thanks.getByText("A greeting states no fact.")).toBeInTheDocument();
    for (const select of within(frame).getAllByRole("combobox"))
      expect(select).toBeDisabled();
  });

  test("a wrong case without an expected category says only that it is not correct", async () => {
    const { user, runtime, frame, status } = await renderItem(
      IDS.classification,
    );
    await user.selectOptions(
      within(frame).getByRole("combobox", { name: CASE_FIGURE }),
      READY,
    );
    await user.selectOptions(
      within(frame).getByRole("combobox", { name: CASE_THANKS }),
      READY,
    );
    runtime.submitItem.mockResolvedValueOnce({
      ...classificationFeedback,
      option_feedback: [
        {
          key: "case-figure",
          choice: "ready",
          expected: null,
          correct: false,
          feedback: null,
        },
        {
          key: "case-thanks",
          choice: "ready",
          expected: "ready",
          correct: true,
          feedback: null,
        },
      ],
    });
    await user.click(
      within(frame).getByRole("button", { name: "Check answer" }),
    );
    await within(status).findByText("Not correct.");
    expect(
      rowOf(frame, CASE_FIGURE).getByText("Not correct"),
    ).toBeInTheDocument();
    expect(rowOf(frame, CASE_THANKS).getByText("Correct")).toBeInTheDocument();
  });

  test("Try again clears the categories", async () => {
    const { user, runtime, frame, status } = await renderItem(
      IDS.classification,
    );
    await user.selectOptions(
      within(frame).getByRole("combobox", { name: CASE_FIGURE }),
      NEEDS_SOURCE,
    );
    await user.selectOptions(
      within(frame).getByRole("combobox", { name: CASE_THANKS }),
      NEEDS_SOURCE,
    );
    runtime.submitItem.mockResolvedValueOnce(classificationFeedback);
    await user.click(
      within(frame).getByRole("button", { name: "Check answer" }),
    );
    await within(status).findByText("Not correct.");

    await user.click(within(frame).getByRole("button", { name: "Try again" }));
    for (const select of within(frame).getAllByRole("combobox")) {
      expect(select).toHaveValue("");
      expect(select).toBeEnabled();
    }
    expect(
      within(frame).queryByText(fullText(`Expected: ${READY}`)),
    ).not.toBeInTheDocument();
    expect(status).toBeEmptyDOMElement();
    expect(
      within(frame).getByRole("button", { name: "Check answer" }),
    ).toBeDisabled();
  });

  test("has no axe violations before and after the submission", async () => {
    const { user, runtime, frame, status, container } = await renderItem(
      IDS.classification,
    );
    await expectNoAxeViolations(container);
    await user.selectOptions(
      within(frame).getByRole("combobox", { name: CASE_FIGURE }),
      NEEDS_SOURCE,
    );
    await user.selectOptions(
      within(frame).getByRole("combobox", { name: CASE_THANKS }),
      NEEDS_SOURCE,
    );
    runtime.submitItem.mockResolvedValueOnce(classificationFeedback);
    await user.click(
      within(frame).getByRole("button", { name: "Check answer" }),
    );
    await within(status).findByText("Not correct.");
    await expectNoAxeViolations(container);
  });
});

// The accessible name joins the label and its "(required)" span; the name
// computation of jsdom drops the space between them, a browser keeps it.
const REQUIRED_CHECK = /^Every fact is checked\.\s*\(required\)$/;
const OPTIONAL_CHECK = "A colleague has read it.";

const releaseCorrect: ItemFeedback = {
  item_id: IDS.checklist,
  correct: true,
  option_feedback: [
    { key: "facts-checked", selected: true, required: true, correct: true },
    { key: "second-reader", selected: false, required: false, correct: true },
  ],
  rules: [],
  reveals: [],
};

/** The log line of a release at `time`, with the whitespace of the DOM text. */
const logLine = (initials: string, time: Date) =>
  `Released by ${initials} at ${new Intl.DateTimeFormat("en", {
    timeStyle: "short",
  }).format(time)}.`.replace(/\s+/g, " ");

describe("ChecklistDrillItem", () => {
  test("enables the release with every required check and 2 to 5 initials after trimming", async () => {
    const { user, frame } = await renderItem(IDS.checklist);
    const release = within(frame).getByRole("button", { name: "Release" });
    const required = within(frame).getByRole("checkbox", {
      name: REQUIRED_CHECK,
    });
    const optional = within(frame).getByRole("checkbox", {
      name: OPTIONAL_CHECK,
    });
    const initials = within(frame).getByRole("textbox", {
      name: "Your initials",
    });
    expect(initials).toHaveAccessibleDescription("2 to 5 characters.");
    expect(release).toBeDisabled();

    await user.type(initials, "AB");
    expect(release).toBeDisabled();
    await user.click(optional);
    expect(release).toBeDisabled();
    await user.click(required);
    expect(release).toBeEnabled();

    await user.clear(initials);
    await user.type(initials, " A ");
    expect(release).toBeDisabled();
    await user.clear(initials);
    await user.type(initials, "ABCDEF");
    expect(release).toBeDisabled();
    await user.clear(initials);
    await user.type(initials, "ABCDE");
    expect(release).toBeEnabled();
    await user.clear(initials);
    await user.type(initials, "  AB  ");
    expect(release).toBeEnabled();

    // The optional check is not needed.
    await user.click(optional);
    expect(release).toBeEnabled();
    await user.click(required);
    expect(release).toBeDisabled();
  });

  test("sends the checks and the initials", async () => {
    const { user, runtime, frame } = await renderItem(IDS.checklist);
    await user.click(
      within(frame).getByRole("checkbox", { name: REQUIRED_CHECK }),
    );
    await user.click(
      within(frame).getByRole("checkbox", { name: OPTIONAL_CHECK }),
    );
    await user.type(
      within(frame).getByRole("textbox", { name: "Your initials" }),
      "AB",
    );
    runtime.submitItem.mockResolvedValueOnce({
      ...releaseCorrect,
      option_feedback: [
        { key: "facts-checked", selected: true, required: true, correct: true },
        {
          key: "second-reader",
          selected: true,
          required: false,
          correct: true,
        },
      ],
    });
    await user.click(within(frame).getByRole("button", { name: "Release" }));
    expect(runtime.submitItem).toHaveBeenCalledTimes(1);
    expect(runtime.submitItem).toHaveBeenCalledWith(IDS.checklist, {
      checks: ["facts-checked", "second-reader"],
      initials: "AB",
    });
  });

  test("a correct release shows the log line with the trimmed initials and the time, and locks the form", async () => {
    const { user, runtime, frame, status } = await renderItem(IDS.checklist);
    await user.click(
      within(frame).getByRole("checkbox", { name: REQUIRED_CHECK }),
    );
    await user.type(
      within(frame).getByRole("textbox", { name: "Your initials" }),
      " AB ",
    );
    runtime.submitItem.mockResolvedValueOnce(releaseCorrect);

    const time = new Date(2026, 9, 11, 9, 30);
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(time);
    try {
      await user.click(within(frame).getByRole("button", { name: "Release" }));
      expect(await within(status).findByText("Correct.")).toBeInTheDocument();
    } finally {
      vi.useRealTimers();
    }

    const line = within(frame).getByText(logLine("AB", time));
    expect(line).toBeInTheDocument();
    // The log line sits below the form, outside the status region.
    expect(status).not.toContainElement(line);
    expect(
      within(frame).queryByText("This check is required."),
    ).not.toBeInTheDocument();
    for (const box of within(frame).getAllByRole("checkbox"))
      expect(box).toBeDisabled();
    expect(
      within(frame).getByRole("textbox", { name: "Your initials" }),
    ).toBeDisabled();
    expect(
      within(frame).queryByRole("button", { name: "Release" }),
    ).not.toBeInTheDocument();
  });

  test("a wrong release marks the missing required check and writes no log line", async () => {
    const { user, runtime, frame, status } = await renderItem(IDS.checklist);
    await user.click(
      within(frame).getByRole("checkbox", { name: REQUIRED_CHECK }),
    );
    await user.type(
      within(frame).getByRole("textbox", { name: "Your initials" }),
      "AB",
    );
    runtime.submitItem.mockResolvedValueOnce({
      ...releaseCorrect,
      correct: false,
      option_feedback: [
        {
          key: "facts-checked",
          selected: false,
          required: true,
          correct: false,
        },
        {
          key: "second-reader",
          selected: false,
          required: false,
          correct: true,
        },
      ],
    });
    await user.click(within(frame).getByRole("button", { name: "Release" }));

    expect(await within(status).findByText("Not correct.")).toBeInTheDocument();
    expect(
      rowOf(frame, "Every fact is checked.").getByText(
        "This check is required.",
      ),
    ).toBeInTheDocument();
    expect(
      rowOf(frame, OPTIONAL_CHECK).queryByText("This check is required."),
    ).not.toBeInTheDocument();
    expect(within(frame).queryByText(/^Released by/)).not.toBeInTheDocument();
  });

  test("Try again clears the checks and the initials and keeps the log", async () => {
    const { user, runtime, frame, status } = await renderItem(IDS.checklist);
    await user.click(
      within(frame).getByRole("checkbox", { name: REQUIRED_CHECK }),
    );
    await user.type(
      within(frame).getByRole("textbox", { name: "Your initials" }),
      "AB",
    );
    runtime.submitItem.mockResolvedValueOnce(releaseCorrect);
    await user.click(within(frame).getByRole("button", { name: "Release" }));
    await within(status).findByText("Correct.");

    await user.click(within(frame).getByRole("button", { name: "Try again" }));
    for (const box of within(frame).getAllByRole("checkbox")) {
      expect(box).not.toBeChecked();
      expect(box).toBeEnabled();
    }
    const initials = within(frame).getByRole("textbox", {
      name: "Your initials",
    });
    expect(initials).toHaveValue("");
    expect(initials).toBeEnabled();
    expect(status).toBeEmptyDOMElement();
    expect(
      within(frame).getByRole("button", { name: "Release" }),
    ).toBeDisabled();
    expect(within(frame).getAllByText(/^Released by AB at /)).toHaveLength(1);
  });

  test("has no axe violations before and after the release", async () => {
    const { user, runtime, frame, status, container } = await renderItem(
      IDS.checklist,
    );
    await expectNoAxeViolations(container);
    await user.click(
      within(frame).getByRole("checkbox", { name: REQUIRED_CHECK }),
    );
    await user.type(
      within(frame).getByRole("textbox", { name: "Your initials" }),
      "AB",
    );
    runtime.submitItem.mockResolvedValueOnce(releaseCorrect);
    await user.click(within(frame).getByRole("button", { name: "Release" }));
    await within(status).findByText("Correct.");
    await expectNoAxeViolations(container);
  });
});

const pollFeedback: ItemFeedback = {
  item_id: IDS.poll,
  correct: null,
  option_feedback: [],
  rules: [],
  reveals: [],
};

describe("PollItem", () => {
  test("enables sending once an option is chosen and sends that option", async () => {
    const { user, runtime, frame } = await renderItem(IDS.poll);
    const send = within(frame).getByRole("button", { name: "Send answer" });
    expect(send).toBeDisabled();
    await user.click(within(frame).getByRole("radio", { name: "Summaries" }));
    expect(
      within(frame).getByRole("radio", { name: "Summaries" }),
    ).toBeChecked();
    expect(send).toBeEnabled();

    runtime.submitItem.mockResolvedValueOnce(pollFeedback);
    await user.click(send);
    expect(runtime.submitItem).toHaveBeenCalledTimes(1);
    expect(runtime.submitItem).toHaveBeenCalledWith(IDS.poll, {
      options: ["option-2"],
    });
  });

  test("thanks for the answer, shows no correctness and locks the options", async () => {
    const { user, runtime, frame, status } = await renderItem(IDS.poll);
    await user.click(within(frame).getByRole("radio", { name: "Emails" }));
    runtime.submitItem.mockResolvedValueOnce(pollFeedback);
    await user.click(
      within(frame).getByRole("button", { name: "Send answer" }),
    );

    expect(
      await within(status).findByText("Thank you for your answer."),
    ).toBeInTheDocument();
    expect(within(frame).queryByText("Correct.")).not.toBeInTheDocument();
    expect(within(frame).queryByText("Not correct.")).not.toBeInTheDocument();
    expect(within(frame).queryByText("Correct answer")).not.toBeInTheDocument();
    expect(
      within(frame).queryByText("Your choice is not correct"),
    ).not.toBeInTheDocument();
    for (const radio of within(frame).getAllByRole("radio"))
      expect(radio).toHaveAttribute("aria-disabled", "true");
    expect(within(frame).getByRole("radio", { name: "Emails" })).toBeChecked();
  });

  test("shows no mark per option even when the feedback holds option entries", async () => {
    const { user, runtime, frame, status } = await renderItem(IDS.poll);
    await user.click(within(frame).getByRole("radio", { name: "Emails" }));
    runtime.submitItem.mockResolvedValueOnce({
      ...pollFeedback,
      option_feedback: [
        {
          key: "option-1",
          selected: true,
          correct: true,
          feedback: "Many start here.",
        },
        {
          key: "option-2",
          selected: false,
          correct: false,
          feedback: "Also common.",
        },
      ],
    });
    await user.click(
      within(frame).getByRole("button", { name: "Send answer" }),
    );
    await within(status).findByText("Thank you for your answer.");
    expect(within(frame).queryByText("Correct answer")).not.toBeInTheDocument();
    expect(
      within(frame).queryByText("Your choice is not correct"),
    ).not.toBeInTheDocument();
    expect(
      within(frame).queryByText("Many start here."),
    ).not.toBeInTheDocument();
  });

  test("has no axe violations before and after the answer", async () => {
    const { user, runtime, frame, status, container } = await renderItem(
      IDS.poll,
    );
    await expectNoAxeViolations(container);
    await user.click(within(frame).getByRole("radio", { name: "Emails" }));
    runtime.submitItem.mockResolvedValueOnce(pollFeedback);
    await user.click(
      within(frame).getByRole("button", { name: "Send answer" }),
    );
    await within(status).findByText("Thank you for your answer.");
    await expectNoAxeViolations(container);
  });
});

describe("PracticeItem", () => {
  test("passes the item and the feedback to onAnswered once", async () => {
    const { user, runtime, frame, status, item, onAnswered } = await renderItem(
      IDS.singleChoice,
    );
    await user.click(within(frame).getByRole("radio", { name: SINGLE_FIRST }));
    runtime.submitItem.mockResolvedValueOnce(singleCorrect);
    await user.click(
      within(frame).getByRole("button", { name: "Check answer" }),
    );
    await within(status).findByText("Correct.");
    expect(onAnswered).toHaveBeenCalledTimes(1);
    expect(onAnswered).toHaveBeenCalledWith(item, singleCorrect);
  });

  test("names the lessons that onAnswered returns in the status region", async () => {
    const lesson = program.modules[0].lessons[0];
    const onAnswered = vi.fn<OnAnswered>(() => [lesson]);
    const { user, runtime, frame, status } = await renderItem(
      IDS.singleChoice,
      onAnswered,
    );
    await user.click(within(frame).getByRole("radio", { name: SINGLE_SECOND }));
    runtime.submitItem.mockResolvedValueOnce(singleWrong);
    await user.click(
      within(frame).getByRole("button", { name: "Check answer" }),
    );

    const link = await within(status).findByRole("link", {
      name: "What a language model does",
    });
    expect(link).toHaveAttribute("href", `#lesson-${IDS.lesson1}`);
    expect(
      within(status).getByText("The explanation in this lesson is open now:"),
    ).toBeInTheDocument();

    await user.click(within(frame).getByRole("button", { name: "Try again" }));
    expect(status).toBeEmptyDOMElement();
  });

  test("a 429 shows the too-many-attempts text and keeps the answer", async () => {
    const { user, runtime, frame, status, onAnswered } = await renderItem(
      IDS.multipleChoice,
    );
    await user.click(within(frame).getByRole("checkbox", { name: MULTI[0] }));
    runtime.submitItem.mockRejectedValueOnce(
      Object.assign(new Error("x"), { status: 429, retryAfter: 120 }),
    );
    await user.click(
      within(frame).getByRole("button", { name: "Check answer" }),
    );

    expect(
      await within(status).findByText(
        "Too many attempts. Try again in 2 minutes.",
      ),
    ).toBeInTheDocument();
    expect(onAnswered).not.toHaveBeenCalled();
    const box = within(frame).getByRole("checkbox", { name: MULTI[0] });
    expect(box).toBeChecked();
    expect(box).toBeEnabled();
    expect(
      within(frame).getByRole("button", { name: "Check answer" }),
    ).toBeEnabled();
  });

  test("another failure shows the send error, and the next answer clears it", async () => {
    const { user, runtime, frame, status } = await renderItem(
      IDS.multipleChoice,
    );
    await user.click(within(frame).getByRole("checkbox", { name: MULTI[0] }));
    runtime.submitItem.mockRejectedValueOnce(new Error("offline"));
    await user.click(
      within(frame).getByRole("button", { name: "Check answer" }),
    );
    expect(
      await within(status).findByText(
        "The answer could not be sent. Please try again.",
      ),
    ).toBeInTheDocument();

    runtime.submitItem.mockResolvedValueOnce({ ...multiWrong, correct: true });
    await user.click(
      within(frame).getByRole("button", { name: "Check answer" }),
    );
    expect(await within(status).findByText("Correct.")).toBeInTheDocument();
    expect(
      within(status).queryByText(
        "The answer could not be sent. Please try again.",
      ),
    ).not.toBeInTheDocument();
  });
});
