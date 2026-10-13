import { useTranslation } from "react-i18next";
import { Link, Outlet } from "react-router";
import { useSession } from "../auth/SessionProvider";
import { LanguageSwitch } from "./LanguageSwitch";
import { MainNav } from "./MainNav";
import { productName } from "./product";
import { ThemeToggle } from "./ThemeToggle";
import { UserMenu } from "./UserMenu";

/**
 * The frame of every route: skip link, header, demo banner and `<main>`. The
 * header holds the main navigation for a full session (`mfa` or `demo`, the
 * sessions that `RequireAuth` admits). The bar wraps onto a second line when
 * its parts do not fit side by side, so it fits a width of 360 pixels.
 */
export function Layout() {
  const { t } = useTranslation();
  const { flags, user, sessionStrength } = useSession();
  const signedIn =
    user !== null && (sessionStrength === "mfa" || sessionStrength === "demo");

  return (
    <div className="flex min-h-screen flex-col">
      <a
        href="#main"
        className="sr-only focus:not-sr-only focus:absolute focus:top-2 focus:left-2 focus:z-50 focus:rounded-md focus:bg-white focus:px-4 focus:py-2 focus:font-medium focus:text-accent-700 focus:outline-2 focus:outline-accent-500 dark:focus:bg-gray-900 dark:focus:text-accent-100"
      >
        {t("layout.skipLink")}
      </a>
      <header className="border-b border-gray-200 dark:border-gray-800">
        {flags.demo && (
          <p className="bg-gray-800 px-4 py-2 text-center text-sm font-medium text-white dark:bg-gray-200 dark:text-gray-900">
            {t("layout.demoBanner")}
          </p>
        )}
        <div className="no-print relative mx-auto flex max-w-5xl flex-wrap items-center gap-x-4 gap-y-2 px-4 py-3">
          <Link
            to="/"
            className="rounded-md text-lg font-semibold text-gray-900 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent-500 dark:text-gray-100"
          >
            {productName}
          </Link>
          {signedIn && <MainNav />}
          <div className="ml-auto flex flex-wrap items-center justify-end gap-2">
            <LanguageSwitch />
            <ThemeToggle />
            <UserMenu />
          </div>
        </div>
      </header>
      <main
        id="main"
        tabIndex={-1}
        className="mx-auto w-full max-w-5xl flex-1 px-4 py-8 focus:outline-none"
      >
        <Outlet />
      </main>
    </div>
  );
}
