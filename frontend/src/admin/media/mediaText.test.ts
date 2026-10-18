import { renderHook } from "@testing-library/react";
import { describe, expect, test } from "vitest";
import i18n from "../../i18n";
import {
  defaultMediaPath,
  formatDuration,
  mediaDirective,
  mediaUrl,
  useMediaFailureText,
} from "./mediaText";

/**
 * Task 0018, step 19: the derived values of the media UI and the messages
 * of every failure code of step 8 and every reason tag of steps 6 and 7,
 * in English and German.
 */
const FAILURES = [
  "too_many_pixels",
  "too_many_frames",
  "too_long",
  "no_video_stream",
  "unsupported_animation",
  "invalid_svg",
  "invalid_captions",
  "malware_found",
  "scan_failed",
  "storage_full",
  "conversion_failed",
  "timeout",
  "interrupted",
];

const TAGS: [string, string[]][] = [
  ["unsupported_animation", ["structure", "first_frame", "too_many_frames"]],
  [
    "invalid_svg",
    [
      "too_large",
      "encoding",
      "doctype",
      "entity",
      "processing_instruction",
      "parse_error",
      "root",
      "embedded_image",
      "css",
      "animation",
    ],
  ],
  [
    "invalid_captions",
    [
      "too_large",
      "encoding",
      "nul",
      "header",
      "too_many_cues",
      "timing",
      "style",
    ],
  ],
  [
    "scan_failed",
    ["limits_exceeded", "size_limit", "timeout", "closed", "connect", "reply"],
  ],
];

describe("the directive", () => {
  test("of an image, an SVG and a video, and none for captions", () => {
    expect(mediaDirective("image", "media/team-photo.webp")).toBe(
      ':::figure{src=media/team-photo.webp alt="" provenance=invented}\n:::\n',
    );
    expect(mediaDirective("svg", "media/release-checks.svg")).toBe(
      ':::figure{src=media/release-checks.svg alt="" provenance=invented}\n:::\n',
    );
    expect(mediaDirective("video", "media/assistant-demo.webm")).toBe(
      ':::video{src=media/assistant-demo.webm title="" provenance=invented}\n:::\n',
    );
    expect(mediaDirective("captions", "media/intro-en.vtt")).toBeNull();
  });

  test("uses the slug of the title and the delivery extension of the kind", () => {
    expect(defaultMediaPath("Team photo", "image")).toBe(
      "media/team-photo.webp",
    );
    expect(defaultMediaPath("Release checks", "svg")).toBe(
      "media/release-checks.svg",
    );
    expect(defaultMediaPath("Assistant demo", "video")).toBe(
      "media/assistant-demo.webm",
    );
    expect(defaultMediaPath("Intro (EN)", "captions")).toBe(
      "media/intro-en.vtt",
    );
  });
});

describe("mediaUrl", () => {
  const digest = "a".repeat(64);

  test("admits the paths of the media route only", () => {
    for (const ext of ["webp", "svg", "webm", "vtt"])
      expect(mediaUrl(`/media/${digest}.${ext}`)).toBe(
        `/media/${digest}.${ext}`,
      );
    for (const url of [
      `https://cdn.example.org/media/${digest}.webp`,
      `//cdn.example.org/media/${digest}.webp`,
      `javascript:alert(1)//media/${digest}.webp`,
      `/media/${digest}.png`,
      `/media/${digest.slice(1)}.webp`,
      `/media/../${digest}.webp`,
      `/media/${digest}.webp?x=1`,
      null,
      undefined,
    ])
      expect(mediaUrl(url)).toBeNull();
  });
});

test("formatDuration writes minutes and hours", () => {
  expect(formatDuration(8_000)).toBe("0:08");
  expect(formatDuration(754_400)).toBe("12:34");
  expect(formatDuration(3_725_000)).toBe("1:02:05");
});

describe.each(["en", "de"])("the failure texts in %s", (language) => {
  const failureText = () => {
    void i18n.changeLanguage(language);
    const { result } = renderHook(() => useMediaFailureText());
    return result.current;
  };

  test("name every failure code of step 8", async () => {
    const text = failureText();
    try {
      expect(text("storage_full", null)).toBe(
        language === "de"
          ? "Der Medienspeicher ist voll."
          : "The media store is full.",
      );
      for (const failure of FAILURES) {
        const message = text(failure, null);
        expect(message).not.toMatch(/admin\.media/);
        // An unknown code shows the code itself.
        expect(message).not.toBe(
          text("unknown-code", null).replace("unknown-code", failure),
        );
      }
    } finally {
      await i18n.changeLanguage("en");
    }
  });

  test("name every reason tag of steps 6 and 7", async () => {
    const text = failureText();
    try {
      for (const [failure, tags] of TAGS)
        for (const tag of tags) {
          const message = text(failure, tag);
          expect(message).toContain(text(failure, null));
          expect(message).not.toMatch(/admin\.media/);
          // An unknown tag shows the tag itself.
          expect(message).not.toBe(
            text(failure, "unknown-tag").replace("unknown-tag", tag),
          );
        }
    } finally {
      await i18n.changeLanguage("en");
    }
  });
});

test("an unknown code or tag appears as the code itself", () => {
  const { result } = renderHook(() => useMediaFailureText());
  expect(result.current("new_code", null)).toBe(
    "The processing failed with the code new_code.",
  );
  expect(result.current("invalid_svg", "new_tag")).toBe(
    "The SVG file could not be rebuilt. Reason: Code new_tag.",
  );
  expect(result.current(null, null)).toBe("The processing failed.");
});
