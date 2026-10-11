import { useEffect, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import { FOCUS_RING } from "../../app/formStyles";
import { feedbackFor } from "./answers";
import { ItemFrame, type ItemProps } from "./ItemFrame";
import { FeedbackMark } from "./parts";

interface LogLine {
  initials: string;
  time: Date;
}

/**
 * Release checks, an initials input and a release button, which is enabled
 * when every required check is set and the initials have 2 to 5
 * characters (0009 step 10). After a successful release a log line with
 * initials and time appears below the form; it lives in component state
 * only.
 */
export function ChecklistDrillItem(props: ItemProps) {
  const { t, i18n } = useTranslation();
  const { item, value, onChange, feedback } = props;
  const checks = value?.checks ?? [];
  const initials = value?.initials ?? "";
  const [log, setLog] = useState<LogLine[]>([]);
  const logged = useRef<typeof feedback>(null);

  useEffect(() => {
    if (feedback?.correct !== true || logged.current === feedback) return;
    logged.current = feedback;
    setLog((lines) => [
      ...lines,
      { initials: initials.trim(), time: new Date() },
    ]);
  }, [feedback, initials]);

  const change = (next: { checks?: string[]; initials?: string }) =>
    onChange({ checks, initials, ...next });

  const initialsId = `${item.id}-initials`;
  const hintId = `${item.id}-initials-hint`;
  return (
    <ItemFrame
      {...props}
      submitLabel={t("items.checklist.release")}
      editor={({ locked }) => (
        <div className="space-y-4">
          <ul className="space-y-2">
            {item.checks.map((check) => {
              const id = `${item.id}-check-${check.key}`;
              const entry = feedbackFor(feedback, check.key);
              return (
                <li key={check.key} className="flex items-start gap-3">
                  <input
                    id={id}
                    type="checkbox"
                    checked={checks.includes(check.key)}
                    disabled={locked}
                    onChange={(event) =>
                      change({
                        checks: event.target.checked
                          ? [
                              ...checks.filter((key) => key !== check.key),
                              check.key,
                            ]
                          : checks.filter((key) => key !== check.key),
                      })
                    }
                    className={`mt-1 size-4 shrink-0 accent-accent-600 ${FOCUS_RING}`}
                  />
                  <div className="min-w-0">
                    <label htmlFor={id}>
                      {check.label}
                      {check.required && (
                        <span className="text-gray-700 dark:text-gray-300">
                          {" "}
                          {t("items.checklist.required")}
                        </span>
                      )}
                    </label>
                    {entry && entry.required && !entry.selected && (
                      <div className="mt-1">
                        <FeedbackMark correct={false}>
                          {t("items.checklist.missing")}
                        </FeedbackMark>
                      </div>
                    )}
                  </div>
                </li>
              );
            })}
          </ul>
          <div>
            <label htmlFor={initialsId} className="text-sm font-medium">
              {t("items.checklist.initials")}
            </label>
            <input
              id={initialsId}
              type="text"
              autoComplete="off"
              maxLength={16}
              value={initials}
              disabled={locked}
              aria-describedby={hintId}
              onChange={(event) => change({ initials: event.target.value })}
              className={`mt-1 block w-32 rounded-md border border-gray-500 bg-white px-3 py-2 text-sm text-gray-900 disabled:cursor-not-allowed disabled:opacity-70 dark:bg-gray-900 dark:text-gray-100 ${FOCUS_RING}`}
            />
            <p
              id={hintId}
              className="mt-1 text-sm text-gray-700 dark:text-gray-300"
            >
              {t("items.checklist.initialsHint")}
            </p>
          </div>
        </div>
      )}
      after={
        log.length > 0 && (
          <ul className="mt-3 space-y-1 text-sm text-gray-700 dark:text-gray-300">
            {log.map((line, index) => (
              <li key={index}>
                {t("items.checklist.logLine", {
                  initials: line.initials,
                  time: new Intl.DateTimeFormat(i18n.language, {
                    timeStyle: "short",
                  }).format(line.time),
                })}
              </li>
            ))}
          </ul>
        )
      }
    />
  );
}
