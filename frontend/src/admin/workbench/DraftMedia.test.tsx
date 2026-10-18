import { act, screen, waitFor, within } from "@testing-library/react";
import { afterEach, describe, expect, test, vi } from "vitest";
import type { MediaAsset } from "../../api/admin/media";
import type {
  DraftMediaEntry,
  PackDraft,
  PackDraftFile,
} from "../../api/admin/workbench";
import { expectNoAxeViolations } from "../../test/axe";
import { installFakeXhr } from "../../test/fakeXhr";
import {
  renderWithProviders,
  requestsTo,
  type RenderWithProvidersResult,
  type StubAnswer,
  type StubResponses,
} from "../../test/render";
import { signedInPayload } from "../../test/session";
import { DraftPage } from "./DraftPage";
import type { PackFileEditorProps } from "./PackFileEditor";

/**
 * Task 0018, step 19: the media entries of the draft page. The file tree
 * shows the media entries below `media/` with the name of their kind and
 * the captions as text files; a media entry opens `MediaPreview` in place
 * of the editor; "Add media" attaches a library asset or a new upload;
 * rename and delete use the media routes; "Add file" creates a captions
 * file with the header `WEBVTT`; and "Download as zip" waits with a
 * sentence until every media entry is `ready`. The editor is a textarea,
 * as in `DraftPage.test.tsx`.
 */
function EditorStub({ value, onChange, language, label }: PackFileEditorProps) {
  return (
    <textarea
      aria-label={label}
      data-language={language}
      value={value}
      onChange={(event) => onChange(event.target.value)}
    />
  );
}

vi.mock("./PackFileEditor", () => ({ PackFileEditor: EditorStub }));

const ID = "00000000-0000-4000-8000-000000000801";
const BASE = `/api/admin/pack-drafts/${ID}`;
const TIME = "2026-10-15T09:00:00Z";
const FUTURE = "2999-01-01T00:00:00Z";
const author = signedInPayload("mfa", {
  roles: ["learner", "author"],
  session: { recent_auth_until: FUTURE },
});

const uuid = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const sha = (n: number) => n.toString(16).padStart(64, "0");

function asset(n: number, overrides: Partial<MediaAsset> = {}): MediaAsset {
  return {
    id: uuid(n),
    kind: "image",
    status: "ready",
    failure: null,
    failure_detail: null,
    progress: 100,
    title: `Asset ${n}`,
    source_name: `asset-${n}.png`,
    origin: "upload",
    ext: "webp",
    bytes: 2_048,
    width: 640,
    height: 480,
    duration_ms: null,
    has_audio: false,
    animated: false,
    has_alpha: false,
    url: `/media/${sha(n)}.webp`,
    poster_url: null,
    inserted_at: TIME,
    updated_at: TIME,
    ...overrides,
  };
}

const PHOTO = asset(1, { title: "Team photo", width: 1280, height: 853 });
const CLIP = asset(2, {
  kind: "video",
  status: "processing",
  progress: 40,
  title: "Assistant demo",
  ext: null,
  bytes: null,
  width: null,
  height: null,
  url: null,
});
const READY_CLIP = asset(2, {
  ...CLIP,
  status: "ready",
  progress: 100,
  ext: "webm",
  bytes: 1_048_576,
  width: 640,
  height: 360,
  duration_ms: 8_000,
  has_audio: true,
  url: `/media/${sha(2)}.webm`,
  poster_url: `/media/${sha(12)}.webp`,
});
const LOGO = asset(3, {
  kind: "svg",
  title: "Logo",
  ext: "svg",
  url: `/media/${sha(3)}.svg`,
});
const CAPTIONS = asset(4, {
  kind: "captions",
  title: "Intro captions",
  ext: "vtt",
  url: `/media/${sha(4)}.vtt`,
});
const BROKEN = asset(5, {
  kind: "svg",
  status: "failed",
  failure: "invalid_svg",
  failure_detail: "css",
  title: "Broken graphic",
  ext: null,
  url: null,
});

