import { useTranslation } from "react-i18next";
import { Markdown } from "../Markdown";
import type { Block } from "../runtime";
import { BlockFrame } from "./BlockFrame";

/**
 * Two cases side by side on wide screens and stacked on narrow ones; each
 * case starts at a paragraph of bold text (`remarkCaseColumns`).
 */
export function CaseComparisonBlock({ block }: { block: Block }) {
  const { t } = useTranslation();
  return (
    <BlockFrame block={block} label={t("blocks.caseComparison")}>
      <Markdown caseColumns>{block.body}</Markdown>
    </BlockFrame>
  );
}
