import { useState, type FormEvent } from "react";
import { useTranslation } from "react-i18next";
import { useChangePassword, type SecuritySummary } from "../api/account";
import { ApiError, passwordErrorKeys } from "../api/errors";
import { AlertRegion, Button, PasswordField, StatusRegion } from "../app/forms";
import { useErrorText } from "../app/useErrorText";
import { useSessionEvents } from "../auth/sessionEvents";

/**
 * A password form (task 0011 steps 9 and 12; ASVS 6.2.2, 6.2.3, 6.2.6,
 * 6.2.7, 6.2.9). The new password has a reveal button, the code-point
 * counter after NFC normalization and the guidance of NIST SP 800-63B-4
 * section 3.1.1.2; it is sent as typed, and the server normalizes it. A 422
 * `validation_failed` names the reason below the field. The 200 answer
 * carries a new session row and CSRF token, so success calls
 * `sessionChanged("renewed")`.
 *
 * With `requireCurrent` the form also asks for the current password; an
 * enrollment or recovery session sets the password without it.
 */
export function PasswordForm({
  requireCurrent,
  submitLabel,
  onChanged,
}: {
  requireCurrent: boolean;
  submitLabel: string;
  onChanged: () => void | Promise<void>;
}) {
  const { t } = useTranslation();
  const errorText = useErrorText();
  const { sessionChanged } = useSessionEvents();
  const change = useChangePassword();
  const [current, setCurrent] = useState("");
  const [password, setPassword] = useState("");
  const [alert, setAlert] = useState<string | null>(null);
  const [passwordErrors, setPasswordErrors] = useState<string[]>([]);
  const [currentErrors, setCurrentErrors] = useState<string[]>([]);

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (change.isPending) return;
    setAlert(null);
    setPasswordErrors([]);
    setCurrentErrors([]);
    try {
      await change.mutateAsync(
        requireCurrent ? { current_password: current, password } : { password },
      );
    } catch (failure) {
      const body = failure instanceof ApiError ? failure.body : null;
      const newKeys = passwordErrorKeys(body).map((key) => t(key));
      const currentKeys = passwordErrorKeys(body, "current_password").map(
        (key) => t(key),
      );
      setPasswordErrors(newKeys);
      setCurrentErrors(currentKeys);
      setAlert(
        newKeys.length > 0
          ? t("account.errors.passwordRejected")
          : (currentKeys[0] ?? errorText(failure)),
      );
      return;
    }
    change.reset();
    setCurrent("");
    setPassword("");
    await sessionChanged("renewed");
    await onChanged();
  };

  return (
    <form onSubmit={(event) => void submit(event)} className="space-y-4">
      <AlertRegion>{alert}</AlertRegion>
      {requireCurrent && (
        <PasswordField
          label={t("account.password.current")}
          name="current_password"
          autoComplete="current-password"
          value={current}
          onChange={setCurrent}
          errors={currentErrors}
          required
        />
      )}
      <PasswordField
        label={t("account.password.new")}
        name="password"
        autoComplete="new-password"
        value={password}
        onChange={setPassword}
        counter
        hint={t("account.password.guidance")}
        errors={passwordErrors}
        required
      />
      <Button type="submit" disabled={change.isPending}>
        {submitLabel}
      </Button>
    </form>
  );
}

/**
 * The password section of the security page. An account with an external
 * identity signs in through its provider only (0004 step 16), so it shows
 * no form.
 */
export function PasswordSection({ security }: { security: SecuritySummary }) {
  const { t } = useTranslation();
  const [changed, setChanged] = useState(false);

  return (
    <section aria-labelledby="password-heading" className="space-y-4">
      <h2 id="password-heading" className="text-xl font-semibold">
        {t("account.password.title")}
      </h2>
      {security.linked_providers.length > 0 ? (
        <p className="text-gray-700 dark:text-gray-300">
          {t("account.password.external")}
        </p>
      ) : security.password_set ? (
        <>
          <StatusRegion>
            {changed ? t("account.password.changed") : null}
          </StatusRegion>
          <PasswordForm
            requireCurrent
            submitLabel={t("account.password.change")}
            onChanged={() => setChanged(true)}
          />
        </>
      ) : (
        <p className="text-gray-700 dark:text-gray-300">
          {t("account.password.notSet")}
        </p>
      )}
    </section>
  );
}