const PHOTO_ENTRY: DraftMediaEntry = {
  id: uuid(901),
  path: "media/team-photo.webp",
  asset: PHOTO,
};
const CLIP_ENTRY: DraftMediaEntry = {
  id: uuid(902),
  path: "media/videos/assistant-demo.webm",
  asset: CLIP,
};

const FILES = [
  { id: uuid(801), path: "pack.yaml" },
  { id: uuid(802), path: "media/intro-en.vtt" },
  { id: uuid(803), path: "modules/01-first-module/module.yaml" },
];
const [, CAPTIONS_FILE] = FILES;

function draftOf(
  lockVersion = 3,
  media: DraftMediaEntry[] = [PHOTO_ENTRY, CLIP_ENTRY],
  files = FILES,
): PackDraft {
  return {
    id: ID,
    title: "Demo pack",
    pack_key: "demo",
    lock_version: lockVersion,
    inserted_at: TIME,
    updated_at: TIME,
    usage: { files: files.length + media.length, bytes: 2_048 },
    limits: { files: 2_000, file_bytes: 1_048_576, draft_bytes: 104_857_600 },
    files: files.map((file) => ({ ...file, bytes: 100, updated_at: TIME })),
    media,
  };
}

const ok = (body: unknown, status = 200): StubAnswer => ({ status, body });

const captionsAnswer: PackDraftFile = {
  ...CAPTIONS_FILE,
  content: "WEBVTT\n\n00:00.000 --> 00:02.000\nHello\n",
  bytes: 38,
  updated_at: TIME,
  lock_version: 3,
};

function renderPage(responses: StubResponses = {}) {
  return renderWithProviders(<DraftPage />, {
    route: `/admin/workbench/${ID}`,
    path: "/admin/workbench/:id",
    session: author,
    responses: {
      [`GET ${BASE}`]: ok(draftOf()),
      [`GET ${BASE}/files/${CAPTIONS_FILE.id}`]: ok(captionsAnswer),
      [`GET /api/admin/media/${PHOTO.id}`]: ok({ ...PHOTO, uses: undefined }),
      [`GET /api/admin/media/${CLIP.id}`]: ok(CLIP),
      ...responses,
    },
  });
}

const findTree = () =>
  screen.findByRole("navigation", { name: "Files of the draft" });

const status = () =>
  screen
    .getAllByRole("status")
    .map((region) => region.textContent)
    .join(" ");

/** Records the URL of every request, with its query. */
function recordRequestUrls(): string[] {
  const urls: string[] = [];
  const Base = globalThis.Request;
  vi.stubGlobal(
    "Request",
    class extends Base {
      constructor(input: RequestInfo | URL, init?: RequestInit) {
        super(input, init);
        urls.push(this.url);
      }
    },
  );
  return urls;
}

async function openMenu(
  { user }: RenderWithProvidersResult,
  path: string,
  item: "Rename" | "Delete",
) {
  const nav = await findTree();
  await user.click(
    within(nav).getByRole("button", { name: `Actions for ${path}` }),
  );
  await user.click(await screen.findByRole("menuitem", { name: item }));
}

const advance = (ms: number) => act(() => vi.advanceTimersByTimeAsync(ms));

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

