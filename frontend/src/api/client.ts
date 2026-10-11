import type { QueryClient } from "@tanstack/react-query";
import createClient, { type Client } from "openapi-fetch";
import { CSRF_ERROR_CODE, errorCode } from "./errors";
import type { paths } from "./paths";
import { queryClient as appQueryClient } from "./queryClient";
import { sessionQueryKey, sessionQueryOptions, type Session } from "./session";

export type ApiClient = Client<paths>;

const CSRF_HEADER = "x-csrf-token";
const MUTATING_METHODS = new Set(["POST", "PUT", "PATCH", "DELETE"]);

/**
 * The typed API client. Every POST, PUT, PATCH and DELETE request carries the
 * CSRF token of the cached session (ASVS 3.5.1). After a 403 with the code
 * `csrf`, the client refetches the session and repeats the request once with
 * the new token; the repeat bypasses the middleware, so a second 403 reaches
 * the caller unchanged. Any other 403, such as `cross_site_request` of the
 * Fetch Metadata plug, reaches the caller without a refetch. A 401, also as
 * the answer to the repeat, invalidates the session query.
 */
export function createApiClient(
  queryClient: QueryClient,
  fetchImpl: (input: Request) => Promise<Response> = globalThis.fetch,
): ApiClient {
  const client = createClient<paths>({
    baseUrl: "",
    credentials: "same-origin",
    fetch: fetchImpl,
  });
  const retries = new WeakMap<Request, Request>();
  const invalidateSession = () =>
    queryClient.invalidateQueries({ queryKey: sessionQueryKey });

  client.use({
    onRequest({ request }) {
      if (!MUTATING_METHODS.has(request.method)) return undefined;
      const token =
        queryClient.getQueryData<Session>(sessionQueryKey)?.csrfToken;
      if (token) request.headers.set(CSRF_HEADER, token);
      retries.set(request, request.clone());
      return undefined;
    },

    async onResponse({ request, response }) {
      const retry = retries.get(request);
      retries.delete(request);
      if (response.status === 401) {
        await invalidateSession();
        return undefined;
      }
      if (response.status !== 403 || retry === undefined) return undefined;
      if ((await errorCode(response)) !== CSRF_ERROR_CODE) return undefined;

      let session: Session;
      try {
        session = await queryClient.fetchQuery({
          ...sessionQueryOptions(client),
          staleTime: 0,
        });
      } catch {
        return undefined;
      }
      retry.headers.set(CSRF_HEADER, session.csrfToken);
      // The repeat bypasses the middleware, so its 401 is handled here.
      const repeated = await fetchImpl(retry);
      if (repeated.status === 401) await invalidateSession();
      return repeated;
    },
  });

  return client;
}

export const api = createApiClient(appQueryClient);
