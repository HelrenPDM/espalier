import { useTranslation } from "react-i18next";
import { Markdown } from "../Markdown";
import type { Block } from "../runtime";
import { BlockFrame } from "./BlockFrame";

export function ExampleBlock({ block }: { block: Block }) {
  const { t } = useTranslation();
  return (
    <BlockFrame
      block={block}
      label={t("blocks.example")}
      className="border-l-4 border-gray-300 pl-4 dark:border-gray-600"
    >
      <Markdown>{block.body}</Markdown>
    </BlockFrame>
  );
}
