import {
  ChatBubbleBottomCenterTextIcon,
  FilmIcon,
  PhotoIcon,
  SwatchIcon,
} from "@heroicons/react/24/outline";
import { useId, useState } from "react";
import { useTranslation } from "react-i18next";
import { Link } from "react-router";
import type { MediaAsset, MediaKind, MediaUses } from "../../api/admin/media";
import { formatDateTime } from "../../app/format";
import { Button, StatusRegion } from "../../app/forms";
import { FOCUS_RING, linkClasses } from "../../app/formStyles";
import { formatBytes } from "../workbench/draftErrors";
import { formatDuration, mediaUrl, useMediaFailureText } from "./mediaText";

/**
 * The parts of the media UI that the library page, its detail dialog, the
 * media entries of the workbench and the pack page share (task 0018, step
 * 19). Titles, file names, paths and codes render as React text, and no
 * part uses `dangerouslySetInnerHTML` (ASVS 3.2.2). A preview takes its
 * address only from `url` or `poster_url` of the API, and only in the form
 * of the media route (`mediaUrl`).
 */

const MUTED = "text-gray-700 dark:text-gray-300";

const KIND_ICONS = {
  image: PhotoIcon,
  svg: SwatchIcon,
  video: FilmIcon,
  captions: ChatBubbleBottomCenterTextIcon,
} as const satisfies Record<MediaKind, unknown>;

/** The decorative icon of a kind; the text beside it names the kind. */
export function MediaKindIcon({
  kind,
  className = "size-5",
}: {
  kind: MediaKind;
  className?: string;
}) {
  const Icon = KIND_ICONS[kind];
  return <Icon aria-hidden="true" className={`shrink-0 ${className}`} />;
}

/** The fields of an asset that its state needs; `AdminPackMedia` has them too. */
interface StateFields {
  status: MediaAsset["status"] | "missing";
  failure: MediaAsset["failure"];
  failure_detail: MediaAsset["failure_detail"];
  /** The progress of a video conversion in percent; absent on the pack page. */
  progress?: number;
}

/**
 * The state of an asset: its name, the progress of a conversion in
 * `processing` as a progress bar named after `subject`, and the message of
 * the failure code and its reason tag of a `failed` asset.
 */
export function MediaState({
  asset,
  subject,
}: {
  asset: StateFields;
  /** The title or path that names the progress bar. */
  subject: string;
}) {
  const { t } = useTranslation();
  const failureText = useMediaFailureText();
  const progress = Math.min(100, Math.max(0, asset.progress ?? 0));
  return (
    <span className="inline-flex flex-col gap-1" data-status={asset.status}>
      <span>
        {asset.status === "processing" && asset.progress !== undefined
          ? t("admin.media.processing", { progress })
          : t(`admin.media.status.${asset.status}`)}
      </span>
      {asset.status === "processing" && asset.progress !== undefined && (
        <progress
          max={100}
          value={progress}
          aria-label={t("admin.media.progressLabel", { subject })}
          className="h-2 w-full max-w-48 accent-accent-600"
        />
      )}
      {asset.status === "failed" && (
        <span className="text-red-700 dark:text-red-300">
          {failureText(asset.failure, asset.failure_detail)}
        </span>
      )}
    </span>
  );
}

const FRAME =
  "flex items-center justify-center overflow-hidden rounded-md border border-gray-200 dark:border-gray-700";

/**
 * The background of a preview: an SVG and an image with transparent
 * pixels sit on white also in dark mode, as the player shows them.
 */
const backdrop = (asset: Pick<MediaAsset, "kind" | "has_alpha">) =>
  asset.kind === "svg" || asset.has_alpha
    ? "bg-white"
    : "bg-gray-100 dark:bg-gray-800";

/** True for an animated image, which shows its poster until it plays. */
const animatedImage = (asset: MediaAsset) =>
  asset.kind === "image" && asset.animated;

/**
 * The small preview of a card: the delivery image, the SVG through an
 * `<img>`, the poster of a video or of an animated image (which never
 * moves in a card, WCAG 2.2 2.2.2), or the icon of the kind for captions
 * and for an asset that is not `ready`. The title beside it names the
 * file, so the image is decorative.
 */
