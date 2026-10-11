import { Dialog, DialogPanel, DialogTitle } from "@headlessui/react";
import type { ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { Button } from "./forms";
import type { ButtonVariant } from "./formStyles";

/**
 * A confirmation in a Headless UI `Dialog`, which traps focus and returns
 * it to the trigger on close. "Cancel" and Escape call `onClose` and send
 * nothing; the confirm button calls `onConfirm`.
 */
export function ConfirmDialog({
  open,
  title,
  children,
  confirmLabel,
  confirmVariant = "primary",
  onConfirm,
  onClose,
}: {
  open: boolean;
  title: string;
  children: ReactNode;
  confirmLabel: string;
  confirmVariant?: ButtonVariant;
  onConfirm: () => void;
  onClose: () => void;
}) {
  const { t } = useTranslation();
  return (
    <Dialog open={open} onClose={onClose} className="relative z-50">
      <div className="fixed inset-0 bg-gray-900/40" aria-hidden="true" />
      <div className="fixed inset-0 flex items-center justify-center p-4">
        <DialogPanel className="w-full max-w-md rounded-lg bg-white p-6 text-gray-900 shadow-xl dark:bg-gray-900 dark:text-gray-100">
          <DialogTitle className="text-lg font-semibold">{title}</DialogTitle>
          <div className="mt-3 space-y-3 text-sm text-gray-700 dark:text-gray-300">
            {children}
          </div>
          <div className="mt-6 flex flex-wrap justify-end gap-3">
            <Button variant="secondary" onClick={onClose} data-autofocus>
              {t("auth.forms.cancel")}
            </Button>
            <Button variant={confirmVariant} onClick={onConfirm}>
              {confirmLabel}
            </Button>
          </div>
        </DialogPanel>
      </div>
    </Dialog>
  );
}
