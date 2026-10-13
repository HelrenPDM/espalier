import { useTranslation } from "react-i18next";
import { NavLink, Outlet } from "react-router";
import { navLinkClasses } from "../app/formStyles";
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
            <NavLink to={`/admin/${section.path}`} className={navLinkClasses}>
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
