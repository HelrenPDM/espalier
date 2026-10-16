import { useTranslation } from "react-i18next";
import { Link } from "react-router";
import { useMediaAsset } from "../../api/admin/media";
import type { DraftMediaEntry } from "../../api/admin/workbench";
import { linkClasses } from "../../app/formStyles";
import {
  CopyText,
  MediaFacts,
  MediaState,
  MediaView,
} from "../media/MediaParts";
import { mediaDirective } from "../media/mediaText";

/**
 * The view of a media entry of a draft in place of the editor (task 0018,
 * step 19): the state of its asset with the progress of a conversion and
 * the failure text, the preview, the facts, the title in the library, and
 * the lesson directive with the path of the entry to copy. The asset is
 * read again every two seconds while it is converted; until the first
 * answer, and after a failed one, the asset of the draft shows. Titles and
 * paths render as text.
 */
export function MediaPreview({ entry }: { entry: DraftMediaEntry }) {
  const { t } = useTranslation();
  const query = useMediaAsset(entry.asset.id);
  const asset = query.data ?? entry.asset;
  const directive = mediaDirective(asset.kind, entry.path);

  return (
    <div className="space-y-4 text-sm text-gray-700 dark:text-gray-300">
      <p>
        <span className="font-medium text-gray-900 dark:text-gray-100">
          {t("admin.media.facts.state")}
        </span>{" "}
        <MediaState asset={asset} subject={entry.path} />
      </p>
      <MediaView asset={asset} title={asset.title} />
      <MediaFacts asset={asset} />
      <p>
        <span className="font-medium text-gray-900 dark:text-gray-100">
          {t("admin.workbench.media.preview.libraryTitle")}
        </span>{" "}
        <span className="break-words">{asset.title}</span>{" "}
        <Link to="/admin/media" className={linkClasses}>
          {t("admin.workbench.media.preview.toLibrary")}
        </Link>
      </p>
      {directive !== null && (
        <CopyText
          label={t("admin.workbench.media.preview.directive")}
          text={directive}
          buttonLabel={t("admin.media.directive.copy")}
        />
      )}
    </div>
  );
}
