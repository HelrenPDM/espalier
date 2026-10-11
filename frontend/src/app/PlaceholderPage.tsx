import { useTranslation } from "react-i18next";
import { MessagePage } from "./MessagePage";

/**
 * Stands in for the pages of later tasks: credentials (0013) and the admin
 * area (0015).
 */
export type Placeholder = "credentials" | "credential" | "admin";

export function PlaceholderPage({ page }: { page: Placeholder }) {
  const { t } = useTranslation();
  return (
    <MessagePage
      title={t(`placeholders.${page}.title`)}
      text={t(`placeholders.${page}.text`)}
    />
  );
}
