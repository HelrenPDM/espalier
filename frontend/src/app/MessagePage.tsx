import { useTranslation } from "react-i18next";
import { Link } from "react-router";

/** A page with a heading, one paragraph and an optional link to `/`. */
export function MessagePage({
  title,
  text,
  homeLink = false,
}: {
  title: string;
  text: string;
  homeLink?: boolean;
}) {
  const { t } = useTranslation();
  return (
    <section className="max-w-2xl">
      <h1 className="text-2xl font-semibold tracking-tight">{title}</h1>
      <p className="mt-4 text-gray-700 dark:text-gray-300">{text}</p>
      {homeLink && (
        <p className="mt-6">
          <Link
            to="/"
            className="font-medium text-accent-600 underline underline-offset-4 hover:text-accent-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent-500 dark:text-accent-100 dark:hover:text-accent-50"
          >
            {t("pages.backHome")}
          </Link>
        </p>
      )}
    </section>
  );
}
