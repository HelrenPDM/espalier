import { Markdown } from "../Markdown";
import type { Block } from "../runtime";
import { BlockFrame } from "./BlockFrame";

export function TextBlock({ block }: { block: Block }) {
  return (
    <BlockFrame block={block}>
      <Markdown>{block.body}</Markdown>
    </BlockFrame>
  );
}
