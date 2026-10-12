import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { useApiClient } from "../apiClientContext";
import { unwrap } from "../errors";
import type { components } from "../schema";

/**
 * The audit log of the admin area (task 0015, steps 8 and 18): pages of 50
 * events, the newest first, filtered by action and actor id.
 */
export type AdminAuditEventList = components["schemas"]["AdminAuditEventList"];
export type AdminAuditEvent = AdminAuditEventList["events"][number];

export interface AuditFilters {
  /** An exact action, such as `user.disabled`. */
  action?: string;
  /** The id of an actor. */
  actorId?: string;
  /** The page, from 1. */
  page: number;
}

export const adminAuditQueryKey = ["admin", "audit"] as const;

/**
 * `GET /api/admin/audit?action=&actor_id=&page=`. A filter without a value
 * stays out of the query. The previous page stays visible while the next
 * loads.
 */
export function useAuditEvents({ action, actorId, page }: AuditFilters) {
  const client = useApiClient();
  return useQuery({
    queryKey: [...adminAuditQueryKey, { action, actorId, page }],
    placeholderData: keepPreviousData,
    queryFn: async (): Promise<AdminAuditEventList> =>
      unwrap(
        await client.GET("/api/admin/audit", {
          params: {
            query: {
              ...(action ? { action } : {}),
              ...(actorId ? { actor_id: actorId } : {}),
              page,
            },
          },
        }),
      ),
  });
}
