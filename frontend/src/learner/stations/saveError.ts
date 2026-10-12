import { useCallback } from "react";
import { useTranslation } from "react-i18next";
import { ApiError, retryMinutes } from "../../api/errors";

/**
 * Returns a function that names why a post of an insights station failed:
 * the wait of a 429 answer of the bucket `insights_write` (task 0014, step
 * 4), and `fallback` for every other failure.
 */
export function useSaveErrorText(): (
  error: unknown,
  fallback: string,
) => string {
  const { t } = useTranslation();
  return useCallback(
    (error: unknown, fallback: string) =>
      error instanceof ApiError && error.status === 429
        ? t("errors.tooManyAttempts", { minutes: retryMinutes(error) })
        : fallback,
    [t],
  );
}
