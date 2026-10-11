import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useEndOtherSessions } from "../api/account";
import { AlertRegion, Button, FocusHeading } from "../app/forms";
import { useErrorText } from "../app/useErrorText";

/**
 * Offers to end every other session after a factor change and after a
 * recovery (task 0011 step 12, ASVS 7.4.3). `onDone` runs after the
 * sessions ended or when the person keeps them.
 */
export function EndOtherSessionsPrompt({ onDone }: { onDone: () => void }) {
  const { t } = useTranslation();
  const errorText = useErrorText();
  const endOthers = useEndOtherSessions();
  const [error, setError] = useState<string | null>(null);

  const end = async () => {
    setError(null);
    try {
      await endOthers.mutateAsync();
      onDone();
    } catch (failure) {
      setError(errorText(failure));
    }
  };

  return (
    <section className="max-w-xl space-y-4 rounded-md border border-gray-300 p-4 dark:border-gray-700">
      <FocusHeading level={2}>{t("account.sessions.promptTitle")}</FocusHeading>
      <p className="text-gray-700 dark:text-gray-300">
        {t("account.sessions.promptText")}
      </p>
      <AlertRegion>{error}</AlertRegion>
      <div className="flex flex-wrap gap-3">
        <Button disabled={endOthers.isPending} onClick={() => void end()}>
          {t("account.sessions.endOthers")}
        </Button>
        <Button variant="secondary" onClick={onDone}>
          {t("account.sessions.keepOthers")}
        </Button>
      </div>
    </section>
  );
}
