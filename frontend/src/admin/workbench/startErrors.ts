import { useCallback } from "react";
import { useTranslation } from "react-i18next";
import type { ApiError } from "../../api/errors";
import { isApiError } from "../../api/admin/fieldErrors";
import { mediaNotReadyEntries } from "../../api/admin/packs";
import { useAdminErrorText } from "../adminErrors";

/**
 * The default number of drafts that the workbench holds (`config :espalier,
 * :pack_drafts, max_drafts:`, task 0016a, step 3). The 409 `draft_limit`
 * answer names the configured limit in `max_drafts`; the notice names this
 * default only for an answer without it.
 */
export const DRAFT_LIMIT = 50;

/**
 * The default number of media entries of a draft (`config :espalier,
 * :media, max_draft_media:`, task 0018, step 4). The 409 `media_limit`
 * answer carries no limit, so the notice names this default.
 */
export const DRAFT_MEDIA_LIMIT = 500;

/** The `max_drafts` of a 409 `draft_limit` answer, or the default. */
function draftLimit(error: ApiError): number {
  const body = error.body;
  if (typeof body === "object" && body !== null && "max_drafts" in body) {
    const limit = body.max_drafts;
    if (typeof limit === "number" && Number.isInteger(limit) && limit > 0)
      return limit;
  }
  return DRAFT_LIMIT;
}

/**
 * Returns a function that translates a failed start of a draft (task
 * 0016a, step 12): the 409 codes of `POST /api/admin/pack-drafts` and
 * `POST /api/admin/pack-draft-uploads` by their own sentences, among them
 * `draft_limit` with the limit and the advice to delete a draft, and every
 * other failure as the admin pages translate it. The workbench page and the
 * button "Edit in the workbench" of the pack page share it.
 *
 * Task 0018 adds two codes. `media_limit` names the limit of media entries
 * per draft. `media_not_ready`, the answer to a start from a program or an
 * import whose captions file is not ready, names each path of the answer
 * with its state and asks the author to wait until the conversion has
 * finished. Paths render as text.
 */
export function useStartErrorText(): (error: unknown) => string {
  const { t } = useTranslation();
  const adminErrorText = useAdminErrorText();
  return useCallback(
    (error: unknown) => {
      if (isApiError(error, 409, "media_not_ready")) {
        const entries = (mediaNotReadyEntries(error.body) ?? [])
          .map(
            (entry) =>
              `${entry.path} (${t(`admin.media.status.${entry.status}`)})`,
          )
          .join(", ");
        return t("admin.workbench.start.errors.mediaNotReady", { entries });
      }
      if (isApiError(error, 409, "media_limit"))
        return t("admin.workbench.start.errors.mediaLimit", {
          limit: DRAFT_MEDIA_LIMIT,
        });
      if (isApiError(error, 409, "draft_limit"))
        return t("admin.workbench.start.errors.draftLimit", {
          limit: draftLimit(error),
        });
      if (isApiError(error, 409, "too_many_files"))
        return t("admin.workbench.start.errors.tooManyFiles");
      if (isApiError(error, 409, "draft_too_large"))
        return t("admin.workbench.start.errors.tooLarge");
      if (isApiError(error, 409, "no_payload"))
        return t("admin.workbench.start.errors.noPayload");
      return adminErrorText(error);
    },
    [t, adminErrorText],
  );
}
