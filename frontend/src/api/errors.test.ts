import { describe, expect, test } from "vitest";
import i18n from "../i18n";
import {
  ApiError,
  RECENT_AUTH_ERROR_CODE,
  errorMessage,
  errorMessageKey,
  passwordErrorKeys,
  retryMinutes,
} from "./errors";

/** The 409 and 422 codes of the account routes with their message keys. */
const CONFLICTS = [
  ["last_factor", "account.errors.lastFactor"],
  ["admin_passkey_required", "account.errors.adminPasskeyRequired"],
  ["totp_already_enabled", "account.errors.totpAlreadyEnabled"],
  ["password_required", "account.errors.passwordRequired"],
  ["link_required", "account.errors.linkRequired"],
  ["identity_in_use", "account.errors.identityInUse"],
  ["provider_already_linked", "account.errors.providerAlreadyLinked"],
  ["registration_failed", "account.errors.registrationFailed"],
  ["invalid_code", "account.errors.invalidCode"],
  ["step_up_not_available", "account.errors.stepUpNotAvailable"],
] as const;

const apiError = (
  status: number,
  body: unknown,
  headers: Record<string, string> = {},
) => new ApiError(new Response(null, { status, headers }), body);

test("RECENT_AUTH_ERROR_CODE is the code of require_recent_auth", () => {
  expect(RECENT_AUTH_ERROR_CODE).toBe("reauth_required");
});

describe("errorMessageKey", () => {
  test("a 429 yields the rate-limit message for every code", () => {
    expect(errorMessageKey(429, "rate_limited")).toBe("errors.tooManyAttempts");
    expect(errorMessageKey(429, null)).toBe("errors.tooManyAttempts");
  });

  test("a 401 yields the sign-in message", () => {
    expect(errorMessageKey(401, "authentication_failed")).toBe(
      "auth.errors.signInFailed",
    );
    expect(errorMessageKey(401, null)).toBe("auth.errors.signInFailed");
  });

  test("a 422 validation_failed names the rejected password", () => {
    expect(errorMessageKey(422, "validation_failed")).toBe(
      "account.errors.passwordRejected",
    );
  });

  test.each(
    CONFLICTS.flatMap(([code, key]) => [
      [409, code, key] as const,
      [422, code, key] as const,
    ]),
  )("%i %s yields %s", (status, code, key) => {
    expect(errorMessageKey(status, code)).toBe(key);
    expect(i18n.exists(key, { lng: "en" })).toBe(true);
  });

  test.each([
    [409, "unknown_conflict"],
    [422, "unknown_rejection"],
    [409, null],
    [403, "last_factor"],
    [403, RECENT_AUTH_ERROR_CODE],
    [400, "validation_failed"],
    [500, null],
    [404, "not_found"],
    // A key of Object.prototype is no code of the table.
    [409, "toString"],
  ])("%i %s yields errors.generic", (status, code) => {
    expect(errorMessageKey(status, code)).toBe("errors.generic");
  });
});

describe("errorMessage", () => {
  test("an ApiError yields its key and the minutes of Retry-After", () => {
    expect(
      errorMessage(
        apiError(429, { error: "rate_limited" }, { "retry-after": "125" }),
      ),
    ).toEqual({ key: "errors.tooManyAttempts", minutes: 3 });
    expect(errorMessage(apiError(409, { error: "last_factor" }))).toEqual({
      key: "account.errors.lastFactor",
      minutes: 1,
    });
  });

  test("any other value yields the generic message", () => {
    expect(errorMessage(new Error("network"))).toEqual({
      key: "errors.generic",
      minutes: 1,
    });
    expect(errorMessage("failed")).toEqual({
      key: "errors.generic",
      minutes: 1,
    });
  });
});

