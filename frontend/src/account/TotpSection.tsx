import { useId, useState } from "react";
import { useTranslation } from "react-i18next";
import {
  factorCount,
  useRemoveTotp,
  type SecuritySummary,
} from "../api/account";
import { ConfirmDialog } from "../app/ConfirmDialog";
import { formatDate } from "../app/format";
import { AlertRegion, Button, StatusRegion } from "../app/forms";
import { useErrorText } from "../app/useErrorText";
import { TotpSetup } from "./TotpSetup";

/**
 * The authenticator app (task 0011 step 12). The page offers no in-place
 * replacement: a person whose only factor is the app adds a passkey before
 * removing it.
 */
export function TotpSection({
  security,
  onFactorChange,
}: {
  security: SecuritySummary;
  onFactorChange: (otherSessions: number) => void;
}) {
  const { t, i18n } = useTranslation();
  const errorText = useErrorText();
  const remove = useRemoveTotp();
  const reasonId = useId();
  const [settingUp, setSettingUp] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState<string | null>(null);
  const last = factorCount(security) <= 1;
  const { enabled, enabled_at: enabledAt } = security.totp;

  const confirmRemove = async () => {
    setConfirming(false);
    setError(null);
    setStatus(null);
    try {
      const { other_sessions } = await remove.mutateAsync();
      setStatus(t("account.totp.removed"));
      onFactorChange(other_sessions);
    } catch (failure) {
      setError(errorText(failure));
    }
  };

  return (
    <section aria-labelledby="totp-heading" className="space-y-4">
      <h2 id="totp-heading" className="text-xl font-semibold">
        {t("account.totp.title")}
      </h2>
      <AlertRegion>{error}</AlertRegion>
      <StatusRegion>{status}</StatusRegion>
      <p className="text-gray-700 dark:text-gray-300">
        {enabled && enabledAt
          ? t("account.totp.enabledSince", {
              date: formatDate(enabledAt, i18n.language),
            })
          : t("account.totp.disabled")}
      </p>
      {enabled ? (
        <>
          <Button
            variant="danger"
            disabled={last || remove.isPending}
            aria-describedby={last ? reasonId : undefined}
            onClick={() => setConfirming(true)}
          >
            {t("account.totp.remove")}
          </Button>
          {last && (
            <p
              id={reasonId}
              className="text-sm text-gray-700 dark:text-gray-300"
            >
              {t("account.factors.lastFactor")}
            </p>
          )}
        </>
      ) : settingUp ? (
        <TotpSetup
          onConfirmed={(result) => {
            setSettingUp(false);
            setStatus(t("account.totp.added"));
            onFactorChange(result.other_sessions);
          }}
          onCancel={() => setSettingUp(false)}
        />
      ) : (
        <Button
          variant="secondary"
          onClick={() => {
            setStatus(null);
            setSettingUp(true);
          }}
        >
          {t("account.totp.setUp")}
        </Button>
      )}
      <ConfirmDialog
        open={confirming}
        title={t("account.totp.removeTitle")}
        confirmLabel={t("account.totp.remove")}
        confirmVariant="danger"
        onConfirm={() => void confirmRemove()}
        onClose={() => setConfirming(false)}
      >
        <p>{t("account.totp.removeText")}</p>
      </ConfirmDialog>
    </section>
  );
}
