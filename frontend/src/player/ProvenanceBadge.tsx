import { useTranslation } from "react-i18next";
import type { Provenance } from "./runtime";

/**
 * The provenance of a block or an item as a visible badge (README section
 * 2, principle 4): five distinct labels in one neutral style. A
 * `placeholder` badge also names the placeholder key.
 */
export function ProvenanceBadge({
  provenance,
  placeholderKey = null,
}: {
  provenance: Provenance;
  placeholderKey?: string | null;
}) {
  const { t } = useTranslation();
  return (
    <span className="inline-flex shrink-0 items-center rounded-full border border-gray-300 bg-gray-50 px-2 py-0.5 text-xs font-medium text-gray-700 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-200">
      <span className="sr-only">{t("provenance.label")} </span>
      {provenance === "placeholder" && placeholderKey
        ? t("provenance.placeholderWithKey", { key: placeholderKey })
        : t(`provenance.${provenance}`)}
    </span>
  );
}
