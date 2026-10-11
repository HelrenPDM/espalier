import { fireEvent, screen, within } from "@testing-library/react";
import { describe, expect, test } from "vitest";
import { ExamSection } from "../../learner/ExamSection";
import { expectNoAxeViolations } from "../../test/axe";
import { id, IDS, item, programFixture, renderPlayer } from "../../test/player";
import { PracticeItem } from "../items/PracticeItem";
import type { ItemView } from "../runtime";
import { ObjectiveChips } from "./ObjectiveChips";
import { ObjectivesPanel } from "./ObjectivesPanel";

const program = programFixture();
const [module1, module2] = program.modules;
const CHIPS = { name: "Objectives of this item" };

const STATEMENT_EVIDENCED = "Learners can explain how a model continues text.";
const STATEMENT_METHOD = "Learners can name the checks of a statement.";
const STATEMENT_PROMPT = "Learners can build a prompt from four parts.";

/** A practice item of module 1 with `objectiveKeys`. */
const keyedItem = (objectiveKeys: string[]): ItemView =>
  item({
    id: id(38),
    key: "m1-keyed",
    kind: "single_choice",
    stem: "Which check comes first?",
    lesson_id: IDS.lesson1,
    objective_keys: objectiveKeys,
    options: [
      { key: "option-1", label: "The figures." },
      { key: "option-2", label: "The layout." },
    ],
  });

/**
 * Renders the chips of `objectiveKeys` for the station of `moduleId` and
 * waits for the player. The heading marks the end of the load, also when
 * no chip list renders.
 */
async function renderChips(
  objectiveKeys: string[],
  moduleId: string = IDS.module1,
) {
  const view = renderPlayer(
    <>
      <h1>Chips</h1>
      <ObjectiveChips
        objectiveKeys={objectiveKeys}
        program={program}
        moduleId={moduleId}
      />
    </>,
  );
  await screen.findByRole("heading", { name: "Chips" });
  return view;
}

/** Renders `entry` as a practice item of module 1 and returns its group. */
async function renderPractice(entry: ItemView, moduleId: string = IDS.module1) {
  const view = renderPlayer(
    <PracticeItem item={entry} moduleId={moduleId} onAnswered={() => []} />,
  );
  const frame = await screen.findByRole("group", { name: entry.stem });
  return { ...view, frame };
}

