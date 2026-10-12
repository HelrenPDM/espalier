import { createContext, useContext } from "react";

/**
 * True while the admin sections are closed for want of a passkey;
 * `PasskeyGateProvider` of `passkeyGate.tsx` provides it.
 */
export const PasskeyRequiredContext = createContext(false);

/** True while the admin sections are closed for want of a passkey. */
export function usePasskeyRequired(): boolean {
  return useContext(PasskeyRequiredContext);
}
