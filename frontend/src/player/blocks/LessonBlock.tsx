import type { Block } from "../runtime";
import { CalloutBlock } from "./CalloutBlock";
import { CaseComparisonBlock } from "./CaseComparisonBlock";
import { ExampleBlock } from "./ExampleBlock";
import { ExplanationBlock } from "./ExplanationBlock";
import { PlaceholderBlock } from "./PlaceholderBlock";
import { QuoteBlock } from "./QuoteBlock";
import { TextBlock } from "./TextBlock";

/** Renders a block by its kind. */
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
  }
}
