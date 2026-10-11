import { useId, useState } from "react";
import { useTranslation } from "react-i18next";
import { productName } from "../app/product";
import { Button, FocusHeading, StatusRegion } from "../app/forms";

/**
 * Shows new recovery codes once (task 0011 step 10). The codes come in the
 * display form of 0005 step 11 (`ABCD-EFGH-IJKL-MNOP-QRST-UVWX-YZ`). They
 * live in the state of the caller only and never reach storage, the URL or
 * the console; `onDone` removes them and resets the mutation that returned
 * them.
 */
export function RecoveryCodesPanel({
  codes,
  onDone,
}: {
  codes: readonly string[];
  onDone: () => void;
}) {
  const { t } = useTranslation();
  const checkboxId = useId();
  const [saved, setSaved] = useState(false);
  const [status, setStatus] = useState<string | null>(null);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(codes.join("\n"));
      setStatus(t("account.recovery.copied"));
    } catch {
      setStatus(t("account.recovery.copyFailed"));
    }
  };

  const download = () => {
    const text = [
      t("account.recovery.fileHeader", {
        product: productName,
        host: window.location.host,
      }),
      "",
      ...codes,
      "",
    ].join("\n");
    const url = URL.createObjectURL(
      new Blob([text], { type: "text/plain;charset=utf-8" }),
    );
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = "recovery-codes.txt";
    document.body.append(anchor);
    anchor.click();
    anchor.remove();
    URL.revokeObjectURL(url);
  };

  return (
    <section className="max-w-xl space-y-4">
      <FocusHeading level={2}>{t("account.recovery.panelTitle")}</FocusHeading>
      <p className="text-gray-700 dark:text-gray-300">
        {t("account.recovery.panelText")}
      </p>
      <ol className="grid gap-2 rounded-md border border-gray-300 p-4 font-mono text-base sm:grid-cols-2 dark:border-gray-700">
        {codes.map((code) => (
          <li key={code}>{code}</li>
        ))}
      </ol>
      <div className="flex flex-wrap gap-3">
        <Button variant="secondary" onClick={() => void copy()}>
          {t("account.recovery.copy")}
        </Button>
        <Button variant="secondary" onClick={download}>
          {t("account.recovery.download")}
        </Button>
      </div>
      <StatusRegion>{status}</StatusRegion>
      <div className="flex items-center gap-2">
        <input
          id={checkboxId}
          type="checkbox"
          checked={saved}
          onChange={(event) => setSaved(event.target.checked)}
          className="size-4 rounded border-gray-500 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent-500"
        />
        <label htmlFor={checkboxId}>{t("account.recovery.saved")}</label>
      </div>
      <Button disabled={!saved} onClick={onDone}>
        {t("auth.forms.continue")}
      </Button>
    </section>
  );
}