export function MediaThumbnail({ asset }: { asset: MediaAsset }) {
  const url =
    asset.status !== "ready"
      ? null
      : asset.kind === "video" || animatedImage(asset)
        ? mediaUrl(asset.poster_url)
        : asset.kind === "image" || asset.kind === "svg"
          ? mediaUrl(asset.url)
          : null;
  return (
    <div className={`aspect-video w-full ${FRAME} ${backdrop(asset)}`}>
      {url === null ? (
        <MediaKindIcon
          kind={asset.kind}
          className="size-10 text-gray-500 dark:text-gray-400"
        />
      ) : (
        <img
          src={url}
          alt=""
          loading="lazy"
          decoding="async"
          className="h-full w-full object-contain"
        />
      )}
    </div>
  );
}

/**
 * The preview of the detail dialog and of a media entry of the workbench:
 * an `<img>` for an image or an SVG, a `<video controls>` with its poster
 * for a video, and a sentence for captions and for an asset that is not
 * `ready`. An animated image shows its poster with a button that plays and
 * pauses the animation, so it never moves by itself (WCAG 2.2 2.2.2).
 * `title` names the image for assistive technology.
 */
export function MediaView({
  asset,
  title,
}: {
  asset: MediaAsset;
  title: string;
}) {
  const { t } = useTranslation();
  const [playing, setPlaying] = useState(false);
  const url = asset.status === "ready" ? mediaUrl(asset.url) : null;
  const poster = mediaUrl(asset.poster_url);
  const size = {
    width: asset.width ?? undefined,
    height: asset.height ?? undefined,
  };

  if (url !== null && (asset.kind === "image" || asset.kind === "svg")) {
    const still = animatedImage(asset) && poster !== null;
    return (
      <div className="space-y-2">
        <div className={`max-w-full p-2 ${FRAME} ${backdrop(asset)}`}>
          <img
            src={still && !playing ? poster : url}
            alt={t("admin.media.view.imageAlt", { title })}
            {...size}
            decoding="async"
            className="h-auto max-h-96 max-w-full object-contain"
          />
        </div>
        {still && (
          <Button
            variant="secondary"
            aria-pressed={playing}
            onClick={() => setPlaying((current) => !current)}
          >
            {t("admin.media.view.playAnimation")}
          </Button>
        )}
      </div>
    );
  }
  if (url !== null && asset.kind === "video")
    return (
      <video
        controls
        preload="metadata"
        playsInline
        poster={poster ?? undefined}
        {...size}
        aria-label={t("admin.media.view.videoLabel", { title })}
        className="h-auto max-h-96 max-w-full rounded-md bg-black"
      >
        <source src={url} type="video/webm" />
        {t("admin.media.view.videoFallback")}
      </video>
    );
  return (
    <div className={`flex-col gap-2 p-4 text-sm ${FRAME} ${MUTED}`}>
      <MediaKindIcon
        kind={asset.kind}
        className="size-10 text-gray-500 dark:text-gray-400"
      />
      <p>
        {asset.kind === "captions" && asset.status === "ready"
          ? t("admin.media.view.captions")
          : t("admin.media.view.notReady")}
      </p>
    </div>
  );
}

/**
 * The facts of an asset: kind, size, dimensions, length, audio, animation,
 * transparency, origin, the name of the uploaded file and the time it
 * entered the library. A fact that the asset does not have yet shows "-".
 */
