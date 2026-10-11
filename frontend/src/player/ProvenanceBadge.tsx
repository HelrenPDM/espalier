import { useTranslation } from "react-i18next";
import type { Provenance } from "./runtime";

/**
 * The provenance of a block or an item as a visible badge (README section
 * 2, principle 4): five distinct labels in one neutral style. A
 * `placeholder` badge also names the placeholder key. A placeholder block
 * that renders a published policy of the organization passes `policyKey`,
 * and the badge then names that policy as the source of the text (README
 * section 7, rule 8).
 */
export function ProvenanceBadge({
  provenance,
  placeholderKey = null,
  policyKey = null,
}: {
  provenance: Provenance;
  placeholderKey?: string | null;
  policyKey?: string | null;
}) {
  const { t } = useTranslation();
  return (
    <span className="inline-flex shrink-0 items-center rounded-full border border-gray-300 bg-gray-50 px-2 py-0.5 text-xs font-medium text-gray-700 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-200">
      <span className="sr-only">{t("provenance.label")} </span>
      {policyKey !== null
        ? t("provenance.policy", { key: policyKey })
        : provenance === "placeholder" && placeholderKey
          ? t("provenance.placeholderWithKey", { key: placeholderKey })
          : t(`provenance.${provenance}`)}
    </span>
  );
}
