import { act, screen, waitFor, within } from "@testing-library/react";
import { afterEach, describe, expect, test, vi } from "vitest";
import type { PackDiff, PackImport, PackMedia } from "../../api/admin/packs";
import { expectNoAxeViolations } from "../../test/axe";
import {
  renderWithProviders,
  requestsTo,
  type StubResponses,
} from "../../test/render";
import { signedInPayload } from "../../test/session";
import { PackPage } from "./PackPage";

/**
 * Task 0018, steps 10 and 19: the section "Media" of the pack page with
 * the state and the facts of every media file of the import and the
 * captions hint for a video with audio that a block shows without
 * captions; "Publish" stays disabled with a sentence while a file is not
 * `ready`, and the page reads the import every two seconds while a file
 * is converted; the publish dialog names the media kind of the diff and
 * the files of a 409 `media_not_ready`.
 */
const ID = "00000000-0000-4000-8000-000000000501";
const PATH = `/api/admin/packs/${ID}`;
const author = signedInPayload("mfa", { roles: ["learner", "author"] });
const sha = (n: number) => n.toString(16).padStart(64, "0");

function media(overrides: Partial<PackMedia> = {}): PackMedia {
  return {
    kind: "video",
    status: "ready",
    failure: null,
    failure_detail: null,
    url: `/media/${sha(1)}.webm`,
    mime: "video/webm",
    width: 640,
    height: 360,
    duration_ms: 8_000,
    progress: 0,
    has_audio: true,
    has_alpha: false,
    animated: false,
    poster_url: `/media/${sha(2)}.webp`,
    ...overrides,
  };
}

const videoBlock = (
  src: string,
  captions: { src: string; lang: string }[] | null,
) => ({
  kind: "video",
  body: "",
  provenance: "invented",
  collapsed_on: [],
  placeholder_key: null,
  cite: [],
  media: { src, embed: null, title: "A video", poster: null, captions },
});

/** A payload whose lessons show three videos, one of them with captions. */
const payload = {
  key: "demo",
  modules: [
    {
      number: 1,
      lessons: [
        {
          key: "01-first-lesson",
          blocks: [
            { kind: "text", body: "Text", media: null },
            videoBlock("media/clip.webm", null),
            videoBlock("media/talk.webm", [
              { src: "media/talk-en.vtt", lang: "en" },
            ]),
            videoBlock("media/silent.webm", []),
            videoBlock("https://cdn.example.org/external.webm", null),
          ],
        },
      ],
    },
  ],
};

const READY: Record<string, PackMedia> = {
  "media/clip.webm": media(),
  "media/talk.webm": media(),
  "media/silent.webm": media({ has_audio: false }),
  "media/talk-en.vtt": media({
    kind: "captions",
    mime: "text/vtt",
    url: `/media/${sha(3)}.vtt`,
    width: null,
    height: null,
    has_audio: false,
    poster_url: null,
  }),
  "media/photo.webp": media({
    kind: "image",
    mime: "image/webp",
    url: `/media/${sha(4)}.webp`,
    width: 1280,
    height: 853,
    duration_ms: null,
    has_audio: false,
    animated: true,
    poster_url: null,
  }),
};

const PROCESSING: Record<string, PackMedia> = {
  ...READY,
  "media/photo.webp": media({
    kind: "image",
    status: "processing",
    url: null,
    mime: null,
    width: null,
    height: null,
    duration_ms: null,
    has_audio: false,
    poster_url: null,
  }),
};

function pack(overrides: Partial<PackImport> = {}): PackImport {
  return {
    id: ID,
    status: "validated",
    pack_key: "demo",
    pack_version: "1.5.0",
    inserted_at: "2026-10-15T09:30:00Z",
    published_at: null,
    payload,
    report: { errors: [], warnings: [] },
    media: READY,
    media_policy: {
      external_hosts: ["cdn.example.org"],
      embed_hosts: [],
      embed_consent: "click",
    },
    alignment: { mode: "strict", matrix: [], errors: [], warnings: [] },
    ...overrides,
  };
}

