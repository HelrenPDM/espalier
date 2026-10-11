import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useApiClient } from "./apiClientContext";
import { credentialsQueryKey, requirementsQueryKey } from "./credentials";
import { unwrap } from "./errors";
import type { components } from "./schema";

/**
 * The queries and the mutation of the policies (task 0013, step 23): the
 * current version of every policy with the acknowledgement state of the
 * signed-in user, the acknowledgement of a version, and the approved tool
 * list.
 */
export type CurrentPolicy =
  components["schemas"]["PolicyList"]["policies"][number];
export type Acknowledgement = components["schemas"]["AcknowledgementView"];
export type ApprovedTool =
  components["schemas"]["ApprovedToolList"]["tools"][number];

export const policiesQueryKey = ["policies"] as const;
export const approvedToolsQueryKey = ["approved-tools"] as const;

/** The current version of every policy, ordered by key. */
export function usePolicies() {
  const client = useApiClient();
  return useQuery({
    queryKey: policiesQueryKey,
    queryFn: async (): Promise<CurrentPolicy[]> =>
      unwrap(await client.GET("/api/policies")).policies,
  });
}

/**
 * Acknowledges a published policy version by its id. On success it writes
 * `acknowledged_at` into the cached policy list and invalidates the
 * policies, the requirements and the credentials, because an
 * acknowledgement can issue a credential.
 */
export function useAcknowledgePolicy() {
  const client = useApiClient();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (versionId: string): Promise<Acknowledgement> =>
      unwrap(
        await client.POST("/api/policy-versions/{id}/acknowledgements", {
          params: { path: { id: versionId } },
        }),
      ),
    onSuccess: (acknowledgement) => {
      queryClient.setQueryData<CurrentPolicy[]>(policiesQueryKey, (policies) =>
        policies?.map((policy) =>
          policy.id === acknowledgement.policy_version_id
            ? { ...policy, acknowledged_at: acknowledgement.acknowledged_at }
            : policy,
        ),
      );
      return Promise.all([
        queryClient.invalidateQueries({ queryKey: policiesQueryKey }),
        queryClient.invalidateQueries({ queryKey: requirementsQueryKey }),
        queryClient.invalidateQueries({ queryKey: credentialsQueryKey }),
      ]);
    },
  });
}

/** The approved tool list, ordered by position. */
export function useApprovedTools() {
  const client = useApiClient();
  return useQuery({
    queryKey: approvedToolsQueryKey,
    queryFn: async (): Promise<ApprovedTool[]> =>
      unwrap(await client.GET("/api/approved-tools")).tools,
  });
}
