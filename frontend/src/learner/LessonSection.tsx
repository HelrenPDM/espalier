import { useCallback } from "react";
import { LessonBlock } from "../player/blocks/LessonBlock";
import { useContentLang } from "../player/contentLang";
import { PracticeItem } from "../player/items/PracticeItem";
import { startsOpen } from "../player/pathLogic";
import type {
  ItemFeedback,
  ItemView,
  Lesson,
  ModuleView,
} from "../player/runtime";
import { useCurrentPlayer } from "../player/usePlayer";

/**
 * A lesson of the module station: its blocks and its practice items. The
 * section carries the id `lesson-<lesson id>`, and its heading takes focus
 * from the lesson links of the objectives panel.
 */
export function LessonSection({
  lesson,
  module,
  items,
  revealCount,
  onAnswered,
}: {
  lesson: Lesson;
  module: ModuleView;
  items: ItemView[];
  /** Grows with each reveal of the lesson, so its explanations take their new start state. */
  revealCount: number;
  onAnswered: (item: ItemView, feedback: ItemFeedback) => Lesson[];
}) {
  const { state, update } = useCurrentPlayer();
  const lang = useContentLang();
  const headingId = `lesson-${lesson.id}-heading`;

  const toggle = useCallback(
    (blockId: string, open: boolean) =>
      update((current) => {
        const has = current.openedExplanations.includes(blockId);
        if (open === has) return current;
        return {
          ...current,
          openedExplanations: open
            ? [...current.openedExplanations, blockId]
            : current.openedExplanations.filter((id) => id !== blockId),
        };
      }),
    [update],
  );

  return (
    <section id={`lesson-${lesson.id}`} aria-labelledby={headingId}>
      <h2
        id={headingId}
        tabIndex={-1}
        lang={lang}
        className="rounded-md text-xl font-semibold tracking-tight focus:outline-2 focus:outline-offset-2 focus:outline-accent-500"
      >
        {lesson.title}
      </h2>
      <div className="mt-4 space-y-6">
        {lesson.blocks.map((block) => (
          <LessonBlock
            key={`${block.id}:${state.path}:${revealCount}`}
            block={block}
            defaultOpen={
              startsOpen(block, state.path, module) ||
              state.openedExplanations.includes(block.id)
            }
            onToggle={(open) => toggle(block.id, open)}
          />
        ))}
        {items.map((item) => (
          <PracticeItem
            key={item.id}
            item={item}
            moduleId={module.id}
            onAnswered={onAnswered}
          />
        ))}
      </div>
    </section>
  );
}
