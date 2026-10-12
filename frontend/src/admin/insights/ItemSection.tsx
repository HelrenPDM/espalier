import { useTranslation } from "react-i18next";
import { useItemReport } from "../../api/reports";
import { MonthHeaders, ShareCell } from "./cells";
import { ReportSection } from "./ReportSection";
import { packLang, TABLE_CLASSES, type SectionProps } from "./reportFormat";

/**
 * The item report: one row per practice item with statistics, by module,
 * with the share correct and the number of attempts per month. The stem
 * renders as text, as in the item frame of the player.
 */
export function ItemSection({ slug, lang }: SectionProps) {
  const { t } = useTranslation();
  const query = useItemReport(slug);

  return (
    <ReportSection
      title={t("reports.items.title")}
      description={t("reports.items.description")}
      query={query}
      isEmpty={(report) => report.rows.length === 0}
      empty={t("reports.items.empty")}
    >
      {(report) => (
        <>
          <thead>
            <tr>
              <th scope="col" className={TABLE_CLASSES.columnHeader}>
                {t("reports.items.module")}
              </th>
              <th scope="col" className={TABLE_CLASSES.columnHeader}>
                {t("reports.items.item")}
              </th>
              <MonthHeaders months={report.months} />
            </tr>
          </thead>
          <tbody>
            {report.rows.map((row) => (
              <tr key={row.item_id}>
                <td className={`${TABLE_CLASSES.cell} tabular-nums`}>
                  {row.module_number}
                </td>
                <th
                  scope="row"
                  className={`${TABLE_CLASSES.rowHeader} min-w-60`}
                >
                  <span lang={packLang(lang, report)}>{row.stem}</span>{" "}
                  <span className="block font-mono text-xs font-normal text-gray-600 dark:text-gray-400">
                    {row.key}
                  </span>
                </th>
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
