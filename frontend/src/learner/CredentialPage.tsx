import { PrinterIcon } from "@heroicons/react/20/solid";
import { useTranslation } from "react-i18next";
import { useParams } from "react-router";
import { Breadcrumbs } from "../app/Breadcrumbs";
import { formatDate } from "../app/format";
import { buttonClasses } from "../app/formStyles";
import { LoadingStatus } from "../app/LoadingStatus";
import { useCredential } from "../api/credentials";
import { ApiError } from "../api/errors";
import { formatDay } from "../player/format";
import { CredentialStatus } from "./CredentialStatus";

const isNotFound = (error: unknown) =>
  error instanceof ApiError && (error.status === 404 || error.status === 422);

/**
 * The breadcrumbs from the credential list to the page `label`; `lang` is
 * the language of a qualification title.
 */
function CredentialTrail({ label, lang }: { label: string; lang?: string }) {
  const { t } = useTranslation();
  return (
    <Breadcrumbs
      className="mb-4"
      items={[
        { label: t("credentials.title"), to: "/me/credentials" },
        { label, lang },
      ]}
    />
  );
}

/**
 * `/me/credentials/:id` (task 0013, step 23): one credential of the
 * signed-in user with qualification title, holder, status, issue date,
 * validity and the tasks it unlocks, as issued (README section 2,
 * principle 2). It shows no score, no percentage and no comparison with
 * other people, and it prints on A4 without the navigation. Any id that is
 * not one of the user's credentials answers 404 (ASVS 8.2.2). The
 * qualification title and the tasks carry the language of the program. The
 * breadcrumbs lead back to the credential list.
 */
export function CredentialPage() {
  const { t, i18n } = useTranslation();
  const { id = "" } = useParams();
  const credential = useCredential(id);

  if (credential.isPending)
    return (
      <section className="max-w-3xl">
        <CredentialTrail label={t("credentials.detailTitle")} />
        <h1 className="text-2xl font-semibold tracking-tight">
          {t("credentials.detailTitle")}
        </h1>
        <div className="mt-4">
          <LoadingStatus text={t("credentials.loadingOne")} />
        </div>
      </section>
    );

  if (credential.isError)
    return (
      <section className="max-w-3xl">
        <CredentialTrail
          label={
            isNotFound(credential.error)
              ? t("credentials.notFoundTitle")
              : t("credentials.detailTitle")
          }
        />
        <h1 className="text-2xl font-semibold tracking-tight">
          {isNotFound(credential.error)
            ? t("credentials.notFoundTitle")
            : t("credentials.detailTitle")}
        </h1>
        <p role="alert" className="mt-4 text-gray-700 dark:text-gray-300">
          {isNotFound(credential.error)
            ? t("credentials.notFound")
            : t("credentials.loadFailedOne")}
        </p>
      </section>
    );

  const {
    qualification_title: title,
    locale,
    holder_display_name: holder,
    status,
    issued_at: issuedAt,
    valid_until: validUntil,
    unlocks_snapshot: unlocks,
  } = credential.data;

  return (
    <article className="credential-sheet max-w-3xl">
      <CredentialTrail label={title} lang={locale} />
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <p className="text-sm font-medium text-gray-700 dark:text-gray-300">
            {t("credentials.kicker")}
          </p>
          <h1
            lang={locale}
            className="mt-1 text-2xl font-semibold tracking-tight"
          >
            {title}
          </h1>
        </div>
        <button
          type="button"
          onClick={() => window.print()}
          className={`no-print inline-flex items-center gap-2 ${buttonClasses("secondary")}`}
        >
          <PrinterIcon aria-hidden="true" className="size-4" />
          {t("credentials.print")}
        </button>
      </div>

      <dl className="mt-6 grid grid-cols-[auto_minmax(0,1fr)] gap-x-6 gap-y-2">
        <dt className="font-medium">{t("credentials.holder")}</dt>
        <dd>{holder ?? t("credentials.noDisplayName")}</dd>
        <dt className="font-medium">{t("credentials.statusLabel")}</dt>
        <dd>
          <CredentialStatus status={status} />
        </dd>
        <dt className="font-medium">{t("credentials.issued")}</dt>
        <dd>{formatDate(issuedAt, i18n.language)}</dd>
        <dt className="font-medium">{t("credentials.validUntil")}</dt>
        <dd>
          {validUntil === null
            ? t("credentials.noExpiry")
            : formatDay(validUntil, i18n.language)}
        </dd>
      </dl>
      {status !== "active" && (
        <p className="mt-4 text-sm text-gray-700 dark:text-gray-300">
          {t(`credentials.statusNote.${status}`)}
        </p>
      )}

      <section aria-labelledby="credential-unlocks" className="mt-8">
        <h2
          id="credential-unlocks"
          className="text-xl font-semibold tracking-tight"
        >
          {t("credentials.unlocks")}
        </h2>
        {unlocks.length === 0 ? (
          <p className="mt-2 text-gray-700 dark:text-gray-300">
            {t("credentials.noUnlocks")}
          </p>
        ) : (
          <ul lang={locale} className="mt-3 list-disc space-y-1 pl-5">
            {unlocks.map((task) => (
              <li key={task}>{task}</li>
            ))}
          </ul>
        )}
      </section>
    </article>
  );
}
