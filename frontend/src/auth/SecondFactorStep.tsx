import { startAuthentication } from "@simplewebauthn/browser";
import { useState, type FormEvent } from "react";
import { useTranslation } from "react-i18next";
import { Link } from "react-router";
import { useApiClient } from "../api/apiClientContext";
import { ApiError, unwrap } from "../api/errors";
import type { components } from "../api/schema";
import { AlertRegion, Button, FocusHeading, TextField } from "../app/forms";
import { linkClasses } from "../app/formStyles";
import { useErrorText } from "../app/useErrorText";
import { useSessionEvents } from "./sessionEvents";
import { classifyWebAuthnError } from "./webauthn";

export type SecondFactorSession = components["schemas"]["SecondFactorSession"];
type SecondFactorRequest = components["schemas"]["SecondFactorRequest"];

/**
 * The second step after every first factor: the password, OIDC and LDAP
 * (task 0011 step 7). It offers the authenticator app, a passkey and a
 * recovery code. `onSignedIn` receives the session body; the caller calls
 * `sessionChanged("signed-in")` and navigates. A 401 keeps the step; when
 * the refetched session no longer reports `pending` (fifth failure or
 * expiry), `onRestart` returns to the first step.
 */
export function SecondFactorStep({
  onSignedIn,
  onRestart,
}: {
  onSignedIn: (session: SecondFactorSession) => void | Promise<void>;
  onRestart: () => void;
}) {
  const { t } = useTranslation();
  const client = useApiClient();
  const errorText = useErrorText();
  const { refreshSession } = useSessionEvents();
  const [mode, setMode] = useState<"totp" | "recovery_code">("totp");
  const [totp, setTotp] = useState("");
  const [recoveryCode, setRecoveryCode] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const failed = async (failure: unknown) => {
    if (failure instanceof ApiError && failure.status === 401) {
      setError(t("auth.errors.signInFailed"));
      const session = await refreshSession().catch(() => null);
      if (session !== null && session.pending === null) onRestart();
      return;
    }
    setError(errorText(failure));
  };

  const verify = async (body: SecondFactorRequest) => {
    const session = unwrap(
      await client.POST("/api/auth/second-factor", { body }),
    );
    await onSignedIn(session);
  };

  const submitCode = async (event: FormEvent) => {
    event.preventDefault();
    if (busy) return;
    setBusy(true);
    setError(null);
    try {
      await verify(
        mode === "totp" ? { totp } : { recovery_code: recoveryCode },
      );
    } catch (failure) {
      await failed(failure);
    } finally {
      setBusy(false);
    }
  };

  const verifyWithPasskey = async () => {
    if (busy) return;
    setBusy(true);
    setError(null);
    try {
      const options = unwrap(
        await client.POST("/api/auth/passkey/options", {
          body: { purpose: "second_factor" },
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
              : t("auth.errors.signInFailed"),
          );
        return;
      }
      await verify({ passkey });
    } catch (failure) {
      await failed(failure);
    } finally {
      setBusy(false);
    }
  };

  return (
    <section className="max-w-md space-y-6">
      <div>
        <FocusHeading>{t("auth.secondFactor.title")}</FocusHeading>
        <p className="mt-2 text-gray-700 dark:text-gray-300">
          {t("auth.secondFactor.text")}
        </p>
      </div>

      <form onSubmit={(event) => void submitCode(event)} className="space-y-4">
        <AlertRegion>{error}</AlertRegion>
        {mode === "totp" ? (
          <TextField
            key="totp"
            label={t("auth.secondFactor.codeLabel")}
            name="totp"
            value={totp}
            onChange={(event) => setTotp(event.target.value)}
            inputMode="numeric"
            autoComplete="one-time-code"
            pattern="[0-9]{6}"
            maxLength={6}
            required
          />
        ) : (
          <TextField
            key="recovery_code"
            label={t("auth.secondFactor.recoveryCodeLabel")}
            name="recovery_code"
            value={recoveryCode}
            onChange={(event) => setRecoveryCode(event.target.value)}
            autoComplete="off"
            spellCheck={false}
            autoCapitalize="characters"
            required
          />
        )}
        <Button type="submit" disabled={busy}>
          {t("auth.secondFactor.submit")}
        </Button>
      </form>

      <div className="flex flex-wrap gap-3">
        <Button
          variant="secondary"
          disabled={busy}
          onClick={() => void verifyWithPasskey()}
        >
          {t("auth.secondFactor.passkey")}
        </Button>
        <Button
          variant="secondary"
          onClick={() => {
            setError(null);
            setMode((current) =>
              current === "totp" ? "recovery_code" : "totp",
            );
          }}
        >
          {mode === "totp"
            ? t("auth.secondFactor.useRecoveryCode")
            : t("auth.secondFactor.useCode")}
        </Button>
      </div>

      <p>
        <Link to="/recover" className={linkClasses}>
          {t("auth.signIn.lostAccess")}
        </Link>
      </p>
    </section>
  );
}
