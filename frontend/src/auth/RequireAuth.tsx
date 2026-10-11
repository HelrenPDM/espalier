import type { ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { Navigate, useLocation } from "react-router";
import { useSession } from "./SessionProvider";

/**
 * Renders its children for a full session (`mfa` or `demo`). Every other
 * state, among them a pending second factor and enrollment and recovery
 * sessions, goes to `/sign-in` with the current path in `return_to`; 0011
 * continues those flows there. While the session loads, nothing redirects.
 * The server checks every request on its own.
 */
export function RequireAuth({ children }: { children: ReactNode }) {
  const { t } = useTranslation();
  const { loading, user, sessionStrength } = useSession();
  const location = useLocation();

  if (loading) {
    return (
      <p role="status" className="text-gray-700 dark:text-gray-300">
        {t("auth.loading")}
      </p>
    );
  }
  if (
    user !== null &&
    (sessionStrength === "mfa" || sessionStrength === "demo")
  )
    return children;

  const returnTo = encodeURIComponent(location.pathname + location.search);
  return <Navigate to={`/sign-in?return_to=${returnTo}`} replace />;
}
