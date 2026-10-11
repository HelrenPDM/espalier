import { useQuery } from "@tanstack/react-query";
import type { ApiClient } from "./client";
import { useApiClient } from "./apiClientContext";
import { sessionQueryOptions } from "./session";

export function useSessionQuery() {
  return useQuery(sessionQueryOptions(useApiClient()));
}

/**
 * Sends `DELETE /api/session` and returns the `logout_url` of a 200 answer
 * (an OIDC session whose provider has an end-session endpoint, 0006 step
 * 13), or `null` for a 204. Throws for every other answer.
 */
export async function deleteSession(client: ApiClient): Promise<string | null> {
  const { data, response } = await client.DELETE("/api/session");
  if (!response.ok)
    throw new Error(`DELETE /api/session answered ${response.status}`);
  return response.status === 200 && data ? data.logout_url : null;
}
