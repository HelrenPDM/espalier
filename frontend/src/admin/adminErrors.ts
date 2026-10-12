import { useCallback } from "react";
import { useTranslation } from "react-i18next";
import { ApiError, RECENT_AUTH_ERROR_CODE, retryMinutes } from "../api/errors";

/**
 * The messages of the 409 and 422 codes of the admin routes (task 0015,
 * steps 3, 4 and 6), and of a 403 `reauth_required` that reaches the page
 * after the step-up dialog was closed.
 */
const CODE_KEYS = {
  own_account: "admin.common.errors.ownAccount",
  user_exists: "admin.common.errors.userExists",
  not_invitable: "admin.common.errors.notInvitable",
  idp_claim: "admin.common.errors.idpClaim",
  demo_user: "admin.common.errors.demoUser",
  already_revoked: "admin.common.errors.alreadyRevoked",
  identity_verification_required:
    "admin.common.errors.identityVerificationRequired",
  [RECENT_AUTH_ERROR_CODE]: "admin.common.errors.reauthCancelled",
} as const;

type KnownCode = keyof typeof CODE_KEYS;

const isKnownCode = (code: string | null): code is KnownCode =>
  code !== null && Object.hasOwn(CODE_KEYS, code);

/**
 * Returns a function that translates a failed admin call: a known code by
 * its own message, then 403, 404, 422 and 429 by their status, and every
 * other failure as the generic message.
 */
export function useAdminErrorText(): (error: unknown) => string {
  const { t } = useTranslation();
  return useCallback(
    (error: unknown) => {
      if (!(error instanceof ApiError)) return t("errors.generic");
      if (isKnownCode(error.code)) return t(CODE_KEYS[error.code]);
      switch (error.status) {
        case 403:
          return t("admin.common.errors.forbidden");
        case 404:
          return t("admin.common.errors.notFound");
        case 422:
          return t("admin.common.errors.validation");
        case 429:
          return t("errors.tooManyAttempts", { minutes: retryMinutes(error) });
        default:
          return t("errors.generic");
      }
    },
    [t],
  );
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** True for an id in the form of the API (`Fields.uuid/1`). */
export const isUuid = (value: string): boolean => UUID.test(value);
