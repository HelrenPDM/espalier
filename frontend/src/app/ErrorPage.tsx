import { useTranslation } from "react-i18next";
import { MessagePage } from "./MessagePage";

/**
 * The error element of the routes. It shows no detail of the error. Inside
 * the layout it fills `<main>`; `standalone` adds its own `<main>` for the
 * case that the layout itself failed.
 */
export function ErrorPage({ standalone = false }: { standalone?: boolean }) {
  const { t } = useTranslation();
  const page = (
    <MessagePage
      title={t("pages.error.title")}
      text={t("pages.error.text")}
      homeLink
    />
  );
  if (!standalone) return page;
  return (
    <main id="main" className="mx-auto w-full max-w-5xl px-4 py-8">
      {page}
    </main>
  );
}
