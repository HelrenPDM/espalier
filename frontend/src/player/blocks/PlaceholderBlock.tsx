import { useTranslation } from "react-i18next";
import { Markdown } from "../Markdown";
import type { Block } from "../runtime";
import { BlockFrame } from "./BlockFrame";

/**
 * A place for a policy of the organization (README section 7, rule 8). It
 * shows its own body with the `placeholder` badge and the placeholder key;
 * 0013 renders the current policy version here once one exists.
 */
export function PlaceholderBlock({ block }: { block: Block }) {
  const { t } = useTranslation();
  return (
    <BlockFrame
      block={{ ...block, provenance: "placeholder" }}
      label={t("blocks.placeholder")}
      className="rounded-md border border-dashed border-gray-400 p-4 dark:border-gray-500"
    >
      <Markdown>{block.body}</Markdown>
    </BlockFrame>
  );
}