describe("the file tree", () => {
  test("shows the media entries below media/ with their kind and the captions as a text file", async () => {
    const { container } = renderPage();
    const nav = await findTree();

    const photo = within(nav).getByRole("button", {
      name: "team-photo.webp, media/, Image",
    });
    const clip = within(nav).getByRole("button", {
      name: "assistant-demo.webm, media/videos/, Video",
    });
    const captions = within(nav).getByRole("button", {
      name: "intro-en.vtt, media/",
    });
    // The media entries and the captions share the directory media/.
    const media = within(nav).getByText("media/").closest("li");
    expect(media).not.toBeNull();
    for (const button of [photo, clip, captions])
      expect(media).toContainElement(button);
    expect(photo.querySelector("svg")).toHaveAttribute("aria-hidden", "true");
    expect(
      screen.getByText("Media entries").nextElementSibling,
    ).toHaveTextContent("2");

    await expectNoAxeViolations(container);
  });

  test("a captions file opens in the editor as plain text", async () => {
    const { user } = renderPage();
    const nav = await findTree();

    await user.click(
      within(nav).getByRole("button", { name: "intro-en.vtt, media/" }),
    );

    const editor = await screen.findByRole("textbox", {
      name: "Content of media/intro-en.vtt",
    });
    expect(editor).toHaveAttribute("data-language", "text");
    expect(editor).toHaveValue(captionsAnswer.content);
  });
});

describe("MediaPreview", () => {
  test("a media entry shows state, preview, facts and the directive in place of the editor", async () => {
    const { user, container, requests } = renderPage();
    const nav = await findTree();
    const button = within(nav).getByRole("button", {
      name: "team-photo.webp, media/, Image",
    });

    await user.click(button);

    const heading = await screen.findByRole("heading", {
      name: "Media file media/team-photo.webp",
    });
    const section = heading.closest("section");
    if (section === null) throw new Error("no section");
    expect(button).toHaveAttribute("aria-current", "true");
    expect(
      within(section).getByRole("img", { name: "Preview of Team photo" }),
    ).toHaveAttribute("src", PHOTO.url);
    expect(section).toHaveTextContent("State Ready");
    expect(section).toHaveTextContent("Dimensions1280 × 853 px");
    expect(section).toHaveTextContent("Title in the library: Team photo");
    expect(
      within(section).getByLabelText("Directive for a lesson"),
    ).toHaveValue(
      ':::figure{src=media/team-photo.webp alt="" provenance=invented}\n:::\n',
    );
    expect(screen.queryByRole("textbox", { name: /^Content of/ })).toBeNull();
    expect(
      requestsTo(requests, "GET", `/api/admin/media/${PHOTO.id}`),
    ).toHaveLength(1);

    await expectNoAxeViolations(container);
  });

  test("a converted video shows its progress and follows the conversion", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    let converted = false;
    const { user, requests } = renderPage({
      [`GET /api/admin/media/${CLIP.id}`]: () =>
        ok(converted ? READY_CLIP : CLIP),
    });
    const reads = () =>
      requestsTo(requests, "GET", `/api/admin/media/${CLIP.id}`).length;
    const nav = await findTree();
    // The download follows the conversion through the draft and reads no
    // asset on its own.
    await advance(50);
    expect(reads()).toBe(0);

    await user.click(
      within(nav).getByRole("button", {
        name: "assistant-demo.webm, media/videos/, Video",
      }),
    );
    const bar = await screen.findByRole("progressbar", {
      name: "Conversion of media/videos/assistant-demo.webm",
    });
    expect(bar).toHaveAttribute("value", "40");
    expect(
      screen.getByText("The preview appears when the file is ready."),
    ).toBeInTheDocument();
    // The preview reads the asset as it opens and then every two seconds.
    await waitFor(() => expect(reads()).toBe(1));
    await advance(2000);
    expect(reads()).toBe(2);

    converted = true;
    await advance(2000);
    await waitFor(() =>
      expect(screen.getByLabelText("Preview of Assistant demo").tagName).toBe(
        "VIDEO",
      ),
    );
    expect(screen.getByLabelText("Directive for a lesson")).toHaveValue(
      ':::video{src=media/videos/assistant-demo.webm title="" provenance=invented}\n:::\n',
    );
    expect(reads()).toBe(3);
    await advance(6000);
    expect(reads()).toBe(3);
  });

  test("opening a file leaves the preview", async () => {
    const { user } = renderPage();
    const nav = await findTree();
    await user.click(
      within(nav).getByRole("button", {
        name: "team-photo.webp, media/, Image",
      }),
    );
    await screen.findByRole("heading", {
      name: "Media file media/team-photo.webp",
    });

    await user.click(
      within(nav).getByRole("button", { name: "intro-en.vtt, media/" }),
    );

    await screen.findByRole("textbox", {
      name: "Content of media/intro-en.vtt",
    });
    expect(
      screen.queryByRole("heading", { name: /^Media file/ }),
    ).not.toBeInTheDocument();
  });
});

