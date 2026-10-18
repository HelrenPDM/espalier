import { useCallback } from "react";
import { useTranslation } from "react-i18next";
import { fieldCodes } from "../../api/admin/fieldErrors";
import type {
  MediaFailure,
  MediaFailureDetail,
  MediaKind,
} from "../../api/admin/media";
import { ApiError } from "../../api/errors";
import { useAdminErrorText } from "../adminErrors";
import { titleSlug, type DeliveryExtension } from "../workbench/paths";

/**
 * The texts and the derived values of the media UI (task 0018, step 19):
 * the delivery extension of a kind, the default path and the directive of
 * an asset, and the messages of the failure codes, their reason tags and
 * the answers of the upload. Every title, path and code reaches the page
 * as React text (ASVS 3.2.2).
 */

/** The extension of the delivery file of each kind (`MediaPath.delivery_path/1`). */
export const DELIVERY_EXTENSION: Record<MediaKind, DeliveryExtension> = {
  image: "webp",
  svg: "svg",
  video: "webm",
  captions: "vtt",
};

/**
 * The address of a delivery file or poster from the API: a path of the
 * media route `/media/<sha256>.<ext>` (step 13), or `null` for anything
 * else, so no other address reaches a `src`.
 */
export function mediaUrl(url: string | null | undefined): string | null {
  if (typeof url !== "string") return null;
  return /^\/media\/[0-9a-f]{64}\.(webp|svg|webm|vtt)$/.test(url) ? url : null;
}

/** `media/<slug of the title>.<delivery extension>`, a path for a draft. */
export const defaultMediaPath = (title: string, kind: MediaKind): string =>
  `media/${titleSlug(title)}.${DELIVERY_EXTENSION[kind]}`;

/**
 * The lesson directive that places a media file at `path`, in the syntax
 * of `Espalier.Catalog.Pack.Directives` (task 0008, step 7; task 0018, step
 * 9): the opening line with the attributes and the closing line. A figure
 * gets an empty `alt` and a video an empty `title`, which the validator
 * rejects until the author fills them; the body (the caption or the
 * transcript) stays empty. Captions have no directive of their own; a
 * video names them in `captions`.
 */
export function mediaDirective(kind: MediaKind, path: string): string | null {
  switch (kind) {
    case "image":
    case "svg":
      return `:::figure{src=${path} alt="" provenance=invented}\n:::\n`;
    case "video":
      return `:::video{src=${path} title="" provenance=invented}\n:::\n`;
    case "captions":
      return null;
  }
}

/** The message keys of the failure codes of step 8. */
const FAILURE_KEYS = {
  too_many_pixels: "admin.media.failure.too_many_pixels",
  too_many_frames: "admin.media.failure.too_many_frames",
  too_long: "admin.media.failure.too_long",
  no_video_stream: "admin.media.failure.no_video_stream",
  unsupported_animation: "admin.media.failure.unsupported_animation",
  invalid_svg: "admin.media.failure.invalid_svg",
  invalid_captions: "admin.media.failure.invalid_captions",
  malware_found: "admin.media.failure.malware_found",
  scan_failed: "admin.media.failure.scan_failed",
  storage_full: "admin.media.failure.storage_full",
  conversion_failed: "admin.media.failure.conversion_failed",
  timeout: "admin.media.failure.timeout",
  interrupted: "admin.media.failure.interrupted",
} as const satisfies Record<MediaFailure, string>;

/**
 * The message keys of the reason tags per failure code: the animated WebP
 * check (step 6), the SVG rebuild (step 6), the WebVTT check (step 6) and
 * the scan (step 7). `too_large` and `encoding` belong to SVG and to
 * captions, with a message each.
 */
const DETAIL_KEYS = {
  unsupported_animation: {
    structure: "admin.media.failureDetail.unsupported_animation.structure",
    first_frame: "admin.media.failureDetail.unsupported_animation.first_frame",
    too_many_frames:
      "admin.media.failureDetail.unsupported_animation.too_many_frames",
  },
  invalid_svg: {
    too_large: "admin.media.failureDetail.invalid_svg.too_large",
    encoding: "admin.media.failureDetail.invalid_svg.encoding",
    doctype: "admin.media.failureDetail.invalid_svg.doctype",
    entity: "admin.media.failureDetail.invalid_svg.entity",
    processing_instruction:
      "admin.media.failureDetail.invalid_svg.processing_instruction",
    parse_error: "admin.media.failureDetail.invalid_svg.parse_error",
    root: "admin.media.failureDetail.invalid_svg.root",
    embedded_image: "admin.media.failureDetail.invalid_svg.embedded_image",
    css: "admin.media.failureDetail.invalid_svg.css",
    animation: "admin.media.failureDetail.invalid_svg.animation",
  },
  invalid_captions: {
    too_large: "admin.media.failureDetail.invalid_captions.too_large",
    encoding: "admin.media.failureDetail.invalid_captions.encoding",
    nul: "admin.media.failureDetail.invalid_captions.nul",
    header: "admin.media.failureDetail.invalid_captions.header",
    too_many_cues: "admin.media.failureDetail.invalid_captions.too_many_cues",
    timing: "admin.media.failureDetail.invalid_captions.timing",
    style: "admin.media.failureDetail.invalid_captions.style",
  },
  scan_failed: {
    limits_exceeded: "admin.media.failureDetail.scan_failed.limits_exceeded",
    size_limit: "admin.media.failureDetail.scan_failed.size_limit",
    timeout: "admin.media.failureDetail.scan_failed.timeout",
    closed: "admin.media.failureDetail.scan_failed.closed",
    connect: "admin.media.failureDetail.scan_failed.connect",
    reply: "admin.media.failureDetail.scan_failed.reply",
  },
} as const satisfies Partial<Record<MediaFailure, Record<string, string>>>;

