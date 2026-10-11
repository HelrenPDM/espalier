import { useState } from "react";
import { useTranslation } from "react-i18next";
import {
  useEndOtherSessions,
  useEndSession,
  type SessionView,
} from "../api/account";
import type { AuthMethod } from "../api/session";
import { formatDateTime } from "../app/format";
import { AlertRegion, Button, StatusRegion } from "../app/forms";
import { useErrorText } from "../app/useErrorText";

/**
 * The active sessions of the account (task 0011 step 12, ASVS 7.5.2).
 * Ending one needs a second factor within the last 10 minutes; the API
 * client opens the step-up dialog when the server asks for it.
 */
export function SessionsSection({ sessions }: { sessions: SessionView[] }) {
  const { t, i18n } = useTranslation();
  const errorText = useErrorText();
  const end = useEndSession();
  const endOthers = useEndOtherSessions();
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState<string | null>(null);
  const others = sessions.filter((session) => !session.current);
  const busy = end.isPending || endOthers.isPending;

  const run = async (action: () => Promise<unknown>) => {
    setError(null);
    setStatus(null);
    try {
      await action();
      setStatus(t("account.sessions.ended"));
    } catch (failure) {
      setError(errorText(failure));
    }
  };

  const method = (value: AuthMethod) => t(`account.sessions.methods.${value}`);

  return (
    <section aria-labelledby="sessions-heading" className="space-y-4">
      <h2 id="sessions-heading" className="text-xl font-semibold">
        {t("account.sessions.title")}
      </h2>
      <AlertRegion>{error}</AlertRegion>
      <StatusRegion>{status}</StatusRegion>
      <ul className="divide-y divide-gray-200 rounded-md border border-gray-300 dark:divide-gray-800 dark:border-gray-700">
        {sessions.map((session) => (
          <li
            key={session.id}
            className="flex flex-wrap items-start justify-between gap-4 p-4"
          >
            <div className="space-y-1">
              <p className="font-medium">
                {session.device ?? t("account.sessions.unknownDevice")}
                {session.current && (
                  <span className="ml-2 rounded bg-gray-100 px-2 py-0.5 text-sm font-normal dark:bg-gray-800">
                    {t("account.sessions.thisDevice")}
                  </span>
                )}
              </p>
              <dl className="grid grid-cols-[auto_1fr] gap-x-3 text-sm text-gray-700 dark:text-gray-300">
                <dt>{t("account.sessions.methodsLabel")}</dt>
                <dd>{session.auth_methods.map(method).join(", ")}</dd>
                <dt>{t("account.sessions.started")}</dt>
                <dd>
                  {formatDateTime(session.authenticated_at, i18n.language)}
                </dd>
                <dt>{t("account.sessions.lastActive")}</dt>
                <dd>{formatDateTime(session.last_seen_at, i18n.language)}</dd>
              </dl>
            </div>
            {!session.current && (
              <Button
                variant="danger"
                disabled={busy}
                onClick={() => void run(() => end.mutateAsync(session.id))}
              >
                {t("account.sessions.end")}{" "}
                <span className="sr-only">
                  {session.device ?? t("account.sessions.unknownDevice")}
                </span>
              </Button>
            )}
          </li>
        ))}
      </ul>
      {others.length > 0 && (
        <Button
          variant="secondary"
          disabled={busy}
          onClick={() => void run(() => endOthers.mutateAsync())}
        >
          {t("account.sessions.endOthers")}
        </Button>
      )}
    </section>
  );
}