describe("ObjectiveChips", () => {
  test("a chip shows the area and the depth and has the statement as its description", async () => {
    await renderChips(["m1-subject-evidenced"]);
    const list = screen.getByRole("list", CHIPS);
    const chip = within(list).getByRole("link", {
      name: "Subject competence, Know",
    });
    expect(chip).toHaveTextContent(/^Subject competence, Know$/);
    expect(chip).toHaveAccessibleDescription(STATEMENT_EVIDENCED);
    // 24 by 24 CSS pixels at least (WCAG 2.2, 2.5.8); jsdom has no layout.
    expect(chip).toHaveClass("min-h-6", "min-w-6");
  });

  test("a key without an objective renders no chip, the others keep their order", async () => {
    await renderChips([
      "m1-method-practice",
      "no-such-objective",
      "m2-method-judge",
    ]);
    const list = screen.getByRole("list", CHIPS);
    const chips = within(list).getAllByRole("listitem");
    expect(chips).toHaveLength(2);
    expect(chips.map((chip) => chip.textContent)).toEqual([
      expect.stringMatching(/^Method competence, Know/),
      expect.stringMatching(/^Method competence, Judge/),
    ]);
    for (const link of within(list).getAllByRole("link"))
      expect(link).toHaveClass("min-h-6", "min-w-6");
  });

  test("keys that all miss render no list", async () => {
    await renderChips(["no-such-objective", "another-missing-key"]);
    expect(screen.queryByRole("list", CHIPS)).not.toBeInTheDocument();
  });

  test("an empty list of keys renders no list", async () => {
    await renderChips([]);
    expect(screen.queryByRole("list", CHIPS)).not.toBeInTheDocument();
  });

  test("a chip of the current module moves focus to the objective in the panel", async () => {
    const entry = keyedItem(["m1-method-practice"]);
    // The panel of the same module renders above the item, as on the station.
    const { user, location } = renderPlayer(
      <>
        <ObjectivesPanel module={module1} />
        <PracticeItem
          item={entry}
          moduleId={IDS.module1}
          onAnswered={() => []}
        />
      </>,
    );
    const frame = await screen.findByRole("group", { name: entry.stem });

    const chip = within(frame).getByRole("link", {
      name: "Method competence, Know",
    });
    expect(chip).toHaveAttribute("href", "#objective-m1-method-practice");
    await user.click(chip);
    const target = document.getElementById("objective-m1-method-practice");
    expect(target).not.toBeNull();
    expect(target).toHaveFocus();
    expect(target).toHaveTextContent(STATEMENT_METHOD);
    // The click prevents the default, so the route stays.
    expect(location()).toBe("/programs/demo");
  });

  test("a chip of another module links to the station of that module", async () => {
    const { user, frame, location } = await renderPractice(
      keyedItem(["m2-subject-prompt"]),
    );
    const chip = within(frame).getByRole("link", {
      name: "Subject competence, Apply",
    });
    expect(chip).toHaveAccessibleDescription(STATEMENT_PROMPT);
    expect(chip).toHaveAttribute(
      "href",
      "/programs/demo/stations/3#objective-m2-subject-prompt",
    );
    await user.click(chip);
    expect(location()).toBe(
      "/programs/demo/stations/3#objective-m2-subject-prompt",
    );
  });

  test("a chip of module 1 on the station of module 2 links to the station of module 1", async () => {
    const { user, location } = await renderChips(
      ["m1-subject-evidenced"],
      IDS.module2,
    );
    const chip = within(screen.getByRole("list", CHIPS)).getByRole("link", {
      name: "Subject competence, Know",
    });
    await user.click(chip);
    expect(location()).toBe(
      "/programs/demo/stations/2#objective-m1-subject-evidenced",
    );
  });
});

describe("the tooltip of a chip", () => {
  test("appears on hover and closes when the pointer leaves", async () => {
    const { user } = await renderChips(["m1-subject-evidenced"]);
    const chip = screen.getByRole("link", { name: "Subject competence, Know" });
    expect(screen.queryByTestId("tooltip")).not.toBeInTheDocument();

    await user.hover(chip);
    const tooltip = screen.getByTestId("tooltip");
    expect(tooltip).toHaveTextContent(STATEMENT_EVIDENCED);
    // The description reaches assistive technology once, through the chip.
    expect(tooltip).toHaveAttribute("aria-hidden", "true");

    await user.unhover(chip);
    expect(screen.queryByTestId("tooltip")).not.toBeInTheDocument();
  });

  test("stays open while the pointer rests on it", async () => {
    const { user } = await renderChips(["m1-subject-evidenced"]);
    const chip = screen.getByRole("link", { name: "Subject competence, Know" });
    await user.hover(chip);
    const bubble = screen.getByTestId("tooltip");
    // React derives mouseenter and mouseleave from the `relatedTarget` of
    // mouseout and mouseover. user-event sends these events without one,
    // which reads as a move out of the window, so the move from the chip to
    // the bubble is dispatched as a browser sends it.
    fireEvent.mouseOut(chip, { relatedTarget: bubble });
    fireEvent.mouseOver(bubble, { relatedTarget: chip });
    expect(screen.getByTestId("tooltip")).toHaveTextContent(
      STATEMENT_EVIDENCED,
    );
    fireEvent.mouseOut(bubble, { relatedTarget: document.body });
    expect(screen.queryByTestId("tooltip")).not.toBeInTheDocument();
  });

  test("appears on focus and closes on blur", async () => {
    const { user } = await renderChips([
      "m1-subject-evidenced",
      "m1-method-practice",
    ]);
    const [first, second] = within(
      screen.getByRole("list", CHIPS),
    ).getAllByRole("link");
    await user.tab();
    expect(first).toHaveFocus();
    expect(screen.getByTestId("tooltip")).toHaveTextContent(
      STATEMENT_EVIDENCED,
    );

    await user.tab();
    expect(second).toHaveFocus();
    const tooltips = screen.getAllByTestId("tooltip");
    expect(tooltips).toHaveLength(1);
    expect(tooltips[0]).toHaveTextContent(STATEMENT_METHOD);
  });

  test("Escape closes it without moving focus", async () => {
    const { user } = await renderChips(["m1-subject-evidenced"]);
    const chip = screen.getByRole("link", { name: "Subject competence, Know" });
    await user.tab();
    expect(chip).toHaveFocus();
    expect(screen.getByTestId("tooltip")).toBeInTheDocument();

    await user.keyboard("{Escape}");
    expect(screen.queryByTestId("tooltip")).not.toBeInTheDocument();
    expect(chip).toHaveFocus();
  });

  test("Escape closes it under the pointer, and a new hover opens it again", async () => {
    const { user } = await renderChips(["m1-subject-evidenced"]);
    const chip = screen.getByRole("link", { name: "Subject competence, Know" });
    await user.hover(chip);
    expect(screen.getByTestId("tooltip")).toBeInTheDocument();
    await user.keyboard("{Escape}");
    expect(screen.queryByTestId("tooltip")).not.toBeInTheDocument();

    await user.unhover(chip);
    await user.hover(chip);
    expect(screen.getByTestId("tooltip")).toBeInTheDocument();
  });
});