const emptyKind = { added: [], changed: [], archived: [] };

const diff: PackDiff = {
  modules: emptyKind,
  lessons: emptyKind,
  learning_objectives: { ...emptyKind, changed_fields: {} },
  items: emptyKind,
  rules: emptyKind,
  assessments: emptyKind,
  qualifications: emptyKind,
  formats: emptyKind,
  sources: emptyKind,
  segments: emptyKind,
  glossary_terms: emptyKind,
  media: {
    added: ["media/clip.webm"],
    changed: ["media/photo.webp"],
    archived: [],
  },
};

function renderPage(responses: StubResponses = {}) {
  return renderWithProviders(<PackPage />, {
    route: `/admin/packs/${ID}`,
    path: "/admin/packs/:id",
    session: author,
    responses: {
      [`GET ${PATH}`]: { status: 200, body: pack() },
      ...responses,
    },
  });
}

const mediaTable = () => screen.findByRole("table", { name: "Media" });

/** The cells of the row whose first cell is `path`. */
function rowOf(table: HTMLElement, path: string): string[] {
  const row = within(table)
    .getAllByRole("row")
    .find((candidate) => candidate.textContent?.startsWith(path));
  if (row === undefined) throw new Error(`no row for ${path}`);
  return within(row)
    .getAllByRole("cell")
    .map((cell) => cell.textContent ?? "");
}

const advance = (ms: number) => act(() => vi.advanceTimersByTimeAsync(ms));

afterEach(() => {
  vi.useRealTimers();
});

describe("the section Media", () => {
  test("lists every file with kind, state and facts, and hints at videos without captions", async () => {
    const { container } = renderPage({
      [`GET ${PATH}`]: { status: 200, body: pack({ media: PROCESSING }) },
    });

    const table = await mediaTable();
    expect(
      within(table)
        .getAllByRole("columnheader")
        .map((cell) => cell.textContent),
    ).toEqual(["Path", "Kind", "State", "Facts"]);
    expect(rowOf(table, "media/clip.webm")).toEqual([
      "media/clip.webm",
      "Video",
      "Ready",
      "640 × 360 px, 0:08, with audio",
    ]);
    expect(rowOf(table, "media/silent.webm")[3]).toBe(
      "640 × 360 px, 0:08, without audio",
    );
    expect(rowOf(table, "media/photo.webp")).toEqual([
      "media/photo.webp",
      "Image",
      "Processing, 0 %",
      "-",
    ]);
    expect(rowOf(table, "media/talk-en.vtt").slice(1, 3)).toEqual([
      "Captions",
      "Ready",
    ]);

    const hint = screen.getByRole("note", { name: "Videos without captions" });
    expect(
      within(hint)
        .getAllByRole("listitem")
        .map((item) => item.textContent),
    ).toEqual(["media/clip.webm"]);

    const publish = screen.getByRole("button", { name: "Publish" });
    expect(publish).toBeDisabled();
    expect(publish).toHaveAccessibleDescription(
      "Media files are still converted. Publishing becomes possible when every media file is ready.",
    );

    await expectNoAxeViolations(container);
  });

  test("reads the import every two seconds while a file is converted and then enables Publish", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    const { requests } = renderPage({
      [`GET ${PATH}`]: [
        { status: 200, body: pack({ media: PROCESSING }) },
        { status: 200, body: pack({ media: READY }) },
      ],
    });

    const table = await mediaTable();
    expect(rowOf(table, "media/photo.webp")[2]).toBe("Processing, 0 %");
    expect(screen.getByRole("button", { name: "Publish" })).toBeDisabled();

    await advance(2000);
    await waitFor(() =>
      expect(screen.getByRole("button", { name: "Publish" })).toBeEnabled(),
    );
    expect(rowOf(table, "media/photo.webp")).toEqual([
      "media/photo.webp",
      "Image",
      "Ready",
      "1280 × 853 px, animated",
    ]);
    expect(requestsTo(requests, "GET", PATH)).toHaveLength(2);

    await advance(6000);
    expect(requestsTo(requests, "GET", PATH)).toHaveLength(2);
  });

  test("a failed or missing file holds the publication back with its failure text", async () => {
    renderPage({
      [`GET ${PATH}`]: {
        status: 200,
        body: pack({
          media: {
            ...READY,
            "media/diagram.svg": media({
              kind: "svg",
              status: "failed",
              failure: "invalid_svg",
              failure_detail: "embedded_image",
              url: null,
              width: null,
              height: null,
              duration_ms: null,
              has_audio: false,
              poster_url: null,
            }),
            "media/gone.webm": media({ status: "missing", url: null }),
          },
        }),
      },
    });

    const table = await mediaTable();
    expect(rowOf(table, "media/diagram.svg")[2]).toBe(
      "FailedThe SVG file could not be rebuilt. Reason: The file embeds a raster image.",
    );
    expect(rowOf(table, "media/gone.webm")[2]).toBe("Missing");
    expect(
      screen.getByRole("button", { name: "Publish" }),
    ).toHaveAccessibleDescription(
      "A media file failed or is missing. Replace it in the pack and import the pack again.",
    );
  });

  test("an import without media states it", async () => {
    renderPage({
      [`GET ${PATH}`]: {
        status: 200,
        body: pack({ media: {}, payload: null, status: "failed" }),
      },
    });

    expect(
      await screen.findByText("The import holds no media file."),
    ).toBeInTheDocument();
    expect(screen.queryByRole("table", { name: "Media" })).toBeNull();
  });
});

