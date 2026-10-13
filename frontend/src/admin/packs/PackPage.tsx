import { useId, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import { Link, useNavigate, useParams } from "react-router";
import { usePackImport, type PackImport } from "../../api/admin/packs";
import { useCreateDraft } from "../../api/admin/workbench";
import { ApiError } from "../../api/errors";
import { formatDateTime } from "../../app/format";
import { AlertRegion, Button, StatusRegion } from "../../app/forms";
import { buttonClasses, linkClasses } from "../../app/formStyles";
import { LoadingStatus } from "../../app/LoadingStatus";
import { useStartErrorText } from "../workbench/startErrors";
import { AlignmentSection } from "./AlignmentSection";
import { ReportEntryList } from "./findings";
import { PublishDialog } from "./PublishDialog";

type BlockReason = "published" | "failed" | "alignment";

/**
 * Why "Publish" is disabled, or `null` when the import can be published:
 * only a `validated` import without an alignment error is publishable.
 */
function blockReason(pack: PackImport): BlockReason | null {
  if (pack.status === "published") return "published";
  if (pack.status !== "validated") return "failed";
  if (pack.alignment.errors.length > 0) return "alignment";
  return null;
}

/**
 * The validation report: the entries of the import report that do not
 * come from the alignment checks, with file and line. The entries with
 * `check` appear in the section "Alignment".
 */
function ValidationReport({ report }: { report: PackImport["report"] }) {
  const { t } = useTranslation();
  const headingId = useId();
  const errors = report.errors.filter((entry) => entry.check === undefined);
  const warnings = report.warnings.filter((entry) => entry.check === undefined);

  return (
    <section aria-labelledby={headingId} className="space-y-4">
      <h2 id={headingId} className="text-xl font-semibold tracking-tight">
        {t("admin.pack.report.title")}
      </h2>
      {errors.length === 0 && warnings.length === 0 ? (
        <p className="text-gray-700 dark:text-gray-300">
          {t("admin.pack.report.empty")}
        </p>
      ) : (
        <>
          {errors.length > 0 && (
            <div className="space-y-2">
              <h3 className="text-lg font-semibold tracking-tight">
                {t("admin.pack.report.errors", { count: errors.length })}
              </h3>
              <ReportEntryList entries={errors} />
            </div>
          )}
          {warnings.length > 0 && (
            <div className="space-y-2">
              <h3 className="text-lg font-semibold tracking-tight">
                {t("admin.pack.report.warnings", { count: warnings.length })}
              </h3>
              <ReportEntryList entries={warnings} />
            </div>
          )}
        </>
      )}
    </section>
  );
}

/** "Publish" with the sentence that names why it is disabled, and its dialog. */
function PublishControl({ pack }: { pack: PackImport }) {
  const { t } = useTranslation();
  const reasonId = useId();
  const doneRef = useRef<HTMLParagraphElement>(null);
  const [open, setOpen] = useState(false);
  const [published, setPublished] = useState(false);
  const reason = blockReason(pack);

  return (
    <div className="space-y-2">
      <div className="flex flex-wrap items-center gap-4">
        <Button
          onClick={() => setOpen(true)}
          disabled={reason !== null}
          aria-describedby={reason === null ? undefined : reasonId}
        >
          {t("admin.pack.publish.button")}
        </Button>
        {reason !== null && (
          <p id={reasonId} className="text-sm text-gray-700 dark:text-gray-300">
            {t(`admin.pack.publish.reason.${reason}`)}
          </p>
        )}
      </div>
      <StatusRegion>
        {published && (
          <p ref={doneRef} tabIndex={-1} className="focus:outline-none">
            {t("admin.pack.publish.done")}
          </p>
        )}
      </StatusRegion>
      <PublishDialog
        pack={pack}
        open={open}
        onClose={() => setOpen(false)}
        onPublished={() => {
          setOpen(false);
          setPublished(true);
          // The dialog returns focus to "Publish", which is disabled now.
          requestAnimationFrame(() => doneRef.current?.focus());
        }}
      />
    </div>
  );
}

/**
 * "Edit in the workbench" for an import with a payload (status `validated`
 * or `published`): it creates a draft from the import (task 0016a, step 12)
 * and moves to the draft. A failed start, such as a 409 `draft_limit`,
 * shows its sentence below the button.
 */
function WorkbenchControl({ pack }: { pack: PackImport }) {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const errorText = useStartErrorText();
  const create = useCreateDraft();

  const start = () => {
    if (create.isPending) return;
    create.mutate(
      { source: "import", pack_import_id: pack.id },
      { onSuccess: (draft) => navigate(`/admin/workbench/${draft.id}`) },
    );
  };

  return (
    <div className="space-y-2">
      <div className="flex flex-wrap items-center gap-4">
        <Button variant="secondary" onClick={start} disabled={create.isPending}>
          {t("admin.workbench.start.fromImport")}
        </Button>
        {create.isPending && (
          <LoadingStatus text={t("admin.workbench.start.creating")} />
        )}
      </div>
      <AlertRegion>
        {create.error === null ? null : errorText(create.error)}
      </AlertRegion>
    </div>
  );
}

function PackView({ pack }: { pack: PackImport }) {
  const { t, i18n } = useTranslation();

  return (
    <div className="max-w-5xl space-y-10">
      <div className="space-y-4">
        <p className="text-sm">
          <Link to="/admin/packs" className={linkClasses}>
            {t("admin.pack.back")}
          </Link>
        </p>
        <h1 className="text-2xl font-semibold tracking-tight">
          {pack.pack_key === null
            ? t("admin.pack.title")
            : t("admin.pack.heading", {
                key: pack.pack_key,
                version: pack.pack_version ?? "-",
              })}
        </h1>
        <dl className="grid grid-cols-[max-content_1fr] gap-x-4 gap-y-1 text-sm">
          <dt className="font-medium">{t("admin.pack.statusLabel")}</dt>
          <dd data-status={pack.status}>
            {t(`admin.pack.status.${pack.status}`)}
          </dd>
          <dt className="font-medium">{t("admin.pack.uploadedAt")}</dt>
          <dd>{formatDateTime(pack.inserted_at, i18n.language)}</dd>
          {pack.published_at !== null && (
            <>
              <dt className="font-medium">{t("admin.pack.publishedAt")}</dt>
              <dd>{formatDateTime(pack.published_at, i18n.language)}</dd>
            </>
          )}
        </dl>
        {pack.payload !== null && (
          <p>
            <Link
              to={`/admin/packs/${pack.id}/preview`}
              className={buttonClasses("secondary")}
            >
              {t("admin.pack.preview")}
            </Link>
          </p>
        )}
        {pack.status !== "failed" && <WorkbenchControl pack={pack} />}
        <PublishControl pack={pack} />
      </div>
      <ValidationReport report={pack.report} />
      <AlignmentSection alignment={pack.alignment} />
    </div>
  );
}

/**
 * `/admin/packs/:id`: one import with its status, the validation report
 * with file and line per error, the section "Alignment", the preview link
 * and the publication (task 0015, step 11), and "Edit in the workbench"
 * (task 0016a, step 12).
 */
export function PackPage() {
  const { t } = useTranslation();
  const { id = "" } = useParams();
  const query = usePackImport(id);

  if (query.isPending) return <LoadingStatus text={t("admin.pack.loading")} />;
  if (query.isError)
    return (
      <section className="max-w-3xl space-y-4">
        <h1 className="text-2xl font-semibold tracking-tight">
          {t("admin.pack.title")}
        </h1>
        <p role="alert" className="text-gray-700 dark:text-gray-300">
          {query.error instanceof ApiError &&
          (query.error.status === 404 || query.error.status === 422)
            ? t("admin.pack.notFound")
            : t("admin.pack.loadFailed")}
        </p>
        <p className="text-sm">
          <Link to="/admin/packs" className={linkClasses}>
            {t("admin.pack.back")}
          </Link>
        </p>
      </section>
    );
  return <PackView pack={query.data} />;
}
