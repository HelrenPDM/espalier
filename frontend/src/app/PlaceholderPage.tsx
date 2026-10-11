import { useTranslation } from "react-i18next";
import { MessagePage } from "./MessagePage";

/** Stands in for the pages of a later task: the admin area (0015). */
export type Placeholder = "admin";

export function PlaceholderPage({ page }: { page: Placeholder }) {
  const { t } = useTranslation();
  return (
    <MessagePage
      title={t(`placeholders.${page}.title`)}
      text={t(`placeholders.${page}.text`)}
    />
  );
}
