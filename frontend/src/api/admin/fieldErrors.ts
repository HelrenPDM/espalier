import { ApiError } from "../errors";

/**
 * The codes of a 422 `validation_failed` answer for `field`, such as
 * `["future"]` for `held_on` or `["unique"]` for `name` (the codes of
 * `EspalierWeb.ChangesetJSON`); `[]` for every other failure.
 */
export function fieldCodes(error: unknown, field: string): string[] {
  if (!(error instanceof ApiError) || error.status !== 422) return [];
  const body = error.body;
  if (typeof body !== "object" || body === null) return [];
  if (!("error" in body) || body.error !== "validation_failed") return [];
  if (!("fields" in body)) return [];
  const fields = body.fields;
  if (typeof fields !== "object" || fields === null) return [];
  const codes: unknown = (fields as Record<string, unknown>)[field];
  return Array.isArray(codes)
    ? codes.filter((code): code is string => typeof code === "string")
    : [];
}

/** True for an `ApiError` with `status` and, when given, `code`. */
export function isApiError(
  error: unknown,
  status: number,
  code?: string,
): error is ApiError {
  return (
    error instanceof ApiError &&
    error.status === status &&
    (code === undefined || error.code === code)
  );
}
