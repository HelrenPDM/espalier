import { useId, useState, type FormEvent } from "react";
import { useTranslation } from "react-i18next";
import { useSearchParams } from "react-router";
import { formatDate } from "../../app/format";
import { Button, TextField } from "../../app/forms";
import { FOCUS_RING } from "../../app/formStyles";
import { LoadingStatus } from "../../app/LoadingStatus";
import {
  isQualificationCode,
  QUALIFICATION_CODE_MAX_LENGTH,
  useRegistrarCredentials,
  type RegistrarCredential,
} from "../../api/admin/registrar";
import { isApiError } from "../../api/admin/fieldErrors";
import { formatDay } from "../../player/format";

const CELL =
  "border-b border-gray-200 px-3 py-2 align-top text-gray-800 dark:border-gray-700 dark:text-gray-200";
const ROW_HEADER =
  "border-b border-gray-200 px-3 py-2 align-top font-medium text-gray-900 dark:border-gray-700 dark:text-gray-100";
const COLUMN_HEADER =
  "border-b border-gray-200 bg-gray-50 px-3 py-2 align-bottom font-semibold text-gray-900 dark:border-gray-700 dark:bg-gray-800 dark:text-gray-100";
const NOT_RECORDED = "text-gray-600 italic dark:text-gray-400";

/**
 * The credentials of one qualification in a table that scrolls sideways
 * inside a focusable region, so a keyboard user can scroll it. One row per
 * credential: a person who holds the code in two programs appears twice.
 */
function CredentialTable({
  code,
  credentials,
}: {
  code: string;
  credentials: RegistrarCredential[];
}) {
  const { t, i18n } = useTranslation();
  const headingId = useId();
  const countId = useId();

  return (
    <section className="mt-8">
      <h2 id={headingId} className="text-xl font-semibold tracking-tight">
        {t("admin.registrar.tableTitle", { code })}
      </h2>
      <p
        id={countId}
        className="mt-1 mb-4 text-sm text-gray-700 dark:text-gray-300"
      >
        {t("admin.registrar.count", { count: credentials.length })}
      </p>
      <div
        role="region"
        aria-labelledby={headingId}
        tabIndex={0}
        className={`overflow-x-auto rounded-lg border border-gray-200 dark:border-gray-700 ${FOCUS_RING}`}
      >
        <table
          aria-labelledby={headingId}
          aria-describedby={countId}
          className="min-w-full border-collapse text-left text-sm"
        >
          <thead>
            <tr>
              <th scope="col" className={COLUMN_HEADER}>
                {t("admin.registrar.name")}
              </th>
              <th scope="col" className={COLUMN_HEADER}>
                {t("admin.registrar.orgUnit")}
              </th>
              <th scope="col" className={COLUMN_HEADER}>
                {t("admin.registrar.status")}
              </th>
              <th scope="col" className={COLUMN_HEADER}>
                {t("admin.registrar.issuedAt")}
              </th>
              <th scope="col" className={COLUMN_HEADER}>
                {t("admin.registrar.validUntil")}
              </th>
            </tr>
          </thead>
          <tbody>
            {credentials.map((credential, index) => (
              // The list carries no id; one row per credential in the
              // order of the server.
              <tr key={index}>
                <th scope="row" className={ROW_HEADER}>
                  {credential.display_name ?? (
                    <span className={NOT_RECORDED}>
                      {t("admin.registrar.noDisplayName")}
                    </span>
                  )}
                </th>
                <td className={CELL}>
                  {credential.org_unit ?? (
                    <span className={NOT_RECORDED}>
                      {t("admin.registrar.noOrgUnit")}
                    </span>
                  )}
                </td>
                <td className={CELL} data-status={credential.status}>
                  {t(`credentials.status.${credential.status}`)}
                </td>
                <td className={`${CELL} whitespace-nowrap`}>
                  {formatDate(credential.issued_at, i18n.language)}
                </td>
                <td className={`${CELL} whitespace-nowrap`}>
                  {credential.valid_until === null
                    ? t("admin.registrar.noExpiry")
                    : formatDay(credential.valid_until, i18n.language)}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}

/** The answer for `code`: loading, the notice of a turned-off list, an error, empty or the table. */
function Credentials({ code }: { code: string }) {
  const { t } = useTranslation();
  const query = useRegistrarCredentials(code);

  if (query.isPending)
    return (
      <div className="mt-8">
        <LoadingStatus text={t("admin.registrar.loading")} />
      </div>
    );
  if (query.isError) {
    // The route answers 404 while REGISTRAR_ENABLED=false (README section 10).
    if (isApiError(query.error, 404))
      return (
        <section
          aria-labelledby="registrar-disabled"
          className="mt-8 max-w-2xl rounded-lg border border-gray-300 bg-gray-50 p-4 dark:border-gray-600 dark:bg-gray-800"
        >
          <h2 id="registrar-disabled" className="font-semibold">
            {t("admin.registrar.disabledTitle")}
          </h2>
          <p className="mt-1 text-gray-700 dark:text-gray-300">
            {t("admin.registrar.disabled")}
          </p>
        </section>
      );
    return (
      <p role="alert" className="mt-8 text-gray-700 dark:text-gray-300">
        {t("admin.registrar.loadFailed")}
      </p>
    );
  }
  if (query.data.length === 0)
    return (
      <p className="mt-8 text-gray-700 dark:text-gray-300">
        {t("admin.registrar.empty", { code })}
      </p>
    );
  return <CredentialTable code={code} credentials={query.data} />;
}

/**
 * `/admin/registrar` (task 0015, step 17): the registrar enters a
 * qualification code, and the page lists every credential of it with
 * display name, org unit, status, `issued_at` and `valid_until` through
 * `GET /api/registrar/credentials?qualification=<code>` (task 0013, step
 * 18). The code stays in the query `?qualification=`. While the instance
 * runs with `REGISTRAR_ENABLED=false`, the route answers 404 and the page
 * says that the credential list is turned off.
 */
export function RegistrarPage() {
  const { t } = useTranslation();
  const [searchParams, setSearchParams] = useSearchParams();
  const requested = searchParams.get("qualification");
  const code =
    requested !== null && isQualificationCode(requested) ? requested : null;
  const [value, setValue] = useState(requested ?? "");
  const [invalid, setInvalid] = useState(requested !== null && code === null);

  const submit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const next = value.trim();
    if (!isQualificationCode(next)) {
      setInvalid(true);
      return;
    }
    setInvalid(false);
    setValue(next);
    setSearchParams({ qualification: next });
  };

  return (
    <section>
      <h1 className="text-2xl font-semibold tracking-tight">
        {t("admin.registrar.title")}
      </h1>
      <p className="mt-2 max-w-3xl text-gray-700 dark:text-gray-300">
        {t("admin.registrar.intro")}
      </p>
      <form noValidate onSubmit={submit} className="mt-6 max-w-xl space-y-3">
        <TextField
          label={t("admin.registrar.codeLabel")}
          hint={t("admin.registrar.codeHint")}
          errors={invalid ? [t("admin.registrar.codeInvalid")] : []}
          name="qualification"
          value={value}
          onChange={(event) => setValue(event.target.value)}
          required
          maxLength={QUALIFICATION_CODE_MAX_LENGTH}
          autoComplete="off"
          spellCheck={false}
          autoCapitalize="off"
        />
        <Button type="submit">{t("admin.registrar.show")}</Button>
      </form>
      {code !== null && <Credentials code={code} />}
    </section>
  );
}
