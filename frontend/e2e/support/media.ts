import { execFileSync } from "node:child_process";
import { writeFile } from "node:fs/promises";
import { join } from "node:path";
import { expect, type Locator, type Page } from "@playwright/test";

/**
 * The members of an HTML video element that the helpers read inside the
 * page; the specs compile without the DOM library.
 */
interface VideoElement {
  muted: boolean;
  readyState: number;
  play(): Promise<void>;
  textTracks: {
    length: number;
    [index: number]: {
      kind: string;
      mode: string;
      cues: { length: number } | null;
    };
  };
}

/** The members of an image element that `expectImageLoaded` reads. */
interface ImageElement {
  complete: boolean;
  naturalWidth: number;
}

/**
 * Waits until the `<img>` of `image` is visible and decoded with a width,
 * so the browser loaded the file and could read it.
 */
export async function expectImageLoaded(image: Locator): Promise<void> {
  await image.scrollIntoViewIfNeeded();
  await expect(image).toBeVisible();
  await expect
    .poll(
      () =>
        image.evaluate((element) => {
          const img = element as unknown as ImageElement;
          return img.complete ? img.naturalWidth : 0;
        }),
      { message: "the natural width of the image" },
    )
    .toBeGreaterThan(0);
}

/**
 * Plays `video` and waits until it holds data for the current position
 * (`readyState` 2, HAVE_CURRENT_DATA, or more) and until its first text
 * track, the captions, has cues. The video plays muted, so no autoplay
 * rule of the browser stops `play()`.
 */
export async function expectVideoPlaysWithCaptions(
  video: Locator,
): Promise<void> {
  await video.scrollIntoViewIfNeeded();
  await video.evaluate(async (element) => {
    const player = element as unknown as VideoElement;
    player.muted = true;
    await player.play();
  });
  await expect
    .poll(
      () =>
        video.evaluate(
          (element) => (element as unknown as VideoElement).readyState,
        ),
      { message: "the readyState of the video after play()" },
    )
    .toBeGreaterThanOrEqual(2);
  // The first track is the default captions track, whose cues load once
  // its mode is `showing`.
  await expect
    .poll(
      () =>
        video.evaluate((element) => {
          const { textTracks } = element as unknown as VideoElement;
          if (textTracks.length === 0) return "no track";
          const track = textTracks[0];
          return `${track.kind}, ${track.mode}, ${track.cues?.length ?? 0} cues`;
        }),
      { message: "the first text track" },
    )
    .toMatch(/^captions, showing, [1-9]\d* cues$/);
}

/** True when the page is no wider than its viewport. */
export async function expectNoHorizontalOverflow(
  page: Page,
  label: string,
): Promise<void> {
  const [scrollWidth, viewport] = await page.evaluate<[number, number]>(
    "[document.documentElement.scrollWidth, window.innerWidth]",
  );
  expect(scrollWidth, label).toBeLessThanOrEqual(viewport);
}

/** The files that `writeMediaFixtures` generates, by their absolute paths. */
export interface MediaFixtures {
  png: string;
  svg: string;
  mp4: string;
  vtt: string;
}

/** Runs ffmpeg of the nix shell with an argument list, without a shell. */
function ffmpeg(args: string[]): void {
  execFileSync(
    "ffmpeg",
    ["-hide_banner", "-loglevel", "error", "-y", ...args],
    {
      stdio: ["ignore", "ignore", "pipe"],
    },
  );
}

/**
 * Writes four small media files into `dir`, named after `stamp`: a PNG of
 * one colour, an SVG with a box and a line of text, an MP4 of three seconds
 * with H.264 video of a test pattern and an AAC tone, and WebVTT captions
 * for it. The colour, the text and the pitch of the tone derive from
 * `stamp`, so each run uploads files that the library does not hold yet
 * (it deduplicates uploads by their content).
 */
export async function writeMediaFixtures(
  dir: string,
  stamp: string,
): Promise<MediaFixtures> {
  const seed = [...stamp].reduce(
    (sum, char) => (sum * 31 + char.charCodeAt(0)) % 0xffffff,
    7,
  );
  const colour = seed.toString(16).padStart(6, "0");
  const files: MediaFixtures = {
    png: join(dir, `e2e-figure-${stamp}.png`),
    svg: join(dir, `e2e-diagram-${stamp}.svg`),
    mp4: join(dir, `e2e-clip-${stamp}.mp4`),
    vtt: join(dir, `e2e-clip-${stamp}-en.vtt`),
  };

  ffmpeg([
    "-f",
    "lavfi",
    "-i",
    `color=c=0x${colour}:s=320x180`,
    "-frames:v",
    "1",
    files.png,
  ]);
  ffmpeg([
    "-f",
    "lavfi",
    "-i",
    "testsrc2=size=320x180:rate=25:duration=3",
    "-f",
    "lavfi",
    "-i",
    `sine=frequency=${300 + (seed % 600)}:duration=3`,
    "-c:v",
    "libx264",
    "-pix_fmt",
    "yuv420p",
    "-c:a",
    "aac",
    "-shortest",
    "-movflags",
    "+faststart",
    files.mp4,
  ]);
  await writeFile(
    files.svg,
    [
      '<svg xmlns="http://www.w3.org/2000/svg" width="320" height="120" viewBox="0 0 320 120">',
      `  <title>Test diagram ${stamp}</title>`,
      '  <rect x="10" y="10" width="300" height="100" rx="8" fill="#e0f2fe" stroke="#0369a1" stroke-width="2"/>',
      `  <text x="160" y="68" font-family="sans-serif" font-size="16" text-anchor="middle" fill="#0f172a">Test diagram ${stamp}</text>`,
      "</svg>",
      "",
    ].join("\n"),
  );
  await writeFile(
    files.vtt,
    [
      "WEBVTT",
      "",
      `NOTE Captions of the test clip ${stamp}.`,
      "",
      "00:00:00.000 --> 00:00:01.500",
      "[A steady tone plays.]",
      "",
      "00:00:01.500 --> 00:00:03.000",
      "A test pattern moves while the tone plays.",
      "",
    ].join("\n"),
  );
  return files;
}
