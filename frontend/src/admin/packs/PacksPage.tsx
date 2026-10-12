import { useId, useRef, useState, type FormEvent } from "react";
import { useTranslation } from "react-i18next";
import { useNavigate } from "react-router";
import { archiveReport, useUploadPack } from "../../api/admin/packs";
import { ApiError } from "../../api/errors";
import { AlertRegion, Button, FocusHeading } from "../../app/forms";
import { FOCUS_RING } from "../../app/formStyles";
import { LoadingStatus } from "../../app/LoadingStatus";
import { useErrorText } from "../../app/useErrorText";
import { ReportEntryList } from "./findings";

/**
 * `/admin/packs`: the upload form of content packs (task 0015, step 11).
 * The archive goes to `POST /api/admin/packs` as `multipart/form-data`;
 * after an upload the page moves to `/admin/packs/:id`, which shows the
 * status and the report of the import, also for a `failed` import. A 413,
 * a 415 and a 422 `archive_rejected` with its report stay on this page.
 */
export function PacksPage() {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const upload = useUploadPack();
  const errorText = useErrorText();
  const inputId = useId();
  const hintId = useId();
  const inputRef = useRef<HTMLInputElement>(null);
  const [file, setFile] = useState<File | null>(null);
  const [missing, setMissing] = useState(false);

  const submit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (upload.isPending) return;
    if (file === null) {
      setMissing(true);
      inputRef.current?.focus();
      return;
    }
    setMissing(false);
    upload.mutate(file, {
      onSuccess: (pack) => navigate(`/admin/packs/${pack.id}`),
    });
  };

  const error = upload.error;
  const rejected =
    error instanceof ApiError && error.status === 422
      ? archiveReport(error.body)
      : null;

  let failure = null;
  if (missing) failure = <p>{t("admin.packs.errors.noFile")}</p>;
  else if (error instanceof ApiError && error.status === 413)
    failure = <p>{t("admin.packs.errors.tooLarge")}</p>;
  else if (error instanceof ApiError && error.status === 415)
    failure = <p>{t("admin.packs.errors.unsupported")}</p>;
  else if (rejected !== null)
    failure = (
      <div className="space-y-2">
        <p>{t("admin.packs.errors.rejected")}</p>
        <ReportEntryList entries={rejected} />
      </div>
    );
  else if (error instanceof ApiError && error.status === 422)
    failure = <p>{t("admin.packs.errors.invalid")}</p>;
  else if (error !== null) failure = <p>{errorText(error)}</p>;

  return (
    <section className="max-w-3xl">
      <FocusHeading>{t("admin.packs.title")}</FocusHeading>
      <p className="mt-2 text-gray-700 dark:text-gray-300">
        {t("admin.packs.intro")}
      </p>
      <form className="mt-6 space-y-4" onSubmit={submit} noValidate>
        <div>
          <label
            htmlFor={inputId}
            className="block text-sm font-medium text-gray-900 dark:text-gray-100"
          >
            {t("admin.packs.file")}
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
              upload.reset();
            }}
            className={`mt-1 block w-full rounded-md border border-gray-500 bg-white px-3 py-2 text-sm text-gray-900 file:mr-3 file:rounded-md file:border-0 file:bg-gray-100 file:px-3 file:py-1 file:text-sm file:font-semibold file:text-gray-900 dark:bg-gray-900 dark:text-gray-100 dark:file:bg-gray-800 dark:file:text-gray-100 ${FOCUS_RING}`}
          />
          <p
            id={hintId}
            className="mt-1 text-sm text-gray-700 dark:text-gray-300"
          >
            {t("admin.packs.fileHint")}
          </p>
        </div>
        <AlertRegion>{failure}</AlertRegion>
        <div className="flex flex-wrap items-center gap-4">
          <Button type="submit" disabled={upload.isPending}>
            {t("admin.packs.upload")}
          </Button>
          {upload.isPending && (
            <LoadingStatus text={t("admin.packs.uploading")} />
          )}
        </div>
      </form>
    </section>
  );
}
