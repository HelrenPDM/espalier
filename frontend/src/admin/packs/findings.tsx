import { useTranslation } from "react-i18next";
import type {
  AlignmentCheckFinding,
  AlignmentFinding,
  ReportEntry,
} from "../../api/admin/packs";
import { linkClasses } from "../../app/formStyles";

const ITEM_CLASSES =
  "rounded-md border border-gray-300 px-3 py-2 text-sm text-gray-800 dark:border-gray-700 dark:text-gray-200";

const Separator = () => <>{", "}</>;

/** A file of the pack, in the type of the code. */
const PackFile = ({ path }: { path: string }) => (
  <span className="font-mono text-xs break-all">{path}</span>
);

/**
 * Opens a file of the pack at a line (the draft page of task 0016a). With
 * `onOpen`, the lists below show the file and the line of an entry as a
 * button when `canOpen` admits the file; an entry on `.` or on a directory
 * keeps its text. The pack page passes neither.
 */
export interface EntryOpener {
  /** Opens `file` and moves the cursor to `line`, when it has one. */
  onOpen?: (file: string, line: number | null) => void;
  /** True for a file that `onOpen` opens; every file without it. */
  canOpen?: (file: string) => boolean;
}

/**
 * The file and the line (or "no line") of an entry: a button that opens
 * the file at the line when `opener` admits the file, and text otherwise.
 */
function FileAndLine({
  file,
  line,
  opener: { onOpen, canOpen = () => true },
}: {
  file: string;
  line: number | null;
  opener: EntryOpener;
}) {
  const { t } = useTranslation();
  const text = (
    <>
      <PackFile path={file} />
      <Separator />
      <span>
        {line === null
          ? t("admin.pack.entry.noLine")
          : t("admin.pack.entry.line", { line })}
      </span>
    </>
  );
  if (onOpen === undefined || !canOpen(file)) return text;
  return (
    <button
      type="button"
      onClick={() => onOpen(file, line)}
      className={`text-left ${linkClasses}`}
    >
      {text}
    </button>
  );
}

/**
 * Entries of an import report or of a rejected archive: file, line (or "no
 * line") and message. A closing entry that stands for omitted entries
 * shows its message alone. With `onOpen`, the file and the line of an
 * entry form a button that opens the file at that line.
 */
export function ReportEntryList({
  entries,
  ...opener
}: EntryOpener & { entries: ReportEntry[] }) {
  return (
    <ul className="space-y-2">
      {entries.map((entry, index) => (
        <li key={index} className={ITEM_CLASSES}>
          {entry.omitted === undefined && (
            <>
              <FileAndLine
                file={entry.file}
                line={entry.line}
                opener={opener}
              />
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
 * key and message of each. With `onOpen`, the file and the line form a
 * button that opens the file at that line.
 */
export function AlignmentFindingList({
  findings,
  ...opener
}: EntryOpener & { findings: AlignmentFinding[] }) {
  const { t } = useTranslation();
  return (
    <ul className="space-y-2">
      {findings.map((finding, index) => (
        <li key={index} className={ITEM_CLASSES}>
          <FileAndLine
            file={finding.file}
            line={finding.line}
            opener={opener}
          />
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
