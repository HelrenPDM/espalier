import { useTranslation } from "react-i18next";
import { NavLink, Outlet } from "react-router";
import { useSession } from "../auth/SessionProvider";
import { PasskeyGateProvider } from "./passkeyGate";
import { usePasskeyRequired } from "./passkeyRequired";
import { sectionsFor } from "./sections";

function AdminNavigation() {
  const { t } = useTranslation();
  const { roles } = useSession();
  const passkeyRequired = usePasskeyRequired();
  // A closed passkey gate replaces the admin sections with the notice.
  const sections = sectionsFor(roles).filter(
    (section) => !(passkeyRequired && section.role === "admin"),
  );

  return (
    <nav aria-label={t("admin.nav.label")} className="no-print md:w-48">
      <ul className="flex flex-wrap gap-2 md:flex-col md:gap-1">
        {sections.map((section) => (
          <li key={section.key}>
            <NavLink
              to={`/admin/${section.path}`}
              className="block rounded-md px-3 py-1.5 text-sm font-medium text-gray-700 hover:bg-gray-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent-500 aria-[current=page]:bg-accent-50 aria-[current=page]:text-accent-700 dark:text-gray-300 dark:hover:bg-gray-800 dark:aria-[current=page]:bg-accent-700 dark:aria-[current=page]:text-white"
            >
              {t(`admin.nav.${section.key}`)}
            </NavLink>
          </li>
        ))}
      </ul>
    </nav>
  );
}

/**
 * The frame of the admin area (task 0015, step 5): the navigation by role
 * beside the page of the current section.
 */
export function AdminLayout() {
  return (
    <PasskeyGateProvider>
      <div className="flex flex-col gap-8 md:flex-row">
        <AdminNavigation />
        <div className="min-w-0 flex-1">
          <Outlet />
        </div>
      </div>
    </PasskeyGateProvider>
  );
}
