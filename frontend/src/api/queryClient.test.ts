import { describe, expect, test } from "vitest";
import { ApiError } from "./errors";
import { queryClient, shouldRetryQuery } from "./queryClient";

const apiError = (status: number) =>
  new ApiError(new Response(null, { status }), { error: "some_code" });

/**
 * The retry rule of the app's query client: `useQuery` and the render
 * helper of the tests run without retries, so the tests call the rule
 * directly.
 */
describe("shouldRetryQuery", () => {
  test.each([400, 401, 403, 404, 409, 422, 429])(
    "an ApiError with status %i fails at once",
    (status) => {
      expect(shouldRetryQuery(0, apiError(status))).toBe(false);
    },
  );

  test.each([500, 502, 503])(
    "an ApiError with status %i loads again up to three times",
    (status) => {
      expect(shouldRetryQuery(0, apiError(status))).toBe(true);
      expect(shouldRetryQuery(2, apiError(status))).toBe(true);
      expect(shouldRetryQuery(3, apiError(status))).toBe(false);
    },
  );

  test("a network error loads again up to three times", () => {
    const error = new TypeError("Failed to fetch");

    expect(shouldRetryQuery(0, error)).toBe(true);
    expect(shouldRetryQuery(2, error)).toBe(true);
    expect(shouldRetryQuery(3, error)).toBe(false);
  });

  test("the app's query client uses the rule for every query", () => {
    expect(queryClient.getDefaultOptions().queries?.retry).toBe(
      shouldRetryQuery,
    );
  });
});