type DetailKeys = typeof DETAIL_KEYS;

/**
 * Every reason tag of the API has a message: a tag that the schema adds
 * without a key here fails `tsc` on this line.
 */
type DetailTag = {
  [F in keyof DetailKeys]: keyof DetailKeys[F];
}[keyof DetailKeys];
const everyTag: Record<Exclude<MediaFailureDetail, DetailTag>, never> = {};
void everyTag;
type DetailKey = {
  [F in keyof DetailKeys]: DetailKeys[F][keyof DetailKeys[F]];
}[keyof DetailKeys];

const failureKey = (failure: string) =>
  Object.hasOwn(FAILURE_KEYS, failure)
    ? FAILURE_KEYS[failure as keyof typeof FAILURE_KEYS]
    : null;

function detailKey(failure: string, detail: string): DetailKey | null {
  if (!Object.hasOwn(DETAIL_KEYS, failure)) return null;
  const group: Record<string, DetailKey> =
    DETAIL_KEYS[failure as keyof DetailKeys];
  return Object.hasOwn(group, detail) ? group[detail] : null;
}

/**
 * Returns a function that names the failure of an asset: the message of
 * its code and, when the code has one, the message of its reason tag. An
 * unknown code or tag appears as the code itself.
 */
export function useMediaFailureText(): (
  failure: string | null,
  detail: string | null,
) => string {
  const { t } = useTranslation();
  return useCallback(
    (failure, detail) => {
      if (failure === null) return t("admin.media.failureUnknown");
      const key = failureKey(failure);
      const text =
        key === null ? t("admin.media.failureCode", { code: failure }) : t(key);
      if (detail === null) return text;
      const reason = detailKey(failure, detail);
      return t("admin.media.failureWithReason", {
        failure: text,
        reason:
          reason === null
            ? t("admin.media.reasonCode", { code: detail })
            : t(reason),
      });
    },
    [t],
  );
}

/** The message keys of the codes of `fields.file` of a 422 upload answer. */
const FILE_CODE_KEYS = {
  unsupported_type: "admin.media.upload.errors.unsupported_type",
  extension_mismatch: "admin.media.upload.errors.extension_mismatch",
  too_large: "admin.media.upload.errors.too_large",
  too_many_pixels: "admin.media.upload.errors.too_many_pixels",
  invalid_type: "admin.media.upload.errors.invalid_type",
} as const;

/**
 * Returns a function that names a failed upload (step 15): the codes of
 * `fields.file` of a 422, the 413 above the upload limit, the 415 without
 * a multipart body, the 409 `storage_full`, a failed network, and every
 * other answer through the messages of the admin area, a 403
 * `reauth_required` after a closed step-up dialog included.
 */
export function useUploadErrorText(): (error: unknown) => string {
  const { t } = useTranslation();
  const adminErrorText = useAdminErrorText();
  return useCallback(
    (error: unknown) => {
      if (!(error instanceof ApiError))
        return t("admin.media.upload.errors.network");
      const code = fieldCodes(error, "file").find((value) =>
        Object.hasOwn(FILE_CODE_KEYS, value),
      ) as keyof typeof FILE_CODE_KEYS | undefined;
      if (code !== undefined) return t(FILE_CODE_KEYS[code]);
      if (error.status === 413)
        return t("admin.media.upload.errors.requestTooLarge");
      if (error.status === 415)
        return t("admin.media.upload.errors.unsupportedMediaType");
      if (error.code === "storage_full")
        return t("admin.media.upload.errors.storageFull");
      return adminErrorText(error);
    },
    [t, adminErrorText],
  );
}

/** A number of milliseconds as `m:ss` or `h:mm:ss`. */
export function formatDuration(milliseconds: number): string {
  const total = Math.round(milliseconds / 1000);
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const seconds = String(total % 60).padStart(2, "0");
  return hours > 0
    ? `${hours}:${String(minutes).padStart(2, "0")}:${seconds}`
    : `${minutes}:${seconds}`;
}
