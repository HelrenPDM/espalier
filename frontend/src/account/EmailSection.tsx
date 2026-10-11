import { useState, type FormEvent } from "react";
import { useTranslation } from "react-i18next";
import { useChangeEmail } from "../api/account";
import { ApiError, RECENT_AUTH_ERROR_CODE } from "../api/errors";
import { Button, StatusRegion, TextField, AlertRegion } from "../app/forms";
import { useSession } from "../auth/SessionProvider";

/**
 * The e-mail address of a local account (task 0011 step 12). The
 * confirmation link goes to the new address, and the page shows the same
 * text for every outcome (ASVS 6.3.8). A closed step-up dialog leaves the
 * form as it was.
 */
export function EmailSection() {
  const { t } = useTranslation();
  const { user } = useSession();
  const change = useChangeEmail();
  const [email, setEmail] = useState("");
  const [sent, setSent] = useState(false);

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (change.isPending) return;
    setSent(false);
    try {
      await change.mutateAsync(email);
    } catch (failure) {
      if (
        failure instanceof ApiError &&
        failure.status === 403 &&
        failure.code === RECENT_AUTH_ERROR_CODE
      )
        return;
    }
    change.reset();
    setEmail("");
    setSent(true);
  };

  return (
    <section aria-labelledby="email-heading" className="space-y-4">
      <h2 id="email-heading" className="text-xl font-semibold">
        {t("account.email.title")}
      </h2>
      {user?.email && (
        <p className="text-gray-700 dark:text-gray-300">
          {t("account.email.current")}{" "}
          <span className="font-medium text-gray-900 dark:text-gray-100">
            {user.email}
          </span>
        </p>
      )}
      <form onSubmit={(event) => void submit(event)} className="space-y-4">
        <AlertRegion />
        <StatusRegion>{sent ? t("account.email.sent") : null}</StatusRegion>
        <TextField
          label={t("account.email.new")}
          type="email"
          name="email"
          autoComplete="email"
          value={email}
          onChange={(event) => setEmail(event.target.value)}
          required
        />
        <Button type="submit" disabled={change.isPending}>
          {t("account.email.submit")}
        </Button>
      </form>
    </section>
  );
}
