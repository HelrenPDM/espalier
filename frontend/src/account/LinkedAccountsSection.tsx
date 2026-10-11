import { useState, type FormEvent } from "react";
import { useTranslation } from "react-i18next";
import {
  useLinkLdap,
  useOidcIntent,
  type SecuritySummary,
} from "../api/account";
import { ApiError } from "../api/errors";
import type { Provider } from "../api/session";
import { ConfirmDialog } from "../app/ConfirmDialog";
import {
  AlertRegion,
  Button,
  PasswordField,
  StatusRegion,
  TextField,
} from "../app/forms";
import { useErrorText } from "../app/useErrorText";
import { rememberReturnTo } from "../auth/returnTo";
import { useSession } from "../auth/SessionProvider";

const blank = (value: string) => value.trim() === "";

/**
 * The connected directory and OIDC accounts (task 0011 step 12). A link
 * ends password sign-in, passkey sign-in alone and recovery for the
 * account (0004 step 16, 0005 steps 8 and 16), so every link first opens a
 * confirmation that states these consequences. Both routes need a second
 * factor within the last 10 minutes; the API client opens the step-up
 * dialog when the server asks for it.
 */
export function LinkedAccountsSection({
  security,
}: {
  security: SecuritySummary;
}) {
  const { t } = useTranslation();
  const { providers } = useSession();
  if (providers.length === 0) return null;

  return (
    <section aria-labelledby="identities-heading" className="space-y-4">
      <h2 id="identities-heading" className="text-xl font-semibold">
        {t("account.identities.title")}
      </h2>
      <ul className="space-y-4">
        {providers.map((provider) => (
          <li
            key={provider.key}
            className="rounded-md border border-gray-300 p-4 dark:border-gray-700"
          >
            {security.linked_providers.includes(provider.key) ? (
              <p>
                <span className="font-medium">{provider.label}</span>
                {": "}
                {t("account.identities.connected")}
              </p>
            ) : provider.kind === "credentials" ? (
              <LinkDirectoryForm provider={provider} />
            ) : (
              <LinkRedirectProvider provider={provider} />
            )}
          </li>
        ))}
      </ul>
    </section>
  );
}

function ConfirmLink({
  provider,
  open,
  onConfirm,
  onClose,
}: {
  provider: Provider;
  open: boolean;
  onConfirm: () => void;
  onClose: () => void;
}) {
  const { t } = useTranslation();
  return (
    <ConfirmDialog
      open={open}
      title={t("account.identities.confirmTitle", { label: provider.label })}
      confirmLabel={t("account.identities.connect")}
      onConfirm={onConfirm}
      onClose={onClose}
    >
      <p>{t("account.identities.confirmLink", { label: provider.label })}</p>
    </ConfirmDialog>
  );
}

function LinkDirectoryForm({ provider }: { provider: Provider }) {
  const { t } = useTranslation();
  const errorText = useErrorText();
  const link = useLinkLdap();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [confirming, setConfirming] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [linked, setLinked] = useState(false);

  const submit = (event: FormEvent) => {
    event.preventDefault();
    setError(null);
    if (blank(username) || blank(password)) {
      setError(t("auth.errors.credentialsRequired"));
      return;
    }
    setConfirming(true);
  };

  const connect = async () => {
    setConfirming(false);
    try {
      await link.mutateAsync({ provider: provider.key, username, password });
      setPassword("");
      setLinked(true);
    } catch (failure) {
      const code = failure instanceof ApiError ? failure.code : null;
      setError(
        code === "identity_in_use"
          ? t("account.errors.identityInUse")
          : code === "provider_already_linked"
            ? t("account.errors.providerAlreadyLinked")
            : errorText(failure),
      );
    }
  };

  return (
    <form
      onSubmit={submit}
      className="space-y-4"
      aria-label={provider.label}
      noValidate
    >
      <h3 className="font-semibold">{provider.label}</h3>
      <AlertRegion>{error}</AlertRegion>
      <StatusRegion>
        {linked ? t("account.identities.linked") : null}
      </StatusRegion>
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
      <Button type="submit" variant="secondary" disabled={link.isPending}>
        {t("account.identities.connectLabel", { label: provider.label })}
      </Button>
      <ConfirmLink
        provider={provider}
        open={confirming}
        onConfirm={() => void connect()}
        onClose={() => setConfirming(false)}
      />
    </form>
  );
}

function LinkRedirectProvider({ provider }: { provider: Provider }) {
  const { t } = useTranslation();
  const errorText = useErrorText();
  const intent = useOidcIntent();
  const [confirming, setConfirming] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const connect = async () => {
    setConfirming(false);
    setError(null);
    try {
      const url = await intent.mutateAsync({
        provider: provider.key,
        purpose: "link",
      });
      rememberReturnTo("/account/security");
      window.location.assign(url);
    } catch (failure) {
      setError(
        failure instanceof ApiError && failure.status === 409
          ? t("account.errors.providerAlreadyLinked")
          : errorText(failure),
      );
    }
  };

  return (
    <div className="space-y-3">
      <AlertRegion>{error}</AlertRegion>
      <Button
        variant="secondary"
        disabled={intent.isPending}
        onClick={() => setConfirming(true)}
      >
        {t("account.identities.connectLabel", { label: provider.label })}
      </Button>
      <ConfirmLink
        provider={provider}
        open={confirming}
        onConfirm={() => void connect()}
        onClose={() => setConfirming(false)}
      />
    </div>
  );
}
