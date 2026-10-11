import { useId } from "react";
import { useTranslation } from "react-i18next";
import { Citations } from "../player/Citations";
import type { Rule } from "../player/runtime";

/**
 * "The rules of this module": number, statement and action of each rule,
 * with the anchor `rule-<number>` that the feedback of the items links to.
 */
export function RulesRecap({ rules }: { rules: Rule[] }) {
  const { t } = useTranslation();
  const headingId = useId();
  if (rules.length === 0) return null;
  return (
    <section
      aria-labelledby={headingId}
      className="rounded-lg border border-gray-200 p-4 dark:border-gray-700"
    >
      <h2 id={headingId} className="text-xl font-semibold tracking-tight">
        {t("rules.title")}
      </h2>
      <ol className="mt-3 space-y-4">
        {rules.map((rule) => (
          <li
            key={rule.id}
            id={`rule-${rule.number}`}
            tabIndex={-1}
            className="rounded-md focus:outline-2 focus:outline-offset-2 focus:outline-accent-500"
          >
            <p className="font-semibold">
              {t("rules.number", { number: rule.number })}
            </p>
            <p>{rule.statement}</p>
            <p className="mt-1 text-gray-700 dark:text-gray-300">
              <span className="font-medium">{t("rules.action")}</span>{" "}
              {rule.action}
            </p>
            <Citations citations={rule.citations} />
          </li>
        ))}
      </ol>
    </section>
  );
}
