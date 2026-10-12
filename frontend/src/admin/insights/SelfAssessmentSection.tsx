import { useTranslation } from "react-i18next";
import { useSelfAssessmentReport } from "../../api/reports";
import { CountCell, MonthHeaders, OrgUnit } from "./cells";
import { ReportSection } from "./ReportSection";
import {
  largestCount,
  packLang,
  TABLE_CLASSES,
  type SectionProps,
} from "./reportFormat";

/**
 * The self-assessment report: once any answer exists, one row per live
 * segment, and per org unit when the report breaks down by org unit, with
 * the number of answers per month. An archived segment, and a key that the
 * program no longer names, has a row only when one of its cells is shown;
 * such a key shows the key itself.
 */
export function SelfAssessmentSection({ slug, lang }: SectionProps) {
  const { t } = useTranslation();
  const query = useSelfAssessmentReport(slug);

  return (
    <ReportSection
      title={t("reports.selfAssessment.title")}
      description={t("reports.selfAssessment.description")}
      query={query}
      isEmpty={(report) => report.rows.length === 0}
      empty={t("reports.selfAssessment.empty")}
    >
      {(report) => {
        const largest = largestCount(report.rows.flatMap((row) => row.cells));
        const textLang = packLang(lang, report);
        return (
          <>
            <thead>
              <tr>
                <th scope="col" className={TABLE_CLASSES.columnHeader}>
                  {t("reports.selfAssessment.segment")}
                </th>
                {report.by_org_unit && (
                  <th scope="col" className={TABLE_CLASSES.columnHeader}>
                    {t("reports.orgUnit")}
                  </th>
                )}
                <MonthHeaders months={report.months} />
              </tr>
            </thead>
            <tbody>
              {report.rows.map((row) => (
                <tr key={JSON.stringify([row.segment_key, row.org_unit])}>
                  <th scope="row" className={TABLE_CLASSES.rowHeader}>
                    {row.label === null ? (
                      <span className="font-mono">{row.segment_key}</span>
                    ) : (
                      <span lang={textLang}>{row.label}</span>
                    )}
                  </th>
                  {report.by_org_unit && (
                    <th scope="row" className={TABLE_CLASSES.rowHeader}>
                      <OrgUnit value={row.org_unit} />
                    </th>
                  )}
                  {row.cells.map((cell, index) => (
                    <CountCell
                      key={report.months[index] ?? index}
                      cell={cell}
                      largest={largest}
                      size={report.min_group_size}
                    />
                  ))}
                </tr>
              ))}
            </tbody>
          </>
        );
      }}
    </ReportSection>
  );
}
