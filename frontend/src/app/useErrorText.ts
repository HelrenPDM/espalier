import { useCallback } from "react";
import { useTranslation } from "react-i18next";
import { errorMessage } from "../api/errors";

/**
 * Returns a function that translates a failure: an `ApiError` by its
 * status and code (`errorMessageKey`, with the minutes of `Retry-After`
 * for 429), and every other value as the generic message.
 */
export function useErrorText(): (error: unknown) => string {
  const { t } = useTranslation();
  return useCallback(
    (error: unknown) => {
      const { key, minutes } = errorMessage(error);
      return t(key, { minutes });
    },
    [t],
  );
}