describe("the item frame", () => {
  test("a practice item with objective keys shows the chip list below the stem", async () => {
    const practice = module1.practice_items.find(
      (entry) => entry.id === IDS.singleChoice,
    )!;
    const { frame } = await renderPractice(practice);
    const list = within(frame).getByRole("list", CHIPS);
    const chip = within(list).getByRole("link", {
      name: "Subject competence, Know",
    });
    expect(chip).toHaveAccessibleDescription(STATEMENT_EVIDENCED);
    expect(chip).toHaveAttribute("href", "#objective-m1-subject-evidenced");
    // The list follows the stem.
    const stem = within(frame).getByText(practice.stem);
    expect(
      stem.compareDocumentPosition(list) & Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
  });

  test("exam items with objective keys show the chip list", async () => {
    const exam = module1.exams[0];
    renderPlayer(<ExamSection exam={exam} module={module1} />);
    await screen.findByRole("heading", { name: exam.title });
    for (const examItem of exam.items) {
      const frame = screen.getByRole("group", { name: examItem.stem });
      const list = within(frame).getByRole("list", CHIPS);
      const chip = within(list).getByRole("link", {
        name: "Subject competence, Know",
      });
      expect(chip).toHaveAccessibleDescription(
        "Learners can explain why answers vary.",
      );
      expect(chip).toHaveAttribute("href", "#objective-m1-subject-exam");
    }
  });

  test("an item with empty objective keys shows no chip list", async () => {
    const plain = module2.practice_items.find(
      (entry) => entry.id === IDS.noObjectives,
    )!;
    expect(plain.objective_keys).toEqual([]);
    const { frame } = await renderPractice(plain, IDS.module2);
    expect(within(frame).queryByRole("list", CHIPS)).not.toBeInTheDocument();
  });

  test("an item whose keys all miss shows no chip list", async () => {
    const { frame } = await renderPractice(keyedItem(["no-such-objective"]));
    expect(within(frame).queryByRole("list", CHIPS)).not.toBeInTheDocument();
  });
});

describe("accessibility", () => {
  test("the chips have no axe violations, with the tooltip closed and open", async () => {
    const { user, frame, container } = await renderPractice(
      keyedItem(["m1-method-practice", "m2-subject-prompt"]),
    );
    await expectNoAxeViolations(container);
    await user.hover(
      within(frame).getByRole("link", { name: "Method competence, Know" }),
    );
    expect(screen.getByTestId("tooltip")).toBeInTheDocument();
    await expectNoAxeViolations(container);
  });
});
