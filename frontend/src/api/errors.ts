/** The code of a rejected anti-forgery token (README section 6.10). */
export const CSRF_ERROR_CODE = "csrf";

/**
 * Reads `error` from the JSON body of a clone of the response, so the caller
 * can still read the body. Returns `null` for any other body.
 */
export async function errorCode(response: Response): Promise<string | null> {
  let body: unknown;
  try {
    body = await response.clone().json();
  } catch {
    return null;
  }
  if (
    typeof body === "object" &&
    body !== null &&
    "error" in body &&
    typeof body.error === "string"
  ) {
    return body.error;
  }
  return null;
}
