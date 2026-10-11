import * as OTPAuth from "otpauth";

/** The TOTP generator of an `otpauth://` URI of `POST /api/me/totp`. */
export function totpFromUri(uri: string): OTPAuth.TOTP {
  const otp = OTPAuth.URI.parse(uri);
  if (!(otp instanceof OTPAuth.TOTP)) throw new Error("no TOTP URI");
  return otp;
}

/**
 * Waits for the next 30-second step plus one second. The server accepts
 * each step once (README section 6.6), so a code after the confirmation
 * needs the next step.
 */
export function waitForNextStep(): Promise<void> {
  const delay = 30_000 - (Date.now() % 30_000) + 1_000;
  return new Promise((resolve) => setTimeout(resolve, delay));
}
