import {
  keepPreviousData,
  useMutation,
  useQuery,
  useQueryClient,
  type QueryClient,
} from "@tanstack/react-query";
import { useApiClient } from "../apiClientContext";
import { unwrap } from "../errors";
import type { components } from "../schema";

/**
 * The user administration of the admin area (task 0015, steps 4 and 12):
 * the paged user list, the lookup by exact address, the invitation and
 * the actions on one user or on every session. Every change pipes through
 * `:admin_write`, so the API client opens the step-up dialog on a 403
 * `reauth_required` and repeats the request once. Every change invalidates
 * the user list, the lookup and the list of grant holders, because each
 * of them shows status, roles or sessions of the changed user.
 */
export type AdminUser = components["schemas"]["AdminUser"];
export type AdminUserList = components["schemas"]["AdminUserList"];
export type AdminUserInvite = components["schemas"]["AdminUserInviteRequest"];
export type FactorResetResult = components["schemas"]["AdminFactorResetResult"];
export type AdminRole = AdminUser["roles"][number];

export const adminUsersQueryKey = ["admin", "users"] as const;
export const grantHoldersQueryKey = ["admin", "role-grants"] as const;

/** Invalidates every view of the admin area that lists users. */
export function invalidateUserViews(queryClient: QueryClient) {
  return Promise.all([
    queryClient.invalidateQueries({ queryKey: adminUsersQueryKey }),
    queryClient.invalidateQueries({ queryKey: grantHoldersQueryKey }),
  ]);
}

/**
 * `GET /api/admin/users?page=<n>`: 50 users per page, ordered by
 * `inserted_at`. The previous page stays visible while the next loads.
 */
export function useAdminUsers(page: number) {
  const client = useApiClient();
  return useQuery({
    queryKey: [...adminUsersQueryKey, "page", page],
    placeholderData: keepPreviousData,
    queryFn: async (): Promise<AdminUserList> =>
      unwrap(
        await client.GET("/api/admin/users", {
          params: { query: { page } },
        }),
      ),
  });
}

/**
 * `POST /api/admin/user-lookups`: the user with the exact address `email`,
 * with its grants, or a 404. The address travels in the body (ASVS
 * 14.2.1); it stays in the memory of the query cache and reaches no URL.
 * With `email` `null` the query sends nothing.
 */
export function useUserLookup(email: string | null) {
  const client = useApiClient();
  return useQuery({
    queryKey: [...adminUsersQueryKey, "lookup", email],
    enabled: email !== null,
    queryFn: async (): Promise<AdminUser> =>
      unwrap(
        await client.POST("/api/admin/user-lookups", {
          body: { email: email ?? "" },
        }),
      ),
  });
}

function useUserMutation<TVariables, TData>(
  mutationFn: (variables: TVariables) => Promise<TData>,
) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn,
    onSuccess: () => invalidateUserViews(queryClient),
  });
}

/** `POST /api/admin/users`: invites a local user (202). */
export function useInviteUser() {
  const client = useApiClient();
  return useUserMutation(async (invite: AdminUserInvite) =>
    unwrap(await client.POST("/api/admin/users", { body: invite })),
  );
}

/** `POST /api/admin/users/:id/invitation`: a new invitation (202). */
export function useResendInvitation() {
  const client = useApiClient();
  return useUserMutation(async (id: string) =>
    unwrap(
      await client.POST("/api/admin/users/{id}/invitation", {
        params: { path: { id } },
      }),
    ),
  );
}

/** `POST /api/admin/users/:id/disable`: answers the disabled user. */
export function useDisableUser() {
  const client = useApiClient();
  return useUserMutation(async (id: string): Promise<AdminUser> =>
    unwrap(
      await client.POST("/api/admin/users/{id}/disable", {
        params: { path: { id } },
      }),
    ),
  );
}

/** `DELETE /api/admin/users/:id/sessions` (204). */
export function useEndUserSessions() {
  const client = useApiClient();
  return useUserMutation(async (id: string) =>
    unwrap(
      await client.DELETE("/api/admin/users/{id}/sessions", {
        params: { path: { id } },
      }),
    ),
  );
}

/**
 * `POST /api/admin/users/:id/reset-factors` with `identity_verified: true`
 * (decision D11): answers whether a local account received a new
 * invitation.
 */
export function useResetFactors() {
  const client = useApiClient();
  return useUserMutation(async (id: string): Promise<FactorResetResult> =>
    unwrap(
      await client.POST("/api/admin/users/{id}/reset-factors", {
        params: { path: { id } },
        body: { identity_verified: true },
      }),
    ),
  );
}

/** `POST /api/admin/users/:id/reset-failure-counters` (204). */
export function useResetFailureCounters() {
  const client = useApiClient();
  return useUserMutation(async (id: string) =>
    unwrap(
      await client.POST("/api/admin/users/{id}/reset-failure-counters", {
        params: { path: { id } },
      }),
    ),
  );
}

/**
 * `DELETE /api/admin/sessions` (204): ends every session, also the one of
 * the acting admin. The caller refetches the session afterwards, so the
 * SPA moves to the sign-in.
 */
export function useEndAllSessions() {
  const client = useApiClient();
  return useUserMutation(async () =>
    unwrap(await client.DELETE("/api/admin/sessions")),
  );
}
