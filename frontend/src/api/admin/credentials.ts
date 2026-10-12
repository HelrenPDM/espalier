import { useMutation } from "@tanstack/react-query";
import { useApiClient } from "../apiClientContext";
import { unwrap } from "../errors";
import type { components } from "../schema";

/**
 * The revocation of a credential by an admin (task 0015, steps 6 and 12).
 * Admins see no credential list (README section 10: "revoke only"); the
 * id comes from the holder's credential page or from the `credential_id`
 * of a webhook event.
 */
export type AdminRevokedCredential =
  components["schemas"]["AdminRevokedCredential"];

/**
 * `POST /api/admin/credentials/:id/revoke`: answers the id, the
 * qualification code and the status `revoked`. An unknown id answers 404,
 * a revoked credential 409 `already_revoked`.
 */
export function useRevokeCredential() {
  const client = useApiClient();
  return useMutation({
    mutationFn: async (id: string): Promise<AdminRevokedCredential> =>
      unwrap(
        await client.POST("/api/admin/credentials/{id}/revoke", {
          params: { path: { id } },
        }),
      ),
  });
}
