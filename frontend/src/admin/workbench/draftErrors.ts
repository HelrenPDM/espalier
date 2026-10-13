import { useCallback } from "react";
import { useTranslation } from "react-i18next";
import { fieldErrors, type PackDraft } from "../../api/admin/workbench";
import { ApiError } from "../../api/errors";
import { useAdminErrorText } from "../adminErrors";

const MEBIBYTE = 1_048_576;
const KIBIBYTE = 1_024;

/** A number of bytes in the units of `language`, such as "1 MB" or "12.5 kB". */
export function formatBytes(bytes: number, language: string): string {
  const [unit, value] =
    bytes >= MEBIBYTE
      ? (["megabyte", bytes / MEBIBYTE] as const)
      : bytes >= KIBIBYTE
        ? (["kilobyte", bytes / KIBIBYTE] as const)
        : (["byte", bytes] as const);
  return new Intl.NumberFormat(language, {
    style: "unit",
    unit,
    unitDisplay: "short",
    maximumFractionDigits: 1,
  }).format(value);
}

/**
 * Returns a function that names the error of a path at the path field of
 * the dialogs "Add file" and "Rename": a 422 with `fields.path`
 * `["invalid_path"]` and a 409 `path_taken`. Every other error gives `null`.
 */
export function usePathErrorText(): (error: unknown) => string | null {
  const { t } = useTranslation();
  return useCallback(
    (error: unknown) => {
      if (fieldErrors(error)?.path?.includes("invalid_path"))
        return t("admin.workbench.draft.errors.invalidPath");
      if (error instanceof ApiError && error.code === "path_taken")
        return t("admin.workbench.draft.errors.pathTaken");
      return null;
    },
    [t],
  );
}

/**
 * Returns a function that translates a failed change, check or import of
 * a draft (task 0016a, step 9): the limits of a draft with their values,
 * the content rules, a 429 `checks_busy`, and every other answer through
 * the messages of the admin area.
 */
export function useDraftErrorText(
  limits: PackDraft["limits"],
): (error: unknown) => string {
  const { t, i18n } = useTranslation();
  const adminErrorText = useAdminErrorText();
  return useCallback(
    (error: unknown) => {
      const size = (bytes: number) => formatBytes(bytes, i18n.language);
      const content = fieldErrors(error)?.content ?? [];
      // The request schema answers `max_length` for a content of more than
      // 1,048,576 characters, before the context counts its bytes.
      if (content.includes("too_large") || content.includes("max_length"))
        return t("admin.workbench.draft.errors.fileTooLarge", {
          size: size(limits.file_bytes),
        });
      if (content.includes("nul_character"))
        return t("admin.workbench.draft.errors.nulCharacter");
      if (!(error instanceof ApiError)) return adminErrorText(error);
      switch (error.code) {
        case "too_many_files":
          return t("admin.workbench.draft.errors.tooManyFiles", {
            max: new Intl.NumberFormat(i18n.language).format(limits.files),
          });
        case "draft_too_large":
          return t("admin.workbench.draft.errors.draftTooLarge", {
            size: size(limits.draft_bytes),
          });
        case "checks_busy":
          return t("admin.workbench.draft.errors.checksBusy");
        default:
          return error.status === 404
            ? t("admin.workbench.draft.errors.notFound")
            : adminErrorText(error);
      }
    },
    [t, i18n.language, adminErrorText, limits],
  );
}
