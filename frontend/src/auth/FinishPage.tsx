import { useQueryClient } from "@tanstack/react-query";
import { useEffect, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import { Link, useNavigate, useSearchParams } from "react-router";
import { securityQueryKey } from "../api/account";
import { useApiClient } from "../api/apiClientContext";
import { ApiError, unwrap } from "../api/errors";
import { sessionQueryOptions } from "../api/session";
import { AlertRegion, FocusHeading, StatusRegion } from "../app/forms";
import { linkClasses } from "../app/formStyles";
import { LoadingStatus } from "../app/LoadingStatus";
import { takeFragmentParam } from "./fragment";
import { takeReturnTo } from "./returnTo";
import { SecondFactorStep, type SecondFactorSession } from "./SecondFactorStep";
import { useSessionEvents } from "./sessionEvents";
import { useSession } from "./SessionProvider";

type Outcome =
  | { kind: "pending" }
  | { kind: "second_factor" }
  | { kind: "linked" }
  | {
      kind: "error";
      key:
        | "auth.errors.signInFailed"
        | "auth.errors.signInRestart"
        | "account.errors.identityInUse"
        | "account.errors.providerAlreadyLinked";
    };

/**
 * `/auth/finish`, the same-origin end of an OIDC flow (task 0011 step 8,
 * README sections 6.5 and 6.12). The callback redirects here with the
 * ticket in the fragment, or with `?error=<code>` after a failure. The
 * ticket works once, so a ref guards the effect against the second run of
 * StrictMode.
 */
export function FinishPage() {
  const { t } = useTranslation();
  const client = useApiClient();
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const { sessionChanged } = useSessionEvents();
  const { user } = useSession();
  const [params] = useSearchParams();
  const callbackError = params.get("error");
  const started = useRef(false);
  const [outcome, setOutcome] = useState<Outcome>(() =>
    callbackError === null
      ? { kind: "pending" }
      : {
          kind: "error",
          key:
            callbackError === "oidc_identity_in_use"
              ? "account.errors.identityInUse"
              : "auth.errors.signInFailed",
        },
  );

  useEffect(() => {
    if (callbackError !== null || started.current) return;
    started.current = true;
    const ticket = takeFragmentParam("ticket");

    const finish = async () => {
      if (ticket === null || ticket === "") {
        setOutcome({ kind: "error", key: "auth.errors.signInFailed" });
        return;
      }
      try {
        // The POST needs the CSRF token of the session.
        await queryClient.ensureQueryData(sessionQueryOptions(client));
        const body = unwrap(
          await client.POST("/api/auth/finish", { body: { ticket } }),
        );
        if ("next" in body) {
          if (body.next === "second_factor") {
            setOutcome({ kind: "second_factor" });
          } else {
            await sessionChanged("signed-in");
            await navigate("/enroll", { replace: true });
          }
        } else if (body.linked === true) {
          takeReturnTo();
          await queryClient.invalidateQueries({ queryKey: securityQueryKey });
          setOutcome({ kind: "linked" });
        } else {
          await sessionChanged("signed-in");
          await navigate(takeReturnTo() ?? "/", { replace: true });
        }
      } catch (failure) {
        const code = failure instanceof ApiError ? failure.code : null;
        setOutcome({
          kind: "error",
          key:
            code === "identity_in_use"
              ? "account.errors.identityInUse"
              : code === "provider_already_linked"
                ? "account.errors.providerAlreadyLinked"
                : "auth.errors.signInFailed",
        });
      }
    };
    void finish();
  }, [callbackError, client, navigate, queryClient, sessionChanged]);

  const secondFactorDone = async (body: SecondFactorSession) => {
    await sessionChanged("signed-in");
    if (body.recovery_codes_remaining !== undefined) {
      takeReturnTo();
      await navigate("/account/security", {
        replace: true,
        state: { recoveryCodesRemaining: body.recovery_codes_remaining },
      });
    } else {
      await navigate(takeReturnTo() ?? "/", { replace: true });
    }
  };

  if (outcome.kind === "second_factor") {
    return (
      <SecondFactorStep
        onSignedIn={secondFactorDone}
        onRestart={() =>
          setOutcome({ kind: "error", key: "auth.errors.signInRestart" })
        }
      />
    );
  }

  const next =
    user !== null ? (
      <Link to="/account/security" className={linkClasses}>
        {t("auth.finish.toSecurity")}
      </Link>
    ) : (
      <Link to="/sign-in" className={linkClasses}>
        {t("auth.finish.toSignIn")}
      </Link>
    );

  return (
    <section className="max-w-md space-y-4">
      <FocusHeading>{t("auth.finish.title")}</FocusHeading>
      <AlertRegion>
        {outcome.kind === "error" ? t(outcome.key) : null}
      </AlertRegion>
      <StatusRegion>
        {outcome.kind === "linked" ? t("account.identities.linked") : null}
      </StatusRegion>
      {outcome.kind === "pending" ? <LoadingStatus /> : <p>{next}</p>}
    </section>
  );
}
