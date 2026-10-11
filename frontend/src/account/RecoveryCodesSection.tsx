import { useState } from "react";
import { useTranslation } from "react-i18next";
import {
  useRegenerateRecoveryCodes,
  type SecuritySummary,
} from "../api/account";
import { ConfirmDialog } from "../app/ConfirmDialog";
import { AlertRegion, Button } from "../app/forms";
import { useErrorText } from "../app/useErrorText";
import { RecoveryCodesPanel } from "./RecoveryCodesPanel";

/** At or below this number of codes left, the section warns. */
const LOW = 3;

/**
 * The recovery codes left and their regeneration behind a confirmation
 * (task 0011 step 12). The new codes appear once in `RecoveryCodesPanel`.
 */
export function RecoveryCodesSection({
  security,
  onRegenerated,
}: {
  security: SecuritySummary;
  onRegenerated: () => void;
}) {
  const { t } = useTranslation();
  const errorText = useErrorText();
  const regenerate = useRegenerateRecoveryCodes();
  const [confirming, setConfirming] = useState(false);
  const [codes, setCodes] = useState<string[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const { remaining } = security.recovery_codes;

  const create = async () => {
    setConfirming(false);
    setError(null);
    try {
      setCodes(await regenerate.mutateAsync());
    } catch (failure) {
      setError(errorText(failure));
    }
  };

  const done = () => {
    setCodes(null);
    regenerate.reset();
    onRegenerated();
  };

  return (
    <section aria-labelledby="recovery-heading" className="space-y-4">
      <h2 id="recovery-heading" className="text-xl font-semibold">
        {t("account.recovery.title")}
      </h2>
      <AlertRegion>{error}</AlertRegion>
      {codes ? (
        <RecoveryCodesPanel codes={codes} onDone={done} />
      ) : (
        <>
          <p className="text-gray-700 dark:text-gray-300">
            {t("account.recovery.remaining", { count: remaining })}
          </p>
          {remaining <= LOW && (
            <p className="font-medium text-amber-800 dark:text-amber-300">
              {t("account.recovery.low")}
            </p>
          )}
          <Button
            variant="secondary"
            disabled={regenerate.isPending}
            onClick={() => setConfirming(true)}
          >
            {t("account.recovery.regenerate")}
          </Button>
        </>
      )}
      <ConfirmDialog
        open={confirming}
        title={t("account.recovery.regenerateTitle")}
        confirmLabel={t("account.recovery.regenerate")}
        onConfirm={() => void create()}
        onClose={() => setConfirming(false)}
      >
        <p>{t("account.recovery.regenerateText")}</p>
      </ConfirmDialog>
    </section>
  );
}
