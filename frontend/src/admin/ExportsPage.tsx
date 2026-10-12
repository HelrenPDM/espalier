import { useId, useState, type FormEvent, type ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { isApiError } from "../api/admin/fieldErrors";
import { RECENT_AUTH_ERROR_CODE } from "../api/errors";
import {
  SCORM_VERSIONS,
  exportRemoved,
  useExport,
  useExportModules,
  useRequestExport,
  type ScormVersion,
} from "../api/exports";
import { usePrograms } from "../api/programs";
import { formatDateTime } from "../app/format";
import { AlertRegion, Button, FocusHeading } from "../app/forms";
import { FOCUS_RING, linkClasses } from "../app/formStyles";
import { LoadingStatus } from "../app/LoadingStatus";
import { useAdminErrorText } from "./adminErrors";

const SELECT = `mt-1 block w-full max-w-md rounded-md border border-gray-500 bg-white px-3 py-2 text-sm text-gray-900 aria-[invalid=true]:border-red-700 dark:bg-gray-900 dark:text-gray-100 dark:aria-[invalid=true]:border-red-400 ${FOCUS_RING}`;
const LABEL = "block text-sm font-medium text-gray-900 dark:text-gray-100";
const FIELD_ERROR = "mt-1 text-sm text-red-700 dark:text-red-300";
const MUTED = "text-gray-700 dark:text-gray-300";

/** An export requested on this page, with the language of its program. */
interface RequestedExport {
  id: string;
  lang: string | undefined;
}

/** A select with a visible label and an error connected to it. */
function SelectField({
  id,
  label,
  error,
  value,
  onChange,
  lang,
  children,
}: {
  id: string;
  label: string;
  error: string | null;
  value: string;
  onChange: (value: string) => void;
  lang?: string;
  children: ReactNode;
}) {
  const errorId = `${id}-error`;
  return (
    <div>
      <label htmlFor={id} className={LABEL}>
        {label}
      </label>
      <select
        id={id}
        lang={lang}
        value={value}
        onChange={(event) => onChange(event.target.value)}
        aria-invalid={error !== null ? true : undefined}
        aria-describedby={error !== null ? errorId : undefined}
        className={SELECT}
      >
        {children}
      </select>
      {error !== null && (
        <p id={errorId} className={FIELD_ERROR}>
          {error}
        </p>
      )}
    </div>
  );
}

/** A radio button with its label to the right. */
function RadioField({
  name,
  label,
  checked,
  onChange,
}: {
  name: string;
  label: string;
  checked: boolean;
  onChange: () => void;
}) {
  const id = useId();
  return (
    <div className="flex items-center gap-2">
      <input
        id={id}
        type="radio"
        name={name}
        checked={checked}
        onChange={onChange}
        className={`size-4 border-gray-500 ${FOCUS_RING}`}
      />
      <label htmlFor={id} className="text-sm text-gray-900 dark:text-gray-100">
        {label}
      </label>
    </div>
  );
}

/** The notice on the answer keys and on the record per person in the LMS. */
function PackageNotice() {
  const { t } = useTranslation();
  const headingId = useId();
  return (
    <section
      aria-labelledby={headingId}
      className="mt-6 max-w-3xl space-y-2 rounded-lg border-2 border-amber-600 bg-amber-50 p-4 text-gray-900 dark:border-amber-400 dark:bg-gray-900 dark:text-gray-100"
    >
      <h2
        id={headingId}
        className="text-lg font-semibold tracking-tight text-amber-900 dark:text-amber-200"
      >
        {t("admin.exports.notice.title")}
      </h2>
      <p className="text-sm">{t("admin.exports.notice.answerKeys")}</p>
      <p className="text-sm">{t("admin.exports.notice.results")}</p>
    </section>
  );
}

const ENTRY =
  "rounded-md border border-gray-300 px-4 py-3 text-sm dark:border-gray-700";

/**
 * One export of the list: module, program, version, the time of the
 * request and the status. A `done` export links its download, a `failed`
 * one shows the error text of the worker. An export whose read answers 404
 * was deleted on the server, for example after the retention period: it
 * shows a text that says so, and no download link. Module and program
 * titles carry the language of the program, each in an element of its own.
 */
function ExportEntry({ id, lang }: RequestedExport) {
  const { t, i18n } = useTranslation();
  const query = useExport(id);
  const exported = query.data;
  const removed = exportRemoved(query.error);

  if (exported === undefined) {
    let text = t("admin.exports.list.loading");
    if (removed) text = t("admin.exports.list.removed");
    else if (query.isError) text = t("admin.exports.list.loadFailed");
    return (
      <li aria-atomic="true" className={ENTRY}>
        <p className={MUTED}>{text}</p>
      </li>
    );
  }

  const { module, status } = exported;
  const version = t(`admin.exports.versions.${exported.scorm_version}`);
  const moduleLabel = (
    <>
      {t("admin.exports.list.module", { number: module.number })}{" "}
      <span lang={lang}>{module.title}</span>
    </>
  );

  return (
    <li
      aria-atomic="true"
      data-status={removed ? "removed" : status}
      className={ENTRY}
    >
      <h3 className="font-semibold text-gray-900 dark:text-gray-100">
        {moduleLabel}
      </h3>
      <p lang={lang} className={MUTED}>
        {module.program.title}
      </p>
      <dl className="mt-2 grid grid-cols-[max-content_1fr] gap-x-4 gap-y-1">
        <dt className="font-medium">{t("admin.exports.list.version")}</dt>
        <dd>{version}</dd>
        <dt className="font-medium">{t("admin.exports.list.requestedAt")}</dt>
        <dd>{formatDateTime(exported.inserted_at, i18n.language)}</dd>
        <dt className="font-medium">{t("admin.exports.list.status")}</dt>
        <dd>
          {removed
            ? t("admin.exports.status.removed")
            : t(`admin.exports.status.${status}`)}
        </dd>
      </dl>
      {removed && (
        <p className={`mt-2 ${MUTED}`}>{t("admin.exports.list.removed")}</p>
      )}
      {!removed && status === "done" && exported.download_path !== null && (
        <p className="mt-2">
          <a href={exported.download_path} download className={linkClasses}>
            {t("admin.exports.list.download")}{" "}
            <span className="sr-only">
              {moduleLabel}
              {", "}
              {version}
            </span>
          </a>
        </p>
      )}
      {!removed && status === "failed" && exported.error !== null && (
        <p className="mt-2 text-red-700 dark:text-red-300">
          {t("admin.exports.list.error")} <span>{exported.error}</span>
        </p>
      )}
      {query.isError && !removed && (
        <p className={`mt-2 ${MUTED}`}>{t("admin.exports.list.loadFailed")}</p>
      )}
    </li>
  );
}

/**
 * `/admin/exports` (task 0016, step 11): an author chooses a module of a
 * published program (`GET /api/programs` and `GET /api/programs/:slug`)
 * and a SCORM version, and requests the export with
 * `POST /api/admin/exports`. The route needs a second factor from the last
 * 10 minutes; the API client opens the step-up dialog on a 403
 * `reauth_required` and repeats the request once after a successful
 * step-up, so the page sees a 403 only after a closed dialog.
 *
 * The page lists the exports requested on it, newest first, in a status
 * region, and reads each one every two seconds while it is `queued` or
 * `running`. A notice states that the package contains the answer keys and
 * that the receiving LMS records results per person.
 */
export function ExportsPage() {
  const { t } = useTranslation();
  const errorText = useAdminErrorText();
  const programs = usePrograms();
  const request = useRequestExport();
  const formHeadingId = useId();
  const listHeadingId = useId();
  const programFieldId = useId();
  const moduleFieldId = useId();

  const [chosenSlug, setChosenSlug] = useState<string | null>(null);
  const slug = chosenSlug ?? programs.data?.[0]?.slug ?? null;
  const program = programs.data?.find((entry) => entry.slug === slug);
  const modules = useExportModules(slug);
  const lang = modules.data?.locale ?? program?.locale;

  const [chosenModule, setChosenModule] = useState("");
  const [version, setVersion] = useState<ScormVersion>("scorm12");
  const [moduleError, setModuleError] = useState<string | null>(null);
  const [formError, setFormError] = useState<string | null>(null);
  const [requested, setRequested] = useState<RequestedExport[]>([]);

  const focusModule = () =>
    requestAnimationFrame(() =>
      document.getElementById(moduleFieldId)?.focus(),
    );

  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (request.isPending) return;
    setFormError(null);
    if (chosenModule === "") {
      setModuleError(t("admin.exports.errors.moduleRequired"));
      focusModule();
      return;
    }
    setModuleError(null);
    try {
      const exported = await request.mutateAsync({
        module_id: chosenModule,
        scorm_version: version,
      });
      setRequested((current) => [{ id: exported.id, lang }, ...current]);
    } catch (failure) {
      if (isApiError(failure, 404)) {
        setChosenModule("");
        setModuleError(t("admin.exports.errors.moduleGone"));
        void modules.refetch();
        focusModule();
      } else if (isApiError(failure, 403, RECENT_AUTH_ERROR_CODE))
        setFormError(t("admin.exports.errors.reauthCancelled"));
      else if (isApiError(failure, 422))
        setFormError(t("admin.exports.errors.rejected"));
      else setFormError(errorText(failure));
    }
  };

  let programField: ReactNode;
  if (programs.isPending)
    programField = (
      <LoadingStatus text={t("admin.exports.form.programsLoading")} />
    );
  else if (programs.isError)
    programField = (
      <p role="alert" className={MUTED}>
        {t("admin.exports.form.programsFailed")}
      </p>
    );
  else if (slug === null)
    programField = (
      <p className={MUTED}>{t("admin.exports.form.noPrograms")}</p>
    );
  else
    programField = (
      <SelectField
        id={programFieldId}
        label={t("admin.exports.form.program")}
        error={null}
        value={slug}
        lang={program?.locale}
        onChange={(next) => {
          setChosenSlug(next);
          setChosenModule("");
          setModuleError(null);
          setFormError(null);
        }}
      >
        {programs.data.map((entry) => (
          <option key={entry.slug} value={entry.slug} lang={entry.locale}>
            {entry.title}
          </option>
        ))}
      </SelectField>
    );

  let moduleField: ReactNode = null;
  if (slug !== null) {
    if (modules.isPending)
      moduleField = (
        <LoadingStatus text={t("admin.exports.form.modulesLoading")} />
      );
    else if (modules.isError)
      moduleField = (
        <p role="alert" className={MUTED}>
          {t("admin.exports.form.modulesFailed")}
        </p>
      );
    else if (modules.data.modules.length === 0)
      moduleField = (
        <p className={MUTED}>{t("admin.exports.form.noModules")}</p>
      );
    else
      moduleField = (
        <SelectField
          id={moduleFieldId}
          label={t("admin.exports.form.module")}
          error={moduleError}
          value={chosenModule}
          lang={chosenModule === "" ? undefined : lang}
          onChange={(next) => {
            setChosenModule(next);
            setModuleError(null);
            setFormError(null);
          }}
        >
          <option value="">{t("admin.exports.form.chooseModule")}</option>
          {modules.data.modules.map((entry) => (
            <option key={entry.id} value={entry.id} lang={lang}>
              {`${entry.number}. ${entry.title}`}
            </option>
          ))}
        </SelectField>
      );
  }
  const canRequest = (modules.data?.modules.length ?? 0) > 0;

  return (
    <section>
      <FocusHeading>{t("admin.exports.title")}</FocusHeading>
      <p className={`mt-2 max-w-3xl ${MUTED}`}>{t("admin.exports.intro")}</p>
      <PackageNotice />

      <section aria-labelledby={formHeadingId} className="mt-8 max-w-xl">
        <h2 id={formHeadingId} className="text-xl font-semibold tracking-tight">
          {t("admin.exports.form.title")}
        </h2>
        <form
          noValidate
          onSubmit={(event) => void submit(event)}
          className="mt-4 space-y-4"
        >
          {programField}
          {moduleField}
          {canRequest && (
            <>
              <fieldset className="space-y-2">
                <legend className={LABEL}>
                  {t("admin.exports.form.version")}
                </legend>
                {SCORM_VERSIONS.map((value) => (
                  <RadioField
                    key={value}
                    name="scorm_version"
                    label={t(`admin.exports.versions.${value}`)}
                    checked={version === value}
                    onChange={() => setVersion(value)}
                  />
                ))}
              </fieldset>
              <AlertRegion>{formError}</AlertRegion>
              <div className="flex flex-wrap items-center gap-4">
                <Button type="submit" disabled={request.isPending}>
                  {t("admin.exports.form.submit")}
                </Button>
                {request.isPending && (
                  <LoadingStatus text={t("admin.exports.form.submitting")} />
                )}
              </div>
            </>
          )}
        </form>
      </section>

      <section aria-labelledby={listHeadingId} className="mt-10 max-w-3xl">
        <h2 id={listHeadingId} className="text-xl font-semibold tracking-tight">
          {t("admin.exports.list.title")}
        </h2>
        <p className={`mt-2 ${MUTED}`}>{t("admin.exports.list.intro")}</p>
        {/* A status region is atomic by default; each entry is atomic
            instead, so a change of status announces that entry only. */}
        <div
          role="status"
          aria-labelledby={listHeadingId}
          aria-atomic="false"
          className="mt-4"
        >
          {requested.length === 0 ? (
            <p className={MUTED}>{t("admin.exports.list.empty")}</p>
          ) : (
            <ul className="space-y-3">
              {requested.map((entry) => (
                <ExportEntry key={entry.id} {...entry} />
              ))}
            </ul>
          )}
        </div>
      </section>
    </section>
  );
}
