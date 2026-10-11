import { useTranslation } from "react-i18next";
import { Markdown } from "../Markdown";
import { CitationText } from "../Citations";
import { ProvenanceBadge } from "../ProvenanceBadge";
import type { Block } from "../runtime";

/**
 * A verbatim quote. Its one caption holds the full citation of each source:
 * title, publisher, edition date, retrieval date and locator.
 */
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
      {block.citations.length > 0 && (
        <figcaption className="mt-2 pl-5 text-sm text-gray-700 dark:text-gray-300">
          {block.citations.map((citation, index) => (
            <span key={`${citation.source.key}-${index}`} className="block">
              <CitationText citation={citation} />
            </span>
          ))}
        </figcaption>
      )}
    </figure>
  );
}
