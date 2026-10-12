import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useApiClient } from "../apiClientContext";
import { credentialsQueryKey, requirementsQueryKey } from "../credentials";
import { unwrap } from "../errors";
import { policiesQueryKey } from "../policies";
import type { components } from "../schema";

/**
 * The policies of the admin area (task 0015, steps 2, 3 and 13): the
 * policies with create, change and delete, the versions of a policy, one
 * version with `refresh_due_count`, the drafts and their publication. The
 * policies page under `src/admin/policies/` reads them through these hooks.
 */
export type AdminPolicy = components["schemas"]["AdminPolicy"]["data"];
export type AdminPolicyFields =
  components["schemas"]["AdminPolicyRequest"]["policy"];
export type AdminPolicyVersion = components["schemas"]["AdminPolicyVersion"];
export type AdminPolicyVersionSummary =
  components["schemas"]["AdminPolicyVersionList"]["versions"][number];
export type AdminDraftFields = Pick<
  components["schemas"]["AdminPolicyVersionRequest"],
  "body" | "effective_from"
>;

export const adminPoliciesQueryKey = ["admin", "policies"] as const;
export const adminPolicyVersionsQueryKey = [
  "admin",
  "policy-versions",
] as const;

const versionsKey = (policyId: string) =>
  [...adminPolicyVersionsQueryKey, "list", policyId] as const;
const versionKey = (id: string) =>
  [...adminPolicyVersionsQueryKey, "one", id] as const;

/** A version without `published_at` is a draft. */
export const isDraft = (version: AdminPolicyVersionSummary) =>
  version.published_at === null;

/**
 * True for a draft whose policy has a published version with a higher
 * number: published, it would never become the current version, so the
 * server answers its publication with 409 `superseded` (step 3).
 */
export function isSuperseded(
  version: AdminPolicyVersionSummary,
  versions: readonly AdminPolicyVersionSummary[],
): boolean {
  return (
    isDraft(version) &&
    versions.some((other) => !isDraft(other) && other.number > version.number)
  );
}

/** The policies, ordered by key. */
export function useAdminPolicies() {
  const client = useApiClient();
  return useQuery({
    queryKey: adminPoliciesQueryKey,
    queryFn: async (): Promise<AdminPolicy[]> =>
      unwrap(await client.GET("/api/admin/policies")).data,
  });
}

/** Creates a policy with key and title. */
export function useCreatePolicy() {
  const client = useApiClient();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (policy: AdminPolicyFields): Promise<AdminPolicy> =>
      unwrap(await client.POST("/api/admin/policies", { body: { policy } }))
        .data,
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: adminPoliciesQueryKey }),
  });
}

/**
 * Changes key or title of a policy. A policy with a published version
 * keeps its key (409 `policy_in_use`).
 */
export function useUpdatePolicy() {
  const client = useApiClient();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({
      id,
      policy,
    }: {
      id: string;
      policy: Partial<AdminPolicyFields>;
    }): Promise<AdminPolicy> =>
      unwrap(
        await client.PUT("/api/admin/policies/{id}", {
          params: { path: { id } },
          body: { policy },
        }),
      ).data,
    onSuccess: (policy) =>
      Promise.all([
        queryClient.invalidateQueries({ queryKey: adminPoliciesQueryKey }),
        queryClient.invalidateQueries({ queryKey: versionsKey(policy.id) }),
        queryClient.invalidateQueries({ queryKey: policiesQueryKey }),
      ]),
  });
}

/**
 * Deletes a policy together with its drafts. A policy with a published
 * version answers 409 `policy_in_use`.
 */
export function useDeletePolicy() {
  const client = useApiClient();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (id: string): Promise<void> => {
      unwrap(
        await client.DELETE("/api/admin/policies/{id}", {
          params: { path: { id } },
        }),
      );
    },
    onSuccess: (_result, id) => {
      queryClient.removeQueries({ queryKey: versionsKey(id) });
      return queryClient.invalidateQueries({
        queryKey: adminPoliciesQueryKey,
      });
    },
  });
}

/** The versions of a policy, the highest number first. */
export function usePolicyVersions(policyId: string) {
  const client = useApiClient();
  return useQuery({
    queryKey: versionsKey(policyId),
    queryFn: async (): Promise<AdminPolicyVersionSummary[]> =>
      unwrap(
        await client.GET("/api/admin/policy-versions", {
          params: { query: { policy_id: policyId } },
        }),
      ).versions,
  });
}

/**
 * One version with `refresh_due_count`, the credentials that a
 * publication with `requires_refresher` would move to `refresh_due` now.
 * The count changes with every credential, so the hook always loads it
 * afresh when a component asks for it.
 */
export function usePolicyVersion(
  id: string,
  { enabled = true }: { enabled?: boolean } = {},
) {
  const client = useApiClient();
  return useQuery({
    enabled,
    staleTime: 0,
    gcTime: 0,
    queryKey: versionKey(id),
    queryFn: async (): Promise<AdminPolicyVersion> =>
      unwrap(
        await client.GET("/api/admin/policy-versions/{id}", {
          params: { path: { id } },
        }),
      ),
  });
}

/** Creates a draft of a policy with the next number. */
export function useCreateDraft() {
  const client = useApiClient();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({
      policyId,
      draft,
    }: {
      policyId: string;
      draft: AdminDraftFields;
    }): Promise<AdminPolicyVersion> =>
      unwrap(
        await client.POST("/api/admin/policy-versions", {
          body: { policy_id: policyId, ...draft },
        }),
      ),
    onSuccess: (version) =>
      queryClient.invalidateQueries({
        queryKey: versionsKey(version.policy_id),
      }),
  });
}

/**
 * Changes body and effective date of a draft. A published version answers
 * 409 `published`; the versions load again after every answer, so the
 * list shows the state of the server.
 */
export function useUpdateDraft() {
  const client = useApiClient();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({
      version,
      draft,
    }: {
      version: Pick<AdminPolicyVersionSummary, "id" | "policy_id">;
      draft: AdminDraftFields;
    }): Promise<AdminPolicyVersion> =>
      unwrap(
        await client.PUT("/api/admin/policy-versions/{id}", {
          params: { path: { id: version.id } },
          body: draft,
        }),
      ),
    onSettled: (_result, _error, { version }) =>
      queryClient.invalidateQueries({
        queryKey: versionsKey(version.policy_id),
      }),
  });
}

/**
 * Publishes a draft with `requires_refresher`. A published version answers
 * 409 `published`, a draft below a published version 409 `superseded`;
 * the versions load again after every answer. A publication changes the
 * current version that learners read and can move credentials to
 * `refresh_due`, so it also invalidates the learner's policies,
 * requirements and credentials.
 */
export function usePublishDraft() {
  const client = useApiClient();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({
      version,
      requiresRefresher,
    }: {
      version: Pick<AdminPolicyVersionSummary, "id" | "policy_id">;
      requiresRefresher: boolean;
    }): Promise<AdminPolicyVersion> =>
      unwrap(
        await client.POST("/api/admin/policy-versions/{id}/publish", {
          params: { path: { id: version.id } },
          body: { requires_refresher: requiresRefresher },
        }),
      ),
    onSuccess: () =>
      Promise.all([
        queryClient.invalidateQueries({ queryKey: policiesQueryKey }),
        queryClient.invalidateQueries({ queryKey: requirementsQueryKey }),
        queryClient.invalidateQueries({ queryKey: credentialsQueryKey }),
      ]),
    onSettled: (_result, _error, { version }) =>
      queryClient.invalidateQueries({
        queryKey: versionsKey(version.policy_id),
      }),
  });
}
