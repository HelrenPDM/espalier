import { startAuthentication } from "@simplewebauthn/browser";
import { useId, useState, type FormEvent } from "react";
import { useTranslation } from "react-i18next";
import { Link } from "react-router";
import { useApiClient } from "../api/apiClientContext";
import { ApiError, unwrap } from "../api/errors";
import type { Provider } from "../api/session";
import {
  AlertRegion,
  Button,
  FocusHeading,
  PasswordField,
  TextField,
} from "../app/forms";
import { linkClasses } from "../app/formStyles";
import { useErrorText } from "../app/useErrorText";
import { rememberReturnTo } from "./returnTo";
import { useSession } from "./SessionProvider";
import { useConditionalPasskey } from "./useConditionalPasskey";
import { classifyWebAuthnError } from "./webauthn";

/** The demo slots of 0004 (`POST /api/auth/demo`, slot 1 to 20). */
const DEMO_SLOTS = Array.from({ length: 20 }, (_, index) => index + 1);

/** Values that RFC 4513 section 5.1.2 asks clients to refuse. */
const blank = (value: string) => value.trim() === "";

type StepProps = {
  /** The checked return path of `return_to`. */
  returnTo: string;
  /** A message from an earlier step, such as `auth.errors.signInRestart`. */
  notice: string | null;
  /** A first factor succeeded and the second factor is pending. */
  onSecondFactor: () => void;
  /** A session started; the caller refetches it and navigates. */
  onSignedIn: () => void | Promise<void>;
};

/**
 * The first step of the sign-in page (task 0011 step 6): the passkey
 * button, the e-mail and password form, one button per redirect provider
 * and one form per credentials provider in the configured order, the demo
 * list, and the links to recovery and to the invitation request. Every
 * action first calls `stop()` of the conditional passkey request.
 */
export function SignInFirstStep({
  returnTo,
  notice,
  onSecondFactor,
  onSignedIn,
}: StepProps) {
  const { t } = useTranslation();
  const client = useApiClient();
  const errorText = useErrorText();
  const { providers, flags } = useSession();
  const [passkeyError, setPasskeyError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const stop = useConditionalPasskey(() => void onSignedIn(), {
    enabled: flags.localAccounts,
    onRejected: () => setPasskeyError(t("auth.errors.signInFailed")),
  });

  const signInWithPasskey = async () => {
    stop();
    if (busy) return;
    setBusy(true);
    setPasskeyError(null);
    try {
      const options = unwrap(
        await client.POST("/api/auth/passkey/options", {
          body: { purpose: "sign_in" },
        }),
      );
      let assertion;
      try {
        assertion = await startAuthentication({ optionsJSON: options });
      } catch (failure) {
        const kind = classifyWebAuthnError(failure);
        if (kind !== "aborted")
          setPasskeyError(
            kind === "cancelled"
              ? t("auth.errors.passkeyCancelled")
              : t("auth.errors.signInFailed"),
          );
        return;
      }
      unwrap(await client.POST("/api/auth/passkey", { body: assertion }));
      await onSignedIn();
    } catch (failure) {
      setPasskeyError(errorText(failure));
    } finally {
      setBusy(false);
    }
  };

  const startRedirect = (provider: Provider) => {
    stop();
    rememberReturnTo(returnTo);
    window.location.assign(provider.startUrl);
  };

  const showInvitationLink =
    flags.localAccounts &&
    (flags.signup === "invite" || flags.signup === "domain");

  return (
    <section className="max-w-md space-y-8">
      <div className="space-y-3">
        <FocusHeading>{t("auth.signIn.title")}</FocusHeading>
        <AlertRegion>{notice}</AlertRegion>
      </div>

      {flags.localAccounts && (
        <div className="space-y-3">
          <AlertRegion>{passkeyError}</AlertRegion>
          <Button
            className="w-full"
            disabled={busy}
            onClick={() => void signInWithPasskey()}
          >
            {t("auth.signIn.passkey")}
          </Button>
        </div>
      )}

      {flags.localAccounts && (
        <PasswordSignInForm onStart={stop} onSecondFactor={onSecondFactor} />
      )}

      {providers.length > 0 && (
        <div className="space-y-4">
          <h2 className="text-lg font-semibold">
            {t("auth.signIn.providers")}
          </h2>
          {providers.map((provider) =>
            provider.kind === "redirect" ? (
              <Button
                key={provider.key}
                variant="secondary"
                className="w-full"
                onClick={() => startRedirect(provider)}
              >
                {provider.label}
              </Button>
            ) : (
              <CredentialsSignInForm
                key={provider.key}
                provider={provider}
                onStart={stop}
                onSecondFactor={onSecondFactor}
                onSignedIn={onSignedIn}
              />
            ),
          )}
        </div>
      )}

      {flags.demo && <DemoSignIn onStart={stop} onSignedIn={onSignedIn} />}

      {flags.localAccounts && (
        <ul className="space-y-2">
          <li>
            <Link to="/recover" className={linkClasses} onClick={stop}>
              {t("auth.signIn.lostAccess")}
            </Link>
          </li>
          {showInvitationLink && (
            <li>
              <Link to="/invite" className={linkClasses} onClick={stop}>
                {t("auth.signIn.requestInvitation")}
              </Link>
            </li>
          )}
        </ul>
      )}
    </section>
  );
}

function PasswordSignInForm({
  onStart,
  onSecondFactor,
}: {
  onStart: () => void;
  onSecondFactor: () => void;
}) {
  const { t } = useTranslation();
  const client = useApiClient();
  const errorText = useErrorText();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    onStart();
    if (busy) return;
    setBusy(true);
    setError(null);
    try {
      unwrap(
        await client.POST("/api/auth/password", { body: { email, password } }),
      );
      setPassword("");
      onSecondFactor();
    } catch (failure) {
      setError(errorText(failure));
    } finally {
      setBusy(false);
    }
  };

  return (
    <form
      onSubmit={(event) => void submit(event)}
      className="space-y-4"
      aria-label={t("auth.signIn.passwordForm")}
    >
      <AlertRegion>{error}</AlertRegion>
      {/* The only input with `webauthn`: startAuthentication looks for
          input[autocomplete$='webauthn'] (conditional UI). */}
      <TextField
        id="signin-email"
        type="email"
        name="username"
        autoComplete="username webauthn"
        label={t("auth.signIn.email")}
        value={email}
        onChange={(event) => setEmail(event.target.value)}
        required
      />
      <PasswordField
        label={t("auth.signIn.password")}
        name="password"
        autoComplete="current-password"
        value={password}
        onChange={setPassword}
        required
      />
      <Button type="submit" disabled={busy}>
        {t("auth.signIn.passwordSubmit")}
      </Button>
    </form>
  );
}

