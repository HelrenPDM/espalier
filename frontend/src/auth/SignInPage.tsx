import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Navigate, useSearchParams } from "react-router";
import { LoadingStatus } from "../app/LoadingStatus";
import { safeReturnTo } from "./returnTo";
import { SecondFactorStep, type SecondFactorSession } from "./SecondFactorStep";
import { useSessionEvents } from "./sessionEvents";
import { useSession } from "./SessionProvider";
import { SignInFirstStep } from "./SignInFirstStep";

/** The location state of `/account/security` after a recovery code. */
export interface RecoveryCodeUsedState {
  recoveryCodesRemaining: number;
}

type Destination = { to: string; state?: RecoveryCodeUsedState };

/**
 * `/sign-in` (task 0011 step 6). An enrollment or recovery session goes on
 * to `/enroll`, a full session to `return_to`, and a pending second factor
 * opens the second-factor step. A completed sign-in refetches the session
 * through `sessionChanged("signed-in")`, and the page then navigates to
 * its destination: `return_to`, or `/account/security` after a recovery
 * code, where the page announces the codes left.
 */
export function SignInPage() {
  const { t } = useTranslation();
  const session = useSession();
  const { sessionChanged } = useSessionEvents();
  const [params] = useSearchParams();
  const returnTo = safeReturnTo(params.get("return_to"));
  const [step, setStep] = useState<"auto" | "first" | "second">("auto");
  const [restarted, setRestarted] = useState(false);
  const [destination, setDestination] = useState<Destination | null>(null);

  if (session.loading) return <LoadingStatus />;
  if (
    session.sessionStrength === "enrollment" ||
    session.sessionStrength === "recovery"
  )
    return <Navigate to="/enroll" replace />;
  if (
    session.user !== null &&
    (session.sessionStrength === "mfa" || session.sessionStrength === "demo")
  ) {
    const target = destination ?? { to: returnTo };
    return <Navigate to={target.to} state={target.state} replace />;
  }

  const signedIn = () => sessionChanged("signed-in");

  const secondFactorDone = async (body: SecondFactorSession) => {
    if (body.recovery_codes_remaining !== undefined)
      setDestination({
        to: "/account/security",
        state: { recoveryCodesRemaining: body.recovery_codes_remaining },
      });
    await signedIn();
  };

  if (step === "second" || (step === "auto" && session.pending !== null)) {
    return (
      <SecondFactorStep
        onSignedIn={secondFactorDone}
        onRestart={() => {
          setRestarted(true);
          setStep("first");
        }}
      />
    );
  }

  return (
    <SignInFirstStep
      returnTo={returnTo}
      notice={restarted ? t("auth.errors.signInRestart") : null}
      onSecondFactor={() => {
        setRestarted(false);
        setStep("second");
      }}
      onSignedIn={signedIn}
    />
  );
}
