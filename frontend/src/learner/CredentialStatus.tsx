import { useTranslation } from "react-i18next";
import type { CredentialStatus as Status } from "../api/credentials";

/**
 * The status of a credential as text (README section 7, rule 7): active,
 * refresher due, expired or revoked. A refresher-due credential is still in
 * force.
 */
export function CredentialStatus({ status }: { status: Status }) {
  const { t } = useTranslation();
  return (
    <span
      data-status={status}
      className="inline-flex items-center rounded-full border border-gray-300 bg-gray-50 px-2 py-0.5 text-xs font-medium text-gray-800 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-200"
    >
      {t(`credentials.status.${status}`)}
    </span>
  );
}
