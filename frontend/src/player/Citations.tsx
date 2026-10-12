import { useTranslation } from "react-i18next";
import { FOCUS_RING } from "../app/formStyles";
import { useExternalLinkTarget } from "./externalLinks";
import { formatDay, safeSourceUrl } from "./format";
import type { Citation } from "./runtime";

/**
 * The title of a source, linked when it has a safe URL. The link opens in
 * the target of `ExternalLinkTargetContext`.
 */
export function SourceTitle({ citation }: { citation: Citation }) {
  const target = useExternalLinkTarget();
  const href = safeSourceUrl(citation.source.url);
  const title = <cite className="not-italic">{citation.source.title}</cite>;
  if (href === null) return title;
  return (
    <a
      href={href}
      target={target}
      rel="noopener noreferrer"
      className={`rounded-sm underline underline-offset-2 hover:text-gray-900 dark:hover:text-gray-100 ${FOCUS_RING}`}
    >
      {title}
    </a>
  );
}

/** One citation: title, publisher, edition date, retrieval date and locator. */
export function CitationText({ citation }: { citation: Citation }) {
  const { t, i18n } = useTranslation();
  return (
    <>
      <SourceTitle citation={citation} />
      {", "}
      {t("citations.details", {
        publisher: citation.source.publisher,
        edition: formatDay(citation.source.edition_date, i18n.language),
        retrieved: formatDay(citation.source.retrieved_on, i18n.language),
      })}
      {citation.locator &&
        ` ${t("citations.locator", { locator: citation.locator })}`}
    </>
  );
}

/** The citations of a block or a rule, each as `CitationText`. */
export function Citations({ citations }: { citations: Citation[] }) {
  const { t } = useTranslation();
  if (citations.length === 0) return null;
  return (
    <div className="mt-3 text-sm text-gray-700 dark:text-gray-300">
      <p className="font-medium">
        {t("citations.title", { count: citations.length })}
      </p>
      <ul className="mt-1 space-y-1">
        {citations.map((citation, index) => (
          <li key={`${citation.source.key}-${index}`}>
            <CitationText citation={citation} />
          </li>
        ))}
      </ul>
    </div>
  );
}
