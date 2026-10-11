import { useTranslation } from "react-i18next";
import { MessagePage } from "./MessagePage";

export function NotFoundPage() {
  const { t } = useTranslation();
  return (
    <MessagePage
      title={t("pages.notFound.title")}
      text={t("pages.notFound.text")}
      homeLink
    />
  );
}
