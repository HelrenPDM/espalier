import { useState, type FormEvent } from "react";
import { useTranslation } from "react-i18next";
import { useNavigate } from "react-router";
import { useApiClient } from "../api/apiClientContext";
import { ApiError, unwrap } from "../api/errors";
import {
  AlertRegion,
  Button,
  FocusHeading,
  StatusRegion,
  TextField,
} from "../app/forms";
import { LoadingStatus } from "../app/LoadingStatus";
import { useErrorText } from "../app/useErrorText";
import { useSessionEvents } from "./sessionEvents";
import { useFragmentToken } from "./useFragmentToken";

/**
 * `/recover` (task 0011 step 11). Without a fragment it requests the
 * recovery link; opened from the mail (`#token=`) it asks for a saved
 * recovery code. Recovery needs both (README section 6.6) and leads to the
 * enrollment wizard only.
 */
export function RecoveryPage() {
  const token = useFragmentToken();
  if (token === undefined) return <LoadingStatus />;
  return token === null ? <StartRecovery /> : <VerifyRecovery token={token} />;
}

function StartRecovery() {
  const { t } = useTranslation();
  const client = useApiClient();
  const [email, setEmail] = useState("");
  const [sent, setSent] = useState(false);
  const [busy, setBusy] = useState(false);

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (busy) return;
    setBusy(true);
    setSent(false);
    try {
      await client.POST("/api/auth/recovery/start", { body: { email } });
    } catch {
      // The same answer for every outcome (ASVS 6.3.8).
    } finally {
      setSent(true);
      setBusy(false);
    }
  };

  return (
    <section className="max-w-md space-y-4">
      <FocusHeading>{t("auth.recovery.title")}</FocusHeading>
      <p className="text-gray-700 dark:text-gray-300">
        {t("auth.recovery.startText")}
      </p>
      <form onSubmit={(event) => void submit(event)} className="space-y-4">
        <AlertRegion />
        <StatusRegion>{sent ? t("auth.recovery.sent") : null}</StatusRegion>
        <TextField
          label={t("auth.signIn.email")}
          type="email"
          name="email"
          autoComplete="email"
          value={email}
          onChange={(event) => setEmail(event.target.value)}
          required
        />
        <Button type="submit" disabled={busy}>
          {t("auth.recovery.startSubmit")}
        </Button>
      </form>
    </section>
  );
}

function VerifyRecovery({ token }: { token: string }) {
  const { t } = useTranslation();
  const client = useApiClient();
  const navigate = useNavigate();
  const errorText = useErrorText();
  const { sessionChanged } = useSessionEvents();
  const [code, setCode] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (busy) return;
    setBusy(true);
    setError(null);
    try {
      unwrap(
        await client.POST("/api/auth/recovery/verify", {
          body: { token, recovery_code: code },
        }),
      );
      await sessionChanged("signed-in");
      await navigate("/enroll", { replace: true });
    } catch (failure) {
      // The token stays in memory: the link works until it expires.
      setError(
        failure instanceof ApiError && failure.status === 429
          ? errorText(failure)
          : t("auth.errors.recoveryFailed"),
      );
    } finally {
      setBusy(false);
    }
  };

  return (
    <section className="max-w-md space-y-4">
      <FocusHeading>{t("auth.recovery.title")}</FocusHeading>
      <p className="text-gray-700 dark:text-gray-300">
        {t("auth.recovery.verifyText")}
      </p>
      <form onSubmit={(event) => void submit(event)} className="space-y-4">
        <AlertRegion>{error}</AlertRegion>
        <TextField
          label={t("auth.recovery.codeLabel")}
          name="recovery_code"
          autoComplete="off"
          spellCheck={false}
          autoCapitalize="characters"
          value={code}
          onChange={(event) => setCode(event.target.value)}
          required
        />
        <Button type="submit" disabled={busy}>
          {t("auth.recovery.verifySubmit")}
        </Button>
      </form>
    </section>
  );
}
