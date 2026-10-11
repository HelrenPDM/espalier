import { useEffect, useRef, useState, type FormEvent } from "react";
import { useTranslation } from "react-i18next";
import {
  useConfirmTotp,
  useTotpSetup,
  type TotpConfirmResult,
} from "../api/account";
import { ApiError } from "../api/errors";
import { AlertRegion, Button, StatusRegion, TextField } from "../app/forms";
import { LoadingStatus } from "../app/LoadingStatus";
import { useErrorText } from "../app/useErrorText";

const QR_PREFIX = "data:image/svg+xml";

/** The base32 secret in groups of four for reading and typing. */
const groupSecret = (secret: string) =>
  (secret.match(/.{1,4}/g) ?? []).join(" ");

/**
 * The authenticator app setup (task 0011 step 12): `POST /api/me/totp` on
 * mount, the QR code as `<img>` with the data URL (the SVG never enters the
 * DOM as markup, ASVS 3.2.2), the secret in groups of four with a copy
 * button, and the first code for `POST /api/me/totp/confirm`.
 *
 * Both mutations set `gcTime: 0` and are reset after the confirmation and
 * when the setup is cancelled or unmounts, so the secret, the `otpauth://`
 * URI and the QR code leave component state and the mutation cache. In an enrollment or
 * recovery session without a password, `onPasswordRequired` reports the
 * 409 `password_required`.
 */
export function TotpSetup({
  onConfirmed,
  onCancel,
  onPasswordRequired,
}: {
  onConfirmed: (result: TotpConfirmResult) => void | Promise<void>;
  onCancel?: () => void;
  onPasswordRequired?: () => void;
}) {
  const { t } = useTranslation();
  const errorText = useErrorText();
  const setup = useTotpSetup();
  const confirm = useConfirmTotp();
  const [code, setCode] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const started = useRef(false);
  const { mutate: start, reset: resetSetup } = setup;
  const resetConfirm = confirm.reset;
  const passwordRequired = useRef(onPasswordRequired);
  useEffect(() => {
    passwordRequired.current = onPasswordRequired;
  });

  useEffect(() => {
    if (started.current) return;
    started.current = true;
    start(undefined, {
      onError: (failure) => {
        if (
          failure instanceof ApiError &&
          failure.status === 409 &&
          failure.code === "password_required" &&
          passwordRequired.current
        ) {
          passwordRequired.current();
          return;
        }
        setError(errorText(failure));
      },
    });
  }, [errorText, start]);

  // On unmount the mutation observers detach, and `gcTime: 0` removes both
  // mutations from the cache. A reset in an effect cleanup would also run
  // on the simulated unmount of StrictMode and drop the pending setup.

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (confirm.isPending) return;
    setError(null);
    let result: TotpConfirmResult;
    try {
      result = await confirm.mutateAsync(code);
    } catch (failure) {
      setError(
        failure instanceof ApiError &&
          failure.status === 422 &&
          failure.code === "invalid_code"
          ? t("account.errors.invalidCode")
          : errorText(failure),
      );
      return;
    }
    resetSetup();
    resetConfirm();
    setCode("");
    await onConfirmed(result);
  };

  const cancel = () => {
    resetSetup();
    resetConfirm();
    onCancel?.();
  };

  const enrollment = setup.data;
  const qr =
    enrollment && enrollment.qr_svg_data_url.startsWith(QR_PREFIX)
      ? enrollment.qr_svg_data_url
      : null;

  return (
    <div className="space-y-4">
      <AlertRegion>{error}</AlertRegion>
      {setup.isPending && <LoadingStatus />}
      {enrollment && (
        <>
          <p className="text-gray-700 dark:text-gray-300">
            {t("account.totp.scan")}
          </p>
          {qr && (
            <img
              src={qr}
              alt={t("account.totp.qrAlt")}
              width={200}
              height={200}
              className="rounded-md bg-white p-2"
            />
          )}
          <div className="space-y-2">
            <p className="text-sm text-gray-700 dark:text-gray-300">
              {t("account.totp.secretLabel")}
            </p>
            <p className="font-mono text-base break-all">
              {groupSecret(enrollment.secret_base32)}
            </p>
            <Button
              variant="secondary"
              onClick={() =>
                void navigator.clipboard
                  .writeText(enrollment.secret_base32)
                  .then(() => setCopied(true))
                  .catch(() => setCopied(false))
              }
            >
              {t("account.totp.copySecret")}
            </Button>
            <StatusRegion>
              {copied ? t("account.totp.secretCopied") : null}
            </StatusRegion>
          </div>
          <form onSubmit={(event) => void submit(event)} className="space-y-4">
            <TextField
              label={t("account.totp.codeLabel")}
              name="code"
              value={code}
              onChange={(event) => setCode(event.target.value)}
              inputMode="numeric"
              autoComplete="one-time-code"
              pattern="[0-9]{6}"
              maxLength={6}
              required
            />
            <div className="flex flex-wrap gap-3">
              <Button type="submit" disabled={confirm.isPending}>
                {t("account.totp.confirm")}
              </Button>
              {onCancel && (
                <Button variant="secondary" onClick={cancel}>
                  {t("auth.forms.cancel")}
                </Button>
              )}
            </div>
          </form>
        </>
      )}
      {!enrollment && onCancel && !setup.isPending && (
        <Button variant="secondary" onClick={cancel}>
          {t("auth.forms.cancel")}
        </Button>
      )}
    </div>
  );
}