describe("the publication", () => {
  test("the dialog names the media files of the diff", async () => {
    const { user } = renderPage({
      [`GET ${PATH}/diff`]: { status: 200, body: diff },
    });

    await user.click(await screen.findByRole("button", { name: "Publish" }));
    const dialog = await screen.findByRole("dialog", { name: "Publish demo?" });
    const heading = await within(dialog).findByRole("heading", {
      name: "Media files",
    });
    const section = heading.closest("section");
    expect(section).toHaveTextContent("Added (1)media/clip.webm");
    expect(section).toHaveTextContent("Changed (1)media/photo.webp");
  });

  test("a 409 media_not_ready lists the files in the dialog and reads the import again", async () => {
    const { user, requests } = renderPage({
      [`GET ${PATH}/diff`]: { status: 200, body: diff },
      [`POST ${PATH}/publish`]: {
        status: 409,
        body: {
          error: "media_not_ready",
          media: [
            { path: "media/clip.webm", status: "processing", failure: null },
            {
              path: "media/diagram.svg",
              status: "failed",
              failure: "invalid_svg",
            },
          ],
        },
      },
    });

    await user.click(await screen.findByRole("button", { name: "Publish" }));
    const dialog = await screen.findByRole("dialog", { name: "Publish demo?" });
    await within(dialog).findByRole("heading", { name: "Media files" });
    await user.click(within(dialog).getByRole("button", { name: "Publish" }));

    expect(
      await within(dialog).findByText(
        "The publication was refused, because these media files are not ready. The import stays unpublished.",
      ),
    ).toBeInTheDocument();
    const entries = within(dialog)
      .getAllByRole("listitem")
      .map((item) => item.textContent)
      .filter((text) => text?.startsWith("media/"));
    expect(entries).toEqual([
      "media/clip.webm: Processing",
      "media/diagram.svg: Failed, The SVG file could not be rebuilt.",
    ]);
    expect(
      within(dialog).queryByRole("button", { name: "Publish" }),
    ).toBeNull();
    await waitFor(() =>
      expect(requestsTo(requests, "GET", PATH)).toHaveLength(2),
    );
    await expectNoAxeViolations(document.body);
  });
});
