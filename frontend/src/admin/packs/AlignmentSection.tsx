import { useId } from "react";
import { useTranslation } from "react-i18next";
import type { AlignmentMatrixRow } from "../../api/admin/packs";
import type { components } from "../../api/schema";
import { FOCUS_RING } from "../../app/formStyles";
import { areaKey, depthKey } from "../../player/objectives/labels";
import { AlignmentFindingList, type EntryOpener } from "./findings";

/**
 * The alignment of a pack: the shared schema `AdminPackAlignment` of the
 * pack view (0015) and of the check of a draft (0016a).
 */
type PackAlignment = components["schemas"]["AdminPackAlignment"];

const BORDER = "border border-gray-300 dark:border-gray-700";

const TABLE_CLASSES = {
  table: "min-w-full border-collapse text-left text-sm",
  caption: "px-3 py-2 text-left font-semibold text-gray-900 dark:text-gray-100",
  columnHeader: `${BORDER} bg-gray-50 px-3 py-2 align-bottom font-semibold text-gray-900 dark:bg-gray-800 dark:text-gray-100`,
  cell: `${BORDER} px-3 py-2 align-top text-gray-800 dark:text-gray-200`,
} as const;

/** A list of keys, or `-` for an empty list. */
function Keys({ values }: { values: readonly string[] }) {
  if (values.length === 0) return <>-</>;
  return (
    <span className="font-mono text-xs break-words">{values.join(", ")}</span>
  );
}

/** The rows of `matrix` per module, in the order of the matrix. */
function byModule(
  matrix: readonly AlignmentMatrixRow[],
): [number, AlignmentMatrixRow[]][] {
  const modules = new Map<number, AlignmentMatrixRow[]>();
  for (const row of matrix) {
    const rows = modules.get(row.module) ?? [];
    rows.push(row);
    modules.set(row.module, rows);
  }
  return [...modules.entries()];
}

function ModuleTable({
  module,
  mode,
  rows,
}: {
  module: number;
  mode: "strict" | "warn" | null;
  rows: AlignmentMatrixRow[];
}) {
  const { t } = useTranslation();
  const captionId = useId();
  const modeLabel =
    mode === null ? "-" : t(`admin.pack.alignment.modes.${mode}`);

  return (
    <div
      role="region"
      aria-labelledby={captionId}
      tabIndex={0}
      className={`overflow-x-auto rounded-lg border border-gray-200 dark:border-gray-700 ${FOCUS_RING}`}
    >
      <table className={TABLE_CLASSES.table}>
        <caption id={captionId} className={TABLE_CLASSES.caption}>
          {t("admin.pack.alignment.caption", { module, mode: modeLabel })}
        </caption>
        <thead>
          <tr>
            {(
              [
                "area",
                "depth",
                "objectives",
                "lessons",
                "evidence",
                "elsewhere",
              ] as const
            ).map((column) => (
              <th
                key={column}
                scope="col"
                className={TABLE_CLASSES.columnHeader}
              >
                {t(`admin.pack.alignment.${column}`)}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr key={`${row.area}-${row.depth}`}>
              <td className={TABLE_CLASSES.cell}>{t(areaKey(row.area))}</td>
              <td className={TABLE_CLASSES.cell}>{t(depthKey(row.depth))}</td>
              <td className={TABLE_CLASSES.cell}>
                <Keys values={row.objectives} />
              </td>
              <td className={TABLE_CLASSES.cell}>
                <Keys values={row.lessons} />
              </td>
              <td className={TABLE_CLASSES.cell}>
                <Keys values={row.evidence} />
              </td>
              <td className={TABLE_CLASSES.cell}>
                {row.elsewhere === null ? (
                  "-"
                ) : (
                  <span className="font-mono text-xs">{row.elsewhere}</span>
                )}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/**
 * The section "Alignment" of the pack page (task 0015, step 11): the
 * alignment matrix of the stored payload as one table per module, whose
 * caption names the module number and the alignment mode, and below it the
 * errors and the warnings of the alignment checks with file, line, check
 * number, key and message, each list with its count in its heading. An
 * import without a stored payload has no matrix; the section says so and
 * lists the findings alone. Area and depth carry the labels of the
 * objectives panel of the player (0012 step 11).
 *
 * The draft page of task 0016a renders the alignment of a check here. It
 * passes `onOpen`, with which the file and the line of a finding open the
 * file at that line, and `noMatrix`, the sentence for a check without a
 * matrix; the pack page passes neither.
 */
export function AlignmentSection({
  alignment,
  noMatrix,
  ...opener
}: EntryOpener & { alignment: PackAlignment; noMatrix?: string }) {
  const { t } = useTranslation();
  const headingId = useId();
  const errorsId = useId();
  const warningsId = useId();

  return (
    <section aria-labelledby={headingId} className="space-y-4">
      <h2 id={headingId} className="text-xl font-semibold tracking-tight">
        {t("admin.pack.alignment.title")}
      </h2>
      {alignment.matrix === null ? (
        <p className="text-gray-700 dark:text-gray-300">
          {noMatrix ?? t("admin.pack.alignment.noMatrix")}
        </p>
      ) : (
        <>
          <p className="text-sm text-gray-700 dark:text-gray-300">
            {t("admin.pack.alignment.description")}
          </p>
          {byModule(alignment.matrix).map(([module, rows]) => (
            <ModuleTable
              key={module}
              module={module}
              mode={alignment.mode}
              rows={rows}
            />
          ))}
        </>
      )}
      <section aria-labelledby={errorsId} className="space-y-2">
        <h3 id={errorsId} className="text-lg font-semibold tracking-tight">
          {t("admin.pack.alignment.errors", {
            count: alignment.errors.length,
          })}
        </h3>
        {alignment.errors.length === 0 ? (
          <p className="text-gray-700 dark:text-gray-300">
            {t("admin.pack.alignment.none")}
          </p>
        ) : (
          <AlignmentFindingList findings={alignment.errors} {...opener} />
        )}
      </section>
      <section aria-labelledby={warningsId} className="space-y-2">
        <h3 id={warningsId} className="text-lg font-semibold tracking-tight">
          {t("admin.pack.alignment.warnings", {
            count: alignment.warnings.length,
          })}
        </h3>
        {alignment.warnings.length === 0 ? (
          <p className="text-gray-700 dark:text-gray-300">
            {t("admin.pack.alignment.none")}
          </p>
        ) : (
          <AlignmentFindingList findings={alignment.warnings} {...opener} />
        )}
      </section>
    </section>
  );
}
