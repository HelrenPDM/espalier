import {
  useEffect,
  useId,
  useRef,
  useState,
  type FormEvent,
  type MouseEvent,
  type ReactNode,
} from "react";
import { useTranslation } from "react-i18next";
import { Link, useNavigate } from "react-router";
import { isApiError } from "../../api/admin/fieldErrors";
import { archiveReport } from "../../api/admin/packs";
import {
  draftDownloadUrl,
  fieldErrors,
  useCreateDraft,
  useDeleteDraft,
  useDrafts,
  useReadDraft,
  useUploadDraft,
  type PackDraft,
} from "../../api/admin/workbench";
import { usePrograms } from "../../api/programs";
import { ConfirmDialog } from "../../app/ConfirmDialog";
import { formatDateTime } from "../../app/format";
import {
  AlertRegion,
  Button,
  FocusHeading,
  StatusRegion,
  TextField,
} from "../../app/forms";
import { buttonClasses, FOCUS_RING, linkClasses } from "../../app/formStyles";
import { LoadingStatus } from "../../app/LoadingStatus";
import { useAdminErrorText } from "../adminErrors";
import { RowAction, TableFrame } from "../adminParts";
import { TABLE_CLASSES } from "../insights/reportFormat";
import { ReportEntryList } from "../packs/findings";
import { mediaStatusBlock } from "../packs/packMedia";
import { useStartErrorText } from "./startErrors";

const LABEL = "block text-sm font-medium text-gray-900 dark:text-gray-100";
const HINT = "mt-1 text-sm text-gray-700 dark:text-gray-300";
const FIELD_ERROR = "mt-1 text-sm text-red-700 dark:text-red-300";
const MUTED = "text-gray-700 dark:text-gray-300";
const CONTROL = `mt-1 block w-full rounded-md border border-gray-500 bg-white px-3 py-2 text-sm text-gray-900 aria-[invalid=true]:border-red-700 dark:bg-gray-900 dark:text-gray-100 dark:aria-[invalid=true]:border-red-400 ${FOCUS_RING}`;
const FILE_INPUT = `${CONTROL} file:mr-3 file:rounded-md file:border-0 file:bg-gray-100 file:px-3 file:py-1 file:text-sm file:font-semibold file:text-gray-900 dark:file:bg-gray-800 dark:file:text-gray-100`;
const START_SECTION =
  "space-y-4 rounded-lg border border-gray-300 p-4 dark:border-gray-700";

/**
 * The length of a pack name that `POST /api/admin/pack-drafts` takes, in
 * code points: the server stores the name in a `varchar(255)` column, which
 * counts code points (`Workbench.check_name/1`). A string `length` and the
 * native `maxLength` count UTF-16 code units, which an emoji takes two of.
 */
const NAME_MAX = 255;

const codePoints = (text: string) => Array.from(text).length;

/** The path of the draft page. */
const draftPath = (id: string) => `/admin/workbench/${id}`;

const BYTE_UNITS = ["byte", "kilobyte", "megabyte", "gigabyte"] as const;

/** A number of bytes in decimal units in the format of `language`. */
function formatBytes(bytes: number, language: string): string {
  let value = bytes;
  let unit = 0;
  while (value >= 1000 && unit < BYTE_UNITS.length - 1) {
    value /= 1000;
    unit += 1;
  }
  return new Intl.NumberFormat(language, {
    style: "unit",
    unit: BYTE_UNITS[unit],
    unitDisplay: "short",
    maximumFractionDigits: unit === 0 ? 0 : 1,
  }).format(value);
}

/** The heading of a start with the button that sends it. */
function StartSection({
  title,
  intro,
  children,
}: {
  title: string;
  intro: string;
  children: ReactNode;
}) {
  const headingId = useId();
  return (
    <section aria-labelledby={headingId} className={START_SECTION}>
      <h3 id={headingId} className="text-lg font-semibold tracking-tight">
        {title}
      </h3>
      <p className={`text-sm ${MUTED}`}>{intro}</p>
      {children}
    </section>
  );
}

/** "Start" with the status line while the start runs. */
function StartButton({ pending, label }: { pending: boolean; label: string }) {
  const { t } = useTranslation();
  return (
    <div className="flex flex-wrap items-center gap-4">
      <Button type="submit" disabled={pending}>
        {label}
      </Button>
      {pending && <LoadingStatus text={t("admin.workbench.start.creating")} />}
    </div>
  );
}

