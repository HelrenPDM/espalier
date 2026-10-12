import { useTranslation } from "react-i18next";
import { useFormatReport } from "../../api/reports";
import { CountCell } from "./cells";
import { ReportSection } from "./ReportSection";
import {
  largestCount,
  packLang,
  TABLE_CLASSES,
  type SectionProps,
} from "./reportFormat";

/** The format report: the "would use" votes per companion format. */
export function FormatSection({ slug, lang }: SectionProps) {
  const { t } = useTranslation();
  const query = useFormatReport(slug);

  return (
    <ReportSection
      title={t("reports.formats.title")}
      description={t("reports.formats.description")}
      query={query}
      isEmpty={(report) => report.formats.length === 0}
      empty={t("reports.formats.empty")}
    >
      {(report) => {
        const largest = largestCount(
          report.formats.map((format) => format.cell),
        );
        const textLang = packLang(lang, report);
        return (
          <>
            <thead>
              <tr>
                <th scope="col" className={TABLE_CLASSES.columnHeader}>
                  {t("reports.formats.format")}
                </th>
                <th scope="col" className={TABLE_CLASSES.columnHeader}>
                  {t("reports.formats.votes")}
                </th>
              </tr>
            </thead>
            <tbody>
              {report.formats.map((format) => (
                <tr key={format.id}>
                  <th scope="row" className={TABLE_CLASSES.rowHeader}>
                    <span lang={textLang}>{format.title}</span>
                  </th>
                  <CountCell
                    cell={format.cell}
                    largest={largest}
                    size={report.min_group_size}
                  />
                </tr>
              ))}
            </tbody>
          </>
        );
      }}
    </ReportSection>
  );
}
