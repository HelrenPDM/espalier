import { useId, useState } from "react";
import { useTranslation } from "react-i18next";
import {
  factorCount,
  useRemovePasskey,
  type PasskeyView,
  type SecuritySummary,
} from "../api/account";
import { ConfirmDialog } from "../app/ConfirmDialog";
import { formatDate, formatDateTime } from "../app/format";
import { AlertRegion, Button, StatusRegion } from "../app/forms";
import { useErrorText } from "../app/useErrorText";
import { PasskeyCreateForm } from "./PasskeyCreateForm";

/**
 * The passkeys of the account (task 0011 step 12, ASVS 6.5.6). "Remove" is
 * disabled for the last second factor; the server applies the full rule and
 * answers 409 `last_factor` or `admin_passkey_required` otherwise.
 */
export function PasskeySection({
  security,
  onFactorChange,
}: {
  security: SecuritySummary;
  onFactorChange: (otherSessions: number) => void;
}) {
  const { t, i18n } = useTranslation();
  const errorText = useErrorText();
  const remove = useRemovePasskey();
  const reasonId = useId();
  const [adding, setAdding] = useState(false);
  const [removing, setRemoving] = useState<PasskeyView | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState<string | null>(null);
  const last = factorCount(security) <= 1;

  const confirmRemove = async () => {
    const passkey = removing;
    setRemoving(null);
    if (passkey === null) return;
    setError(null);
    setStatus(null);
    try {
      const { other_sessions } = await remove.mutateAsync(passkey.id);
      setStatus(t("account.passkeys.removed"));
      onFactorChange(other_sessions);
    } catch (failure) {
      setError(errorText(failure));
    }
  };

  const backupState = (passkey: PasskeyView) =>
    passkey.backed_up
      ? t("account.passkeys.synced")
      : passkey.backup_eligible
        ? t("account.passkeys.syncable")
        : t("account.passkeys.deviceOnly");

  return (
    <section aria-labelledby="passkeys-heading" className="space-y-4">
      <h2 id="passkeys-heading" className="text-xl font-semibold">
        {t("account.passkeys.title")}
      </h2>
      <AlertRegion>{error}</AlertRegion>
      <StatusRegion>{status}</StatusRegion>
      {security.passkeys.length === 0 ? (
        <p className="text-gray-700 dark:text-gray-300">
          {t("account.passkeys.none")}
        </p>
      ) : (
        <ul className="divide-y divide-gray-200 rounded-md border border-gray-300 dark:divide-gray-800 dark:border-gray-700">
          {security.passkeys.map((passkey) => (
            <li
              key={passkey.id}
              className="flex flex-wrap items-start justify-between gap-4 p-4"
            >
              <div className="space-y-1">
                <p className="font-medium">
                  {passkey.nickname ?? t("account.passkeys.unnamed")}
                </p>
                <dl className="grid grid-cols-[auto_1fr] gap-x-3 text-sm text-gray-700 dark:text-gray-300">
                  <dt>{t("account.passkeys.created")}</dt>
                  <dd>{formatDate(passkey.inserted_at, i18n.language)}</dd>
                  <dt>{t("account.passkeys.lastUsed")}</dt>
                  <dd>
                    {passkey.last_used_at
                      ? formatDateTime(passkey.last_used_at, i18n.language)
                      : t("account.passkeys.neverUsed")}
                  </dd>
                  <dt>{t("account.passkeys.backup")}</dt>
                  <dd>{backupState(passkey)}</dd>
                </dl>
              </div>
              <Button
                variant="danger"
                disabled={last || remove.isPending}
                aria-describedby={last ? reasonId : undefined}
                onClick={() => setRemoving(passkey)}
              >
                {t("account.passkeys.remove")}{" "}
                <span className="sr-only">
                  {passkey.nickname ?? t("account.passkeys.unnamed")}
                </span>
              </Button>
            </li>
          ))}
        </ul>
      )}
      {last && (
        <p id={reasonId} className="text-sm text-gray-700 dark:text-gray-300">
          {t("account.factors.lastFactor")}
        </p>
      )}
      {adding ? (
        <PasskeyCreateForm
          onCreated={(result) => {
            setAdding(false);
            setStatus(t("account.passkeys.added"));
            onFactorChange(result.other_sessions);
          }}
          onCancel={() => setAdding(false)}
        />
      ) : (
        <Button
          variant="secondary"
          onClick={() => {
            setStatus(null);
            setAdding(true);
          }}
        >
          {t("account.passkeys.add")}
        </Button>
      )}
      <ConfirmDialog
        open={removing !== null}
        title={t("account.passkeys.removeTitle")}
        confirmLabel={t("account.passkeys.remove")}
        confirmVariant="danger"
        onConfirm={() => void confirmRemove()}
        onClose={() => setRemoving(null)}
      >
        <p>
          {t("account.passkeys.removeText", {
            name: removing?.nickname ?? t("account.passkeys.unnamed"),
          })}
        </p>
      </ConfirmDialog>
    </section>
  );
}
