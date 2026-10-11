import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useConfirmEmail } from "../api/account";
import { ApiError, RECENT_AUTH_ERROR_CODE } from "../api/errors";
import { AlertRegion, Button, FocusHeading, StatusRegion } from "../app/forms";
import { linkClasses } from "../app/formStyles";
import { LoadingStatus } from "../app/LoadingStatus";
import { useSession } from "../auth/SessionProvider";
import { useFragmentToken } from "../auth/useFragmentToken";

type State = "idle" | "changed" | "signedOut" | "invalid";

/**
 * `/account/email/confirm`, the link of the e-mail change mail (0004 step
 * 20, README section 6.12). The token stays in memory; the request leaves
 * only after "Confirm new address". Without a session the page offers the
 * sign-in in a new tab and waits until this tab's session shows a user,
 * which the `signed-in` message of the other tab refreshes.
 */
export function EmailConfirmPage() {
  const { t } = useTranslation();
  const token = useFragmentToken();
  const { user, loading } = useSession();
  const confirm = useConfirmEmail();
  const [state, setState] = useState<State>("idle");

  if (token === undefined || loading) return <LoadingStatus />;

  const submit = async () => {
    if (confirm.isPending || token === null) return;
    try {
      await confirm.mutateAsync(token);
      setState("changed");
    } catch (failure) {
      if (failure instanceof ApiError && failure.status === 401)
        setState("signedOut");
      else if (
        failure instanceof ApiError &&
        failure.status === 403 &&
        failure.code === RECENT_AUTH_ERROR_CODE
      )
        setState("idle");
      else setState("invalid");
    }
  };

  const waiting = state === "signedOut" && user === null;

  return (
    <section className="max-w-md space-y-4">
      <FocusHeading>{t("account.email.confirmTitle")}</FocusHeading>
      <AlertRegion>
        {token === null || state === "invalid"
          ? t("auth.errors.linkInvalid")
          : state === "signedOut"
            ? t("account.email.signInFirst")
            : null}
      </AlertRegion>
      <StatusRegion>
        {state === "changed" ? t("account.email.changed") : null}
      </StatusRegion>
      {token !== null && state !== "changed" && state !== "invalid" && (
        <>
          <p className="text-gray-700 dark:text-gray-300">
            {t("account.email.confirmText")}
          </p>
          {state === "signedOut" && (
            <p>
              <a
                href="/sign-in"
                target="_blank"
                rel="noopener noreferrer"
                className={linkClasses}
              >
                {t("account.email.signInNewTab")}
              </a>
            </p>
          )}
          <Button
            disabled={confirm.isPending || waiting}
            onClick={() => void submit()}
          >
            {t("account.email.confirm")}
          </Button>
        </>
      )}
    </section>
  );
}
