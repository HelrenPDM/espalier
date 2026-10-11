import { useTranslation } from "react-i18next";
import { Markdown } from "../Markdown";
import { SourceTitle } from "../Citations";
import { ProvenanceBadge } from "../ProvenanceBadge";
import type { Block } from "../runtime";

/** A verbatim quote with a citation line per source. */
export function QuoteBlock({ block }: { block: Block }) {
  const { t } = useTranslation();
  return (
    <figure data-block-kind={block.kind}>
      <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
        <p className="text-sm font-semibold text-gray-800 dark:text-gray-200">
          {t("blocks.quote")}
        </p>
        <ProvenanceBadge provenance={block.provenance} />
      </div>
      <blockquote className="border-l-4 border-gray-400 pl-4 dark:border-gray-500">
        <Markdown className="italic">{block.body}</Markdown>
      </blockquote>
      {block.citations.map((citation, index) => (
        <figcaption
          key={`${citation.source.key}-${index}`}
          className="mt-2 pl-5 text-sm text-gray-700 dark:text-gray-300"
        >
          <SourceTitle citation={citation} />
          {", "}
          {citation.source.publisher}
          {citation.locator &&
            ` ${t("citations.locator", { locator: citation.locator })}`}
        </figcaption>
      ))}
    </figure>
  );
}
