import { useQueryClient } from "@tanstack/react-query";
import { useEffect, useState, type ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { Link } from "react-router";
import { ApiError, PASSKEY_REQUIRED_ERROR_CODE } from "../api/errors";
import { useSession } from "../auth/SessionProvider";
import { PasskeyRequiredContext, usePasskeyRequired } from "./passkeyRequired";

const isPasskeyRequired = (error: unknown) =>
  error instanceof ApiError && error.code === PASSKEY_REQUIRED_ERROR_CODE;

/**
 * Tracks whether the admin routes are closed to this admin: the session
 * flag `adminPasskeyRequired` says so up front, and a 403
 * `passkey_required` of any query or mutation says so as soon as it
 * arrives. The state lasts while the admin area stays mounted, so a visit
 * to `/account/security`, where the admin enrolls a passkey, starts afresh.
 */
export function PasskeyGateProvider({ children }: { children: ReactNode }) {
  const queryClient = useQueryClient();
  const { flags } = useSession();
  const [seen, setSeen] = useState(false);

  useEffect(() => {
    const unsubscribeQueries = queryClient
      .getQueryCache()
      .subscribe((event) => {
        if (isPasskeyRequired(event.query.state.error)) setSeen(true);
      });
    const unsubscribeMutations = queryClient
      .getMutationCache()
      .subscribe((event) => {
        if (isPasskeyRequired(event.mutation?.state.error)) setSeen(true);
      });
    return () => {
      unsubscribeQueries();
      unsubscribeMutations();
    };
  }, [queryClient]);

  return (
    <PasskeyRequiredContext.Provider value={flags.adminPasskeyRequired || seen}>
      {children}
    </PasskeyRequiredContext.Provider>
  );
}

/**
 * The notice that replaces the admin sections while a passkey is missing.
 * `level` is the level of its heading: 1 on its own, 2 below a page heading.
 */
export function PasskeyNotice({ level = 1 }: { level?: 1 | 2 }) {
  const { t } = useTranslation();
  const Heading = level === 1 ? "h1" : "h2";
  return (
    <section className="max-w-2xl" aria-labelledby="passkey-notice">
      <Heading
        id="passkey-notice"
        className={
          level === 1
            ? "text-2xl font-semibold tracking-tight"
            : "text-lg font-semibold"
        }
      >
        {t("admin.passkeyRequired.title")}
      </Heading>
      <p className="mt-4 text-gray-700 dark:text-gray-300">
        {t("admin.passkeyRequired.text")}
      </p>
      <p className="mt-6">
        <Link
          to="/account/security"
          className="font-medium text-accent-600 underline underline-offset-4 hover:text-accent-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent-500 dark:text-accent-100 dark:hover:text-accent-50"
        >
          {t("admin.passkeyRequired.link")}
        </Link>
      </p>
    </section>
  );
}

/**
 * Renders an admin section, or the passkey notice in its place while the
 * passkey gate is closed.
 */
export function AdminPasskeyGate({ children }: { children: ReactNode }) {
  return usePasskeyRequired() ? <PasskeyNotice /> : children;
}
