import type { Block, BlockMedia } from "../player/runtime";

/** A media URL of the platform: `/media/<digest>.<ext>` with a digest of one repeated hex digit. */
export const mediaUrl = (digit: string, ext: "webp" | "svg" | "webm" | "vtt") =>
  `/media/${digit.repeat(64)}.${ext}`;

export const EMBED_URL = "https://player.example.org/watch/intro";
export const EXTERNAL_URL = "https://cdn.example.org/clips/intro.mp4";

const NO_MEDIA: BlockMedia = {
  image: null,
  video: null,
  poster: null,
  embed: null,
  captions: [],
  alt: null,
  decorative: false,
  size: "full",
  title: null,
  available: true,
};

/** The media of a figure with a still WebP image of 800 by 600 pixels. */
export const figureMedia = (
  overrides: Partial<BlockMedia> = {},
): BlockMedia => ({
  ...NO_MEDIA,
  image: {
    url: mediaUrl("a", "webp"),
    mime: "image/webp",
    width: 800,
    height: 600,
    has_alpha: false,
    animated: false,
  },
  alt: "Four release checks in a row",
  ...overrides,
});

/** The media of a video file of the pack with its poster and two caption tracks. */
export const videoMedia = (
  overrides: Partial<BlockMedia> = {},
): BlockMedia => ({
  ...NO_MEDIA,
  size: null,
  title: "A tour of the assistant",
  video: {
    url: mediaUrl("b", "webm"),
    mime: "video/webm",
    width: 640,
    height: 360,
    duration_ms: 8000,
    has_audio: true,
    external: false,
  },
  poster: { url: mediaUrl("c", "webp"), width: 640, height: 360 },
  captions: [
    { url: mediaUrl("d", "vtt"), lang: "en" },
    { url: mediaUrl("e", "vtt"), lang: "de" },
  ],
  ...overrides,
});

/** The media of an external video file on `url`. */
export const externalMedia = (
  url = EXTERNAL_URL,
  overrides: Partial<BlockMedia> = {},
): BlockMedia => ({
  ...NO_MEDIA,
  size: null,
  title: "A clip from the library",
  video: {
    url,
    mime: "video/mp4",
    width: null,
    height: null,
    duration_ms: null,
    has_audio: null,
    external: true,
  },
  ...overrides,
});

/** The media of an embed player on `url`. */
export const embedMedia = (
  url = EMBED_URL,
  overrides: Partial<BlockMedia> = {},
): BlockMedia => {
  let host = "";
  try {
    host = new URL(url).host;
  } catch {
    // An invalid URL keeps an empty host.
  }
  return {
    ...NO_MEDIA,
    size: null,
    title: "A talk on checking sources",
    embed: { url, host },
    ...overrides,
  };
};

/** A `figure` or `video` block with `media` and an empty body. */
export const mediaBlock = (
  kind: "figure" | "video",
  media: BlockMedia | null,
  overrides: Partial<Block> = {},
): Block => ({
  id: `00000000-0000-4000-8000-${kind === "figure" ? "000000000081" : "000000000082"}`,
  kind,
  body: "",
  provenance: "invented",
  collapsed_on: [],
  placeholder_key: null,
  policy: null,
  media,
  citations: [],
  ...overrides,
});
