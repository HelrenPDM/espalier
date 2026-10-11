import { Dialog, DialogPanel, DialogTitle } from "@headlessui/react";
import {
  startAuthentication,
  type AuthenticationResponseJSON,
} from "@simplewebauthn/browser";
import { useState, type FormEvent } from "react";
import { useTranslation } from "react-i18next";
import { useLocation } from "react-router";
import { useOidcIntent, useSecurity } from "../api/account";
import { useApiClient } from "../api/apiClientContext";
import { ApiError, unwrap } from "../api/errors";
import { AlertRegion, Button, TextField } from "../app/forms";
import { LoadingStatus } from "../app/LoadingStatus";
import { useErrorText } from "../app/useErrorText";
import { rememberReturnTo } from "../auth/returnTo";
import { useSessionEvents } from "../auth/sessionEvents";
import { useSession } from "../auth/SessionProvider";
import { classifyWebAuthnError } from "../auth/webauthn";

/**
 * The step-up dialog (task 0011 step 13, ASVS 7.5.1). It confirms the
 * person with a local second factor through `POST /api/me/reauth`: a
 * passkey with options of the purpose `reauth`, or a code of the
 * authenticator app. A session without a local factor whose methods hold
 * `idp_mfa` steps up at its provider through an intent with `max_age=0`;
 * that leaves the page, so the dialog resolves `false` and the person
 * repeats the change after the return.
 *
 * `onDone(true)` follows a successful step-up, after the refetch of the
 * session with its new CSRF token; `onDone(false)` follows a close.
 */
export function StepUpDialog({
  open,
  onDone,
}: {
  open: boolean;
  onDone: (success: boolean) => void;
}) {
  const { t } = useTranslation();
  return (
    <Dialog open={open} onClose={() => onDone(false)} className="relative z-50">
      <div className="fixed inset-0 bg-gray-900/40" aria-hidden="true" />
      <div className="fixed inset-0 flex items-center justify-center p-4">
        <DialogPanel className="w-full max-w-md space-y-4 rounded-lg bg-white p-6 text-gray-900 shadow-xl dark:bg-gray-900 dark:text-gray-100">
          <DialogTitle className="text-lg font-semibold">
            {t("account.stepUp.title")}
          </DialogTitle>
          <p className="text-sm text-gray-700 dark:text-gray-300">
            {t("account.stepUp.text")}
          </p>
          {open && <StepUpMethods onDone={onDone} />}
        </DialogPanel>
      </div>
    </Dialog>
  );
}

function StepUpMethods({ onDone }: { onDone: (success: boolean) => void }) {
  const { t } = useTranslation();
  const client = useApiClient();
  const errorText = useErrorText();
  const location = useLocation();
  const { authMethods, providerKey, providers } = useSession();
  const { sessionChanged } = useSessionEvents();
  const security = useSecurity();
  const intent = useOidcIntent();
  const [code, setCode] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const failed = (failure: unknown) =>
    setError(
      failure instanceof ApiError && failure.status === 401
        ? t("auth.errors.stepUpFailed")
        : errorText(failure),
    );

  // A step-up issues a new session token and CSRF token (0005 step 13).
  const reauth = async (
    body: { totp: string } | { passkey: AuthenticationResponseJSON },
  ) => {
    unwrap(await client.POST("/api/me/reauth", { body }));
    await sessionChanged("renewed");
    onDone(true);
  };

  const withPasskey = async () => {
    if (busy) return;
    setBusy(true);
    setError(null);
    try {
      const options = unwrap(
        await client.POST("/api/auth/passkey/options", {
          body: { purpose: "reauth" },
        }),
      );
      let passkey;
      try {
        passkey = await startAuthentication({ optionsJSON: options });
      } catch (failure) {
        const kind = classifyWebAuthnError(failure);
        if (kind !== "aborted")
          setError(
            kind === "cancelled"
              ? t("auth.errors.passkeyCancelled")
              : t("auth.errors.stepUpFailed"),
          );
        return;
      }
      await reauth({ passkey });
    } catch (failure) {
      failed(failure);
    } finally {
      setBusy(false);
    }
  };

  const withCode = async (event: FormEvent) => {
    event.preventDefault();
    if (busy) return;
    setBusy(true);
    setError(null);
    try {
      await reauth({ totp: code });
    } catch (failure) {
      failed(failure);
    } finally {
      setBusy(false);
    }
  };

  const atProvider = async (key: string) => {
    if (busy) return;
    setBusy(true);
    setError(null);
    try {
      const url = await intent.mutateAsync({
        provider: key,
        purpose: "step_up",
      });
      rememberReturnTo(location.pathname);
      window.location.assign(url);
      onDone(false);
    } catch {
      setError(t("errors.generic"));
    } finally {
      setBusy(false);
    }
  };

  if (security.isPending) return <LoadingStatus />;
  const passkeys = security.data?.passkeys.length ?? 0;
  const totp = security.data?.totp.enabled ?? false;
  const provider =
    providerKey === null
      ? undefined
      : providers.find((entry) => entry.key === providerKey);
  const viaProvider =
    passkeys === 0 &&
    !totp &&
    authMethods.includes("idp_mfa") &&
    provider !== undefined;

  return (
    <div className="space-y-4">
      <AlertRegion>{error}</AlertRegion>
      {passkeys > 0 && (
        <Button
          className="w-full"
          disabled={busy}
          onClick={() => void withPasskey()}
          data-autofocus
        >
          {t("account.stepUp.passkey")}
        </Button>
      )}
      {totp && (
        <form onSubmit={(event) => void withCode(event)} className="space-y-3">
          <TextField
            label={t("account.stepUp.codeLabel")}
            name="totp"
            value={code}
            onChange={(event) => setCode(event.target.value)}
            inputMode="numeric"
            autoComplete="one-time-code"
            pattern="[0-9]{6}"
            maxLength={6}
            required
            data-autofocus={passkeys === 0 ? true : undefined}
          />
          <Button type="submit" variant="secondary" disabled={busy}>
            {t("account.stepUp.confirm")}
          </Button>
        </form>
      )}
      {viaProvider && provider && (
        <Button
          className="w-full"
          disabled={busy}
          onClick={() => void atProvider(provider.key)}
          data-autofocus
        >
          {t("account.stepUp.provider", { label: provider.label })}
        </Button>
      )}
      {passkeys === 0 && !totp && !viaProvider && (
        <p className="text-sm">{t("account.stepUp.unavailable")}</p>
      )}
      <div className="flex justify-end">
        <Button variant="secondary" onClick={() => onDone(false)}>
          {t("auth.forms.cancel")}
        </Button>
      </div>
    </div>
  );
}
