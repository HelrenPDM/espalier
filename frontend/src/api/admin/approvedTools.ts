import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useApiClient } from "../apiClientContext";
import { unwrap } from "../errors";
import { approvedToolsQueryKey } from "../policies";
import type { components } from "../schema";

/**
 * The approved tool list of the admin area (task 0015, steps 2 and 14):
 * the list, and adding, changing and deleting a tool. Every change also
 * invalidates the learner's list of `GET /api/approved-tools`.
 */
export type AdminApprovedTool =
  components["schemas"]["AdminApprovedTool"]["data"];
export type AdminApprovedToolFields =
  components["schemas"]["AdminApprovedToolRequest"]["approved_tool"];
export type ApprovedToolStatus = AdminApprovedTool["status"];

export const APPROVED_TOOL_STATUSES: readonly ApprovedToolStatus[] = [
  "approved",
  "restricted",
  "not_approved",
];

export const adminApprovedToolsQueryKey = ["admin", "approved-tools"] as const;

/** The tools, ordered by position. */
export function useAdminApprovedTools() {
  const client = useApiClient();
  return useQuery({
    queryKey: adminApprovedToolsQueryKey,
    queryFn: async (): Promise<AdminApprovedTool[]> =>
      unwrap(await client.GET("/api/admin/approved-tools")).data,
  });
}

function useInvalidateTools() {
  const queryClient = useQueryClient();
  return () =>
    Promise.all([
      queryClient.invalidateQueries({ queryKey: adminApprovedToolsQueryKey }),
      queryClient.invalidateQueries({ queryKey: approvedToolsQueryKey }),
    ]);
}

/** Adds a tool; the body is `{"approved_tool": {...}}`. */
export function useCreateApprovedTool() {
  const client = useApiClient();
  const invalidate = useInvalidateTools();
  return useMutation({
    mutationFn: async (
      tool: AdminApprovedToolFields,
    ): Promise<AdminApprovedTool> =>
      unwrap(
        await client.POST("/api/admin/approved-tools", {
          body: { approved_tool: tool },
        }),
      ).data,
    onSuccess: invalidate,
  });
}

/** Changes a tool; the body is `{"approved_tool": {...}}` with the changed fields. */
export function useUpdateApprovedTool() {
  const client = useApiClient();
  const invalidate = useInvalidateTools();
  return useMutation({
    mutationFn: async ({
      id,
      tool,
    }: {
      id: string;
      tool: Partial<AdminApprovedToolFields>;
    }): Promise<AdminApprovedTool> =>
      unwrap(
        await client.PUT("/api/admin/approved-tools/{id}", {
          params: { path: { id } },
          body: { approved_tool: tool },
        }),
      ).data,
    onSuccess: invalidate,
  });
}

/** Deletes a tool. */
export function useDeleteApprovedTool() {
  const client = useApiClient();
  const invalidate = useInvalidateTools();
  return useMutation({
    mutationFn: async (id: string): Promise<void> => {
      unwrap(
        await client.DELETE("/api/admin/approved-tools/{id}", {
          params: { path: { id } },
        }),
      );
    },
    onSuccess: invalidate,
  });
}
