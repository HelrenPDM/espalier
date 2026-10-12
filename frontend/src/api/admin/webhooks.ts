import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useApiClient } from "../apiClientContext";
import { unwrap } from "../errors";
import type { components } from "../schema";

/**
 * The webhooks of credential events (task 0015, steps 2 and 16). The
 * generated routes keep the nested body `{"webhook": {...}}` and answer
 * `{"data": ...}`.
 */
export type AdminWebhook = components["schemas"]["AdminWebhook"]["data"];
export type AdminWebhookFields =
  components["schemas"]["AdminWebhookRequest"]["webhook"];
export type WebhookEvent = AdminWebhookFields["events"][number];

/** The four credential events of task 0013, in the order of the form. */
export const WEBHOOK_EVENTS: readonly WebhookEvent[] = [
  "credential.issued",
  "credential.refresh_due",
  "credential.expired",
  "credential.revoked",
];

export const adminWebhooksQueryKey = ["admin", "webhooks"] as const;

/** `GET /api/admin/webhooks`. */
export function useAdminWebhooks() {
  const client = useApiClient();
  return useQuery({
    queryKey: adminWebhooksQueryKey,
    queryFn: async (): Promise<AdminWebhook[]> =>
      unwrap(await client.GET("/api/admin/webhooks")).data,
  });
}

/**
 * `POST /api/admin/webhooks {"webhook": {...}}` (201). A URL outside
 * `WEBHOOK_ALLOWED_HOSTS` answers 422 with `host_not_allowed` on `url`, and
 * an unset secret variable answers 422 `secret_env_unset`.
 */
export function useCreateWebhook() {
  const client = useApiClient();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (webhook: AdminWebhookFields): Promise<AdminWebhook> =>
      unwrap(await client.POST("/api/admin/webhooks", { body: { webhook } }))
        .data,
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: adminWebhooksQueryKey }),
  });
}

/** `DELETE /api/admin/webhooks/:id` (204). */
export function useDeleteWebhook() {
  const client = useApiClient();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) =>
      unwrap(
        await client.DELETE("/api/admin/webhooks/{id}", {
          params: { path: { id } },
        }),
      ),
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: adminWebhooksQueryKey }),
  });
}
