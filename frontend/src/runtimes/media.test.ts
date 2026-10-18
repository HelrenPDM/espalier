import { describe, expect, test } from "vitest";
import type { components } from "../api/schema";
import type { BlockMedia } from "../player/runtime";
import { isScormContent, type ScormContent } from "./content";
import { fakeScorm12 } from "./fakeLms";
import type { MediaPolicy, PayloadBlockMedia } from "./media";
import { Scorm12Runtime } from "./scorm12";
import { scormContent } from "./scormFixture";
import {
  payloadToProgramView,
  type PackPayload,
  type PayloadBlock,
} from "./standalone";

/**
 * Task 0018 step 18: `payloadToProgramView` resolves the `media/` paths of
 * figure and video blocks through the media object of
 * `GET /api/admin/packs/:id` (with the allowlists of the installation) or
 * of `content.json` (without allowlists) into the `BlockMedia` shape of
 * the platform API (step 12).
 */
type AdminPackMedia = components["schemas"]["AdminPackMedia"];

const digest = (digit: string) => digit.repeat(64);
const url = (digit: string, ext: string) => `/media/${digest(digit)}.${ext}`;

const block = (
  kind: PayloadBlock["kind"],
  media: PayloadBlockMedia | null,
  body = "",
): PayloadBlock => ({
  kind,
  body,
  provenance: "invented",
  collapsed_on: [],
  placeholder_key: null,
  cite: [],
  media,
});

const figure = (media: PayloadBlockMedia) =>
  block("figure", {
    src: null,
    alt: null,
    decorative: null,
    size: null,
    ...media,
  });

const video = (media: PayloadBlockMedia) =>
  block("video", {
    src: null,
    embed: null,
    title: "A video",
    poster: null,
    captions: null,
    ...media,
  });

/** The blocks of the lesson, in this order. */
const BLOCKS: PayloadBlock[] = [
  block("text", null, "Plain text."),
  figure({ src: "media/photo.png", alt: "A desk with two screens" }),
  figure({ src: "media/diagram.svg", decorative: true, size: "small" }),
  figure({ src: "media/loop.gif", alt: "A cursor moves", size: "medium" }),
  video({
    src: "media/clip.mp4",
    captions: [
      { src: "media/clip-en.vtt", lang: "en" },
      { src: "media/clip-de.vtt", lang: "de" },
    ],
  }),
  video({ src: "media/clip.mp4", poster: "media/photo.png", captions: [] }),
  video({ src: "https://cdn.example.org/clips/intro.webm" }),
  video({ src: "https://other.example.net/clips/intro.mp4" }),
  video({ embed: "https://player.example.org:8443/watch/1" }),
  video({ embed: "https://videos.example.net/embed/7" }),
  video({
    src: "media/clip.mp4",
    captions: [{ src: "media/pending.vtt", lang: "en" }],
  }),
  figure({ src: "media/missing.png", alt: "Gone" }),
  figure({ src: "media/sketch.svg", alt: "A sketch of the flow" }),
  // A poster attribute that names an animated image.
  video({ src: "media/clip.mp4", poster: "media/loop.gif", captions: [] }),
];

function payload(blocks = BLOCKS): PackPayload {
  return {
    key: "media-pack",
    title: "Media pack",
    locale: "en",
    version: "1.0.0",
    sources: [],
    glossary: [],
    segments: [],
    stations: [{ kind: "module", title: "Media", module: 1, config: {} }],
    formats: [],
    modules: [
      {
        number: 1,
        title: "Media",
        summary: "Media.",
        phases: ["understand"],
        single_path: false,
        lessons: [{ key: "intro", title: "Intro", position: 1, blocks }],
        objectives: [],
        rules: [],
        items: [],
        assessments: [],
      },
    ],
  };
}

const entry = (
  kind: AdminPackMedia["kind"],
  overrides: Partial<AdminPackMedia> = {},
): AdminPackMedia => ({
  kind,
  status: "ready",
  failure: null,
  failure_detail: null,
  url: null,
  mime: null,
  width: null,
  height: null,
  duration_ms: null,
  progress: 100,
  has_audio: false,
  has_alpha: false,
  animated: false,
  poster_url: null,
  ...overrides,
});

