import { Menu, MenuButton, MenuItem, MenuItems } from "@headlessui/react";
import { ChevronDownIcon } from "@heroicons/react/20/solid";
import { useTranslation } from "react-i18next";
import { Link } from "react-router";
import { useSession } from "../auth/SessionProvider";

const ITEM_CLASSES =
  "block w-full px-4 py-2 text-left text-sm text-gray-900 data-focus:bg-accent-50 dark:text-gray-100 dark:data-focus:bg-accent-700";

/**
 * The display name of a signed-in session with the security settings of an
 * `mfa` session (0011) and the sign-out action (ASVS 7.4.4). The credentials
 * and the policies (0013) sit in the main navigation.
 */
export function UserMenu() {
  const { t } = useTranslation();
  const { user, sessionStrength, signOut } = useSession();
  if (user === null) return null;

  return (
    <Menu as="div" className="relative">
      <MenuButton className="flex items-center gap-1 rounded-md px-3 py-1.5 text-sm font-medium text-gray-900 hover:bg-gray-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent-500 dark:text-gray-100 dark:hover:bg-gray-800">
        {user.displayName ?? t("layout.account")}
        <ChevronDownIcon aria-hidden="true" className="size-4" />
      </MenuButton>
      <MenuItems className="absolute right-0 z-10 mt-2 w-48 rounded-md border border-gray-200 bg-white py-1 shadow-lg focus:outline-none dark:border-gray-700 dark:bg-gray-900">
        {sessionStrength === "mfa" && (
          <MenuItem>
            <Link to="/account/security" className={ITEM_CLASSES}>
              {t("account.menu")}
            </Link>
          </MenuItem>
        )}
        <MenuItem>
          <button
            type="button"
            onClick={() => void signOut()}
            className={ITEM_CLASSES}
          >
            {t("layout.signOut")}
          </button>
        </MenuItem>
      </MenuItems>
    </Menu>
  );
}
