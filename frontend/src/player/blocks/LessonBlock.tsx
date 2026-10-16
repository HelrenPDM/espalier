import type { Block } from "../runtime";
import { CalloutBlock } from "./CalloutBlock";
import { CaseComparisonBlock } from "./CaseComparisonBlock";
import { ExampleBlock } from "./ExampleBlock";
import { ExplanationBlock } from "./ExplanationBlock";
import { FigureBlock } from "./FigureBlock";
import { PlaceholderBlock } from "./PlaceholderBlock";
import { QuoteBlock } from "./QuoteBlock";
import { TextBlock } from "./TextBlock";
import { VideoBlock } from "./VideoBlock";

/**
 * Renders a block by its kind. The switch ends with an exhaustiveness
 * check, so a kind of the API without a component fails `tsc`.
 */
export function LessonBlock({
  block,
  defaultOpen,
  onToggle,
}: {
  block: Block;
  /** The start state of an explanation. */
  defaultOpen: boolean;
  /** Called when an explanation opens or closes. */
  onToggle: (open: boolean) => void;
}) {
  switch (block.kind) {
    case "text":
      return <TextBlock block={block} />;
    case "explanation":
      return (
        <ExplanationBlock
          block={block}
          defaultOpen={defaultOpen}
          onToggle={onToggle}
        />
      );
    case "example":
      return <ExampleBlock block={block} />;
    case "case_comparison":
      return <CaseComparisonBlock block={block} />;
    case "quote":
      return <QuoteBlock block={block} />;
    case "callout":
      return <CalloutBlock block={block} />;
    case "placeholder":
      return <PlaceholderBlock block={block} />;
    case "figure":
      return <FigureBlock block={block} />;
    case "video":
      return <VideoBlock block={block} />;
    default: {
      const unknown: never = block.kind;
      void unknown;
      return null;
    }
  }
}
