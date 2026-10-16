import { mediaInProgress } from "../../api/admin/media";
import type { PackImport } from "../../api/admin/packs";

/**
 * The media state of an import for the pack page (task 0018, steps 10 and
 * 19): the reason that holds a publication back, and the video files that
 * a block shows without captions.
 */

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const list = (value: unknown): unknown[] => (Array.isArray(value) ? value : []);

/**
 * The `media/` paths of the video files that a video block of `payload`
 * shows without captions. The payload of an import is the normalized pack
 * (0008 step 9): `modules[].lessons[].blocks[]`, where a video block holds
 * `media` with `src` and `captions` (0018 step 9). An embed or an external
 * file has no path of the pack and stays out.
 */
export function videosWithoutCaptions(payload: unknown): Set<string> {
  const paths = new Set<string>();
  if (!isRecord(payload)) return paths;
  for (const module of list(payload.modules)) {
    if (!isRecord(module)) continue;
    for (const lesson of list(module.lessons)) {
      if (!isRecord(lesson)) continue;
      for (const block of list(lesson.blocks)) {
        if (!isRecord(block) || block.kind !== "video") continue;
        const media = block.media;
        if (!isRecord(media) || typeof media.src !== "string") continue;
        if (!media.src.startsWith("media/")) continue;
        if (list(media.captions).length === 0) paths.add(media.src);
      }
    }
  }
  return paths;
}

/**
 * Why media files in the states `statuses` hold an action back:
 * `mediaFailed` while one is `failed` or `missing`, `mediaPending` while
 * one is `queued` or `processing`, and `null` when every one is `ready`.
 * The publication of an import and the download of a draft wait for it.
 */
export function mediaStatusBlock(
  statuses: readonly string[],
): "mediaFailed" | "mediaPending" | null {
  if (statuses.some((status) => status === "failed" || status === "missing"))
    return "mediaFailed";
  if (statuses.some(mediaInProgress)) return "mediaPending";
  return null;
}

/**
 * Why the media of an import hold its publication back
 * (`mediaStatusBlock`). The publish gate of the server decides again
 * (step 10).
 */
export function mediaBlockReason(
  pack: PackImport,
): "mediaFailed" | "mediaPending" | null {
  return mediaStatusBlock(
    Object.values(pack.media).map((entry) => entry.status),
  );
}
