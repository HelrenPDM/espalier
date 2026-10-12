import { Dialog, DialogPanel, DialogTitle } from "@headlessui/react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Button } from "../../app/forms";
import { CheckboxField } from "../adminParts";

/**
 * The confirmation of the reset of decision D11 (task 0015, step 12). It
 * states that every second factor and every session of the person ends
 * and that a local account receives a new invitation, and "Reset second
 * factors" stays disabled until the admin confirms that the organization
 * has verified the person's identity. The checkbox starts unchecked each
 * time the dialog opens.
 */
export function ResetFactorsDialog({
  name,
  onConfirm,
  onClose,
}: {
  /** The person whose factors are reset; `null` closes the dialog. */
  name: string | null;
  onConfirm: () => void;
  onClose: () => void;
}) {
  const { t } = useTranslation();
  const [verified, setVerified] = useState(false);
  const [shownFor, setShownFor] = useState(name);
  if (shownFor !== name) {
    setShownFor(name);
    setVerified(false);
  }

  return (
    <Dialog open={name !== null} onClose={onClose} className="relative z-50">
      <div className="fixed inset-0 bg-gray-900/40" aria-hidden="true" />
      <div className="fixed inset-0 flex items-center justify-center p-4">
        <DialogPanel className="w-full max-w-md rounded-lg bg-white p-6 text-gray-900 shadow-xl dark:bg-gray-900 dark:text-gray-100">
          <DialogTitle className="text-lg font-semibold">
            {t("admin.users.resetDialog.title")}
          </DialogTitle>
          <div className="mt-3 space-y-3 text-sm text-gray-700 dark:text-gray-300">
            <p>{t("admin.users.resetDialog.text", { name })}</p>
            <p>{t("admin.users.resetDialog.invitation")}</p>
          </div>
          <div className="mt-4">
            <CheckboxField
              label={t("admin.users.resetDialog.verified")}
              checked={verified}
              onChange={setVerified}
            />
          </div>
          <div className="mt-6 flex flex-wrap justify-end gap-3">
            <Button variant="secondary" onClick={onClose} data-autofocus>
              {t("auth.forms.cancel")}
            </Button>
            <Button variant="danger" disabled={!verified} onClick={onConfirm}>
              {t("admin.users.resetDialog.confirm")}
            </Button>
          </div>
        </DialogPanel>
      </div>
    </Dialog>
  );
}
