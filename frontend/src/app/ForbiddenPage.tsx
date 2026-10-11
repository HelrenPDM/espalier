import { useTranslation } from "react-i18next";
import { MessagePage } from "./MessagePage";

export function ForbiddenPage() {
  const { t } = useTranslation();
  return (
    <MessagePage
      title={t("pages.forbidden.title")}
      text={t("pages.forbidden.text")}
      homeLink
    />
  );
}
