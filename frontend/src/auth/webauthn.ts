/**
 * The outcome of a failed WebAuthn ceremony of `@simplewebauthn/browser`:
 * `aborted` when the SPA cancelled it, `cancelled` when the person closed
 * the browser dialog or it timed out, `duplicate` when the authenticator
 * already holds a passkey of the account, and `failed` otherwise.
 */
export type WebAuthnFailure = "aborted" | "cancelled" | "duplicate" | "failed";

export function classifyWebAuthnError(error: unknown): WebAuthnFailure {
  if (typeof error !== "object" || error === null) return "failed";
  const { code, name } = error as { code?: unknown; name?: unknown };
  if (code === "ERROR_CEREMONY_ABORTED") return "aborted";
  if (name === "NotAllowedError") return "cancelled";
  if (code === "ERROR_AUTHENTICATOR_PREVIOUSLY_REGISTERED") return "duplicate";
  return "failed";
}
