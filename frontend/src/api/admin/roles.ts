import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useApiClient } from "../apiClientContext";
import { unwrap } from "../errors";
import type { components } from "../schema";
import {
  grantHoldersQueryKey,
  invalidateUserViews,
  type AdminUser,
} from "./users";

/**
 * Role grants of the admin area (task 0015, steps 3 and 15): the users who
 * hold a grant beyond `learner`, and adding and removing `manual` grants.
 * Both changes end every session of the affected user (README section
 * 6.5). The lookup of one user by address is `useUserLookup` of
 * `users.ts`, whose answer carries the grants.
 */
export type AdminRoleGrant = components["schemas"]["AdminRoleGrant"];
export type GrantableRole =
  components["schemas"]["AdminRoleGrantRequest"]["role"];
export type UserGrant = AdminUser["grants"][number];

/** The roles an admin grants, in the order of the role select. */
export const GRANTABLE_ROLES: readonly GrantableRole[] = [
  "facilitator",
  "author",
  "registrar",
  "analyst",
  "admin",
];

/** `GET /api/admin/role-grants`: the users with a grant beyond `learner`. */
export function useGrantHolders() {
  const client = useApiClient();
  return useQuery({
    queryKey: grantHoldersQueryKey,
    queryFn: async (): Promise<AdminUser[]> =>
      unwrap(await client.GET("/api/admin/role-grants")).users,
  });
}

/** `POST /api/admin/role-grants {user_id, role}`: answers the grant (201). */
export function useGrantRole() {
  const client = useApiClient();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({
      userId,
      role,
    }: {
      userId: string;
      role: GrantableRole;
    }): Promise<AdminRoleGrant> =>
      unwrap(
        await client.POST("/api/admin/role-grants", {
          body: { user_id: userId, role },
        }),
      ),
    onSuccess: () => invalidateUserViews(queryClient),
  });
}

/**
 * `DELETE /api/admin/role-grants/:id` (204) for a `manual` grant; an
 * `idp_claim` grant answers 409 `idp_claim`.
 */
export function useRevokeGrant() {
  const client = useApiClient();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) =>
      unwrap(
        await client.DELETE("/api/admin/role-grants/{id}", {
          params: { path: { id } },
        }),
      ),
    onSuccess: () => invalidateUserViews(queryClient),
  });
}
