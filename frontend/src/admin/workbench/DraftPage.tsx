import {
  useQueryClient,
  type QueryObserverResult,
} from "@tanstack/react-query";
import { useEffect, useId, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import { Link, useBlocker, useNavigate, useParams } from "react-router";
import type { ReportEntry } from "../../api/admin/packs";
import {
  draftDownloadUrl,
  draftQueryKey,
  staleDraft,
  useCheckDraft,
  useDraft,
  useDraftFile,
  useFollowDraftMedia,
  useImportDraft,
  useSaveFile,
  type DraftFileEntry,
  type DraftMediaEntry,
  type PackDraft,
  type PackDraftCheck,
} from "../../api/admin/workbench";
import { ApiError } from "../../api/errors";
import { Breadcrumbs } from "../../app/Breadcrumbs";
import { formatDateTime } from "../../app/format";
import { AlertRegion, Button, StatusRegion } from "../../app/forms";
import { buttonClasses, linkClasses } from "../../app/formStyles";
import { LoadingStatus } from "../../app/LoadingStatus";
import { AlignmentSection } from "../packs/AlignmentSection";
import { ReportEntryList } from "../packs/findings";
import { mediaStatusBlock } from "../packs/packMedia";
import { formatBytes, useDraftErrorText } from "./draftErrors";
import { FileTree } from "./FileTree";
import { MediaPreview } from "./MediaPreview";
import { PackFileEditor } from "./PackFileEditor";
import { pathLanguage } from "./paths";
import { WorkbenchDialog } from "./WorkbenchDialog";

const MUTED = "text-gray-700 dark:text-gray-300";
const NOTICE =
  "rounded-md border-2 border-amber-600 bg-amber-50 px-3 py-2 text-sm text-gray-900 dark:border-amber-400 dark:bg-gray-900 dark:text-gray-100";
const BADGE =
  "rounded bg-amber-100 px-1.5 py-0.5 text-sm font-medium text-amber-900 dark:bg-amber-900 dark:text-amber-100";

/** The text of the open file: as in the editor and as last loaded or saved. */
interface EditorText {
  fileId: string;
  /** The path at the time of loading, for a file that another session deleted. */
  path: string;
  text: string;
  saved: string;
}

/**
 * A file, or a media entry of task 0018, to open once the unsaved changes
 * are saved or discarded.
 */
type PendingOpen =
  { fileId: string; line: number | null } | { mediaId: string };

/** A check answer and the revision of the editor text it ran on. */
interface CheckRun {
  result: PackDraftCheck;
  revision: number;
}

/** The number of entries, with the entries that a closing entry stands for. */
const entryCount = (entries: readonly ReportEntry[]) =>
  entries.reduce((sum, entry) => sum + (entry.omitted ?? 1), 0);

const isNotFound = (error: unknown) =>
  error instanceof ApiError && error.status === 404;

/**
 * The section "Check report": every error and every warning of the check,
 * the lines of `mix espalier.validate` with the findings of the alignment
 * checks among them, with file, line and message, and a note when the
 * draft changed since the check. The counts of the headings are those of
 * the announcement. An entry on a file of the draft opens that file at its
 * line.
 */
function CheckReport({
  report,
  outdated,
  canOpen,
  onOpen,
}: {
  report: PackDraftCheck["report"];
  outdated: boolean;
  canOpen: (file: string) => boolean;
  onOpen: (file: string, line: number | null) => void;
}) {
  const { t } = useTranslation();
  const headingId = useId();
  const errorsId = useId();
  const warningsId = useId();
  const { errors, warnings } = report;

  return (
    <section aria-labelledby={headingId} className="space-y-4">
      <h2 id={headingId} className="text-xl font-semibold tracking-tight">
        {t("admin.workbench.draft.report.title")}
      </h2>
      {outdated && (
        <p className={NOTICE}>{t("admin.workbench.draft.report.outdated")}</p>
      )}
      <p className={`text-sm ${MUTED}`}>
        {t("admin.workbench.draft.report.intro")}
      </p>
      <section aria-labelledby={errorsId} className="space-y-2">
        <h3 id={errorsId} className="text-lg font-semibold tracking-tight">
          {t("admin.workbench.draft.report.errors", {
            count: entryCount(errors),
          })}
        </h3>
        {errors.length === 0 ? (
          <p className={MUTED}>{t("admin.workbench.draft.report.none")}</p>
        ) : (
          <ReportEntryList entries={errors} canOpen={canOpen} onOpen={onOpen} />
        )}
      </section>
      <section aria-labelledby={warningsId} className="space-y-2">
        <h3 id={warningsId} className="text-lg font-semibold tracking-tight">
          {t("admin.workbench.draft.report.warnings", {
            count: entryCount(warnings),
          })}
        </h3>
        {warnings.length === 0 ? (
          <p className={MUTED}>{t("admin.workbench.draft.report.none")}</p>
        ) : (
          <ReportEntryList
            entries={warnings}
            canOpen={canOpen}
            onOpen={onOpen}
          />
        )}
      </section>
    </section>
  );
}

/** The pack key, the files and the bytes of the draft against its limits. */
function DraftFacts({ draft }: { draft: PackDraft }) {
  const { t, i18n } = useTranslation();
  const number = new Intl.NumberFormat(i18n.language);
  return (
    <dl className="grid grid-cols-[max-content_1fr] gap-x-4 gap-y-1 text-sm">
      <dt className="font-medium">{t("admin.workbench.draft.packKey")}</dt>
      <dd>
        {draft.pack_key === null ? (
          t("admin.workbench.draft.noPackKey")
        ) : (
          <code className="font-mono text-xs break-all">{draft.pack_key}</code>
        )}
      </dd>
      <dt className="font-medium">{t("admin.workbench.draft.files")}</dt>
      <dd>
        {t("admin.workbench.draft.usage", {
          used: number.format(draft.usage.files),
          limit: number.format(draft.limits.files),
        })}
      </dd>
      <dt className="font-medium">{t("admin.workbench.draft.mediaEntries")}</dt>
      <dd>{number.format(draft.media?.length ?? 0)}</dd>
      <dt className="font-medium">{t("admin.workbench.draft.size")}</dt>
      <dd>
        {t("admin.workbench.draft.usage", {
          used: formatBytes(draft.usage.bytes, i18n.language),
          limit: formatBytes(draft.limits.draft_bytes, i18n.language),
        })}{" "}
        {t("admin.workbench.draft.fileLimit", {
          limit: formatBytes(draft.limits.file_bytes, i18n.language),
        })}
      </dd>
      <dt className="font-medium">{t("admin.workbench.draft.updatedAt")}</dt>
      <dd>{formatDateTime(draft.updated_at, i18n.language)}</dd>
    </dl>
  );
}

function DraftView({
  draft,
  reloadDraft,
}: {
  draft: PackDraft;
  reloadDraft: () => Promise<QueryObserverResult<PackDraft>>;
}) {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const editorHeadingId = useId();
  const importReasonId = useId();
  const downloadReasonId = useId();
  const saveButton = useRef<HTMLButtonElement>(null);
  const files = draft.files ?? [];
  const errorText = useDraftErrorText(draft.limits);

  const [openFileId, setOpenFileId] = useState<string | null>(null);
  // The media entry shown in place of the editor (task 0018).
  const [openMediaId, setOpenMediaId] = useState<string | null>(null);
  const [editor, setEditor] = useState<EditorText | null>(null);
  const [cursor, setCursor] = useState({ line: 1, column: 1 });
  const [goTo, setGoTo] = useState<{ line: number } | null>(null);
  // Grows with every change of the editor text: an edit, a discard or the
  // stored version after a conflict. A check remembers it.
  const [revision, setRevision] = useState(0);
  const [announcement, setAnnouncement] = useState({ text: "", key: 0 });
  const [alert, setAlert] = useState<string | null>(null);
  const [pending, setPending] = useState<PendingOpen | null>(null);
  const [conflict, setConflict] = useState<number | null>(null);
  // True while "Load the stored version" reads the draft and the file.
  const [loadingStored, setLoadingStored] = useState(false);
  const [checkRun, setCheckRun] = useState<CheckRun | null>(null);

  const fileQuery = useDraftFile(draft.id, openFileId);
  const saveFile = useSaveFile(draft.id);
  const check = useCheckDraft(draft.id);
  const importDraft = useImportDraft(draft.id);

  // The editor takes the stored text once per opened file, from a read
  // that succeeded and is not refetching. After a failed read, TanStack
  // Query keeps the data of an earlier read, which never reaches the
  // editor; useDraftFile drops the content of a closed file besides.
  if (
    openFileId !== null &&
    editor?.fileId !== openFileId &&
    fileQuery.isSuccess &&
    !fileQuery.isFetching &&
    fileQuery.data.id === openFileId
  )
    setEditor({
      fileId: fileQuery.data.id,
      path: fileQuery.data.path,
      text: fileQuery.data.content,
      saved: fileQuery.data.content,
    });

  const openEntry = files.find((file) => file.id === openFileId) ?? null;
  const openMedia: DraftMediaEntry | null =
    (draft.media ?? []).find((entry) => entry.id === openMediaId) ?? null;
  // The download answers 409 `media_not_ready` while an entry is not
  // `ready`, and a plain link cannot show that answer; the page follows
  // the conversions and offers the link once every entry is `ready`.
  useFollowDraftMedia(draft);
  const downloadBlock = mediaStatusBlock(
    (draft.media ?? []).map((entry) => entry.asset.status),
  );
  const ready = editor !== null && editor.fileId === openFileId;
  const dirty = ready && editor.text !== editor.saved;
  const path = openEntry?.path ?? (ready ? editor.path : null);
  const missing = openFileId !== null && openEntry === null;
  const editorLabel =
    path === null ? "" : t("admin.workbench.draft.editor.label", { path });

  const announce = (text: string) =>
    setAnnouncement((current) => ({ text, key: current.key + 1 }));

  // A file that another session deleted answers 404; the tree reads the
  // draft again and leaves it out.
  const fileError = fileQuery.error;
  useEffect(() => {
    if (fileError instanceof ApiError && fileError.status === 404)
      void reloadDraft();
  }, [fileError, reloadDraft]);

  // A reload or a closed tab with unsaved changes asks first.
  useEffect(() => {
    if (!dirty) return;
    const warn = (event: BeforeUnloadEvent) => {
      event.preventDefault();
      event.returnValue = "";
    };
    window.addEventListener("beforeunload", warn);
    return () => window.removeEventListener("beforeunload", warn);
  }, [dirty]);

  // A navigation within the SPA with unsaved changes asks first.
  const blocker = useBlocker(
    ({ currentLocation, nextLocation }) =>
      dirty && currentLocation.pathname !== nextLocation.pathname,
  );

  const openFile = (fileId: string, line: number | null) => {
    setPending(null);
    setOpenMediaId(null);
    if (fileId !== openFileId) {
      setOpenFileId(fileId);
      setEditor(null);
      setCursor({ line: line ?? 1, column: 1 });
    }
    setGoTo(line === null ? null : { line });
  };

  /** Shows a media entry in place of the editor, which closes its file. */
  const showMedia = (mediaId: string) => {
    setPending(null);
    setOpenFileId(null);
    setEditor(null);
    setGoTo(null);
    setOpenMediaId(mediaId);
  };

  /** Shows a media entry, after the question on the unsaved changes of a file. */
  const requestMedia = (mediaId: string) => {
    if (dirty) {
      setPending({ mediaId });
      return;
    }
    showMedia(mediaId);
  };

  /** Opens a file, after the question on the unsaved changes of another. */
  const requestOpen = (fileId: string, line: number | null = null) => {
    if (fileId === openFileId) {
      if (line !== null) setGoTo({ line });
      return;
    }
    if (dirty) {
      setPending({ fileId, line });
      return;
    }
    openFile(fileId, line);
  };

  const fileAt = (file: string) =>
    files.find((entry) => entry.path === file) ?? null;

  const openAt = (file: string, line: number | null) => {
    const entry = fileAt(file);
    if (entry !== null) requestOpen(entry.id, line);
  };

  const changeText = (text: string) => {
    setEditor((current) => (current === null ? current : { ...current, text }));
    setRevision((current) => current + 1);
  };

  /**
   * After a 404 on a save: reads the draft again. A file that another
   * session deleted leaves the tree, and the notice of the editor states
   * it. Otherwise an alert states that the draft or the file no longer
   * exists, and the text stays in the editor, so that it can be copied.
   */
  const afterSaveNotFound = async (fileId: string) => {
    const reloaded = await reloadDraft();
    if (
      reloaded.status === "success" &&
      !(reloaded.data.files ?? []).some((file) => file.id === fileId)
    )
      return;
    setAlert(
      reloaded.status === "error" && isNotFound(reloaded.error)
        ? t("admin.workbench.draft.editor.draftDeleted")
        : t("admin.workbench.draft.editor.saveNotFound"),
    );
  };

  /**
   * `PUT` of the open file with the cached `lock_version`. Resolves `true`
   * after a success; a 409 `stale_draft` opens the conflict dialog, and a
   * 404 reads the draft again (`afterSaveNotFound`).
   */
  const save = async (): Promise<boolean> => {
    if (
      !dirty ||
      editor === null ||
      openEntry === null ||
      saveFile.isPending ||
      loadingStored
    )
      return false;
    const { fileId, text } = editor;
    const savedPath = openEntry.path;
    setAlert(null);
    try {
      await saveFile.mutateAsync({
        fileId,
        content: text,
        lock_version: draft.lock_version,
      });
    } catch (error) {
      const stored = staleDraft(error);
      if (stored !== null) setConflict(stored);
      else if (isNotFound(error)) await afterSaveNotFound(fileId);
      else setAlert(errorText(error));
      return false;
    }
    setEditor((current) =>
      current !== null && current.fileId === fileId
        ? { ...current, saved: text }
        : current,
    );
    announce(t("admin.workbench.draft.saved", { path: savedPath }));
    return true;
  };

  const saveFromButton = async () => {
    await save();
    // The button is disabled while the save runs, which can take the focus.
    if (document.activeElement === document.body) saveButton.current?.focus();
  };

  const runCheck = () => {
    if (check.isPending) return;
    setAlert(null);
    const overlay =
      dirty && editor !== null && !missing
        ? { file_id: editor.fileId, content: editor.text }
        : null;
    const atRevision = revision;
    announce(t("admin.workbench.draft.check.running"));
    check.mutate(overlay, {
      onSuccess: (result) => {
        setCheckRun({ result, revision: atRevision });
        announce(
          t("admin.workbench.draft.check.finished", {
            errors: t("admin.workbench.draft.check.errorCount", {
              count: entryCount(result.report.errors),
            }),
            warnings: t("admin.workbench.draft.check.warningCount", {
              count: entryCount(result.report.warnings),
            }),
          }),
        );
      },
      onError: (error) => {
        announce("");
        setAlert(errorText(error));
      },
    });
  };

  const createImport = () => {
    if (dirty || loadingStored || importDraft.isPending) return;
    setAlert(null);
    announce(t("admin.workbench.draft.import.running"));
    importDraft.mutate(draft.lock_version, {
      onSuccess: (pack) => void navigate(`/admin/packs/${pack.id}`),
      onError: (error) => {
        announce("");
        const stored = staleDraft(error);
        if (stored !== null) setConflict(stored);
        else setAlert(errorText(error));
      },
    });
  };

  /**
   * "Load the stored version": the draft and then the open file again. The
   * draft comes first, so the text is at least as new as the cached
   * `lock_version`. Until both reads end, the editor takes no input and
   * nothing saves or imports: the cache holds the new `lock_version` before
   * the editor holds the stored text, and a save in between would replace
   * the change of the other session without a 409.
   */
  const loadStored = async () => {
    if (loadingStored) return;
    const before = draft.lock_version;
    const fileId = openFileId;
    setConflict(null);
    setAlert(null);
    setLoadingStored(true);
    try {
      const reloaded = await reloadDraft();
      if (reloaded.status !== "success") {
        setAlert(
          isNotFound(reloaded.error)
            ? t("admin.workbench.draft.editor.draftDeleted")
            : t("admin.workbench.draft.conflict.loadFailed"),
        );
        return;
      }
      // A file that another session deleted leaves the tree, and the
      // notice of the editor states it.
      if (
        fileId === null ||
        !(reloaded.data.files ?? []).some((file) => file.id === fileId)
      )
        return;
      const result = await fileQuery.refetch();
      if (result.status !== "success") {
        // A 404 reads the draft again (the effect on `fileError` above).
        if (isNotFound(result.error)) return;
        // The editor keeps a text that is not the stored one, so the next
        // save or import sends the version that the text belongs to and
        // meets the conflict again.
        queryClient.setQueryData<PackDraft>(
          draftQueryKey(draft.id),
          (current) =>
            current === undefined
              ? current
              : { ...current, lock_version: before },
        );
        setAlert(t("admin.workbench.draft.conflict.loadFailed"));
        return;
      }
      const stored = result.data;
      if (stored.id !== fileId) return;
      setEditor({
        fileId: stored.id,
        path: stored.path,
        text: stored.content,
        saved: stored.content,
      });
      setRevision((current) => current + 1);
    } finally {
      setLoadingStored(false);
    }
  };

  /**
   * "Keep my version": the `lock_version` of the answer replaces the cached
   * one, and the text stays unsaved, so the next save replaces the stored
   * version.
   */
  const keepMine = () => {
    if (conflict === null) return;
    queryClient.setQueryData<PackDraft>(draftQueryKey(draft.id), (current) =>
      current === undefined ? current : { ...current, lock_version: conflict },
    );
    setConflict(null);
  };

  const guardOpen = pending !== null || blocker.state === "blocked";

  const closeGuard = () => {
    setPending(null);
    if (blocker.state === "blocked") blocker.reset();
  };

  const proceed = (target: PendingOpen | null) => {
    if (blocker.state === "blocked") blocker.proceed();
    else if (target === null) return;
    else if ("mediaId" in target) showMedia(target.mediaId);
    else openFile(target.fileId, target.line);
  };

  const guardSave = async () => {
    const target = pending;
    // A save that ended while the question was open left nothing unsaved.
    if (!dirty || (await save())) proceed(target);
    else closeGuard();
  };

  const guardDiscard = () => {
    const target = pending;
    setEditor((current) =>
      current === null ? current : { ...current, text: current.saved },
    );
    setRevision((current) => current + 1);
    proceed(target);
  };

  const onDeleted = (file: DraftFileEntry) => {
    if (file.id === openFileId) {
      setOpenFileId(null);
      setEditor(null);
      setGoTo(null);
    }
    announce(t("admin.workbench.draft.deleted", { path: file.path }));
  };

  const onMediaDeleted = (entry: DraftMediaEntry) => {
    if (entry.id === openMediaId) setOpenMediaId(null);
    announce(t("admin.workbench.media.removed", { path: entry.path }));
  };

  const checkOutdated =
    checkRun !== null &&
    (checkRun.result.lock_version < draft.lock_version ||
      checkRun.revision !== revision);

  let editorBody;
  if (openMedia !== null)
    editorBody = <MediaPreview key={openMedia.id} entry={openMedia} />;
  else if (openFileId === null)
    editorBody = (
      <p className={MUTED}>{t("admin.workbench.draft.editor.none")}</p>
    );
  else if (ready)
    editorBody = (
      <>
        <div className="flex flex-wrap items-center gap-4">
          {/* Without changes the button stays focusable and does nothing. */}
          <button
            ref={saveButton}
            type="button"
            onClick={() => void saveFromButton()}
            disabled={saveFile.isPending || loadingStored}
            aria-disabled={!dirty || missing ? true : undefined}
            className={`${buttonClasses()} aria-disabled:cursor-not-allowed aria-disabled:opacity-50`}
          >
            {t("admin.workbench.draft.editor.save")}
          </button>
          <p className={`text-sm ${MUTED}`}>
            {t("admin.workbench.draft.editor.saveHint")}
          </p>
        </div>
        <PackFileEditor
          key={editor.fileId}
          value={editor.text}
          onChange={changeText}
          language={pathLanguage(path ?? editor.path) ?? "yaml"}
          label={editorLabel}
          readOnly={loadingStored}
          onSave={() => void save()}
          onCursor={(line, column) => setCursor({ line, column })}
          goTo={goTo}
        />
        <p className={`text-sm ${MUTED}`}>
          {t("admin.workbench.draft.editor.cursor", cursor)}
        </p>
      </>
    );
  else if (fileQuery.isError)
    editorBody = (
      <p role="alert" className={MUTED}>
        {fileQuery.error instanceof ApiError && fileQuery.error.status === 404
          ? t("admin.workbench.draft.editor.gone")
          : t("admin.workbench.draft.editor.loadFailed")}
      </p>
    );
  else
    editorBody = (
      <LoadingStatus text={t("admin.workbench.draft.editor.loading")} />
    );

  return (
    <div className="space-y-10">
      <div className="space-y-4">
        <Breadcrumbs
          items={[
            {
              label: t("admin.workbench.draft.breadcrumb"),
              to: "/admin/workbench",
            },
            { label: draft.title },
          ]}
        />
        <h1 className="text-2xl font-semibold tracking-tight break-words">
          {draft.title}
        </h1>
        <DraftFacts draft={draft} />
        <div className="flex flex-wrap items-center gap-3">
          <Button variant="secondary" onClick={runCheck}>
            {t("admin.workbench.draft.check.button")}
          </Button>
          <Button
            onClick={createImport}
            disabled={dirty || loadingStored}
            aria-describedby={dirty ? importReasonId : undefined}
          >
            {t("admin.workbench.draft.import.button")}
          </Button>
          {downloadBlock === null ? (
            <a
              href={draftDownloadUrl(draft.id)}
              download
              className={buttonClasses("secondary")}
            >
              {t("admin.workbench.draft.download")}
            </a>
          ) : (
            <Button
              variant="secondary"
              disabled
              aria-describedby={downloadReasonId}
            >
              {t("admin.workbench.draft.download")}
            </Button>
          )}
        </div>
        {dirty && (
          <p id={importReasonId} className={`text-sm ${MUTED}`}>
            {t("admin.workbench.draft.import.unsaved")}
          </p>
        )}
        {downloadBlock !== null && (
          <p id={downloadReasonId} className={`text-sm ${MUTED}`}>
            {t(`admin.workbench.draft.downloadReason.${downloadBlock}`)}
          </p>
        )}
        <StatusRegion>
          {announcement.text !== "" && (
            <p key={announcement.key}>{announcement.text}</p>
          )}
        </StatusRegion>
        <AlertRegion>{alert}</AlertRegion>
      </div>

      <div className="grid gap-8 lg:grid-cols-[16rem_minmax(0,1fr)]">
        <FileTree
          draft={draft}
          openFileId={openFileId}
          openMediaId={openMedia?.id ?? null}
          unsaved={dirty}
          onOpen={(fileId) => requestOpen(fileId)}
          onOpenMedia={requestMedia}
          onCreated={(next, created) => {
            announce(t("admin.workbench.draft.added", { path: created }));
            const entry = next.files?.find((file) => file.path === created);
            if (entry !== undefined && !dirty) openFile(entry.id, null);
          }}
          onRenamed={(from, to) =>
            announce(t("admin.workbench.draft.renamed", { from, to }))
          }
          onDeleted={onDeleted}
          onMediaAdded={(next, added) => {
            announce(t("admin.workbench.media.added", { path: added }));
            const entry = next.media?.find((media) => media.path === added);
            if (entry !== undefined && !dirty) showMedia(entry.id);
          }}
          onMediaDeleted={onMediaDeleted}
          onConflict={setConflict}
        />
        <section
          aria-labelledby={editorHeadingId}
          className="min-w-0 space-y-3"
        >
          <h2
            id={editorHeadingId}
            className="flex flex-wrap items-baseline gap-x-3 gap-y-1 text-xl font-semibold tracking-tight"
          >
            <span className="break-all">
              {openMedia !== null
                ? t("admin.workbench.media.preview.title", {
                    path: openMedia.path,
                  })
                : path === null
                  ? t("admin.workbench.draft.editor.title")
                  : editorLabel}
            </span>{" "}
            {dirty && (
              <span className={BADGE}>
                {t("admin.workbench.draft.editor.unsaved")}
              </span>
            )}
          </h2>
          {missing && path !== null && (
            <p role="alert" className={NOTICE}>
              {ready
                ? t("admin.workbench.draft.editor.deletedKeep", { path })
                : t("admin.workbench.draft.editor.deleted", { path })}
            </p>
          )}
          {editorBody}
        </section>
      </div>

      {checkRun !== null && (
        <>
          <CheckReport
            report={checkRun.result.report}
            outdated={checkOutdated}
            canOpen={(file) => fileAt(file) !== null}
            onOpen={openAt}
          />
          <AlignmentSection
            alignment={checkRun.result.alignment}
            noMatrix={t("admin.workbench.draft.report.noMatrix")}
            canOpen={(file) => fileAt(file) !== null}
            onOpen={openAt}
          />
        </>
      )}

      <WorkbenchDialog
        open={guardOpen}
        title={t("admin.workbench.draft.unsaved.title")}
        onClose={closeGuard}
        actions={
          <>
            <Button variant="secondary" onClick={closeGuard} data-autofocus>
              {t("auth.forms.cancel")}
            </Button>
            <Button variant="danger" onClick={guardDiscard}>
              {t("admin.workbench.draft.unsaved.discard")}
            </Button>
            <Button
              onClick={() => void guardSave()}
              disabled={saveFile.isPending || loadingStored || missing}
            >
              {t("admin.workbench.draft.unsaved.save")}
            </Button>
          </>
        }
      >
        <p>{t("admin.workbench.draft.unsaved.body", { path: path ?? "" })}</p>
      </WorkbenchDialog>

      <WorkbenchDialog
        open={conflict !== null}
        title={t("admin.workbench.draft.conflict.title")}
        onClose={() => setConflict(null)}
        actions={
          <>
            <Button variant="secondary" onClick={() => setConflict(null)}>
              {t("auth.forms.cancel")}
            </Button>
            {dirty && (
              <Button variant="secondary" onClick={keepMine}>
                {t("admin.workbench.draft.conflict.keep")}
              </Button>
            )}
            <Button onClick={() => void loadStored()} data-autofocus>
              {t("admin.workbench.draft.conflict.load")}
            </Button>
          </>
        }
      >
        <p>{t("admin.workbench.draft.conflict.body")}</p>
        <p>{t("admin.workbench.draft.conflict.loadHint")}</p>
        {dirty && <p>{t("admin.workbench.draft.conflict.keepHint")}</p>}
      </WorkbenchDialog>
    </div>
  );
}

/**
 * `/admin/workbench/:id`: a draft of the pack workbench (task 0016a, step
 * 13) with its file tree, the editor of one file, saving with optimistic
 * locking, the check with its report and the alignment matrix, the import
 * and the download. While a media entry is `queued`, `processing` or
 * `failed` (task 0018), "Download as zip" stays disabled with a sentence
 * that names the reason, and the page reads the draft every two seconds
 * while an entry is converted. File content, paths and messages render as
 * text (ASVS 3.2.2).
 */
export function DraftPage() {
  const { t } = useTranslation();
  const { id = "" } = useParams();
  const query = useDraft(id);

  if (query.data !== undefined)
    return (
      <DraftView key={id} draft={query.data} reloadDraft={query.refetch} />
    );
  if (query.isPending)
    return <LoadingStatus text={t("admin.workbench.draft.loading")} />;
  return (
    <section className="max-w-3xl space-y-4">
      <h1 className="text-2xl font-semibold tracking-tight">
        {t("admin.workbench.draft.title")}
      </h1>
      <p role="alert" className={MUTED}>
        {query.error instanceof ApiError &&
        (query.error.status === 404 || query.error.status === 422)
          ? t("admin.workbench.draft.notFound")
          : t("admin.workbench.draft.loadFailed")}
      </p>
      <p className="text-sm">
        <Link to="/admin/workbench" className={linkClasses}>
          {t("admin.workbench.draft.back")}
        </Link>
      </p>
    </section>
  );
}
