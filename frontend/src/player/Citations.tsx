import { useTranslation } from "react-i18next";
import { FOCUS_RING } from "../app/formStyles";
import { formatDay, safeSourceUrl } from "./format";
import type { Citation } from "./runtime";

/** The title of a source, linked when it has a safe URL. */
export function SourceTitle({ citation }: { citation: Citation }) {
  const href = safeSourceUrl(citation.source.url);
  const title = <cite className="not-italic">{citation.source.title}</cite>;
  if (href === null) return title;
  return (
    <a
      href={href}
      rel="noopener noreferrer"
      className={`rounded-sm underline underline-offset-2 hover:text-gray-900 dark:hover:text-gray-100 ${FOCUS_RING}`}
    >
      {title}
    </a>
  );
}

/**
 * The citations of a block or a rule: title, publisher, edition date,
 * retrieval date and locator of each source.
 */
export function Citations({ citations }: { citations: Citation[] }) {
  const { t, i18n } = useTranslation();
  if (citations.length === 0) return null;
  return (
    <div className="mt-3 text-sm text-gray-700 dark:text-gray-300">
      <p className="font-medium">
        {t("citations.title", { count: citations.length })}
      </p>
      <ul className="mt-1 space-y-1">
        {citations.map((citation, index) => (
          <li key={`${citation.source.key}-${index}`}>
            <SourceTitle citation={citation} />
            {", "}
            {t("citations.details", {
              publisher: citation.source.publisher,
              edition: formatDay(citation.source.edition_date, i18n.language),
              retrieved: formatDay(citation.source.retrieved_on, i18n.language),
            })}
            {citation.locator &&
              ` ${t("citations.locator", { locator: citation.locator })}`}
          </li>
        ))}
      </ul>
    </div>
  );
}
