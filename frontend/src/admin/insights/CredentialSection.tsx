import { useTranslation } from "react-i18next";
import { useCredentialReport, type CredentialReport } from "../../api/reports";
import { CountCell } from "./cells";
import { ReportSection } from "./ReportSection";
import {
  largestCount,
  packLang,
  TABLE_CLASSES,
  type SectionProps,
} from "./reportFormat";

type Status =
  CredentialReport["qualifications"][number]["statuses"][number]["status"];

/** The statuses as columns, in the order of the report. */
const STATUSES: readonly Status[] = [
  "active",
  "refresh_due",
  "expired",
  "revoked",
];

/**
 * The credential report: one row per qualification with the number of
 * credentials per status. An archived qualification appears only with at
 * least one shown cell, and its row says that it is archived.
 */
export function CredentialSection({ slug, lang }: SectionProps) {
  const { t } = useTranslation();
  const query = useCredentialReport(slug);

  return (
    <ReportSection
      title={t("reports.credentials.title")}
      description={t("reports.credentials.description")}
      query={query}
      isEmpty={(report) => report.qualifications.length === 0}
      empty={t("reports.credentials.empty")}
    >
      {(report) => {
        const largest = largestCount(
          report.qualifications.flatMap((qualification) =>
            qualification.statuses.map((entry) => entry.cell),
          ),
        );
        const textLang = packLang(lang, report);
        return (
          <>
            <thead>
              <tr>
                <th scope="col" className={TABLE_CLASSES.columnHeader}>
                  {t("reports.credentials.qualification")}
                </th>
                {STATUSES.map((status) => (
                  <th
                    key={status}
                    scope="col"
                    className={TABLE_CLASSES.columnHeader}
                  >
                    {t(`credentials.status.${status}`)}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {report.qualifications.map((qualification) => (
                <tr
                  key={JSON.stringify([
                    qualification.code,
                    qualification.archived,
                  ])}
                >
                  <th scope="row" className={TABLE_CLASSES.rowHeader}>
                    <span lang={textLang}>{qualification.title}</span>{" "}
                    <span className="block font-mono text-xs font-normal text-gray-600 dark:text-gray-400">
                      {qualification.code}
                    </span>{" "}
                    {qualification.archived && (
                      <span className="mt-1 inline-flex items-center rounded-full border border-gray-300 bg-gray-50 px-2 py-0.5 text-xs font-medium text-gray-800 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-200">
                        {t("reports.credentials.archived")}
                      </span>
                    )}
                  </th>
                  {STATUSES.map((status) => {
                    const entry = qualification.statuses.find(
                      (candidate) => candidate.status === status,
                    );
                    return (
                      <CountCell
                        key={status}
                        cell={entry?.cell ?? { suppressed: true }}
                        largest={largest}
                        size={report.min_group_size}
                      />
                    );
                  })}
                </tr>
              ))}
            </tbody>
          </>
        );
      }}
    </ReportSection>
  );
}