/** The media object of the admin pack view, keyed by pack path. */
const PREVIEW_MEDIA: Record<string, AdminPackMedia> = {
  "media/photo.png": entry("image", {
    url: url("1", "webp"),
    mime: "image/webp",
    width: 1200,
    height: 800,
  }),
  "media/diagram.svg": entry("svg", {
    url: url("2", "svg"),
    mime: "image/svg+xml",
    width: 640,
    height: 320,
    has_alpha: true,
  }),
  "media/loop.gif": entry("image", {
    url: url("3", "webp"),
    mime: "image/webp",
    width: 400,
    height: 300,
    animated: true,
    poster_url: url("4", "webp"),
  }),
  "media/clip.mp4": entry("video", {
    url: url("5", "webm"),
    mime: "video/webm",
    width: 640,
    height: 360,
    duration_ms: 8000,
    has_audio: true,
    poster_url: url("6", "webp"),
  }),
  "media/clip-en.vtt": entry("captions", {
    url: url("7", "vtt"),
    mime: "text/vtt",
  }),
  "media/clip-de.vtt": entry("captions", {
    url: url("8", "vtt"),
    mime: "text/vtt",
  }),
  "media/pending.vtt": entry("captions", { status: "processing" }),
  "media/missing.png": entry("image", { status: "missing" }),
  // An SVG without a fixed size: it has no size facts.
  "media/sketch.svg": entry("svg", {
    url: url("9", "svg"),
    mime: "image/svg+xml",
    has_alpha: true,
  }),
};

const POLICY: MediaPolicy = {
  external_hosts: ["CDN.example.org"],
  embed_hosts: ["player.example.org:8443"],
};

