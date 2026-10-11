import { useTranslation } from "react-i18next";
import { Link } from "react-router";
import { formatDate } from "../app/format";
import { linkClasses } from "../app/formStyles";
import { LoadingStatus } from "../app/LoadingStatus";
import { useCredentials } from "../api/credentials";
import { formatDay } from "../player/format";
import { CredentialStatus } from "./CredentialStatus";

/**
 * `/me/credentials` (task 0013, step 23): the credentials of the signed-in
 * user, the newest first, each with its qualification, status, issue date
 * and validity, and a link to its page. A credential names tasks (README
 * section 2, principle 2), so the list shows no score.
 */
export function CredentialListPage() {
  const { t, i18n } = useTranslation();
  const credentials = useCredentials();

  return (
    <section className="max-w-3xl">
      <h1 className="text-2xl font-semibold tracking-tight">
        {t("credentials.title")}
      </h1>
      {credentials.isPending ? (
        <div className="mt-4">
          <LoadingStatus text={t("credentials.loading")} />
        </div>
      ) : credentials.isError ? (
        <p role="alert" className="mt-4 text-gray-700 dark:text-gray-300">
          {t("credentials.loadFailed")}
        </p>
      ) : credentials.data.length === 0 ? (
        <p className="mt-4 text-gray-700 dark:text-gray-300">
          {t("credentials.empty")}
        </p>
      ) : (
        <ul className="mt-6 space-y-4">
          {credentials.data.map((credential) => (
            <li
              key={credential.id}
              className="rounded-lg border border-gray-200 p-4 dark:border-gray-700"
            >
              <div className="flex flex-wrap items-center justify-between gap-2">
                <Link
                  to={`/me/credentials/${credential.id}`}
                  lang={credential.locale}
                  className={`text-lg ${linkClasses}`}
                >
                  {credential.qualification_title}
                </Link>
                <CredentialStatus status={credential.status} />
              </div>
              <dl className="mt-2 grid grid-cols-[auto_minmax(0,1fr)] gap-x-4 gap-y-1 text-sm text-gray-700 dark:text-gray-300">
                <dt className="font-medium">{t("credentials.issued")}</dt>
                <dd>{formatDate(credential.issued_at, i18n.language)}</dd>
                <dt className="font-medium">{t("credentials.validUntil")}</dt>
                <dd>
                  {credential.valid_until === null
                    ? t("credentials.noExpiry")
                    : formatDay(credential.valid_until, i18n.language)}
                </dd>
              </dl>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