export function MediaFacts({ asset }: { asset: MediaAsset }) {
  const { t, i18n } = useTranslation();
  const none = "-";
  const yesNo = (value: boolean) =>
    value ? t("admin.media.facts.yes") : t("admin.media.facts.no");
  const rows: [string, string][] = [
    [t("admin.media.facts.kind"), t(`admin.media.kinds.${asset.kind}`)],
    [
      t("admin.media.facts.size"),
      asset.bytes === null ? none : formatBytes(asset.bytes, i18n.language),
    ],
  ];
  if (asset.kind !== "captions")
    rows.push([
      t("admin.media.facts.dimensions"),
      asset.width === null || asset.height === null
        ? none
        : t("admin.media.facts.pixels", {
            width: asset.width,
            height: asset.height,
          }),
    ]);
  if (asset.kind === "video" || asset.kind === "captions")
    rows.push([
      t("admin.media.facts.duration"),
      asset.duration_ms === null ? none : formatDuration(asset.duration_ms),
    ]);
  if (asset.kind === "video")
    rows.push([t("admin.media.facts.audio"), yesNo(asset.has_audio)]);
  if (asset.kind === "image")
    rows.push(
      [t("admin.media.facts.animated"), yesNo(asset.animated)],
      [t("admin.media.facts.transparency"), yesNo(asset.has_alpha)],
    );
  rows.push(
    [t("admin.media.facts.origin"), t(`admin.media.origins.${asset.origin}`)],
    [t("admin.media.facts.sourceName"), asset.source_name ?? none],
    [
      t("admin.media.facts.added"),
      formatDateTime(asset.inserted_at, i18n.language),
    ],
  );

  return (
    <dl className="grid grid-cols-[max-content_minmax(0,1fr)] gap-x-4 gap-y-1 text-sm">
      {rows.map(([term, value]) => (
        <div key={term} className="contents">
          <dt className="font-medium text-gray-900 dark:text-gray-100">
            {term}
          </dt>
          <dd className="break-words">{value}</dd>
        </div>
      ))}
    </dl>
  );
}

/**
 * A text to copy, such as a lesson directive: a read-only field with a
 * visible label and a button that writes the text to the clipboard, with
 * the outcome in a status region.
 */
export function CopyText({
  label,
  text,
  buttonLabel,
}: {
  label: string;
  text: string;
  buttonLabel: string;
}) {
  const { t } = useTranslation();
  const id = useId();
  const [status, setStatus] = useState<string | null>(null);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(text);
      setStatus(t("admin.common.copied"));
    } catch {
      setStatus(t("admin.common.copyFailed"));
    }
  };

  return (
    <div className="space-y-2">
      <label
        htmlFor={id}
        className="block text-sm font-medium text-gray-900 dark:text-gray-100"
      >
        {label}
      </label>
      <textarea
        id={id}
        readOnly
        rows={text.split("\n").length}
        value={text}
        spellCheck={false}
        onFocus={(event) => event.target.select()}
        className={`block w-full resize-none rounded-md border border-gray-500 bg-gray-50 px-3 py-2 font-mono text-xs break-all text-gray-900 dark:bg-gray-800 dark:text-gray-100 ${FOCUS_RING}`}
      />
      <Button variant="secondary" onClick={() => void copy()}>
        {buttonLabel}
      </Button>
      <StatusRegion>{status}</StatusRegion>
    </div>
  );
}

/** True when no program, draft or validated import uses the asset. */
const unused = (uses: MediaUses) =>
  uses.programs.length === 0 &&
  uses.drafts.length === 0 &&
  uses.imports.length === 0;

/**
 * The uses of an asset (step 8): the published programs, the drafts with
 * the path of the asset there, and the validated imports, each with a
 * link to its page. Titles, keys and paths render as text.
 */
export function UsesList({ uses }: { uses: MediaUses }) {
  const { t, i18n } = useTranslation();
  if (unused(uses))
    return <p className={MUTED}>{t("admin.media.uses.none")}</p>;
  return (
    <ul className="list-disc space-y-1 pl-5 text-sm">
      {uses.programs.map((program) => (
        <li key={`program:${program.slug}`}>
          {t("admin.media.uses.program")}{" "}
          <Link
            to={`/programs/${encodeURIComponent(program.slug)}`}
            className={linkClasses}
          >
            {program.title}
          </Link>
        </li>
      ))}
      {uses.drafts.map((draft) => (
        <li key={`draft:${draft.id}:${draft.path}`}>
          {t("admin.media.uses.draft")}{" "}
          <Link
            to={`/admin/workbench/${encodeURIComponent(draft.id)}`}
            className={linkClasses}
          >
            {draft.title}
          </Link>
          {", "}
          <code className="font-mono text-xs break-all">{draft.path}</code>
        </li>
      ))}
      {uses.imports.map((entry) => (
        <li key={`import:${entry.id}`}>
          {t("admin.media.uses.import")}{" "}
          <Link
            to={`/admin/packs/${encodeURIComponent(entry.id)}`}
            className={linkClasses}
          >
            {entry.pack_key ?? t("admin.media.uses.noPackKey")}
          </Link>
          {", "}
          {formatDateTime(entry.inserted_at, i18n.language)}
        </li>
      ))}
    </ul>
  );
}
