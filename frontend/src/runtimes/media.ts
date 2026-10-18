import type {
  BlockMedia,
  FigureSize,
  MediaCaption,
  MediaImage,
  MediaPoster,
  MediaVideo,
} from "../player/runtime";

/**
 * The `media` of a payload block (task 0018, step 9): for a `figure`
 * `src`, `alt`, `decorative` and `size`, for a `video` `src`, `embed`,
 * `title`, `poster` and `captions`, each `null` when absent; `null` for
 * the other kinds. A `src`, `poster` or caption `src` that starts with
 * `media/` names a file of the pack; a video `src` that is an `https:` URL
 * names an external file.
 */
export interface PayloadBlockMedia {
  src?: string | null;
  alt?: string | null;
  decorative?: boolean | null;
  size?: FigureSize | null;
  embed?: string | null;
  title?: string | null;
  poster?: string | null;
  captions?: { src: string; lang: string }[] | null;
}

/**
 * A media file of the pack: an entry of the `media` object of
 * `GET /api/admin/packs/:id` (`AdminPackMedia`, whose `url` is `null`
 * until the file is `ready`) or of `content.json` of a SCORM package
 * (`url` relative to `index.html`). The members that the resolution reads.
 */
export interface PackMediaEntry {
  kind: "image" | "svg" | "video" | "captions";
  url: string | null;
  width: number | null;
  height: number | null;
  duration_ms: number | null;
  has_audio: boolean;
  has_alpha: boolean;
  animated: boolean;
  poster_url: string | null;
}

/** The media files of a pack keyed by their `media/` path. */
export type PackMedia = Readonly<Record<string, PackMediaEntry>>;

/**
 * The allowlists of the installation (`media_policy` of
 * `GET /api/admin/packs/:id`), each entry `host` or `host:port`. A SCORM
 * package has none: there every external file and embed is available.
 */
export interface MediaPolicy {
  external_hosts: readonly string[];
  embed_hosts: readonly string[];
}

const PACK_PATH = "media/";

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const isSize = (value: unknown): value is number =>
  typeof value === "number" && Number.isFinite(value) && value > 0;

/**
 * `host` or `host:port` of an `https:` URL as `URL.host` gives it: lower
 * case, with the port only when it is not 443; `null` for another value.
 */
function httpsHost(url: string): string | null {
  try {
    const parsed = new URL(url);
    return parsed.protocol === "https:" && parsed.host !== ""
      ? parsed.host
      : null;
  } catch {
    return null;
  }
}

/** An allowlist entry in the form of `URL.host`. */
function hostEntry(entry: string): string {
  return httpsHost(`https://${entry}`) ?? entry.toLowerCase();
}

const allowed = (hosts: readonly string[], host: string) =>
  hosts.some((entry) => hostEntry(entry) === host);

/** The type of an external video file by the extension of its path. */
function externalMime(url: string): MediaVideo["mime"] | null {
  try {
    const path = new URL(url).pathname.toLowerCase();
    if (path.endsWith(".webm")) return "video/webm";
    if (path.endsWith(".mp4")) return "video/mp4";
    return null;
  } catch {
    return null;
  }
}

const NO_MEDIA: BlockMedia = {
  image: null,
  video: null,
  poster: null,
  embed: null,
  captions: [],
  alt: null,
  decorative: false,
  size: null,
  title: null,
  available: false,
};

/**
 * Resolves the `media/` paths of the payload blocks through a media object
 * into the `BlockMedia` shape of the platform API (task 0018, step 12).
 */
class MediaResolver {
  readonly #media: PackMedia;
  readonly #policy: MediaPolicy | null;

  constructor(media: PackMedia, policy: MediaPolicy | null) {
    this.#media = media;
    this.#policy = policy;
  }

  /** The entry at `path` with its URL, or `null` while it has none. */
  #file(path: string, kinds: readonly PackMediaEntry["kind"][]) {
    if (!Object.hasOwn(this.#media, path)) return null;
    const entry: unknown = this.#media[path];
    if (!isRecord(entry) || typeof entry.url !== "string") return null;
    const file = entry as unknown as PackMediaEntry & { url: string };
    return kinds.includes(file.kind) ? file : null;
  }

  /**
   * The poster of the `poster` attribute: that image with its size. An
   * animated image gives its still first frame (`poster_url`), because a
   * browser plays an animated poster without a control to stop it (WCAG
   * 2.2 2.2.2); without that frame it gives no poster, as a missing file
   * does.
   */
  #posterAt(path: string): MediaPoster | null {
    const file = this.#file(path, ["image", "svg"]);
    if (file === null || !isSize(file.width) || !isSize(file.height))
      return null;
    const size = { width: file.width, height: file.height };
    if (file.kind === "image" && file.animated === true)
      return typeof file.poster_url === "string"
        ? { url: file.poster_url, ...size }
        : null;
    return { url: file.url, ...size };
  }

