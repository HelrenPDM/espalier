import { useState, type FormEvent } from "react";
import { useTranslation } from "react-i18next";
import {
  useRegisterPasskey,
  type PasskeyRegistrationResult,
} from "../api/account";
import { ApiError } from "../api/errors";
import { AlertRegion, Button, TextField } from "../app/forms";
import { useErrorText } from "../app/useErrorText";
import { classifyWebAuthnError } from "../auth/webauthn";

/**
 * The passkey path of the enrollment wizard and of "Add a passkey" (task
 * 0011 steps 9 and 12): a nickname of at most 60 characters, then
 * `startRegistration` without automatic registration. `onCreated` receives the
 * answer, which after an enrollment carries `recovery_codes` and
 * `session`; the form resets its mutation right after the call.
 */
export function PasskeyCreateForm({
  onCreated,
  onCancel,
}: {
  onCreated: (result: PasskeyRegistrationResult) => void | Promise<void>;
  onCancel?: () => void;
}) {
  const { t, i18n } = useTranslation();
  const errorText = useErrorText();
  const register = useRegisterPasskey();
  const [nickname, setNickname] = useState(() =>
    t("account.passkeys.defaultNickname", {
      date: new Intl.DateTimeFormat(i18n.language, {
        dateStyle: "medium",
      }).format(new Date()),
    }),
  );
  const [error, setError] = useState<string | null>(null);

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (register.isPending) return;
    setError(null);
    let result: PasskeyRegistrationResult;
    try {
      result = await register.mutateAsync(nickname);
    } catch (failure) {
      if (failure instanceof ApiError) {
        setError(
          failure.status === 422 && failure.code === "registration_failed"
            ? t("account.errors.registrationFailed")
            : errorText(failure),
        );
        return;
      }
      const kind = classifyWebAuthnError(failure);
      if (kind === "aborted") return;
      setError(
        kind === "duplicate"
          ? t("account.errors.passkeyExists")
          : kind === "cancelled"
            ? t("auth.errors.passkeyCancelled")
            : t("account.errors.registrationFailed"),
      );
      return;
    }
    register.reset();
    await onCreated(result);
  };

  return (
    <form onSubmit={(event) => void submit(event)} className="space-y-4">
      <AlertRegion>{error}</AlertRegion>
      <TextField
        label={t("account.passkeys.nickname")}
        hint={t("account.passkeys.nicknameHint")}
        name="nickname"
        autoComplete="off"
        maxLength={60}
        value={nickname}
        onChange={(event) => setNickname(event.target.value)}
      />
      <div className="flex flex-wrap gap-3">
        <Button type="submit" disabled={register.isPending}>
          {t("account.passkeys.create")}
        </Button>
        {onCancel && (
          <Button variant="secondary" onClick={onCancel}>
            {t("auth.forms.cancel")}
          </Button>
        )}
      </div>
    </form>
  );
}