/**
 * The form of a provider with `kind` `credentials` (0007 step 5). It posts
 * through the typed operation `POST /api/auth/ldap/{provider}`, whose path
 * equals the entry's `startUrl`.
 */
function CredentialsSignInForm({
  provider,
  onStart,
  onSecondFactor,
  onSignedIn,
}: {
  provider: Provider;
  onStart: () => void;
  onSecondFactor: () => void;
  onSignedIn: () => void | Promise<void>;
}) {
  const { t } = useTranslation();
  const client = useApiClient();
  const errorText = useErrorText();
  const titleId = useId();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    onStart();
    if (busy) return;
    if (blank(username) || blank(password)) {
      setError(t("auth.errors.credentialsRequired"));
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const { next } = unwrap(
        await client.POST("/api/auth/ldap/{provider}", {
          params: { path: { provider: provider.key } },
          body: { username, password },
        }),
      );
      setPassword("");
      if (next === "second_factor") onSecondFactor();
      else await onSignedIn();
    } catch (failure) {
      if (
        failure instanceof ApiError &&
        failure.status === 409 &&
        failure.code === "link_required"
      )
        setError(t("auth.errors.linkRequired"));
      else setError(errorText(failure));
    } finally {
      setBusy(false);
    }
  };

  return (
    <form
      onSubmit={(event) => void submit(event)}
      className="space-y-4 rounded-md border border-gray-300 p-4 dark:border-gray-700"
      aria-labelledby={titleId}
      noValidate
    >
      <h3 id={titleId} className="font-semibold">
        {provider.label}
      </h3>
      <AlertRegion>{error}</AlertRegion>
      <TextField
        label={t("auth.signIn.username")}
        name="username"
        autoComplete="username"
        autoCapitalize="off"
        spellCheck={false}
        value={username}
        onChange={(event) => setUsername(event.target.value)}
        required
      />
      <PasswordField
        label={t("auth.signIn.password")}
        name="password"
        autoComplete="current-password"
        value={password}
        onChange={setPassword}
        required
      />
      <Button type="submit" variant="secondary" disabled={busy}>
        {t("auth.signIn.credentialsSubmit", { label: provider.label })}
      </Button>
    </form>
  );
}

/** One button per demo slot; the request of 0010's `signInAsDemo`. */
function DemoSignIn({
  onStart,
  onSignedIn,
}: {
  onStart: () => void;
  onSignedIn: () => void | Promise<void>;
}) {
  const { t } = useTranslation();
  const client = useApiClient();
  const errorText = useErrorText();
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const signIn = async (slot: number) => {
    onStart();
    if (busy) return;
    setBusy(true);
    setError(null);
    try {
      unwrap(await client.POST("/api/auth/demo", { body: { slot } }));
      await onSignedIn();
    } catch (failure) {
      setError(errorText(failure));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="space-y-3">
      <h2 className="text-lg font-semibold">{t("auth.demo.title")}</h2>
      <AlertRegion>{error}</AlertRegion>
      <ul className="grid grid-cols-2 gap-2">
        {DEMO_SLOTS.map((slot) => (
          <li key={slot}>
            <Button
              variant="secondary"
              className="w-full"
              disabled={busy}
              onClick={() => void signIn(slot)}
            >
              {t("auth.demo.slot", { slot })}
            </Button>
          </li>
        ))}
      </ul>
    </div>
  );
}
