import { useQuery } from "@tanstack/react-query";
import { api } from "./client";
import { sessionQueryOptions } from "./session";

export function useSessionQuery() {
  return useQuery(sessionQueryOptions(api));
}

/** Sends `DELETE /api/session` and returns the response. */
export async function deleteSession(): Promise<Response> {
  const { response } = await api.DELETE("/api/session");
  return response;
}
