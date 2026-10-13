import { Dialog, DialogPanel, DialogTitle } from "@headlessui/react";
import type { ReactNode } from "react";

/**
 * A dialog of the draft page in the frame of `ConfirmDialog`: a Headless
 * UI `Dialog`, which traps the focus and returns it to the control that
 * opened it, with a title, a body and a row of actions. Escape calls
 * `onClose`. A form dialog passes `onSubmit`, so Enter in a field submits.
 */
export function WorkbenchDialog({
  open,
  title,
  children,
  actions,
  onClose,
  onSubmit,
}: {
  open: boolean;
  title: string;
  children: ReactNode;
  actions: ReactNode;
  onClose: () => void;
  onSubmit?: () => void;
}) {
  const body = (
    <>
      <div className="mt-3 space-y-4 text-sm text-gray-700 dark:text-gray-300">
        {children}
      </div>
      <div className="mt-6 flex flex-wrap justify-end gap-3">{actions}</div>
    </>
  );
  return (
    <Dialog open={open} onClose={onClose} className="relative z-50">
      <div className="fixed inset-0 bg-gray-900/40" aria-hidden="true" />
      <div className="fixed inset-0 flex items-center justify-center overflow-y-auto p-4">
        <DialogPanel className="w-full max-w-lg rounded-lg bg-white p-6 text-gray-900 shadow-xl dark:bg-gray-900 dark:text-gray-100">
          <DialogTitle className="text-lg font-semibold break-words">
            {title}
          </DialogTitle>
          {onSubmit === undefined ? (
            body
          ) : (
            <form
              noValidate
              onSubmit={(event) => {
                event.preventDefault();
                onSubmit();
              }}
            >
              {body}
            </form>
          )}
        </DialogPanel>
      </div>
    </Dialog>
  );
}
