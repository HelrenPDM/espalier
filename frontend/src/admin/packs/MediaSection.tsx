import { useId } from "react";
import { useTranslation } from "react-i18next";
import type { PackImport, PackMedia } from "../../api/admin/packs";
import { TABLE_CLASSES } from "../insights/reportFormat";
import { TableFrame } from "../adminParts";
import { MediaKindIcon, MediaState } from "../media/MediaParts";
import { formatDuration } from "../media/mediaText";
import { videosWithoutCaptions } from "./packMedia";

const MUTED = "text-gray-700 dark:text-gray-300";

/** The facts of an entry in one line: size in pixels, length and audio. */
function EntryFacts({ entry }: { entry: PackMedia }) {
  const { t } = useTranslation();
  const facts: string[] = [];
  if (entry.width !== null && entry.height !== null)
    facts.push(
      t("admin.media.facts.pixels", {
        width: entry.width,
        height: entry.height,
      }),
    );
  if (entry.duration_ms !== null) facts.push(formatDuration(entry.duration_ms));
  if (entry.kind === "video" && entry.status === "ready")
    facts.push(
      entry.has_audio
        ? t("admin.pack.media.withAudio")
        : t("admin.pack.media.withoutAudio"),
    );
  if (entry.animated) facts.push(t("admin.pack.media.animated"));
  return <>{facts.length === 0 ? "-" : facts.join(", ")}</>;
}

/**
 * The section "Media" of the pack page (task 0018, steps 10 and 19): every
 * media file of the import by its path, with its kind, its state (the
 * progress of a conversion, the failure text of a failed file, `missing`
 * for a deleted asset) and its facts. A notice lists every video file with
 * an audio track that a video block shows without captions (WCAG 2.2
 * 1.2.2), because the validator cannot know the audio track. Paths and
 * codes render as text (ASVS 3.2.2).
 */
export function MediaSection({ pack }: { pack: PackImport }) {
  const { t } = useTranslation();
  const headingId = useId();
  const hintId = useId();
  const entries = Object.entries(pack.media).sort(([a], [b]) =>
    a < b ? -1 : a > b ? 1 : 0,
  );
  const uncaptioned = videosWithoutCaptions(pack.payload);
  const hinted = entries
    .filter(
      ([path, entry]) =>
        entry.kind === "video" && entry.has_audio && uncaptioned.has(path),
    )
    .map(([path]) => path);

  return (
    // The table region carries the name of the heading, so the section
    // stays unnamed, as on the reports page (`TableFrame`).
    <section className="space-y-4">
      <h2 id={headingId} className="text-xl font-semibold tracking-tight">
        {t("admin.pack.media.title")}
      </h2>
      {entries.length === 0 ? (
        <p className={MUTED}>{t("admin.pack.media.empty")}</p>
      ) : (
        <>
          <p className={`text-sm ${MUTED}`}>{t("admin.pack.media.intro")}</p>
          <TableFrame labelledBy={headingId}>
            <thead>
              <tr>
                <th scope="col" className={TABLE_CLASSES.columnHeader}>
                  {t("admin.pack.media.path")}
                </th>
                <th scope="col" className={TABLE_CLASSES.columnHeader}>
                  {t("admin.pack.media.kind")}
                </th>
                <th scope="col" className={TABLE_CLASSES.columnHeader}>
                  {t("admin.pack.media.state")}
                </th>
                <th scope="col" className={TABLE_CLASSES.columnHeader}>
                  {t("admin.pack.media.facts")}
                </th>
              </tr>
            </thead>
            <tbody>
              {entries.map(([path, entry]) => (
                <tr key={path} data-status={entry.status}>
                  <td className={TABLE_CLASSES.cell}>
                    <code className="font-mono text-xs break-all">{path}</code>
                  </td>
                  <td className={TABLE_CLASSES.cell}>
                    <span className="flex items-center gap-1">
                      <MediaKindIcon kind={entry.kind} className="size-4" />
                      {t(`admin.media.kinds.${entry.kind}`)}
                    </span>
                  </td>
                  <td className={TABLE_CLASSES.cell}>
                    <MediaState asset={entry} subject={path} />
                  </td>
                  <td className={TABLE_CLASSES.cell}>
                    <EntryFacts entry={entry} />
                  </td>
                </tr>
              ))}
            </tbody>
          </TableFrame>
        </>
      )}
      {hinted.length > 0 && (
        <div
          role="note"
          aria-labelledby={hintId}
          className="space-y-2 rounded-md border-2 border-amber-600 bg-amber-50 px-3 py-2 text-sm text-gray-900 dark:border-amber-400 dark:bg-gray-900 dark:text-gray-100"
        >
          <p id={hintId} className="font-semibold">
            {t("admin.pack.media.captionsHintTitle")}
          </p>
          <p>{t("admin.pack.media.captionsHint")}</p>
          <ul className="list-disc pl-5">
            {hinted.map((path) => (
              <li key={path}>
                <code className="font-mono text-xs break-all">{path}</code>
              </li>
            ))}
          </ul>
        </div>
      )}
    </section>
  );
}