describe("the media routes", () => {
  test("Rename sends PATCH with the path and the lock_version", async () => {
    const renamed: DraftMediaEntry = {
      ...PHOTO_ENTRY,
      path: "media/figures/team.webp",
    };
    const page = renderPage({
      [`PATCH ${BASE}/media/${PHOTO_ENTRY.id}`]: ok(
        draftOf(4, [renamed, CLIP_ENTRY]),
      ),
    });
    const { user, requests } = page;

    await openMenu(page, PHOTO_ENTRY.path, "Rename");
    const dialog = await screen.findByRole("dialog", {
      name: "Rename media/team-photo.webp",
    });
    const field = within(dialog).getByRole("textbox", { name: "New path" });
    expect(field).toHaveValue("media/team-photo.webp");

    await user.clear(field);
    await user.type(field, "media/figures/team.png");
    await user.click(within(dialog).getByRole("button", { name: "Rename" }));
    expect(
      await within(dialog).findByText(/ending in \.webp\./),
    ).toBeInTheDocument();
    expect(
      requestsTo(requests, "PATCH", `${BASE}/media/${PHOTO_ENTRY.id}`),
    ).toHaveLength(0);

    await user.clear(field);
    await user.type(field, "media/figures/team.webp");
    await user.click(within(dialog).getByRole("button", { name: "Rename" }));

    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
    expect(
      requestsTo(requests, "PATCH", `${BASE}/media/${PHOTO_ENTRY.id}`).map(
        (request) => request.body,
      ),
    ).toEqual([{ path: "media/figures/team.webp", lock_version: 3 }]);
    expect(
      within(await findTree()).getByRole("button", {
        name: "team.webp, media/figures/, Image",
      }),
    ).toBeInTheDocument();
    expect(status()).toContain(
      "Renamed media/team-photo.webp to media/figures/team.webp",
    );
  });

  test("Delete sends DELETE with the lock_version and leaves the asset in the library", async () => {
    const urls = recordRequestUrls();
    const page = renderPage({
      [`DELETE ${BASE}/media/${PHOTO_ENTRY.id}`]: ok(draftOf(4, [CLIP_ENTRY])),
    });
    const { user, requests } = page;
    const nav = await findTree();
    await user.click(
      within(nav).getByRole("button", {
        name: "team-photo.webp, media/, Image",
      }),
    );
    await screen.findByRole("heading", {
      name: "Media file media/team-photo.webp",
    });

    await openMenu(page, PHOTO_ENTRY.path, "Delete");
    const dialog = await screen.findByRole("dialog", {
      name: "Remove media/team-photo.webp from the draft?",
    });
    expect(dialog).toHaveTextContent("The file stays in the media library.");
    await user.click(within(dialog).getByRole("button", { name: "Remove" }));

    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
    expect(
      requestsTo(requests, "DELETE", `${BASE}/media/${PHOTO_ENTRY.id}`),
    ).toHaveLength(1);
    expect(
      urls
        .map((url) => new URL(url))
        .filter((url) => url.pathname === `${BASE}/media/${PHOTO_ENTRY.id}`)
        .map((url) => url.search),
    ).toEqual(["?lock_version=3"]);
    expect(
      within(nav).queryByRole("button", { name: /^team-photo\.webp/ }),
    ).toBeNull();
    expect(
      screen.queryByRole("heading", { name: /^Media file/ }),
    ).not.toBeInTheDocument();
    expect(status()).toContain("Removed media media/team-photo.webp");
  });

  test("a 409 stale_draft opens the conflict dialog", async () => {
    const page = renderPage({
      [`DELETE ${BASE}/media/${PHOTO_ENTRY.id}`]: {
        status: 409,
        body: { error: "stale_draft", lock_version: 5 },
      },
    });

    await openMenu(page, PHOTO_ENTRY.path, "Delete");
    const dialog = await screen.findByRole("dialog", {
      name: "Remove media/team-photo.webp from the draft?",
    });
    await page.user.click(
      within(dialog).getByRole("button", { name: "Remove" }),
    );

    expect(
      await screen.findByRole("dialog", { name: "The draft changed" }),
    ).toBeInTheDocument();
  });
});

