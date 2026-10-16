import type { QueryClient } from "@tanstack/react-query";
import createClient, { type Client } from "openapi-fetch";
import {
  CSRF_ERROR_CODE,
  ENROLLMENT_ERROR_CODE,
  RECENT_AUTH_ERROR_CODE,
  errorCode,
} from "./errors";
import type { paths } from "./paths";
import { queryClient as appQueryClient } from "./queryClient";
import { sessionQueryKey, sessionQueryOptions, type Session } from "./session";
import { requestStepUp } from "./stepUp";

export type ApiClient = Client<paths>;

/** The header that carries the CSRF token of the session (ASVS 3.5.1). */
export const CSRF_HEADER = "x-csrf-token";
const MUTATING_METHODS = new Set(["POST", "PUT", "PATCH", "DELETE"]);

/**
 * The answer to a 401 of any request. A 401 `unauthenticated` (or without
 * a code) means the session is gone, so every other cached query leaves
 * the cache (ASVS 14.3.1). The codes of a rejected credential
 * (`authentication_failed`, `invalid_credentials`, `ticket_invalid`) leave
 * the session of the browser as it was; the session query is refetched for
 * every 401, which shows an ended pending second factor. The API client
 * calls it for its answers, and the media upload of 0018, which sends its
 * body with `XMLHttpRequest`, for its own.
 */
export async function handleUnauthenticated(
  queryClient: QueryClient,
  response: Response,
): Promise<void> {
  const code = await errorCode(response);
  if (code === null || code === "unauthenticated")
    queryClient.removeQueries({
      predicate: (query) => query.queryKey[0] !== sessionQueryKey[0],
    });
  await queryClient.invalidateQueries({ queryKey: sessionQueryKey });
}

/**
 * The typed API client. Every POST, PUT, PATCH and DELETE request carries the
 * CSRF token of the cached session (ASVS 3.5.1). After a 403 with the code
 * `csrf`, the client refetches the session and repeats the request once with
 * the new token; the repeat bypasses the middleware, so a second 403 reaches
 * the caller unchanged. Any other 403, such as `cross_site_request` of the
 * Fetch Metadata plug, reaches the caller without a refetch.
 *
 * A 403 with `RECENT_AUTH_ERROR_CODE` asks for a step-up (task 0011, ASVS
 * 7.5.1). After a successful step-up, which refetched the session, the
 * client repeats the request once with the new CSRF token; after a closed
 * dialog, and for a second 403, the answer reaches the caller unchanged. A
 * 403 with `ENROLLMENT_ERROR_CODE` invalidates the session query, so
 * `RequireAuth` sends the person on to the enrollment wizard.
 *
 * A 401, also as the answer to a repeat, invalidates the session query; a
 * 401 `unauthenticated` also removes every other cached query (ASVS
 * 14.3.1).
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
  // Two clones per mutating request: one for the CSRF repeat, one for the
  // repeat after a step-up. A body can be read once per clone.
  const retries = new WeakMap<Request, { csrf: Request; stepUp: Request }>();

  const unauthenticated = (response: Response) =>
    handleUnauthenticated(queryClient, response);

  const repeat = async (retry: Request, csrfToken: string | undefined) => {
    if (csrfToken) retry.headers.set(CSRF_HEADER, csrfToken);
    // The repeat bypasses the middleware, so its 401 is handled here.
    const repeated = await fetchImpl(retry);
    if (repeated.status === 401) await unauthenticated(repeated);
    return repeated;
  };

  client.use({
    onRequest({ request }) {
      if (!MUTATING_METHODS.has(request.method)) return undefined;
      const token =
        queryClient.getQueryData<Session>(sessionQueryKey)?.csrfToken;
      if (token) request.headers.set(CSRF_HEADER, token);
      retries.set(request, {
        csrf: request.clone(),
        stepUp: request.clone(),
      });
      return undefined;
    },

    async onResponse({ request, response }) {
      const retry = retries.get(request);
      retries.delete(request);
      if (response.status === 401) {
        await unauthenticated(response);
        return undefined;
      }
      if (response.status !== 403) return undefined;

      const code = await errorCode(response);
      if (code === ENROLLMENT_ERROR_CODE) {
        await queryClient.invalidateQueries({ queryKey: sessionQueryKey });
        return undefined;
      }
      if (retry === undefined) return undefined;

      if (code === RECENT_AUTH_ERROR_CODE) {
        if (!(await requestStepUp())) return undefined;
        const token =
          queryClient.getQueryData<Session>(sessionQueryKey)?.csrfToken;
        return repeat(retry.stepUp, token);
      }

      if (code !== CSRF_ERROR_CODE) return undefined;
      let session: Session;
      try {
        session = await queryClient.fetchQuery({
          ...sessionQueryOptions(client),
          staleTime: 0,
        });
      } catch {
        return undefined;
      }
      return repeat(retry.csrf, session.csrfToken);
    },
  });

  return client;
}

export const api = createApiClient(appQueryClient);
