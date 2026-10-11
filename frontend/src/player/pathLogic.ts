import type { Block, ItemFeedback, ModuleView, Path } from "./runtime";

/**
 * Whether an explanation starts open (README section 7, rule 2): it starts
 * collapsed when the current path is in its `collapsed_on` and the module
 * has `single_path: false`, and open otherwise. A block that the learner
 * opened (`openedExplanations`) starts open as well; the caller adds that.
 */
export function startsOpen(
  block: Pick<Block, "collapsed_on">,
  path: Path,
  module: Pick<ModuleView, "single_path">,
): boolean {
  return module.single_path || !block.collapsed_on.includes(path);
}

/**
 * The lessons whose explanations open after an answer (README section 7,
 * rule 3): the `reveals` of a wrong answer on the short path in a module
 * with `single_path: false`, and none otherwise.
 */
export function revealTargets(
  feedback: Pick<ItemFeedback, "correct" | "reveals">,
  path: Path,
  module: Pick<ModuleView, "single_path">,
): string[] {
  if (feedback.correct !== false || path !== "short" || module.single_path)
    return [];
  return [...feedback.reveals];
}