describe("Add media", () => {
  const LIBRARY = "/api/admin/media";
  const ATTACH = `${BASE}/media`;
  const LOGO_ENTRY: DraftMediaEntry = {
    id: uuid(903),
    path: "media/logo.svg",
    asset: LOGO,
  };

  async function openDialog(page: RenderWithProvidersResult) {
    await page.user.click(
      within(await findTree()).getByRole("button", { name: "Add media" }),
    );
    return screen.findByRole("dialog", { name: "Add media" });
  }

  test("attaches an image, SVG or video asset of the library at its default path", async () => {
    const urls = recordRequestUrls();
    const page = renderPage({
      [`GET ${LIBRARY}`]: ok({
        items: [LOGO, CAPTIONS, BROKEN, PHOTO],
        next: null,
      }),
      [`POST ${ATTACH}`]: ok(
        draftOf(4, [LOGO_ENTRY, PHOTO_ENTRY, CLIP_ENTRY]),
        201,
      ),
      [`GET ${LIBRARY}/${LOGO.id}`]: ok(LOGO),
    });
    const { user, requests } = page;

    const dialog = await openDialog(page);
    await user.click(
      await within(dialog).findByRole("button", {
        name: /^File of the library/,
      }),
    );
    const options = await screen.findAllByRole("option");
    expect(options.map((option) => option.textContent)).toEqual([
      "LogoSVG graphic, Ready",
      "Team photoImage, Ready",
    ]);
    await user.click(options[0]);
    expect(within(dialog).getByLabelText("Path in the draft")).toHaveValue(
      "media/logo.svg",
    );
    await expectNoAxeViolations(dialog);

    await user.click(within(dialog).getByRole("button", { name: "Add media" }));

    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
    expect(
      requestsTo(requests, "POST", ATTACH).map((request) => request.body),
    ).toEqual([
      { media_asset_id: LOGO.id, path: "media/logo.svg", lock_version: 3 },
    ]);
    expect(
      urls
        .map((url) => new URL(url))
        .filter((url) => url.pathname === LIBRARY)
        .map((url) => Object.fromEntries(url.searchParams))[0],
    ).toEqual({ limit: "100" });
    expect(status()).toContain("Added media media/logo.svg");
    expect(
      await screen.findByRole("heading", { name: "Media file media/logo.svg" }),
    ).toBeInTheDocument();
  });

  test("uploads a new file and attaches it", async () => {
    const fresh = asset(6, {
      kind: "video",
      status: "queued",
      progress: 0,
      title: "New clip",
      ext: null,
      url: null,
    });
    const { requests: xhr } = installFakeXhr([{ status: 201, body: fresh }]);
    const page = renderPage({
      [`GET ${LIBRARY}`]: ok({ items: [], next: null }),
      [`POST ${ATTACH}`]: ok(
        draftOf(4, [
          PHOTO_ENTRY,
          CLIP_ENTRY,
          { id: uuid(904), path: "media/new-clip.webm", asset: fresh },
        ]),
        201,
      ),
    });
    const { user, requests } = page;

    const dialog = await openDialog(page);
    expect(
      await within(dialog).findByText(
        "The library holds no image, SVG graphic or video yet. Upload a file below.",
      ),
    ).toBeInTheDocument();
    await user.upload(
      within(dialog).getByLabelText("Choose a file"),
      new File([new Uint8Array(5_000)], "new-clip.mp4", { type: "video/mp4" }),
    );

    await waitFor(() =>
      expect(within(dialog).getByLabelText("Path in the draft")).toHaveValue(
        "media/new-clip.webm",
      ),
    );
    expect(
      within(dialog).getByRole("button", { name: /^File of the library/ }),
    ).toHaveTextContent("New clip");
    await user.click(within(dialog).getByRole("button", { name: "Add media" }));

    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
    expect(xhr).toHaveLength(1);
    expect(
      requestsTo(requests, "POST", ATTACH).map((request) => request.body),
    ).toEqual([
      {
        media_asset_id: fresh.id,
        path: "media/new-clip.webm",
        lock_version: 3,
      },
    ]);
  });

  test("names a missing choice, a wrong extension and the media limit", async () => {
    const page = renderPage({
      [`GET ${LIBRARY}`]: ok({ items: [LOGO], next: null }),
      [`POST ${ATTACH}`]: { status: 409, body: { error: "media_limit" } },
    });
    const { user, requests } = page;

    const dialog = await openDialog(page);
    await within(dialog).findByRole("button", { name: /^File of the library/ });
    await user.click(within(dialog).getByRole("button", { name: "Add media" }));
    expect(
      within(dialog).getByText("Choose a file of the library, or upload one."),
    ).toBeInTheDocument();

    await user.click(
      within(dialog).getByRole("button", { name: /^File of the library/ }),
    );
    await user.click(await screen.findByRole("option", { name: /^Logo/ }));
    const path = within(dialog).getByLabelText("Path in the draft");
    await user.clear(path);
    await user.type(path, "media/logo.webp");
    await user.click(within(dialog).getByRole("button", { name: "Add media" }));
    expect(path).toHaveAccessibleDescription(/ending in \.svg\./);
    expect(requestsTo(requests, "POST", ATTACH)).toHaveLength(0);

    await user.clear(path);
    await user.type(path, "media/brand/logo.svg");
    await user.click(within(dialog).getByRole("button", { name: "Add media" }));
    expect(
      await within(dialog).findByText(
        "The draft holds the largest number of media entries. Remove a media entry first.",
      ),
    ).toBeInTheDocument();
  });
});