/** "Empty pack": the skeleton of task 0016a step 5 under a name. */
function StartEmpty() {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const errorText = useStartErrorText();
  const create = useCreateDraft();
  const nameId = useId();
  const [name, setName] = useState("");
  const [nameInvalid, setNameInvalid] = useState(false);

  const submit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (create.isPending) return;
    const trimmed = name.trim();
    if (trimmed === "" || codePoints(trimmed) > NAME_MAX) {
      setNameInvalid(true);
      document.getElementById(nameId)?.focus();
      return;
    }
    setNameInvalid(false);
    create.mutate(
      { source: "empty", name: trimmed },
      { onSuccess: (draft) => navigate(draftPath(draft.id)) },
    );
  };

  const serverNameInvalid = (fieldErrors(create.error)?.name ?? []).length > 0;
  const failure =
    create.error !== null && !serverNameInvalid
      ? errorText(create.error)
      : null;

  return (
    <StartSection
      title={t("admin.workbench.start.empty.title")}
      intro={t("admin.workbench.start.empty.intro")}
    >
      <form noValidate onSubmit={submit} className="max-w-md space-y-4">
        <TextField
          id={nameId}
          label={t("admin.workbench.start.empty.name")}
          hint={t("admin.workbench.start.empty.nameHint")}
          name="pack-name"
          autoComplete="off"
          value={name}
          errors={
            nameInvalid || serverNameInvalid
              ? [t("admin.workbench.start.empty.nameInvalid")]
              : []
          }
          onChange={(event) => {
            setName(event.target.value);
            setNameInvalid(false);
            create.reset();
          }}
        />
        <AlertRegion>{failure}</AlertRegion>
        <StartButton
          pending={create.isPending}
          label={t("admin.workbench.start.empty.submit")}
        />
      </form>
    </StartSection>
  );
}

/** "Published program": a program of `GET /api/programs`. */
function StartFromProgram() {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const errorText = useStartErrorText();
  const programs = usePrograms();
  const create = useCreateDraft();
  const selectId = useId();
  const errorId = useId();
  const [slug, setSlug] = useState("");
  const [missing, setMissing] = useState(false);
  const [gone, setGone] = useState(false);

  const submit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (create.isPending) return;
    if (slug === "") {
      setMissing(true);
      document.getElementById(selectId)?.focus();
      return;
    }
    setMissing(false);
    create.mutate(
      { source: "program", program_slug: slug },
      {
        onSuccess: (draft) => navigate(draftPath(draft.id)),
        onError: (failure) => {
          // A program that is no longer published answers 404.
          if (isApiError(failure, 404)) {
            setSlug("");
            setGone(true);
            void programs.refetch();
          }
        },
      },
    );
  };

  let fieldError: string | null = null;
  if (missing) fieldError = t("admin.workbench.start.program.missing");
  else if (gone) fieldError = t("admin.workbench.start.program.gone");
  const failure =
    create.error !== null && !isApiError(create.error, 404)
      ? errorText(create.error)
      : null;
  const chosen = programs.data?.find((program) => program.slug === slug);

  let field: ReactNode;
  if (programs.isPending)
    field = <LoadingStatus text={t("admin.workbench.start.program.loading")} />;
  else if (programs.isError)
    field = (
      <p role="alert" className={MUTED}>
        {t("admin.workbench.start.program.loadFailed")}
      </p>
    );
  else if (programs.data.length === 0)
    field = <p className={MUTED}>{t("admin.workbench.start.program.none")}</p>;
  else
    field = (
      <>
        <div>
          <label htmlFor={selectId} className={LABEL}>
            {t("admin.workbench.start.program.label")}
          </label>
          <select
            id={selectId}
            name="program"
            value={slug}
            lang={chosen?.locale}
            aria-invalid={fieldError !== null ? true : undefined}
            aria-describedby={fieldError !== null ? errorId : undefined}
            onChange={(event) => {
              setSlug(event.target.value);
              setMissing(false);
              setGone(false);
              create.reset();
            }}
            className={CONTROL}
          >
            <option value="">
              {t("admin.workbench.start.program.choose")}
            </option>
            {programs.data.map((program) => (
              <option
                key={program.slug}
                value={program.slug}
                lang={program.locale}
              >
                {program.title}
              </option>
            ))}
          </select>
          {fieldError !== null && (
            <p id={errorId} className={FIELD_ERROR}>
              {fieldError}
            </p>
          )}
        </div>
        <AlertRegion>{failure}</AlertRegion>
        <StartButton
          pending={create.isPending}
          label={t("admin.workbench.start.program.submit")}
        />
      </>
    );

  return (
    <StartSection
      title={t("admin.workbench.start.program.title")}
      intro={t("admin.workbench.start.program.intro")}
    >
      <form noValidate onSubmit={submit} className="max-w-md space-y-4">
        {field}
      </form>
    </StartSection>
  );
}