  #allowed(list: "external_hosts" | "embed_hosts", host: string | null) {
    if (host === null) return false;
    return this.#policy === null || allowed(this.#policy[list], host);
  }

  figure(media: PayloadBlockMedia): BlockMedia {
    const decorative = media.decorative === true;
    const size: FigureSize =
      media.size === "small" || media.size === "medium" ? media.size : "full";
    const file =
      typeof media.src === "string" && media.src.startsWith(PACK_PATH)
        ? this.#file(media.src, ["image", "svg"])
        : null;
    // An SVG without a fixed size has no size facts; the image then keeps
    // `null` for both, as the platform API gives it.
    const sized =
      file !== null && isSize(file.width) && isSize(file.height)
        ? { width: file.width, height: file.height }
        : null;
    const image: MediaImage | null =
      file === null
        ? null
        : {
            url: file.url,
            mime: file.kind === "svg" ? "image/svg+xml" : "image/webp",
            width: sized?.width ?? null,
            height: sized?.height ?? null,
            has_alpha: file.has_alpha === true,
            animated: file.kind === "image" && file.animated === true,
          };
    // The first frame of an animated image is a raster with its size.
    const poster: MediaPoster | null =
      image !== null &&
      image.animated &&
      sized !== null &&
      typeof file?.poster_url === "string"
        ? { url: file.poster_url, ...sized }
        : null;
    return {
      ...NO_MEDIA,
      image,
      poster,
      alt: decorative ? null : (media.alt ?? null),
      decorative,
      size,
      available: image !== null,
    };
  }

  video(media: PayloadBlockMedia): BlockMedia {
    const title = media.title ?? null;

    if (typeof media.embed === "string") {
      const host = httpsHost(media.embed);
      return {
        ...NO_MEDIA,
        embed: { url: media.embed, host: host ?? "" },
        title,
        available: this.#allowed("embed_hosts", host),
      };
    }

    const captionPaths = media.captions ?? [];
    const captions: MediaCaption[] = captionPaths.flatMap(({ src, lang }) => {
      const file = this.#file(src, ["captions"]);
      return file === null ? [] : [{ url: file.url, lang }];
    });
    const attributePoster =
      typeof media.poster === "string" ? this.#posterAt(media.poster) : null;
    const filesFound =
      captions.length === captionPaths.length &&
      (typeof media.poster !== "string" || attributePoster !== null);

    const src = typeof media.src === "string" ? media.src : null;
    if (src === null) return { ...NO_MEDIA, title };

    if (src.startsWith(PACK_PATH)) {
      const file = this.#file(src, ["video"]);
      const video: MediaVideo | null =
        file === null
          ? null
          : {
              url: file.url,
              mime: "video/webm",
              width: isSize(file.width) ? file.width : null,
              height: isSize(file.height) ? file.height : null,
              duration_ms: file.duration_ms ?? null,
              has_audio: file.has_audio ?? null,
              external: false,
            };
      const ownPoster =
        video !== null &&
        typeof file?.poster_url === "string" &&
        video.width !== null &&
        video.height !== null
          ? { url: file.poster_url, width: video.width, height: video.height }
          : null;
      return {
        ...NO_MEDIA,
        video,
        poster: attributePoster ?? ownPoster,
        captions,
        title,
        available: video !== null && filesFound,
      };
    }

    const host = httpsHost(src);
    const mime = externalMime(src);
    return {
      ...NO_MEDIA,
      video: {
        url: src,
        mime: mime ?? "video/mp4",
        width: null,
        height: null,
        duration_ms: null,
        has_audio: null,
        external: true,
      },
      poster: attributePoster,
      captions,
      title,
      available:
        mime !== null && this.#allowed("external_hosts", host) && filesFound,
    };
  }
}

/** The `BlockMedia` of a payload block from its `kind` and `media`. */
export type BlockMediaResolver = (
  kind: string,
  media: PayloadBlockMedia | null | undefined,
) => BlockMedia | null;

/**
 * Resolves the media of payload blocks through the media object `files`
 * of the pack into the `BlockMedia` shape of the platform API (task 0018,
 * step 12):
 *
 * - `figure`: `image` from the file at `src` (`image/webp`, or
 *   `image/svg+xml` for an SVG; `width` and `height` `null` for an SVG
 *   without a fixed size), `poster` for an animated image (its
 *   `poster_url` with the image size), `alt` (`null` when decorative),
 *   `decorative` and `size` (`full` when absent).
 * - `video` with a `media/` `src`: `video` (`video/webm`, `external:
 *   false`), `poster` from the `poster` attribute (the still first frame
 *   of an animated image) or else the first frame of the video with the
 *   video size, and `captions`.
 * - `video` with an `https:` `src`: `video` with the type of its extension,
 *   `external: true` and the other facts `null`.
 * - `video` with `embed`: `embed` with the URL and its host.
 *
 * `available` is false when a referenced file of the pack has no URL (it
 * is missing or not `ready`), or, with a `policy`, when the host of an
 * external file or an embed (with the port when it is not 443) is not in
 * its list. Without a policy (a SCORM package) every host is available.
 * Every other kind gives `null`.
 */
export function blockMediaResolver(
  files: PackMedia,
  policy: MediaPolicy | null,
): BlockMediaResolver {
  const resolver = new MediaResolver(files, policy);
  return (kind, media) => {
    if (kind !== "figure" && kind !== "video") return null;
    if (!isRecord(media)) return { ...NO_MEDIA };
    return kind === "figure" ? resolver.figure(media) : resolver.video(media);
  };
}
