import { useTranslation } from "react-i18next";
import { useCompetenceReport } from "../../api/reports";
import { areaKey, depthKey } from "../../player/objectives/labels";
import { MonthHeaders, OrgUnit, ShareCell } from "./cells";
import { ReportSection } from "./ReportSection";
import { TABLE_CLASSES, type SectionProps } from "./reportFormat";

/**
 * The competence report (task 0014, step 9): one row per entry of `rows`,
 * labelled with its competence area and its depth and, when the report
 * breaks down by org unit, with its org unit, and the share correct and the
 * number of attempts per month. The labels are those of the objectives
 * panel of the player.
 */
export function CompetenceSection({ slug }: SectionProps) {
  const { t } = useTranslation();
  const query = useCompetenceReport(slug);

  return (
    <ReportSection
      title={t("reports.competence.title")}
      description={t("reports.competence.description")}
      query={query}
      isEmpty={(report) => report.rows.length === 0}
      empty={t("reports.competence.empty")}
    >
      {(report) => (
        <>
          <thead>
            <tr>
              <th scope="col" className={TABLE_CLASSES.columnHeader}>
                {t("reports.competence.area")}
              </th>
              <th scope="col" className={TABLE_CLASSES.columnHeader}>
                {t("reports.competence.depth")}
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
              <tr key={JSON.stringify([row.area, row.depth, row.org_unit])}>
                <th scope="row" className={TABLE_CLASSES.rowHeader}>
                  {t(areaKey(row.area))}
                </th>
                <th scope="row" className={TABLE_CLASSES.rowHeader}>
                  {t(depthKey(row.depth))}
                </th>
                {report.by_org_unit && (
                  <th scope="row" className={TABLE_CLASSES.rowHeader}>
                    <OrgUnit value={row.org_unit} />
                  </th>
                )}
                {row.cells.map((cell, index) => (
                  <ShareCell
                    key={report.months[index] ?? index}
                    cell={cell}
                    size={report.min_group_size}
                  />
                ))}
              </tr>
            ))}
          </tbody>
        </>
      )}
    </ReportSection>
  );
}
