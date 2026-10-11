import { InformationCircleIcon } from "@heroicons/react/20/solid";
import { useTranslation } from "react-i18next";
import { Markdown } from "../Markdown";
import type { Block } from "../runtime";
import { BlockFrame } from "./BlockFrame";

export function CalloutBlock({ block }: { block: Block }) {
  const { t } = useTranslation();
  return (
    <BlockFrame
      block={block}
      label={
        <span className="inline-flex items-center gap-1">
          <InformationCircleIcon aria-hidden="true" className="size-5" />
          {t("blocks.callout")}
        </span>
      }
      className="rounded-md border border-accent-100 bg-accent-50 p-4 dark:border-gray-700 dark:bg-gray-900"
    >
      <Markdown>{block.body}</Markdown>
    </BlockFrame>
  );
}
