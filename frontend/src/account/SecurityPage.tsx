import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useLocation } from "react-router";
import { useSecurity, useSessions } from "../api/account";
import { AlertRegion, Button, FocusHeading, StatusRegion } from "../app/forms";
import { LoadingStatus } from "../app/LoadingStatus";
import { useSession } from "../auth/SessionProvider";
import { EmailSection } from "./EmailSection";
import { EndOtherSessionsPrompt } from "./EndOtherSessionsPrompt";
import { LinkedAccountsSection } from "./LinkedAccountsSection";
import { PasskeySection } from "./PasskeySection";
import { PasswordSection } from "./PasswordSection";
import { RecoveryCodesSection } from "./RecoveryCodesSection";
import { SessionsSection } from "./SessionsSection";
import { TotpSection } from "./TotpSection";

/** The codes left after a sign-in with a recovery code (`SignInPage`). */
function recoveryCodesUsed(state: unknown): number | null {
  if (typeof state !== "object" || state === null) return null;
  const value = (state as { recoveryCodesRemaining?: unknown })
    .recoveryCodesRemaining;
  return typeof value === "number" ? value : null;
}

/**
 * `/account/security` behind `RequireAuth` (task 0011 step 12): passkeys,
 * the authenticator app, recovery codes, password, e-mail, connected
 * accounts and sessions of an `mfa` session. A demo session sees a notice
 * only. Every change passes the step-up dialog when the API asks for it
 * (ASVS 7.5.1); the page has its own sign-out button (ASVS 7.4.4).
 */
export function SecurityPage() {
  const { t } = useTranslation();
  const location = useLocation();
  const session = useSession();
  const mfa = session.sessionStrength === "mfa";
  const security = useSecurity({ enabled: mfa });
  const sessions = useSessions({ enabled: mfa });
  const [prompt, setPrompt] = useState(false);
  const [usedCodes] = useState(() => recoveryCodesUsed(location.state));

  const title = <FocusHeading>{t("account.title")}</FocusHeading>;

  if (!mfa) {
    return (
      <section className="max-w-2xl space-y-4">
        {title}
        <p className="text-gray-700 dark:text-gray-300">
          {t("account.demoNotice")}
        </p>
      </section>
    );
  }

  const onFactorChange = (otherSessions: number) => {
    if (otherSessions > 0) setPrompt(true);
  };
  const hasOtherSessions = (sessions.data ?? []).some(
    (entry) => !entry.current,
  );

  return (
    <div className="max-w-3xl space-y-10">
      <div className="space-y-3">
        {title}
        <StatusRegion>
          {usedCodes !== null
            ? t("account.recovery.usedNotice", { count: usedCodes })
            : null}
        </StatusRegion>
      </div>

      {prompt && <EndOtherSessionsPrompt onDone={() => setPrompt(false)} />}

      {security.isPending || sessions.isPending ? (
        <LoadingStatus />
      ) : security.data === undefined || sessions.data === undefined ? (
        <AlertRegion>{t("errors.generic")}</AlertRegion>
      ) : (
        <>
          {session.flags.adminPasskeyRequired && (
            <p className="rounded-md border border-amber-600 p-4 font-medium text-amber-900 dark:border-amber-400 dark:text-amber-200">
              {t("account.passkeys.adminRequired")}
            </p>
          )}
          <PasskeySection
            security={security.data}
            onFactorChange={onFactorChange}
          />
          <TotpSection
            security={security.data}
            onFactorChange={onFactorChange}
          />
          <RecoveryCodesSection
            security={security.data}
            onRegenerated={() => {
              if (hasOtherSessions) setPrompt(true);
            }}
          />
          <PasswordSection security={security.data} />
          {security.data.linked_providers.length === 0 && <EmailSection />}
          <LinkedAccountsSection security={security.data} />
          <SessionsSection sessions={sessions.data} />
        </>
      )}

      <section aria-labelledby="sign-out-heading" className="space-y-3">
        <h2 id="sign-out-heading" className="text-xl font-semibold">
          {t("account.signOut.title")}
        </h2>
        <Button variant="secondary" onClick={() => void session.signOut()}>
          {t("layout.signOut")}
        </Button>
      </section>
    </div>
  );
}
