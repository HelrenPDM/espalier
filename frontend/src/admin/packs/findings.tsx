import { useTranslation } from "react-i18next";
import type {
  AlignmentCheckFinding,
  AlignmentFinding,
  ReportEntry,
} from "../../api/admin/packs";

const ITEM_CLASSES =
  "rounded-md border border-gray-300 px-3 py-2 text-sm text-gray-800 dark:border-gray-700 dark:text-gray-200";

const Separator = () => <>{", "}</>;

/** A file of the pack, in the type of the code. */
const PackFile = ({ path }: { path: string }) => (
  <span className="font-mono text-xs break-all">{path}</span>
);

/**
 * Entries of an import report or of a rejected archive: file, line (or "no
 * line") and message. A closing entry that stands for omitted entries
 * shows its message alone.
 */
export function ReportEntryList({ entries }: { entries: ReportEntry[] }) {
  const { t } = useTranslation();
  return (
    <ul className="space-y-2">
      {entries.map((entry, index) => (
        <li key={index} className={ITEM_CLASSES}>
          {entry.omitted === undefined && (
            <>
              <PackFile path={entry.file} />
              <Separator />
              <span>
                {entry.line === null
                  ? t("admin.pack.entry.noLine")
                  : t("admin.pack.entry.line", { line: entry.line })}
              </span>
              {": "}
            </>
          )}
          <span>{entry.message}</span>
        </li>
      ))}
    </ul>
  );
}

/**
 * Findings of the alignment checks of an import: file, line, check number,
 * key and message of each.
 */
export function AlignmentFindingList({
  findings,
}: {
  findings: AlignmentFinding[];
}) {
  const { t } = useTranslation();
  return (
    <ul className="space-y-2">
      {findings.map((finding, index) => (
        <li key={index} className={ITEM_CLASSES}>
          <PackFile path={finding.file} />
          <Separator />
          <span>{t("admin.pack.entry.line", { line: finding.line })}</span>
          <Separator />
          <span>{t("admin.pack.entry.check", { check: finding.check })}</span>
          <Separator />
          <code className="font-mono text-xs">{finding.key}</code>
          {": "}
          <span>{finding.message}</span>
        </li>
      ))}
    </ul>
  );
}

/**
 * Findings of the alignment check at publish time (the 409
 * `alignment_errors` answer): file, module, check number, key and message.
 */
export function CheckFindingList({
  findings,
}: {
  findings: AlignmentCheckFinding[];
}) {
  const { t } = useTranslation();
  return (
    <ul className="space-y-2">
      {findings.map((finding, index) => (
        <li key={index} className={ITEM_CLASSES}>
          <PackFile path={finding.file} />
          <Separator />
          <span>
            {t("admin.pack.entry.module", { module: finding.module })}
          </span>
          <Separator />
          <span>{t("admin.pack.entry.check", { check: finding.check })}</span>
          <Separator />
          <code className="font-mono text-xs">{finding.key}</code>
          {": "}
          <span>{finding.message}</span>
        </li>
      ))}
    </ul>
  );
}
