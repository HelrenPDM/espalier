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
 * The returned `stop()` ends the ceremony for good and aborts a request of
 * the run still in flight: every other action of the page calls it first,
 * so neither a new nor a late `sign_in` options answer replaces the session
 * cookie of that action, such as the ceremony id of a second-factor passkey.
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
    // Aborts the requests of the run. A response that arrives after stop()
    // would otherwise still set the session cookie of the conditional
    // ceremony and replace the cookie of a later action, such as the
    // pending state after the password.
    const requests = new AbortController();

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
          signal: requests.signal,
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
          signal: requests.signal,
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
      requests.abort();
      WebAuthnAbortService.cancelCeremony();
    };
    stopRef.current = stop;
    void run();
    return stop;
  }, [client, enabled]);

  return useCallback(() => stopRef.current(), []);
}
