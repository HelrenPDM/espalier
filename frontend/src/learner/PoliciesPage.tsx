import { useId, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import { formatDate } from "../app/format";
import { buttonClasses } from "../app/formStyles";
import { LoadingStatus } from "../app/LoadingStatus";
import {
  useAcknowledgePolicy,
  useApprovedTools,
  usePolicies,
  type CurrentPolicy,
} from "../api/policies";
import { formatDay } from "../player/format";
import { Markdown } from "../player/Markdown";

/**
 * The current version of one policy with "I have read this version". After
 * the acknowledgement the button gives way to the date of the
 * acknowledgement, and focus moves to that line.
 */
function PolicyVersion({ policy }: { policy: CurrentPolicy }) {
  const { t, i18n } = useTranslation();
  const headingId = useId();
  const stateRef = useRef<HTMLParagraphElement>(null);
  const acknowledge = useAcknowledgePolicy();
  const [failed, setFailed] = useState(false);

  const submit = async () => {
    setFailed(false);
    try {
      await acknowledge.mutateAsync(policy.id);
      requestAnimationFrame(() => stateRef.current?.focus());
    } catch {
      setFailed(true);
    }
  };

  return (
    <section
      aria-labelledby={headingId}
      data-policy-key={policy.key}
      className="rounded-lg border border-gray-200 p-4 dark:border-gray-700"
    >
      <h2 id={headingId} className="text-xl font-semibold tracking-tight">
        {policy.title}
      </h2>
      <p className="mt-1 text-sm text-gray-700 dark:text-gray-300">
        {t("policies.version", {
          number: policy.number,
          date: formatDay(policy.effective_from, i18n.language),
        })}
      </p>
      <Markdown lang={null} className="mt-4">
        {policy.body}
      </Markdown>
      <div className="mt-4">
        {policy.acknowledged_at === null ? (
          <button
            type="button"
            onClick={() => void submit()}
            disabled={acknowledge.isPending}
            aria-describedby={headingId}
            className={buttonClasses("primary")}
          >
            {acknowledge.isPending
              ? t("policies.acknowledging")
              : t("policies.acknowledge")}
          </button>
        ) : (
          <p
            ref={stateRef}
            tabIndex={-1}
            data-acknowledged="true"
            className="text-sm font-medium focus:outline-none"
          >
            {t("policies.acknowledged", {
              date: formatDate(policy.acknowledged_at, i18n.language),
            })}
          </p>
        )}
        {failed && (
          <p
            role="alert"
            className="mt-2 text-sm text-red-800 dark:text-red-300"
          >
            {t("policies.acknowledgeFailed")}
          </p>
        )}
      </div>
    </section>
  );
}

/**
 * The approved tool list with status, conditions and review date. The
 * table scrolls sideways at phone width inside a wrapper that takes the
 * keyboard focus, so the arrow keys scroll it (WCAG 2.1.1).
 */
function ApprovedTools() {
  const { t, i18n } = useTranslation();
  const tools = useApprovedTools();

  return (
    <section aria-labelledby="approved-tools" className="mt-10">
      <h2 id="approved-tools" className="text-xl font-semibold tracking-tight">
        {t("policies.tools.title")}
      </h2>
      {tools.isPending ? (
        <div className="mt-4">
          <LoadingStatus text={t("policies.tools.loading")} />
        </div>
      ) : tools.isError ? (
        <p role="alert" className="mt-4 text-gray-700 dark:text-gray-300">
          {t("policies.tools.loadFailed")}
        </p>
      ) : tools.data.length === 0 ? (
        <p className="mt-4 text-gray-700 dark:text-gray-300">
          {t("policies.tools.empty")}
        </p>
      ) : (
        <div
          tabIndex={0}
          role="group"
          aria-labelledby="approved-tools"
          className="mt-4 overflow-x-auto rounded-md focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent-500"
        >
          <table
            aria-labelledby="approved-tools"
            className="w-full border-collapse text-left text-sm"
          >
            <thead>
              <tr className="border-b border-gray-300 dark:border-gray-600">
                <th scope="col" className="py-2 pr-4 font-semibold">
                  {t("policies.tools.name")}
                </th>
                <th scope="col" className="py-2 pr-4 font-semibold">
                  {t("policies.tools.vendor")}
                </th>
                <th scope="col" className="py-2 pr-4 font-semibold">
                  {t("policies.tools.status")}
                </th>
                <th scope="col" className="py-2 pr-4 font-semibold">
                  {t("policies.tools.conditions")}
                </th>
                <th scope="col" className="py-2 font-semibold">
                  {t("policies.tools.reviewedOn")}
                </th>
              </tr>
            </thead>
            <tbody>
              {tools.data.map((tool) => (
                <tr
                  key={tool.id}
                  className="border-b border-gray-200 align-top dark:border-gray-700"
                >
                  <th scope="row" className="py-2 pr-4 font-medium">
                    {tool.name}
                  </th>
                  <td className="py-2 pr-4">{tool.vendor}</td>
                  <td className="py-2 pr-4" data-status={tool.status}>
                    {t(`policies.tools.statuses.${tool.status}`)}
                  </td>
                  <td className="py-2 pr-4">
                    {tool.conditions ?? t("policies.tools.noConditions")}
                  </td>
                  <td className="py-2 whitespace-nowrap">
                    {tool.reviewed_on === null
                      ? t("policies.tools.notReviewed")
                      : formatDay(tool.reviewed_on, i18n.language)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}

/**
 * `/policies` (task 0013, step 23): the current version of every policy of
 * the organization as Markdown with title, number and effective date, an
 * "I have read this version" button with the acknowledgement state per
 * version, and the approved tool list (README section 7, rule 8).
 */
export function PoliciesPage() {
  const { t } = useTranslation();
  const policies = usePolicies();

  return (
    <div className="max-w-3xl">
      <h1 className="text-2xl font-semibold tracking-tight">
        {t("policies.title")}
      </h1>
      <p className="mt-2 text-gray-700 dark:text-gray-300">
        {t("policies.intro")}
      </p>
      {policies.isPending ? (
        <div className="mt-6">
          <LoadingStatus text={t("policies.loading")} />
        </div>
      ) : policies.isError ? (
        <p role="alert" className="mt-6 text-gray-700 dark:text-gray-300">
          {t("policies.loadFailed")}
        </p>
      ) : policies.data.length === 0 ? (
        <p className="mt-6 text-gray-700 dark:text-gray-300">
          {t("policies.empty")}
        </p>
      ) : (
        <div className="mt-6 space-y-6">
          {policies.data.map((policy) => (
            <PolicyVersion key={policy.id} policy={policy} />
          ))}
        </div>
      )}
      <ApprovedTools />
    </div>
  );
}
