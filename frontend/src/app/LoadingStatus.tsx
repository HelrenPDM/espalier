import { useTranslation } from "react-i18next";

/** The status line while the session or a page's data loads. */
export function LoadingStatus() {
  const { t } = useTranslation();
  return (
    <p role="status" className="text-gray-700 dark:text-gray-300">
      {t("auth.loading")}
    </p>
  );
}