describe("Add file", () => {
  test("creates a captions file media/<key>.vtt with the header WEBVTT and an empty line", async () => {
    const created = { id: uuid(810), path: "media/intro-de.vtt" };
    const page = renderPage({
      [`POST ${BASE}/files`]: ok(
        draftOf(4, undefined, [...FILES, created]),
        201,
      ),
      [`GET ${BASE}/files/${created.id}`]: ok({
        ...created,
        content: "WEBVTT\n\n",
        bytes: 8,
        updated_at: TIME,
        lock_version: 4,
      }),
    });
    const { user, requests } = page;

    await user.click(
      within(await findTree()).getByRole("button", { name: "Add file" }),
    );
    const dialog = await screen.findByRole("dialog", { name: "Add a file" });
    await user.click(
      within(dialog).getByRole("radio", {
        name: "Captions file (WebVTT) below media/",
      }),
    );
    await user.type(within(dialog).getByLabelText("Captions key"), "intro-de");
    expect(within(dialog).getByLabelText("Path")).toHaveValue(
      "media/intro-de.vtt",
    );
    await expectNoAxeViolations(dialog);
    await user.click(within(dialog).getByRole("button", { name: "Add file" }));

    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
    expect(
      requestsTo(requests, "POST", `${BASE}/files`).map(
        (request) => request.body,
      ),
    ).toEqual([
      { path: "media/intro-de.vtt", content: "WEBVTT\n\n", lock_version: 3 },
    ]);
    expect(
      await screen.findByRole("textbox", {
        name: "Content of media/intro-de.vtt",
      }),
    ).toHaveAttribute("data-language", "text");
  });
});

