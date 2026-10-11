import { CheckCircleIcon, XCircleIcon } from "@heroicons/react/20/solid";
import type { ReactNode } from "react";
import { useContentLang } from "../contentLang";

/** The mark of an option, slot, case or check after a submission. */
export function FeedbackMark({
  correct,
  children,
}: {
  correct: boolean;
  children: ReactNode;
}) {
  const Icon = correct ? CheckCircleIcon : XCircleIcon;
  return (
    <span
      className={`inline-flex items-center gap-1 text-sm font-medium ${
        correct
          ? "text-green-800 dark:text-green-300"
          : "text-red-800 dark:text-red-300"
      }`}
    >
      <Icon aria-hidden="true" className="size-4 shrink-0" />
      {children}
    </span>
  );
}

/** The feedback text of an option, slot, case or check. */
export function FeedbackText({ text }: { text: string | null | undefined }) {
  const lang = useContentLang();
  if (!text) return null;
  return (
    <p lang={lang} className="mt-1 text-sm text-gray-700 dark:text-gray-300">
      {text}
    </p>
  );
}
