/** The code of a rejected anti-forgery token (README section 6.10). */
export const CSRF_ERROR_CODE = "csrf";

/**
 * The code of `require_recent_auth/2` (README sections 6.10 and 6.12): the
 * change needs a second factor within the last 10 minutes.
 */
export const RECENT_AUTH_ERROR_CODE = "reauth_required";

/**
 * The code of `EspalierWeb.Plugs.RequireAdminPasskey` (README section 6.11,
 * task 0015): an admin without a passkey on an admin route.
 */
export const PASSKEY_REQUIRED_ERROR_CODE = "passkey_required";

/** The code of an enrollment or recovery session on a route of a full session. */
export const ENROLLMENT_ERROR_CODE = "enrollment_required";

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
  return codeOf(body);
}

function codeOf(body: unknown): string | null {
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

/**
 * A failed API call: the status, the error code of the body, the body and,
 * for a 429, the seconds of `Retry-After`.
 */
export class ApiError extends Error {
  readonly status: number;
  readonly code: string | null;
  readonly body: unknown;
  readonly retryAfter: number | null;

  constructor(response: Response, body: unknown) {
    const code = codeOf(body);
    super(`API answered ${response.status}${code ? ` ${code}` : ""}`);
    this.name = "ApiError";
    this.status = response.status;
    this.code = code;
    this.body = body;
    const retryAfter = Number.parseInt(
      response.headers.get("retry-after") ?? "",
      10,
    );
    this.retryAfter = Number.isFinite(retryAfter) ? retryAfter : null;
  }
}

/**
 * Returns `data` of an openapi-fetch result for a 2xx answer and throws an
 * `ApiError` otherwise, so the query and mutation hooks see failures.
 */
export function unwrap<T>(result: {
  data?: T;
  error?: unknown;
  response: Response;
}): T {
  if (!result.response.ok) throw new ApiError(result.response, result.error);
  return result.data as T;
}

const CONFLICT_KEYS = {
  last_factor: "account.errors.lastFactor",
  admin_passkey_required: "account.errors.adminPasskeyRequired",
  totp_already_enabled: "account.errors.totpAlreadyEnabled",
  password_required: "account.errors.passwordRequired",
  link_required: "account.errors.linkRequired",
  identity_in_use: "account.errors.identityInUse",
  provider_already_linked: "account.errors.providerAlreadyLinked",
  registration_failed: "account.errors.registrationFailed",
  invalid_code: "account.errors.invalidCode",
  step_up_not_available: "account.errors.stepUpNotAvailable",
} as const;

type ConflictCode = keyof typeof CONFLICT_KEYS;

export type ErrorMessageKey =
  | "errors.tooManyAttempts"
  | "auth.errors.signInFailed"
  | "account.errors.passwordRejected"
  | (typeof CONFLICT_KEYS)[ConflictCode]
  | "errors.generic";

const isConflictCode = (code: string | null): code is ConflictCode =>
  code !== null && Object.hasOwn(CONFLICT_KEYS, code);

/**
 * The message key for an error answer (task 0011, step 3): 429 and 401 have
 * one message each, a 422 `validation_failed` names the rejected password,
 * every 409 and 422 code of the account routes has its own message under
 * `account.errors`, and every other answer shows the generic message.
 */
export function errorMessageKey(
  status: number,
  code: string | null,
): ErrorMessageKey {
  if (status === 429) return "errors.tooManyAttempts";
  if (status === 401) return "auth.errors.signInFailed";
  if (status === 422 && code === "validation_failed")
    return "account.errors.passwordRejected";
  if ((status === 409 || status === 422) && isConflictCode(code))
    return CONFLICT_KEYS[code];
  return "errors.generic";
}

/** The minutes of a 429 answer for `errors.tooManyAttempts`, rounded up. */
export function retryMinutes(error: unknown): number {
  const seconds = error instanceof ApiError ? error.retryAfter : null;
  return Math.max(1, Math.ceil((seconds ?? 60) / 60));
}

/** The message key and its values for any thrown value. */
export function errorMessage(error: unknown): {
  key: ErrorMessageKey;
  minutes: number;
} {
  if (!(error instanceof ApiError))
    return { key: "errors.generic", minutes: 1 };
  return {
    key: errorMessageKey(error.status, error.code),
    minutes: retryMinutes(error),
  };
}

const PASSWORD_CODES = [
  "too_short",
  "too_long",
  "common",
  "context",
  "breached",
] as const;
const CURRENT_PASSWORD_CODES = ["required", "invalid"] as const;

export type PasswordErrorKey =
  | `account.password.errors.${(typeof PASSWORD_CODES)[number]}`
  | `account.password.errors.current_${(typeof CURRENT_PASSWORD_CODES)[number]}`;

/**
 * The field messages of a 422 `validation_failed` body (0004 step 36): one
 * key per known code under `fields.password`, or with `field`
 * `"current_password"` one key per known code under
 * `fields.current_password`. Every other body yields `[]`.
 */
export function passwordErrorKeys(
  body: unknown,
  field: "password" | "current_password" = "password",
): PasswordErrorKey[] {
  if (codeOf(body) !== "validation_failed") return [];
  const fields =
    typeof body === "object" && body !== null && "fields" in body
      ? body.fields
      : null;
  if (typeof fields !== "object" || fields === null || !(field in fields))
    return [];
  const codes: unknown = (fields as Record<string, unknown>)[field];
  if (!Array.isArray(codes)) return [];

  const keys: PasswordErrorKey[] = [];
  for (const code of codes) {
    if (field === "password") {
      const known = PASSWORD_CODES.find((value) => value === code);
      if (known) keys.push(`account.password.errors.${known}`);
    } else {
      const known = CURRENT_PASSWORD_CODES.find((value) => value === code);
      if (known) keys.push(`account.password.errors.current_${known}`);
    }
  }
  return keys;
}
