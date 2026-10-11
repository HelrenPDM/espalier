import { QueryClient } from "@tanstack/react-query";
import { ApiError } from "./errors";

/** The most retries of a failed query. */
const MAX_RETRIES = 3;

/**
 * Whether a failed query loads again. An `ApiError` with a status below
 * 500, such as 401, 403, 404, 422 or 429, fails at once, because a repeat
 * gets the same answer. A network error and a 5xx answer load again up to
 * three times.
 */
export function shouldRetryQuery(failureCount: number, error: unknown) {
  if (error instanceof ApiError && error.status < 500) return false;
  return failureCount < MAX_RETRIES;
}

export const queryClient = new QueryClient({
  defaultOptions: { queries: { retry: shouldRetryQuery } },
});
