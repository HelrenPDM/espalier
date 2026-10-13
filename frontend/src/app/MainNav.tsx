import { Popover, PopoverButton, PopoverPanel } from "@headlessui/react";
import { Bars3Icon } from "@heroicons/react/20/solid";
import { useTranslation } from "react-i18next";
import { Link, useLocation } from "react-router";
import { ADMIN_ROLES } from "../admin/sections";
import { useSession } from "../auth/SessionProvider";
import { FOCUS_RING, navLinkClasses } from "./formStyles";

/** The key of a main section, also the key of its label below `layout.nav`. */
type SectionKey = "programs" | "credentials" | "policies" | "admin";

interface Section {
  key: SectionKey;
  to: string;
  /** Whether `pathname` lies in the section. */
  active: (pathname: string) => boolean;
}

/** A matcher for `path` and every path below it. */
const below = (path: string) => (pathname: string) =>
  pathname === path || pathname.startsWith(`${path}/`);

/**
 * The main sections in the order of the navigation. The program list `/`
 * and the pages of a program form one section.
 */
const SECTIONS: readonly Section[] = [
  {
    key: "programs",
    to: "/",
    active: (pathname) => pathname === "/" || below("/programs")(pathname),
  },
  {
    key: "credentials",
    to: "/me/credentials",
    active: below("/me/credentials"),
  },
  { key: "policies", to: "/policies", active: below("/policies") },
  { key: "admin", to: "/admin", active: below("/admin") },
];

function SectionLinks({
  sections,
  className,
  onNavigate,
}: {
  sections: readonly Section[];
  className: string;
  onNavigate?: () => void;
}) {
  const { t } = useTranslation();
  const { pathname } = useLocation();
  return (
    <ul className={className}>
      {sections.map((section) => (
        <li key={section.key}>
          <Link
            to={section.to}
            aria-current={section.active(pathname) ? "page" : undefined}
            onClick={onNavigate}
            className={navLinkClasses}
          >
            {t(`layout.nav.${section.key}`)}
          </Link>
        </li>
      ))}
    </ul>
  );
}

/**
 * The main navigation of a signed-in session in the header: the programs,
 * the credentials and the policies (0012, 0013), and the admin area (0015)
 * for a session with one of `ADMIN_ROLES`. The section of the current path
 * carries `aria-current="page"`. From the `md` breakpoint up the links sit
 * in the header bar; below it the "Menu" button opens a panel with the same
 * links, which closes after a navigation, on Escape and on a click outside.
 * The entry of the admin area is convenience; the router guards and the
 * server decide (ASVS 8.3.1).
 */
export function MainNav() {
  const { t } = useTranslation();
  const { roles } = useSession();
  const staff = roles.some((role) => ADMIN_ROLES.includes(role));
  const sections = SECTIONS.filter(
    (section) => section.key !== "admin" || staff,
  );

  return (
    <nav aria-label={t("layout.nav.label")} className="md:flex-1">
      <SectionLinks
        sections={sections}
        className="hidden md:flex md:flex-wrap md:items-center md:gap-1"
      />
      <Popover className="md:hidden">
        <PopoverButton
          className={`flex items-center gap-1 rounded-md px-3 py-1.5 text-sm font-medium text-gray-900 hover:bg-gray-100 data-open:bg-gray-100 dark:text-gray-100 dark:hover:bg-gray-800 dark:data-open:bg-gray-800 ${FOCUS_RING}`}
        >
          <Bars3Icon aria-hidden="true" className="size-5" />
          {t("layout.nav.menu")}
        </PopoverButton>
        <PopoverPanel className="absolute inset-x-4 top-full z-20 mt-1 rounded-md border border-gray-200 bg-white p-2 shadow-lg focus:outline-none dark:border-gray-700 dark:bg-gray-900">
          {({ close }) => (
            <SectionLinks
              sections={sections}
              className="flex flex-col gap-1"
              onNavigate={() => close()}
            />
          )}
        </PopoverPanel>
      </Popover>
    </nav>
  );
}