const none: BlockMedia = {
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

const packVideo = (digit: string, ext: string) => ({
  url: url(digit, ext),
  mime: "video/webm" as const,
  width: 640,
  height: 360,
  duration_ms: 8000,
  has_audio: true,
  external: false,
});

const externalVideo = (src: string, mime: "video/webm" | "video/mp4") => ({
  url: src,
  mime,
  width: null,
  height: null,
  duration_ms: null,
  has_audio: null,
  external: true,
});

/** The expected media of `BLOCKS` with the preview media and `POLICY`. */
const EXPECTED: (BlockMedia | null)[] = [
  null,
  {
    ...none,
    image: {
      url: url("1", "webp"),
      mime: "image/webp",
      width: 1200,
      height: 800,
      has_alpha: false,
      animated: false,
    },
    alt: "A desk with two screens",
    size: "full",
    available: true,
  },
  {
    ...none,
    image: {
      url: url("2", "svg"),
      mime: "image/svg+xml",
      width: 640,
      height: 320,
      has_alpha: true,
      animated: false,
    },
    decorative: true,
    size: "small",
    available: true,
  },
  {
    ...none,
    image: {
      url: url("3", "webp"),
      mime: "image/webp",
      width: 400,
      height: 300,
      has_alpha: false,
      animated: true,
    },
    poster: { url: url("4", "webp"), width: 400, height: 300 },
    alt: "A cursor moves",
    size: "medium",
    available: true,
  },
  {
    ...none,
    video: packVideo("5", "webm"),
    poster: { url: url("6", "webp"), width: 640, height: 360 },
    captions: [
      { url: url("7", "vtt"), lang: "en" },
      { url: url("8", "vtt"), lang: "de" },
    ],
    title: "A video",
    available: true,
  },
  {
    ...none,
    video: packVideo("5", "webm"),
    poster: { url: url("1", "webp"), width: 1200, height: 800 },
    title: "A video",
    available: true,
  },
  {
    ...none,
    video: externalVideo(
      "https://cdn.example.org/clips/intro.webm",
      "video/webm",
    ),
    title: "A video",
    available: true,
  },
  {
    ...none,
    video: externalVideo(
      "https://other.example.net/clips/intro.mp4",
      "video/mp4",
    ),
    title: "A video",
    available: false,
  },
  {
    ...none,
    embed: {
      url: "https://player.example.org:8443/watch/1",
      host: "player.example.org:8443",
    },
    title: "A video",
    available: true,
  },
  {
    ...none,
    embed: {
      url: "https://videos.example.net/embed/7",
      host: "videos.example.net",
    },
    title: "A video",
    available: false,
  },
  {
    ...none,
    video: packVideo("5", "webm"),
    poster: { url: url("6", "webp"), width: 640, height: 360 },
    title: "A video",
    available: false,
  },
  { ...none, alt: "Gone", size: "full" },
  {
    ...none,
    image: {
      url: url("9", "svg"),
      mime: "image/svg+xml",
      width: null,
      height: null,
      has_alpha: true,
      animated: false,
    },
    alt: "A sketch of the flow",
    size: "full",
    available: true,
  },
  {
    ...none,
    video: packVideo("5", "webm"),
    // The still first frame of the animated image, so the poster never
    // moves (WCAG 2.2 2.2.2).
    poster: { url: url("4", "webp"), width: 400, height: 300 },
    title: "A video",
    available: true,
  },
];

const blockMedia = (view: ReturnType<typeof payloadToProgramView>) =>
  view.modules[0].lessons[0].blocks.map((entry) => entry.media);

describe("payloadToProgramView with the media of the admin preview", () => {
  test("resolves every media path into the BlockMedia of the platform API", () => {
    expect(
      blockMedia(payloadToProgramView(payload(), PREVIEW_MEDIA, POLICY)),
    ).toEqual(EXPECTED);
  });

  test("a host outside the lists is unavailable, and an empty list admits none", () => {
    const media = blockMedia(
      payloadToProgramView(payload(), PREVIEW_MEDIA, {
        external_hosts: [],
        embed_hosts: ["player.example.org"],
      }),
    );

    expect(media[6]?.available).toBe(false);
    // The port is part of the host: player.example.org admits only port 443.
    expect(media[8]?.available).toBe(false);
  });

  test("a file that is not ready makes its block unavailable", () => {
    const media = blockMedia(
      payloadToProgramView(
        payload(),
        {
          ...PREVIEW_MEDIA,
          "media/photo.png": entry("image", { status: "queued" }),
          "media/clip.mp4": entry("video", {
            status: "failed",
            failure: "conversion_failed",
          }),
        },
        POLICY,
      ),
    );

    expect(media[1]).toEqual({
      ...none,
      alt: "A desk with two screens",
      size: "full",
    });
    expect(media[4]).toMatchObject({ video: null, available: false });
    // The poster attribute names the photo, which is not ready either.
    expect(media[5]).toMatchObject({ poster: null, available: false });
  });

  test("an SVG without size facts is available, and an image without them has no poster", () => {
    const media = blockMedia(
      payloadToProgramView(
        payload([
          figure({ src: "media/sketch.svg", alt: "A sketch of the flow" }),
          figure({ src: "media/loop.gif", alt: "A cursor moves" }),
        ]),
        {
          "media/sketch.svg": entry("svg", {
            url: url("9", "svg"),
            width: 640,
            height: null,
          }),
          "media/loop.gif": entry("image", {
            url: url("3", "webp"),
            animated: true,
            poster_url: url("4", "webp"),
          }),
        },
        POLICY,
      ),
    );

    // One size alone is no size fact either.
    expect(media[0]).toMatchObject({
      image: { mime: "image/svg+xml", width: null, height: null },
      available: true,
    });
    expect(media[1]).toMatchObject({
      image: { width: null, height: null, animated: true },
      poster: null,
      available: true,
    });
  });

  test("an animated poster without its still first frame counts as missing", () => {
    const media = blockMedia(
      payloadToProgramView(
        payload([
          video({
            src: "media/clip.mp4",
            poster: "media/loop.gif",
            captions: [],
          }),
        ]),
        {
          ...PREVIEW_MEDIA,
          "media/loop.gif": {
            ...PREVIEW_MEDIA["media/loop.gif"],
            poster_url: null,
          },
        },
        POLICY,
      ),
    );

    // The animated file never becomes the poster: the video shows its own
    // first frame and the notice of a missing file.
    expect(media[0]).toMatchObject({
      poster: { url: url("6", "webp"), width: 640, height: 360 },
      available: false,
    });
  });

  test("an external URL that is not https: or has no video extension is unavailable", () => {
    const media = blockMedia(
      payloadToProgramView(
        payload([
          video({ src: "https://cdn.example.org/stream.m3u8" }),
          video({ embed: "http://player.example.org:8443/watch/1" }),
        ]),
        {},
        POLICY,
      ),
    );

    expect(media.map((entry) => entry?.available)).toEqual([false, false]);
  });

  test("blocks without media, from a payload before task 0018, resolve as before", () => {
    const old = block("text", null);
    delete (old as Partial<PayloadBlock>).media;
    const program = payloadToProgramView(payload([old]));

    expect(program.modules[0].lessons[0].blocks[0].media).toBeNull();
  });
});

describe("payloadToProgramView with the media of content.json", () => {
  /** The media object of a SCORM package: URLs relative to index.html. */
  const scormMedia = (): ScormContent["media"] =>
    Object.fromEntries(
      Object.entries(PREVIEW_MEDIA)
        .filter(([, value]) => value.url !== null)
        .map(([path, value]) => [
          path,
          {
            url: (value.url as string).slice(1),
            kind: value.kind,
            mime: value.mime as string,
            width: value.width,
            height: value.height,
            duration_ms: value.duration_ms,
            has_audio: value.has_audio,
            has_alpha: value.has_alpha,
            animated: value.animated,
            poster_url: value.poster_url?.slice(1) ?? null,
          },
        ]),
    );

  const relative = (media: BlockMedia | null): BlockMedia | null => {
    if (media === null) return null;
    const strip = (value: string) =>
      value.startsWith("/media/") ? value.slice(1) : value;
    return {
      ...media,
      image: media.image && { ...media.image, url: strip(media.image.url) },
      video: media.video && { ...media.video, url: strip(media.video.url) },
      poster: media.poster && { ...media.poster, url: strip(media.poster.url) },
      captions: media.captions.map((caption) => ({
        ...caption,
        url: strip(caption.url),
      })),
    };
  };

  test("without a policy every host is available, and the files keep their package URLs", async () => {
    const content: ScormContent = {
      ...scormContent({ exam: false }),
      media: scormMedia(),
    };
    content.module.lessons = [
      { key: "intro", title: "Intro", position: 1, blocks: BLOCKS },
    ];
    expect(isScormContent(content)).toBe(true);

    const { api } = fakeScorm12();
    const runtime = new Scorm12Runtime(content, api);
    runtime.start();
    try {
      const program = await runtime.loadProgram(content.program.slug);
      const media = blockMedia(program);

      expect(media).toEqual(
        EXPECTED.map((expected, index) => {
          const resolved = relative(expected);
          // No allowlist in a package; the pending captions file is not
          // in the package, so that block stays unavailable.
          return resolved !== null && (index === 7 || index === 9)
            ? { ...resolved, available: true }
            : resolved;
        }),
      );
      expect(media[1]?.image?.url).toBe(`media/${digest("1")}.webp`);
      expect(media[12]).toMatchObject({
        image: { url: `media/${digest("9")}.svg`, width: null, height: null },
        available: true,
      });
    } finally {
      runtime.finish();
    }
  });

  test("isScormContent requires the media object", () => {
    const { media: _media, ...withoutMedia } = scormContent();

    expect(isScormContent(scormContent())).toBe(true);
    expect(isScormContent(withoutMedia)).toBe(false);
    expect(isScormContent({ ...scormContent(), media: [] })).toBe(false);
  });
});
