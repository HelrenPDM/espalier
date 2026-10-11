import { useState, type FormEvent } from "react";
import { useTranslation } from "react-i18next";
import { useNavigate } from "react-router";
import { useApiClient } from "../api/apiClientContext";
import { ApiError, unwrap } from "../api/errors";
import {
  AlertRegion,
  Button,
  FocusHeading,
  StatusRegion,
  TextField,
} from "../app/forms";
import { LoadingStatus } from "../app/LoadingStatus";
import { useErrorText } from "../app/useErrorText";
import { useSessionEvents } from "./sessionEvents";
import { useSession } from "./SessionProvider";
import { useFragmentToken } from "./useFragmentToken";

/**
 * `/invite` (task 0011 step 9). With `#token=` from the invitation mail, a
 * click on "Continue" accepts the invitation; the page sends nothing before
 * the click, which keeps the two-step consumption of e-mail tokens (README
 * section 6.4, ASVS 7.6.2). Without a token it offers the invitation
 * request of `SIGNUP=invite` or `domain`.
 */
export function InvitationPage() {
  const token = useFragmentToken();
  const { loading, flags } = useSession();

  if (token === undefined || loading) return <LoadingStatus />;
  if (token !== null) return <AcceptInvitation token={token} />;
  if (flags.signup === "invite" || flags.signup === "domain")
    return <RequestInvitation />;
  return <InvalidLink />;
}

function InvalidLink() {
  const { t } = useTranslation();
  return (
    <section className="max-w-md space-y-4">
      <FocusHeading>{t("auth.invitation.title")}</FocusHeading>
      <AlertRegion>{t("auth.errors.linkInvalid")}</AlertRegion>
    </section>
  );
}

function AcceptInvitation({ token }: { token: string }) {
  const { t } = useTranslation();
  const client = useApiClient();
  const navigate = useNavigate();
  const { sessionChanged } = useSessionEvents();
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const accept = async () => {
    if (busy) return;
    setBusy(true);
    setError(null);
    try {
      unwrap(
        await client.POST("/api/auth/invitations/accept", { body: { token } }),
      );
      await sessionChanged("signed-in");
      await navigate("/enroll", { replace: true });
    } catch {
      setError(t("auth.errors.linkInvalid"));
    } finally {
      setBusy(false);
    }
  };

  return (
    <section className="max-w-md space-y-4">
      <FocusHeading>{t("auth.invitation.title")}</FocusHeading>
      <p className="text-gray-700 dark:text-gray-300">
        {t("auth.invitation.text")}
      </p>
      <AlertRegion>{error}</AlertRegion>
      <Button disabled={busy} onClick={() => void accept()}>
        {t("auth.forms.continue")}
      </Button>
    </section>
  );
}

function RequestInvitation() {
  const { t } = useTranslation();
  const client = useApiClient();
  const errorText = useErrorText();
  const [email, setEmail] = useState("");
  const [sent, setSent] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (busy) return;
    setBusy(true);
    setError(null);
    setSent(false);
    try {
      unwrap(await client.POST("/api/auth/invitations", { body: { email } }));
      setSent(true);
    } catch (failure) {
      // The same answer for every address (ASVS 6.3.8), except the limit.
      if (failure instanceof ApiError && failure.status === 429)
        setError(errorText(failure));
      else setSent(true);
    } finally {
      setBusy(false);
    }
  };

  return (
    <section className="max-w-md space-y-4">
      <FocusHeading>{t("auth.invitation.requestTitle")}</FocusHeading>
      <p className="text-gray-700 dark:text-gray-300">
        {t("auth.invitation.requestText")}
      </p>
      <form onSubmit={(event) => void submit(event)} className="space-y-4">
        <AlertRegion>{error}</AlertRegion>
        <StatusRegion>{sent ? t("auth.invitation.sent") : null}</StatusRegion>
        <TextField
          label={t("auth.signIn.email")}
          type="email"
          name="email"
          autoComplete="email"
          value={email}
          onChange={(event) => setEmail(event.target.value)}
          required
        />
        <Button type="submit" disabled={busy}>
          {t("auth.invitation.requestSubmit")}
        </Button>
      </form>
    </section>
  );
}