/**
 * The paths of an uploaded archive that the draft left out, with the link
 * to the draft. Its heading takes the focus when it appears.
 */
function SkippedPanel({ draft }: { draft: PackDraft }) {
  const { t } = useTranslation();
  const headingRef = useRef<HTMLHeadingElement>(null);
  const headingId = useId();
  useEffect(() => {
    headingRef.current?.focus();
  }, []);
  const skipped = draft.skipped ?? { paths: [], omitted: 0 };

  return (
    <section
      aria-labelledby={headingId}
      className="space-y-3 rounded-lg border border-accent-600 p-4 dark:border-accent-500"
    >
      <h4
        id={headingId}
        ref={headingRef}
        tabIndex={-1}
        className="font-semibold focus:outline-none"
      >
        {t("admin.workbench.start.archive.created", { title: draft.title })}
      </h4>
      <p className="text-sm">{t("admin.workbench.start.archive.skipped")}</p>
      <ul className="list-disc space-y-1 pl-6 text-sm">
        {skipped.paths.map((path) => (
          <li key={path} className="font-mono text-xs break-all">
            {path}
          </li>
        ))}
      </ul>
      {skipped.omitted > 0 && (
        <p className="text-sm">
          {t("admin.workbench.start.archive.omitted", {
            count: skipped.omitted,
          })}
        </p>
      )}
      <p>
        <Link to={draftPath(draft.id)} className={buttonClasses("primary")}>
          {t("admin.workbench.start.archive.open")}
        </Link>
      </p>
    </section>
  );
}

/**
 * "Zip archive": the upload with the limits of the pack upload. A draft
 * that left no path out opens at once; otherwise the skipped paths appear
 * below the form with the link to the draft.
 */
function StartFromArchive() {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const errorText = useStartErrorText();
  const upload = useUploadDraft();
  const inputId = useId();
  const hintId = useId();
  const inputRef = useRef<HTMLInputElement>(null);
  const [file, setFile] = useState<File | null>(null);
  const [missing, setMissing] = useState(false);
  const [created, setCreated] = useState<PackDraft | null>(null);

  const submit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (upload.isPending) return;
    if (file === null) {
      setMissing(true);
      inputRef.current?.focus();
      return;
    }
    setMissing(false);
    setCreated(null);
    upload.mutate(file, {
      onSuccess: (draft) => {
        const skipped = draft.skipped;
        if (
          skipped !== undefined &&
          (skipped.paths.length > 0 || skipped.omitted > 0)
        )
          setCreated(draft);
        else void navigate(draftPath(draft.id));
      },
    });
  };

  const error = upload.error;
  const rejected = isApiError(error, 422) ? archiveReport(error.body) : null;

  let failure: ReactNode = null;
  if (missing) failure = <p>{t("admin.packs.errors.noFile")}</p>;
  else if (isApiError(error, 413))
    failure = <p>{t("admin.packs.errors.tooLarge")}</p>;
  else if (isApiError(error, 415))
    failure = <p>{t("admin.packs.errors.unsupported")}</p>;
  else if (rejected !== null)
    failure = (
      <div className="space-y-2">
        <p>{t("admin.workbench.start.archive.rejected")}</p>
        <ReportEntryList entries={rejected} />
      </div>
    );
  else if (isApiError(error, 422))
    failure = <p>{t("admin.packs.errors.invalid")}</p>;
  else if (error !== null) failure = <p>{errorText(error)}</p>;

  return (
    <StartSection
      title={t("admin.workbench.start.archive.title")}
      intro={t("admin.workbench.start.archive.intro")}
    >
      <form noValidate onSubmit={submit} className="max-w-md space-y-4">
        <div>
          <label htmlFor={inputId} className={LABEL}>
            {t("admin.workbench.start.archive.file")}
          </label>
          <input
            ref={inputRef}
            id={inputId}
            type="file"
            name="file"
            accept=".zip,application/zip"
            aria-describedby={hintId}
            aria-invalid={missing ? true : undefined}
            onChange={(event) => {
              setFile(event.target.files?.[0] ?? null);
              setMissing(false);
              setCreated(null);
              upload.reset();
            }}
            className={FILE_INPUT}
          />
          <p id={hintId} className={HINT}>
            {t("admin.workbench.start.archive.fileHint")}
          </p>
        </div>
        <AlertRegion>{failure}</AlertRegion>
        <StartButton
          pending={upload.isPending}
          label={t("admin.workbench.start.archive.submit")}
        />
      </form>
      {created !== null && <SkippedPanel draft={created} />}
    </StartSection>
  );
}

