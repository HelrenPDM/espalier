import type { ReactNode } from "react";
import type { Role } from "../api/session";
import { ForbiddenPage } from "../app/ForbiddenPage";
import { useSession } from "./SessionProvider";

/**
 * Renders its children when the session holds one of the roles in `anyOf`,
 * and the 403 page otherwise. It decides what the SPA shows; the server
 * checks every role (ASVS 8.3.1).
 */
export function RequireRole({
  anyOf,
  children,
}: {
  anyOf: readonly Role[];
  children: ReactNode;
}) {
  const { roles } = useSession();
  if (!anyOf.some((role) => roles.includes(role))) return <ForbiddenPage />;
  return children;
}
