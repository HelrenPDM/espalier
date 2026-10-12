import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useApiClient } from "../apiClientContext";
import { unwrap } from "../errors";
import type { components } from "../schema";

/**
 * The machine clients of the integration API (task 0015, steps 3 and 16).
 * The answer of a create carries the bearer token once; the mutation sets
 * `gcTime: 0`, so the token leaves the mutation cache once the page resets
 * the mutation, and it never reaches a query.
 */
export type AdminApiClient =
  components["schemas"]["AdminApiClientList"]["clients"][number];
export type AdminApiClientCreated =
  components["schemas"]["AdminApiClientCreated"];
export type AdminApiClientRequest =
  components["schemas"]["AdminApiClientRequest"];
export type ApiClientScope = AdminApiClientRequest["scopes"][number];

export const API_CLIENT_SCOPES: readonly ApiClientScope[] = [
  "credentials:read",
];

export const adminApiClientsQueryKey = ["admin", "api-clients"] as const;

/** `GET /api/admin/api-clients`. */
export function useAdminApiClients() {
  const client = useApiClient();
  return useQuery({
    queryKey: adminApiClientsQueryKey,
    queryFn: async (): Promise<AdminApiClient[]> =>
      unwrap(await client.GET("/api/admin/api-clients")).clients,
  });
}

/** `POST /api/admin/api-clients {name, scopes}`: the client and its token (201). */
export function useCreateApiClient() {
  const client = useApiClient();
  const queryClient = useQueryClient();
  return useMutation({
    gcTime: 0,
    mutationFn: async (
      request: AdminApiClientRequest,
    ): Promise<AdminApiClientCreated> =>
      unwrap(await client.POST("/api/admin/api-clients", { body: request })),
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: adminApiClientsQueryKey }),
  });
}

/** `DELETE /api/admin/api-clients/:id` (204). */
export function useDeleteApiClient() {
  const client = useApiClient();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) =>
      unwrap(
        await client.DELETE("/api/admin/api-clients/{id}", {
          params: { path: { id } },
        }),
      ),
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: adminApiClientsQueryKey }),
  });
}