/**
 * The drafts, newest change first, with download and "Delete". The list
 * carries no media, and the download answers 409 `media_not_ready` while a
 * media entry is not `ready`, which a plain link cannot show. A click on a
 * download therefore reads the draft first: while an entry is `queued`,
 * `processing` or `failed`, the alert names the reason of the draft page
 * and nothing is downloaded; otherwise the link is followed.
 */
function DraftList() {
  const { t, i18n } = useTranslation();
  const errorText = useAdminErrorText();
  const drafts = useDrafts();
  const remove = useDeleteDraft();
  const readDraft = useReadDraft();
  const headingId = useId();
  const headingRef = useRef<HTMLHeadingElement>(null);
  // One check of a download at a time, and the click that follows the
  // link after a passed check goes to the browser.
  const checking = useRef(false);
  const following = useRef(false);
  const [deleting, setDeleting] = useState<PackDraft | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState<string | null>(null);

  const download = (event: MouseEvent<HTMLAnchorElement>, draft: PackDraft) => {
    if (following.current) return;
    event.preventDefault();
    if (checking.current) return;
    checking.current = true;
    const link = event.currentTarget;
    setError(null);
    setStatus(null);
    void (async () => {
      try {
        const current = await readDraft(draft.id);
        const block = mediaStatusBlock(
          (current.media ?? []).map((entry) => entry.asset.status),
        );
        if (block !== null) {
          setError(t(`admin.workbench.draft.downloadReason.${block}`));
          return;
        }
        following.current = true;
        link.click();
      } catch (failure) {
        setError(errorText(failure));
        if (isApiError(failure, 404)) void drafts.refetch();
      } finally {
        following.current = false;
        checking.current = false;
      }
    })();
  };

  const confirm = async () => {
    const draft = deleting;
    setDeleting(null);
    if (draft === null) return;
    setError(null);
    setStatus(null);
    try {
      await remove.mutateAsync(draft.id);
      setStatus(t("admin.workbench.list.deleted", { title: draft.title }));
      // The row and its button are gone; the focus moves to the list.
      requestAnimationFrame(() => headingRef.current?.focus());
    } catch (failure) {
      setError(errorText(failure));
      if (isApiError(failure, 404)) void drafts.refetch();
    }
  };

  let body: ReactNode;
  if (drafts.isPending)
    body = <LoadingStatus text={t("admin.workbench.list.loading")} />;
  else if (drafts.isError)
    body = (
      <p role="alert" className={MUTED}>
        {t("admin.common.loadFailed")}
      </p>
    );
  else if (drafts.data.length === 0)
    body = <p className={MUTED}>{t("admin.workbench.list.empty")}</p>;
  else
    body = (
      <TableFrame labelledBy={headingId}>
        <thead>
          <tr>
            <th scope="col" className={TABLE_CLASSES.columnHeader}>
              {t("admin.workbench.list.columns.title")}
            </th>
            <th scope="col" className={TABLE_CLASSES.columnHeader}>
              {t("admin.workbench.list.columns.packKey")}
            </th>
            <th scope="col" className={TABLE_CLASSES.columnHeader}>
              {t("admin.workbench.list.columns.files")}
            </th>
            <th scope="col" className={TABLE_CLASSES.columnHeader}>
              {t("admin.workbench.list.columns.size")}
            </th>
            <th scope="col" className={TABLE_CLASSES.columnHeader}>
              {t("admin.workbench.list.columns.updatedAt")}
            </th>
            <th scope="col" className={TABLE_CLASSES.columnHeader}>
              {t("admin.workbench.list.columns.actions")}
            </th>
          </tr>
        </thead>
        <tbody>
          {drafts.data.map((draft) => (
            <tr key={draft.id}>
              <th scope="row" className={TABLE_CLASSES.rowHeader}>
                <Link to={draftPath(draft.id)} className={linkClasses}>
                  {draft.title}
                </Link>
              </th>
              <td className={TABLE_CLASSES.cell}>
                {draft.pack_key === null ? (
                  t("admin.common.none")
                ) : (
                  <code className="font-mono text-xs break-all">
                    {draft.pack_key}
                  </code>
                )}
              </td>
              <td className={TABLE_CLASSES.cell}>
                {new Intl.NumberFormat(i18n.language).format(draft.usage.files)}
              </td>
              <td className={TABLE_CLASSES.cell}>
                {formatBytes(draft.usage.bytes, i18n.language)}
              </td>
              <td className={TABLE_CLASSES.cell}>
                {formatDateTime(draft.updated_at, i18n.language)}
              </td>
              <td className={TABLE_CLASSES.cell}>
                <div className="flex flex-wrap gap-x-4 gap-y-1">
                  <a
                    href={draftDownloadUrl(draft.id)}
                    download
                    className={`text-sm ${linkClasses}`}
                    onClick={(event) => download(event, draft)}
                  >
                    {t("admin.workbench.list.download")}{" "}
                    <span className="sr-only">{draft.title}</span>
                  </a>
                  <RowAction
                    subject={draft.title}
                    danger
                    disabled={remove.isPending}
                    onClick={() => setDeleting(draft)}
                  >
                    {t("admin.workbench.list.delete")}
                  </RowAction>
                </div>
              </td>
            </tr>
          ))}
        </tbody>
      </TableFrame>
    );

  return (
    <section className="mt-10 space-y-4">
      <h2
        id={headingId}
        ref={headingRef}
        tabIndex={-1}
        className="text-xl font-semibold tracking-tight focus:outline-none"
      >
        {t("admin.workbench.list.drafts")}
      </h2>
      <AlertRegion>{error}</AlertRegion>
      <StatusRegion>{status}</StatusRegion>
      {body}
      <ConfirmDialog
        open={deleting !== null}
        title={t("admin.workbench.list.deleteDialog.title")}
        confirmLabel={t("admin.workbench.list.delete")}
        confirmVariant="danger"
        onConfirm={() => void confirm()}
        onClose={() => setDeleting(null)}
      >
        <p>
          {t("admin.workbench.list.deleteDialog.text", {
            title: deleting?.title ?? "",
          })}
        </p>
      </ConfirmDialog>
    </section>
  );
}

