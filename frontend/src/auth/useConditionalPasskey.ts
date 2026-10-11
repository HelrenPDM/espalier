import {
  WebAuthnAbortService,
  browserSupportsWebAuthnAutofill,
  startAuthentication,
} from "@simplewebauthn/browser";
import { useCallback, useEffect, useRef } from "react";
import { useApiClient } from "../api/apiClientContext";
import type { SessionPayload } from "../api/session";

/** The server's challenge expires after 300 seconds (README section 6.6). */
const RENEW_AFTER_MS = 290_000;

/**
 * Passkey sign-in through the browser's autofill (conditional UI, task 0011
 * step 6). Only `SignInFirstStep` calls it, so it runs only while the field
 * with `autocomplete="username webauthn"` is on the page, and only with
 * `enabled`.
 *
 * The ceremony waits until the person picks a passkey (ASVS 7.6.2). A failed
 * options request and a rejection of the conditional request show nothing;
 * `onRejected` runs when the server rejects a passkey the person picked.
 *
 * The returned `stop()` ends the ceremony for good: every other action of
 * the page calls it first, so no new `sign_in` options request replaces the
 * ceremony id of a second-factor passkey in the session cookie.
 */
export function useConditionalPasskey(
  onSignedIn: (session: SessionPayload) => void,
  {
    enabled = true,
    onRejected,
  }: { enabled?: boolean; onRejected?: () => void } = {},
): () => void {
  const client = useApiClient();
  const stopRef = useRef<() => void>(() => {});
  const callbacks = useRef({ onSignedIn, onRejected });
  useEffect(() => {
    callbacks.current = { onSignedIn, onRejected };
  });

  useEffect(() => {
    if (!enabled) return undefined;
    let active = true;
    let timer: ReturnType<typeof setTimeout> | undefined;

    const clearTimer = () => {
      if (timer !== undefined) clearTimeout(timer);
      timer = undefined;
    };

    const run = async (): Promise<void> => {
      if (!(await browserSupportsWebAuthnAutofill()) || !active) return;

      let options;
      try {
        ({ data: options } = await client.POST("/api/auth/passkey/options", {
          body: { purpose: "sign_in" },
        }));
      } catch {
        return;
      }
      if (!active || options === undefined) return;

      timer = setTimeout(() => {
        timer = undefined;
        WebAuthnAbortService.cancelCeremony();
        void run();
      }, RENEW_AFTER_MS);

      let assertion;
      try {
        assertion = await startAuthentication({
          optionsJSON: options,
          useBrowserAutofill: true,
        });
      } catch {
        // Aborted by the timer or by stop(), or rejected by the browser.
        return;
      }
      if (!active) return;
      clearTimer();

      try {
        const { data } = await client.POST("/api/auth/passkey", {
          body: assertion,
        });
        if (!active) return;
        if (data === undefined) callbacks.current.onRejected?.();
        else callbacks.current.onSignedIn(data);
      } catch {
        if (active) callbacks.current.onRejected?.();
      }
    };

    const stop = () => {
      active = false;
      clearTimer();
      WebAuthnAbortService.cancelCeremony();
    };
    stopRef.current = stop;
    void run();
    return stop;
  }, [client, enabled]);

  return useCallback(() => stopRef.current(), []);
}