describe("passwordErrorKeys", () => {
  test("yields one key per code of fields.password", () => {
    expect(
      passwordErrorKeys({
        error: "validation_failed",
        fields: {
          password: ["too_short", "too_long", "common", "context", "breached"],
        },
      }),
    ).toEqual([
      "account.password.errors.too_short",
      "account.password.errors.too_long",
      "account.password.errors.common",
      "account.password.errors.context",
      "account.password.errors.breached",
    ]);
  });

  test("with current_password yields one key per code of fields.current_password", () => {
    const body = {
      error: "validation_failed",
      fields: { current_password: ["required", "invalid"] },
    };

    expect(passwordErrorKeys(body, "current_password")).toEqual([
      "account.password.errors.current_required",
      "account.password.errors.current_invalid",
    ]);
    expect(passwordErrorKeys(body)).toEqual([]);
  });

  test("reads only the codes of the requested field", () => {
    const body = {
      error: "validation_failed",
      fields: { password: ["breached"], current_password: ["invalid"] },
    };

    expect(passwordErrorKeys(body)).toEqual([
      "account.password.errors.breached",
    ]);
    expect(passwordErrorKeys(body, "current_password")).toEqual([
      "account.password.errors.current_invalid",
    ]);
  });

  test("drops unknown codes", () => {
    expect(
      passwordErrorKeys({
        error: "validation_failed",
        fields: { password: ["too_short", "mystery", 7, "invalid"] },
      }),
    ).toEqual(["account.password.errors.too_short"]);
    expect(
      passwordErrorKeys(
        {
          error: "validation_failed",
          fields: { current_password: ["invalid", "too_short"] },
        },
        "current_password",
      ),
    ).toEqual(["account.password.errors.current_invalid"]);
  });

  test("every key it yields exists in en.json", () => {
    const keys = [
      ...passwordErrorKeys({
        error: "validation_failed",
        fields: {
          password: ["too_short", "too_long", "common", "context", "breached"],
        },
      }),
      ...passwordErrorKeys(
        {
          error: "validation_failed",
          fields: { current_password: ["required", "invalid"] },
        },
        "current_password",
      ),
    ];

    expect(keys).toHaveLength(7);
    for (const key of keys) expect(i18n.exists(key, { lng: "en" })).toBe(true);
  });

  test.each([
    [
      "another error code",
      { error: "last_factor", fields: { password: ["common"] } },
    ],
    ["a body without an error code", { fields: { password: ["common"] } }],
    ["validation_failed without fields", { error: "validation_failed" }],
    ["fields of null", { error: "validation_failed", fields: null }],
    [
      "a code string instead of a list",
      { error: "validation_failed", fields: { password: "common" } },
    ],
    [
      "another field only",
      { error: "validation_failed", fields: { email: ["invalid"] } },
    ],
    ["null", null],
    ["a string", "validation_failed"],
    ["a list", ["validation_failed"]],
  ])("yields [] for %s", (_name, body) => {
    expect(passwordErrorKeys(body)).toEqual([]);
    expect(passwordErrorKeys(body, "current_password")).toEqual([]);
  });
});

describe("ApiError", () => {
  test("carries the status, the code and the body", () => {
    const body = { error: "last_factor" };
    const error = apiError(409, body);

    expect(error).toBeInstanceOf(Error);
    expect(error.name).toBe("ApiError");
    expect(error.status).toBe(409);
    expect(error.code).toBe("last_factor");
    expect(error.body).toBe(body);
  });

  test("reads retryAfter in seconds from the Retry-After header", () => {
    expect(
      apiError(429, { error: "rate_limited" }, { "retry-after": "61" })
        .retryAfter,
    ).toBe(61);
  });

  test("has no retryAfter without the header or with a date", () => {
    expect(apiError(429, { error: "rate_limited" }).retryAfter).toBeNull();
    expect(
      apiError(
        429,
        { error: "rate_limited" },
        { "retry-after": "Wed, 21 Oct 2026 07:28:00 GMT" },
      ).retryAfter,
    ).toBeNull();
  });

  test("has no code for a body without a string error", () => {
    expect(apiError(500, null).code).toBeNull();
    expect(apiError(500, { error: 1 }).code).toBeNull();
    expect(apiError(500, "text").code).toBeNull();
  });
});

describe("retryMinutes", () => {
  test.each([
    ["1", 1],
    ["59", 1],
    ["60", 1],
    ["61", 2],
    ["120", 2],
    ["121", 3],
    ["3600", 60],
  ])("Retry-After %s yields %i minutes", (seconds, minutes) => {
    expect(
      retryMinutes(
        apiError(429, { error: "rate_limited" }, { "retry-after": seconds }),
      ),
    ).toBe(minutes);
  });

  test("yields at least one minute", () => {
    expect(
      retryMinutes(
        apiError(429, { error: "rate_limited" }, { "retry-after": "0" }),
      ),
    ).toBe(1);
  });

  test("yields one minute without Retry-After and for other values", () => {
    expect(retryMinutes(apiError(429, { error: "rate_limited" }))).toBe(1);
    expect(retryMinutes(new Error("network"))).toBe(1);
    expect(retryMinutes(null)).toBe(1);
  });
});
