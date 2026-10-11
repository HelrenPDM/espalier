import { describe, expect, test } from "vitest";
import { IDS, module1, module2 } from "../test/player";
import { revealTargets, startsOpen } from "./pathLogic";
import type { Block, ModuleView } from "./runtime";

/** The explanation of module 1 with `collapsed_on: ["short"]`. */
function collapsibleExplanation(): Block {
  const block = module1()
    .lessons.flatMap((lesson) => lesson.blocks)
    .find((entry) => entry.id === IDS.explanationShort);
  if (block === undefined) throw new Error("fixture lacks the explanation");
  return block;
}

const twoPaths: Pick<ModuleView, "single_path"> = { single_path: false };
const singlePath: Pick<ModuleView, "single_path"> = { single_path: true };

const wrong = { correct: false, reveals: [IDS.lesson1, IDS.lesson2] };

describe("startsOpen", () => {
  test("an explanation collapsed on the short path starts closed there and open on the full path", () => {
    const block = collapsibleExplanation();
    expect(block.collapsed_on).toEqual(["short"]);
    expect(module1().single_path).toBe(false);

    expect(startsOpen(block, "short", module1())).toBe(false);
    expect(startsOpen(block, "full", module1())).toBe(true);
  });

  test("an explanation without collapsed_on starts open on both paths", () => {
    const block = { collapsed_on: [] };

    expect(startsOpen(block, "short", twoPaths)).toBe(true);
    expect(startsOpen(block, "full", twoPaths)).toBe(true);
  });

  test("a module with single_path: true ignores the path", () => {
    const block = collapsibleExplanation();
    expect(module2().single_path).toBe(true);

    expect(startsOpen(block, "short", module2())).toBe(true);
    expect(startsOpen(block, "full", module2())).toBe(true);
    expect(
      startsOpen({ collapsed_on: ["short", "full"] }, "full", singlePath),
    ).toBe(true);
  });
});

describe("revealTargets", () => {
  test("a wrong answer on the short path returns the lessons of reveals", () => {
    expect(revealTargets(wrong, "short", module1())).toEqual([
      IDS.lesson1,
      IDS.lesson2,
    ]);
  });

  test("the result is a copy of reveals", () => {
    const feedback = { correct: false, reveals: [IDS.lesson1] };
    const targets = revealTargets(feedback, "short", twoPaths);

    expect(targets).not.toBe(feedback.reveals);
    targets.push(IDS.lesson3);
    expect(feedback.reveals).toEqual([IDS.lesson1]);
  });

  test("a wrong answer on the full path returns no lesson", () => {
    expect(revealTargets(wrong, "full", module1())).toEqual([]);
  });

  test("a correct answer returns no lesson on either path", () => {
    const correct = { correct: true, reveals: [IDS.lesson1] };

    expect(revealTargets(correct, "short", twoPaths)).toEqual([]);
    expect(revealTargets(correct, "full", twoPaths)).toEqual([]);
  });

  test("a poll answer (correct: null) returns no lesson", () => {
    const poll = { correct: null, reveals: [IDS.lesson1] };

    expect(revealTargets(poll, "short", twoPaths)).toEqual([]);
    expect(revealTargets(poll, "full", twoPaths)).toEqual([]);
  });

  test("a module with single_path: true ignores the path", () => {
    expect(revealTargets(wrong, "short", module2())).toEqual([]);
    expect(revealTargets(wrong, "full", module2())).toEqual([]);
    expect(revealTargets(wrong, "short", singlePath)).toEqual([]);
  });
});