/**
 * `/admin/workbench` (task 0016a, step 12): the drafts of the pack
 * workbench with a link to each draft, its download and "Delete" behind a
 * confirmation, and three starting points: an empty pack under a name, a
 * published program and a zip archive. The fourth starting point, an
 * import with a payload, is the button "Edit in the workbench" of the pack
 * page. Each start moves to the new draft; a start from an archive that
 * left files out of the pack layout first lists their paths here, with
 * the link to the draft. A 409 `draft_limit` names the limit and the advice
 * to delete a draft. Every start needs a second factor from the last 10
 * minutes; the API client opens the step-up dialog and repeats the request.
 * A download reads the draft first and names the reason in the alert while
 * a media entry is not `ready` (task 0018).
 */
export function WorkbenchPage() {
  const { t } = useTranslation();
  const startHeadingId = useId();

  return (
    <section>
      <FocusHeading>{t("admin.workbench.list.title")}</FocusHeading>
      <p className={`mt-2 max-w-3xl ${MUTED}`}>
        {t("admin.workbench.list.intro")}
      </p>
      <DraftList />
      <section aria-labelledby={startHeadingId} className="mt-10 max-w-3xl">
        <h2
          id={startHeadingId}
          className="text-xl font-semibold tracking-tight"
        >
          {t("admin.workbench.start.title")}
        </h2>
        <p className={`mt-2 ${MUTED}`}>{t("admin.workbench.start.intro")}</p>
        <div className="mt-4 space-y-6">
          <StartEmpty />
          <StartFromProgram />
          <StartFromArchive />
        </div>
      </section>
    </section>
  );
}
