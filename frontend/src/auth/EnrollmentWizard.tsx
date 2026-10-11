import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Navigate, useNavigate } from "react-router";
import { EndOtherSessionsPrompt } from "../account/EndOtherSessionsPrompt";
import { PasskeyCreateForm } from "../account/PasskeyCreateForm";
import { PasswordForm } from "../account/PasswordSection";
import { RecoveryCodesPanel } from "../account/RecoveryCodesPanel";
import { TotpSetup } from "../account/TotpSetup";
import { Button, FocusHeading } from "../app/forms";
import { LoadingStatus } from "../app/LoadingStatus";
import { takeReturnTo } from "./returnTo";
import { useSessionEvents } from "./sessionEvents";
import { useSession } from "./SessionProvider";

type Screen =
  "choose" | "passkey" | "password" | "totp" | "codes" | "others" | "done";

/** The members of a factor answer that complete an enrollment. */
type Completion = {
  recovery_codes?: string[];
  other_sessions: number;
  session?: unknown;
};

/**
 * `/enroll` (task 0011 step 9): the first second factor of an invitation,
 * of a first OIDC or LDAP sign-in, or after a recovery. It renders while
 * the session strength is `enrollment` or `recovery`, and after the
 * completion while it shows the recovery codes and the offer to end other
 * sessions (ASVS 6.3.3, 7.4.3).
 */
export function EnrollmentWizard() {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const session = useSession();
  const { sessionChanged } = useSessionEvents();
  const [screen, setScreen] = useState<Screen>("choose");
  const [codes, setCodes] = useState<string[] | null>(null);
  const [otherSessions, setOtherSessions] = useState(0);
  const [destination, setDestination] = useState("/");

  const finished =
    screen === "codes" || screen === "others" || screen === "done";
  if (session.loading) return <LoadingStatus />;
  if (
    !finished &&
    session.sessionStrength !== "enrollment" &&
    session.sessionStrength !== "recovery"
  )
    return <Navigate to="/sign-in" replace />;

  const recovery = session.sessionStrength === "recovery";

  const leave = (to: string) => void navigate(to, { replace: true });

  // The answer that completes the enrollment carries `recovery_codes` and
  // `session`: the server replaced the session token, so the session is
  // refetched at once, while the wizard keeps its screens.
  const complete = async (result: Completion) => {
    const to = recovery ? "/account/security" : (takeReturnTo() ?? "/");
    setDestination(to);
    setOtherSessions(result.other_sessions);
    if (result.recovery_codes && result.recovery_codes.length > 0) {
      setCodes(result.recovery_codes);
      setScreen("codes");
    } else if (result.other_sessions > 0) {
      setScreen("others");
    } else {
      setScreen("done");
    }
    await sessionChanged("renewed");
    if (
      !(result.recovery_codes && result.recovery_codes.length > 0) &&
      result.other_sessions === 0
    )
      leave(to);
  };

  const codesSaved = () => {
    setCodes(null);
    if (otherSessions > 0) setScreen("others");
    else {
      setScreen("done");
      leave(destination);
    }
  };

  const title = recovery
    ? t("auth.enroll.recoveryTitle")
    : t("auth.enroll.title");

  switch (screen) {
    case "codes":
      return codes ? (
        <RecoveryCodesPanel codes={codes} onDone={codesSaved} />
      ) : (
        <LoadingStatus />
      );
    case "others":
      return (
        <EndOtherSessionsPrompt
          onDone={() => {
            setScreen("done");
            leave(destination);
          }}
        />
      );
    case "done":
      return <LoadingStatus />;
    case "passkey":
      return (
        <section className="max-w-md space-y-4">
          <FocusHeading>{t("auth.enroll.passkeyTitle")}</FocusHeading>
          <p className="text-gray-700 dark:text-gray-300">
            {t("auth.enroll.passkeyText")}
          </p>
          <PasskeyCreateForm
            onCreated={complete}
            onCancel={() => setScreen("choose")}
          />
        </section>
      );
    case "password":
      return (
        <section className="max-w-md space-y-4">
          <FocusHeading>{t("auth.enroll.passwordTitle")}</FocusHeading>
          <p className="text-gray-700 dark:text-gray-300">
            {t("auth.enroll.passwordText")}
          </p>
          <PasswordForm
            requireCurrent={false}
            submitLabel={t("auth.enroll.passwordSubmit")}
            onChanged={() => setScreen("totp")}
          />
          <Button variant="secondary" onClick={() => setScreen("choose")}>
            {t("auth.forms.back")}
          </Button>
        </section>
      );
    case "totp":
      return (
        <section className="max-w-md space-y-4">
          <FocusHeading>{t("auth.enroll.totpTitle")}</FocusHeading>
          <TotpSetup
            onConfirmed={complete}
            onCancel={() => setScreen("choose")}
            onPasswordRequired={() => setScreen("password")}
          />
        </section>
      );
    case "choose":
      return (
        <section className="max-w-md space-y-6">
          <div>
            <FocusHeading>{title}</FocusHeading>
            <p className="mt-2 text-gray-700 dark:text-gray-300">
              {recovery ? t("auth.enroll.recoveryText") : t("auth.enroll.text")}
            </p>
          </div>
          <div className="flex flex-col gap-3">
            <Button onClick={() => setScreen("passkey")}>
              {t("auth.enroll.choosePasskey")}
            </Button>
            <Button variant="secondary" onClick={() => setScreen("totp")}>
              {t("auth.enroll.chooseTotp")}
            </Button>
          </div>
        </section>
      );
  }
}