/**
 * The download answers 409 `media_not_ready` while an entry is not `ready`,
 * which a plain link cannot show. "Download as zip" therefore stays
 * disabled with a sentence while an entry is converted or failed, and the
 * page reads the draft every two seconds, one request for every entry,
 * until it can offer the link. The read takes only the assets of the
 * entries, so the editor keeps its text and the save its `lock_version`.
 */
describe("the download", () => {
  const DOWNLOAD = "Download as zip";
  const PENDING =
    "Media files are still converted. The download becomes possible when every media file is ready.";
  const FAILED =
    "A media file of the draft failed. Remove its entry or replace it with a ready file, then download the draft.";
  const BROKEN_ENTRY: DraftMediaEntry = {
    id: uuid(904),
    path: "media/broken.svg",
    asset: BROKEN,
  };
  const READY_CLIP_ENTRY: DraftMediaEntry = {
    ...CLIP_ENTRY,
    asset: READY_CLIP,
  };

  const assetReads = (requests: RenderWithProvidersResult["requests"]) =>
    requests.filter((request) => request.path.startsWith("/api/admin/media"));

  test("waits with a sentence while an entry is converted and offers the link once every entry is ready", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    let converted = false;
    const { container, requests } = renderPage({
      [`GET ${BASE}`]: () =>
        ok(
          draftOf(3, [PHOTO_ENTRY, converted ? READY_CLIP_ENTRY : CLIP_ENTRY]),
        ),
    });
    const draftReads = () => requestsTo(requests, "GET", BASE).length;

    const button = await screen.findByRole("button", { name: DOWNLOAD });
    expect(button).toBeDisabled();
    expect(button).toHaveAccessibleDescription(PENDING);
    expect(screen.queryByRole("link", { name: DOWNLOAD })).toBeNull();
    // The loaded draft counts as the first read.
    expect(draftReads()).toBe(1);
    await expectNoAxeViolations(container);

    // One read of the draft every two seconds, and no read of an asset.
    let before = draftReads();
    await advance(2000);
    expect(draftReads()).toBe(before + 1);
    expect(screen.getByRole("button", { name: DOWNLOAD })).toBeDisabled();
    before = draftReads();
    await advance(2000);
    expect(draftReads()).toBe(before + 1);

    converted = true;
    before = draftReads();
    await advance(2000);

    const link = await screen.findByRole("link", { name: DOWNLOAD });
    expect(link).toHaveAttribute("href", `${BASE}/download`);
    expect(link).toHaveAttribute("download");
    expect(screen.queryByText(PENDING)).toBeNull();
    expect(draftReads()).toBe(before + 1);
    // The reads end with the conversion.
    await advance(6000);
    expect(draftReads()).toBe(before + 1);
    expect(assetReads(requests)).toEqual([]);
  });

  test("a read of the draft keeps the unsaved text, the focus and the lock_version of the page", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    // Another session saved a change meanwhile, so the read carries a newer
    // lock_version and no longer names the captions file.
    const { user, requests } = renderPage({
      [`GET ${BASE}`]: [
        ok(draftOf()),
        ok(draftOf(7, [PHOTO_ENTRY, READY_CLIP_ENTRY], [FILES[0], FILES[2]])),
      ],
      [`PUT ${BASE}/files/${CAPTIONS_FILE.id}`]: ok(
        draftOf(4, [PHOTO_ENTRY, READY_CLIP_ENTRY]),
      ),
    });
    const nav = await findTree();
    await user.click(
      within(nav).getByRole("button", { name: "intro-en.vtt, media/" }),
    );
    const editor = await screen.findByRole("textbox", {
      name: "Content of media/intro-en.vtt",
    });
    await user.type(editor, "More");
    expect(editor).toHaveFocus();

    await advance(2000);

    const link = await screen.findByRole("link", { name: DOWNLOAD });
    expect(link).toHaveAttribute("href", `${BASE}/download`);
    expect(requestsTo(requests, "GET", BASE)).toHaveLength(2);
    expect(editor).toHaveFocus();
    expect(editor).toHaveValue(`${captionsAnswer.content}More`);
    expect(
      within(nav).getByRole("button", {
        name: "intro-en.vtt, media/, unsaved",
      }),
    ).toHaveAttribute("aria-current", "true");

    await user.click(screen.getByRole("button", { name: "Save" }));
    await waitFor(() =>
      expect(
        requestsTo(requests, "PUT", `${BASE}/files/${CAPTIONS_FILE.id}`),
      ).toHaveLength(1),
    );
    expect(
      requestsTo(requests, "PUT", `${BASE}/files/${CAPTIONS_FILE.id}`)[0].body,
    ).toEqual({ content: `${captionsAnswer.content}More`, lock_version: 3 });
    // The draft holds no entry in progress any more, so the reads end.
    await advance(6000);
    expect(requestsTo(requests, "GET", BASE)).toHaveLength(2);
    expect(assetReads(requests)).toEqual([]);
  });

  test("a read that started before a change of the draft leaves the newer assets of the change", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    let release: (answer: StubAnswer) => void = () => undefined;
    const held = new Promise<StubAnswer>((resolve) => {
      release = resolve;
    });
    let reads = 0;
    const renamed: DraftMediaEntry = {
      ...PHOTO_ENTRY,
      path: "media/figures/team.webp",
    };
    const page = renderPage({
      // The second read answers after the rename, with the state of the
      // video before its conversion ended.
      [`GET ${BASE}`]: () => {
        reads += 1;
        return reads === 1 ? ok(draftOf()) : held;
      },
      [`PATCH ${BASE}/media/${PHOTO_ENTRY.id}`]: ok(
        draftOf(4, [renamed, READY_CLIP_ENTRY]),
      ),
    });
    const { user, requests } = page;
    await findTree();
    await advance(2000);
    expect(requestsTo(requests, "GET", BASE)).toHaveLength(2);

    await openMenu(page, PHOTO_ENTRY.path, "Rename");
    const dialog = await screen.findByRole("dialog", {
      name: "Rename media/team-photo.webp",
    });
    const field = within(dialog).getByRole("textbox", { name: "New path" });
    await user.clear(field);
    await user.type(field, renamed.path);
    await user.click(within(dialog).getByRole("button", { name: "Rename" }));
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
    expect(
      await screen.findByRole("link", { name: DOWNLOAD }),
    ).toBeInTheDocument();

    release(ok(draftOf(3, [PHOTO_ENTRY, CLIP_ENTRY])));
    await advance(6000);

    expect(screen.getByRole("link", { name: DOWNLOAD })).toBeInTheDocument();
    expect(requestsTo(requests, "GET", BASE)).toHaveLength(2);
  });

  test("a failed entry holds the download back with its own sentence", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    const { container, requests } = renderPage({
      [`GET ${BASE}`]: ok(draftOf(3, [PHOTO_ENTRY, BROKEN_ENTRY])),
    });

    const button = await screen.findByRole("button", { name: DOWNLOAD });
    expect(button).toBeDisabled();
    expect(button).toHaveAccessibleDescription(FAILED);
    await expectNoAxeViolations(container);
    // A failed entry is not converted, so the page reads nothing more.
    await advance(6000);
    expect(requestsTo(requests, "GET", BASE)).toHaveLength(1);
    expect(assetReads(requests)).toEqual([]);
  });

  test("a draft whose entries are ready offers the link and reads no asset", async () => {
    const { requests } = renderPage({
      [`GET ${BASE}`]: ok(draftOf(3, [PHOTO_ENTRY])),
    });

    const link = await screen.findByRole("link", { name: DOWNLOAD });
    expect(link).toHaveAttribute("href", `${BASE}/download`);
    expect(screen.queryByRole("button", { name: DOWNLOAD })).toBeNull();
    expect(requestsTo(requests, "GET", BASE)).toHaveLength(1);
    expect(assetReads(requests)).toEqual([]);
  });
});
