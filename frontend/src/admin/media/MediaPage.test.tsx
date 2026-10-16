import {
  act,
  fireEvent,
  screen,
  waitFor,
  within,
} from "@testing-library/react";
import { afterEach, describe, expect, test, vi } from "vitest";
import type { MediaAsset, MediaUses } from "../../api/admin/media";
import type { PackDraft } from "../../api/admin/workbench";
import { setStepUpHandler } from "../../api/stepUp";
import { expectNoAxeViolations } from "../../test/axe";
import { installFakeXhr } from "../../test/fakeXhr";
import {
  renderWithProviders,
  requestsTo,
  type StubResponses,
} from "../../test/render";
import { sessionPayload, signedInPayload } from "../../test/session";
import { MediaPage } from "./MediaPage";

/**
 * Task 0018, step 19: the media library page `/admin/media` with its
 * upload zone, filters, cards and polling, and the detail dialog with
 * preview, facts, title, uses, "Copy directive", "Add to draft" and the
 * deletion. The answers of the media routes are written by hand; the
 * upload runs through a fake `XMLHttpRequest`.
 */
const ROUTE = "/admin/media";
const LIST = "/api/admin/media";
const FUTURE = "2999-01-01T00:00:00Z";
const DRAFTS = "/api/admin/pack-drafts";

const uuid = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const sha = (n: number) => n.toString(16).padStart(64, "0");

const author = (recentAuthUntil: string | null = FUTURE) =>
  signedInPayload("mfa", {
    roles: ["learner", "author"],
    session: { recent_auth_until: recentAuthUntil },
  });

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
    inserted_at: "2026-10-15T09:00:00Z",
    updated_at: "2026-10-15T09:00:00Z",
    ...overrides,
  };
}

const PHOTO = asset(1, {
  title: "Team photo",
  source_name: "team-photo.jpg",
  bytes: 245_760,
  width: 1280,
  height: 853,
});
const DIAGRAM = asset(2, {
  kind: "svg",
  status: "failed",
  failure: "invalid_svg",
  failure_detail: "doctype",
  progress: 0,
  title: "Release checks",
  source_name: "release-checks.svg",
  ext: null,
  bytes: null,
  width: null,
  height: null,
  url: null,
});
const CLIP = asset(3, {
  kind: "video",
  status: "processing",
  progress: 40,
  title: "Assistant demo",
  source_name: "assistant-demo.mp4",
  ext: null,
  bytes: null,
  width: null,
  height: null,
  url: null,
});
const READY_CLIP = asset(3, {
  ...CLIP,
  status: "ready",
  progress: 100,
  ext: "webm",
  bytes: 1_048_576,
  width: 640,
  height: 360,
  duration_ms: 8_000,
  has_audio: true,
  url: `/media/${sha(3)}.webm`,
  poster_url: `/media/${sha(13)}.webp`,
});
const CAPTIONS = asset(4, {
  kind: "captions",
  title: "Intro captions en",
  source_name: "intro-captions-en.vtt",
  ext: "vtt",
  bytes: 1_200,
  width: null,
  height: null,
  duration_ms: 8_000,
  url: `/media/${sha(4)}.vtt`,
});

const NO_USES: MediaUses = { programs: [], drafts: [], imports: [] };

const USES: MediaUses = {
  programs: [{ slug: "demo", title: "Demo program" }],
  drafts: [{ id: uuid(70), title: "Demo pack", path: "media/team-photo.webp" }],
  imports: [
    { id: uuid(50), pack_key: "demo", inserted_at: "2026-10-14T08:00:00Z" },
  ],
};

const DRAFT: PackDraft = {
  id: uuid(70),
  title: "Demo pack",
  pack_key: "demo",
  lock_version: 4,
  inserted_at: "2026-10-13T09:00:00Z",
  updated_at: "2026-10-13T09:00:00Z",
  usage: { files: 12, bytes: 40_960 },
  limits: { files: 2_000, file_bytes: 1_048_576, draft_bytes: 104_857_600 },
};

const list = (items: MediaAsset[], next: string | null = null) => ({
  status: 200,
  body: { items, next },
});

function renderPage(responses: StubResponses = {}, session = author()) {
  return renderWithProviders(<MediaPage />, {
    route: ROUTE,
    session,
    responses: {
      [`GET ${LIST}`]: list([PHOTO, DIAGRAM, CLIP, CAPTIONS]),
      ...responses,
    },
  });
}

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

/** The queries of the list requests, as objects. */
const listQueries = (urls: string[]) =>
  urls
    .map((url) => new URL(url))
    .filter((url) => url.pathname === LIST)
    .map((url) => Object.fromEntries(url.searchParams));

/** Replaces the clipboard stub of user-event; call it after the render. */
function mockClipboard() {
  const writeText = vi.fn(async (_text: string) => {});
  Object.defineProperty(navigator, "clipboard", {
    configurable: true,
    value: { writeText },
  });
  return writeText;
}

/** The card of the asset titled `title`. */
async function card(title: string) {
  const button = await screen.findByRole("button", { name: title });
  const item = button.closest("li");
  if (item === null) throw new Error(`no card for ${title}`);
  return item;
}

const advance = (ms: number) => act(() => vi.advanceTimersByTimeAsync(ms));

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
  setStepUpHandler(null);
  Reflect.deleteProperty(navigator, "clipboard");
});

describe("the cards", () => {
  test("show preview, title, kind, size and state with progress and failure text", async () => {
    const { container } = renderPage();

    const photo = await card("Team photo");
    expect(photo).toHaveTextContent("KindImage");
    expect(photo).toHaveTextContent("Size240 kB");
    expect(photo).toHaveTextContent("StateReady");
    const image = photo.querySelector("img");
    expect(image).toHaveAttribute("src", PHOTO.url);
    expect(image).toHaveAttribute("alt", "");

    const diagram = await card("Release checks");
    expect(diagram).toHaveTextContent("KindSVG graphic");
    expect(diagram).toHaveTextContent("Size-");
    expect(diagram).toHaveTextContent(
      "Failed" +
        "The SVG file could not be rebuilt. Reason: The file holds a DOCTYPE declaration.",
    );
    expect(diagram.querySelector("img")).toBeNull();

    const clip = await card("Assistant demo");
    expect(clip).toHaveTextContent("Processing, 40 %");
    const bar = within(clip).getByRole("progressbar", {
      name: "Conversion of Assistant demo",
    });
    expect(bar).toHaveAttribute("value", "40");

    const captions = await card("Intro captions en");
    expect(captions).toHaveTextContent("KindCaptions");
    expect(captions.querySelector("img")).toBeNull();

    await expectNoAxeViolations(container);
  });

  test("render titles as text", async () => {
    const markup = asset(9, { title: '<img src=x onerror="alert(1)">' });
    renderPage({ [`GET ${LIST}`]: list([markup]) });

    const button = await screen.findByRole("button", {
      name: '<img src=x onerror="alert(1)">',
    });
    expect(button.querySelector("img")).toBeNull();
  });

  test("states an empty library and a filter without match", async () => {
    const { user } = renderPage({ [`GET ${LIST}`]: list([]) });

    expect(
      await screen.findByText("The library holds no file yet."),
    ).toBeInTheDocument();
    await user.click(
      screen.getByRole("checkbox", { name: "Unused files only" }),
    );
    expect(
      await screen.findByText("No file matches the filters."),
    ).toBeInTheDocument();
  });

  test("show more loads the next page through the cursor", async () => {
    const urls = recordRequestUrls();
    const { user } = renderPage({
      [`GET ${LIST}`]: [list([PHOTO], "cursor-1"), list([CAPTIONS])],
    });

    await card("Team photo");
    await user.click(screen.getByRole("button", { name: "Show more files" }));

    await card("Intro captions en");
    expect(screen.getByRole("button", { name: "Team photo" })).toBeVisible();
    expect(
      screen.queryByRole("button", { name: "Show more files" }),
    ).not.toBeInTheDocument();
    expect(listQueries(urls)).toEqual([
      { limit: "50" },
      { limit: "50", after: "cursor-1" },
    ]);
  });
});

describe("the polling", () => {
  test("reads the list every two seconds while an asset is processing", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    const { requests } = renderPage({
      [`GET ${LIST}`]: [list([CLIP]), list([READY_CLIP])],
    });

    const clip = await card("Assistant demo");
    expect(clip).toHaveTextContent("Processing, 40 %");
    expect(requestsTo(requests, "GET", LIST)).toHaveLength(1);

    await advance(2000);
    await waitFor(() => expect(clip).toHaveTextContent("StateReady"));
    expect(requestsTo(requests, "GET", LIST)).toHaveLength(2);
    expect(clip.querySelector("img")).toHaveAttribute(
      "src",
      READY_CLIP.poster_url,
    );

    // No asset is converted any more, so the list is not read again.
    await advance(6000);
    expect(requestsTo(requests, "GET", LIST)).toHaveLength(2);
  });
});

describe("the filters", () => {
  test("send kind, state, unused and the search, and clear again", async () => {
    const urls = recordRequestUrls();
    const { user } = renderPage();
    await card("Team photo");
    const filters = screen.getByRole("region", { name: "Filters" });

    await user.selectOptions(within(filters).getByLabelText("Kind"), "video");
    await user.selectOptions(within(filters).getByLabelText("State"), "failed");
    await user.click(
      within(filters).getByRole("checkbox", { name: "Unused files only" }),
    );
    await user.type(
      within(filters).getByLabelText("Search by title"),
      " photo ",
    );
    await user.click(within(filters).getByRole("button", { name: "Search" }));

    await waitFor(() =>
      expect(listQueries(urls).at(-1)).toEqual({
        kind: "video",
        status: "failed",
        unused: "true",
        q: "photo",
        limit: "50",
      }),
    );

    await user.click(
      within(filters).getByRole("button", { name: "Clear filters" }),
    );
    await waitFor(() =>
      expect(listQueries(urls).at(-1)).toEqual({ limit: "50" }),
    );
    expect(within(filters).getByLabelText("Search by title")).toHaveValue("");
  });
});

describe("the upload", () => {
  const png = () =>
    new File([new Uint8Array(4_000)], "team-photo.png", { type: "image/png" });
  const mp4 = () =>
    new File([new Uint8Array(8_000)], "clip.mp4", { type: "video/mp4" });

  test("uploads several files one after the other with a progress bar each", async () => {
    const { requests: xhr } = installFakeXhr([
      {
        status: 201,
        body: asset(20, { status: "queued", title: "team-photo" }),
      },
      {
        status: 422,
        body: {
          error: "validation_failed",
          fields: { file: ["extension_mismatch"] },
        },
      },
    ]);
    const { user, requests, container } = renderPage();
    await card("Team photo");

    await user.upload(screen.getByLabelText("Choose files"), [png(), mp4()]);

    const uploads = screen.getByRole("status", { name: "Uploads" });
    await waitFor(() =>
      expect(within(uploads).getAllByRole("listitem")).toHaveLength(2),
    );
    const [first, second] = within(uploads).getAllByRole("listitem");
    await waitFor(() =>
      expect(first).toHaveTextContent(
        "Uploaded. The library converts the file now.",
      ),
    );
    await waitFor(() =>
      expect(second).toHaveTextContent(
        "The extension of the file name does not match its content.",
      ),
    );
    expect(first).toHaveTextContent("team-photo.png");
    expect(
      within(first).getByRole("progressbar", {
        name: "Upload of team-photo.png",
      }),
    ).toHaveAttribute("value", "4000");
    expect(
      within(second).getByRole("progressbar", { name: "Upload of clip.mp4" }),
    ).toBeInTheDocument();
    expect(xhr.map((request) => request.headers["x-csrf-token"])).toEqual([
      "csrf-1",
      "csrf-1",
    ]);
    // The finished upload marks the list stale, which reads it again.
    await waitFor(() =>
      expect(requestsTo(requests, "GET", LIST).length).toBeGreaterThan(1),
    );
    await expectNoAxeViolations(container);
  });

  test("an existing file names its asset", async () => {
    installFakeXhr([{ status: 200, body: PHOTO }]);
    const { user } = renderPage();
    await card("Team photo");

    await user.upload(screen.getByLabelText("Choose files"), png());

    expect(
      await screen.findByText(
        "The library holds this file already as Team photo.",
      ),
    ).toBeInTheDocument();
  });

  test.each([
    [
      413,
      { error: "request_too_large" },
      "The file is larger than the largest upload of the installation.",
    ],
    [409, { error: "storage_full" }, "The media store is full."],
  ])("a %i answer names its reason", async (status, body, text) => {
    installFakeXhr([{ status, body }]);
    const { user } = renderPage();
    await card("Team photo");

    await user.upload(screen.getByLabelText("Choose files"), png());

    expect(await screen.findByText(new RegExp(text))).toBeInTheDocument();
  });

  test("a closed step-up dialog sends none of the files", async () => {
    const { requests: xhr } = installFakeXhr([{ status: 201, body: PHOTO }]);
    const { user } = renderPage({}, author(null));
    await card("Team photo");
    const handler = vi.fn(async () => false);
    setStepUpHandler(handler);

    await user.upload(screen.getByLabelText("Choose files"), [png(), mp4()]);

    const uploads = screen.getByRole("status", { name: "Uploads" });
    await waitFor(() =>
      expect(
        within(uploads)
          .getAllByRole("listitem")
          .map((item) => item.dataset.state),
      ).toEqual(["failed", "failed"]),
    );
    const [first, second] = within(uploads).getAllByRole("listitem");
    expect(first).toHaveTextContent(
      "The change was not made, because the confirmation with a second factor was cancelled.",
    );
    expect(second).toHaveTextContent(
      "Not sent, because the confirmation with a second factor was cancelled.",
    );
    expect(handler).toHaveBeenCalledTimes(1);
    expect(xhr).toHaveLength(0);
  });

  test.each([
    [
      "an ended session",
      { status: 401, body: { error: "unauthenticated" } },
      // The session read after the 401 is signed out.
      { status: 200, body: sessionPayload() },
      "Not sent, because the session has ended. Choose the file again after the sign-in.",
    ],
    [
      "an account without a second factor",
      { status: 403, body: { error: "enrollment_required" } },
      { status: 200, body: author() },
      "Not sent, because the account has no second factor yet. Choose the file again after its setup.",
    ],
  ])(
    "after %s, the waiting files are not sent",
    async (_case, answer, session, text) => {
      const { requests: xhr } = installFakeXhr([
        answer,
        { status: 201, body: PHOTO },
      ]);
      const { user } = renderPage({ "GET /api/session": session });
      await card("Team photo");
      const handler = vi.fn(async () => false);
      setStepUpHandler(handler);

      await user.upload(screen.getByLabelText("Choose files"), [png(), mp4()]);

      const uploads = screen.getByRole("status", { name: "Uploads" });
      await waitFor(() =>
        expect(
          within(uploads)
            .getAllByRole("listitem")
            .map((item) => item.dataset.state),
        ).toEqual(["failed", "failed"]),
      );
      const [, second] = within(uploads).getAllByRole("listitem");
      expect(second).toHaveTextContent(text);
      // The next file asks for no step-up over the sign-in or the
      // enrollment.
      expect(handler).not.toHaveBeenCalled();
      expect(xhr).toHaveLength(1);
    },
  );

  test("a zone that leaves the page sends none of the waiting files", async () => {
    const { requests: xhr } = installFakeXhr([{ status: 201, body: PHOTO }]);
    const { unmount } = renderPage();
    await card("Team photo");

    fireEvent.change(screen.getByLabelText("Choose files"), {
      target: { files: [png(), mp4()] },
    });
    expect(xhr).toHaveLength(1);
    unmount();
    // The first upload ends after the page has gone.
    await act(() => new Promise((resolve) => setTimeout(resolve, 20)));

    expect(xhr).toHaveLength(1);
  });
});

describe("the detail dialog", () => {
  const PHOTO_PATH = `${LIST}/${PHOTO.id}`;

  const openPhoto = async (responses: StubResponses = {}) => {
    const result = renderPage({
      [`GET ${PHOTO_PATH}`]: { status: 200, body: { ...PHOTO, uses: USES } },
      [`GET ${DRAFTS}`]: { status: 200, body: { data: [DRAFT] } },
      ...responses,
    });
    await result.user.click(
      await screen.findByRole("button", { name: "Team photo" }),
    );
    const dialog = await screen.findByRole("dialog", { name: "Team photo" });
    await within(dialog).findByRole("link", { name: "Demo program" });
    return { ...result, dialog };
  };

  test("shows preview, facts, uses with links and the directive to copy", async () => {
    const { user, dialog } = await openPhoto();
    const writeText = mockClipboard();

    const preview = within(dialog).getByRole("img", {
      name: "Preview of Team photo",
    });
    expect(preview).toHaveAttribute("src", PHOTO.url);
    expect(preview).toHaveAttribute("width", "1280");
    expect(dialog).toHaveTextContent("Dimensions1280 × 853 px");
    expect(dialog).toHaveTextContent("Original fileteam-photo.jpg");
    expect(dialog).toHaveTextContent("OriginUpload");
    expect(
      within(dialog).getByRole("link", { name: "Demo program" }),
    ).toHaveAttribute("href", "/programs/demo");
    expect(
      within(dialog).getByRole("link", { name: "Demo pack" }),
    ).toHaveAttribute("href", `/admin/workbench/${uuid(70)}`);
    expect(dialog).toHaveTextContent("media/team-photo.webp");
    expect(within(dialog).getByRole("link", { name: "demo" })).toHaveAttribute(
      "href",
      `/admin/packs/${uuid(50)}`,
    );

    const directive = within(dialog).getByLabelText("Directive for a lesson");
    expect(directive).toHaveValue(
      ':::figure{src=media/team-photo.webp alt="" provenance=invented}\n:::\n',
    );
    await user.click(
      within(dialog).getByRole("button", { name: "Copy directive" }),
    );
    expect(writeText).toHaveBeenCalledWith(
      ':::figure{src=media/team-photo.webp alt="" provenance=invented}\n:::\n',
    );
    expect(
      await within(dialog).findByText("Copied to the clipboard."),
    ).toBeInTheDocument();

    await expectNoAxeViolations(document.body);
  });

  test("an animated image shows its poster until the author plays it", async () => {
    const animation = asset(6, {
      title: "Typing animation",
      animated: true,
      poster_url: `/media/${sha(16)}.webp`,
    });
    const { user } = renderPage({
      [`GET ${LIST}`]: list([animation]),
      [`GET ${LIST}/${animation.id}`]: {
        status: 200,
        body: { ...animation, uses: NO_USES },
      },
      [`GET ${DRAFTS}`]: { status: 200, body: { data: [] } },
    });

    const item = await card("Typing animation");
    expect(item.querySelector("img")).toHaveAttribute(
      "src",
      animation.poster_url,
    );
    await user.click(
      within(item).getByRole("button", { name: "Typing animation" }),
    );
    const dialog = await screen.findByRole("dialog", {
      name: "Typing animation",
    });
    const preview = within(dialog).getByRole("img", {
      name: "Preview of Typing animation",
    });
    expect(preview).toHaveAttribute("src", animation.poster_url);
    expect(dialog).toHaveTextContent("AnimatedYes");

    const play = within(dialog).getByRole("button", {
      name: "Play the animation",
    });
    expect(play).toHaveAttribute("aria-pressed", "false");
    await user.click(play);
    expect(preview).toHaveAttribute("src", animation.url);
    expect(play).toHaveAttribute("aria-pressed", "true");
    await user.click(play);
    expect(preview).toHaveAttribute("src", animation.poster_url);
  });

  test("a video plays in a video element and copies a video directive", async () => {
    const { user } = renderPage({
      [`GET ${LIST}`]: list([READY_CLIP]),
      [`GET ${LIST}/${READY_CLIP.id}`]: {
        status: 200,
        body: { ...READY_CLIP, uses: NO_USES },
      },
      [`GET ${DRAFTS}`]: { status: 200, body: { data: [] } },
    });

    await user.click(
      await screen.findByRole("button", { name: "Assistant demo" }),
    );
    const dialog = await screen.findByRole("dialog", {
      name: "Assistant demo",
    });
    await within(dialog).findByText(
      "No published program, draft or validated import uses this file.",
    );

    const video = dialog.querySelector("video");
    expect(video).toHaveAttribute("controls");
    expect(video).toHaveAttribute("poster", READY_CLIP.poster_url);
    expect(video?.querySelector("source")).toHaveAttribute(
      "src",
      READY_CLIP.url,
    );
    expect(video?.querySelector("source")).toHaveAttribute(
      "type",
      "video/webm",
    );
    expect(dialog).toHaveTextContent("Length0:08");
    expect(dialog).toHaveTextContent("Audio trackYes");
    expect(within(dialog).getByLabelText("Directive for a lesson")).toHaveValue(
      ':::video{src=media/assistant-demo.webm title="" provenance=invented}\n:::\n',
    );
    expect(dialog).toHaveTextContent("The workbench holds no draft.");

    await expectNoAxeViolations(document.body);
  });

  test("saves a new title", async () => {
    const { user, dialog, requests } = await openPhoto({
      [`PATCH ${PHOTO_PATH}`]: {
        status: 200,
        body: { ...PHOTO, title: "Team photo 2026" },
      },
    });

    const field = within(dialog).getByLabelText("Title");
    await user.clear(field);
    await user.type(field, "  Team photo 2026 ");
    await user.click(
      within(dialog).getByRole("button", { name: "Save title" }),
    );

    expect(
      await within(dialog).findByText("The title is saved."),
    ).toBeInTheDocument();
    const [patch] = requestsTo(requests, "PATCH", PHOTO_PATH);
    expect(patch.body).toEqual({ title: "Team photo 2026" });
    expect(patch.headers.get("x-csrf-token")).toBe("csrf-1");
    expect(
      screen.getByRole("dialog", { name: "Team photo 2026" }),
    ).toBeInTheDocument();
  });

  test("an empty title is refused before a request", async () => {
    const { user, dialog, requests } = await openPhoto();

    await user.clear(within(dialog).getByLabelText("Title"));
    await user.click(
      within(dialog).getByRole("button", { name: "Save title" }),
    );

    expect(
      within(dialog).getByText("Enter a title of 1 to 255 characters."),
    ).toBeInTheDocument();
    expect(requestsTo(requests, "PATCH", PHOTO_PATH)).toHaveLength(0);
  });

  test("a deletion refused with 409 asset_in_use shows the uses", async () => {
    const { user, dialog } = await openPhoto({
      [`DELETE ${PHOTO_PATH}`]: {
        status: 409,
        body: { error: "asset_in_use", uses: USES },
      },
    });

    await user.click(within(dialog).getByRole("button", { name: "Delete" }));
    const confirm = await screen.findByRole("dialog", {
      name: "Delete Team photo?",
    });
    await user.click(within(confirm).getByRole("button", { name: "Delete" }));

    const alert = await within(confirm).findByText(
      "The file stays in the library, because it is in use:",
    );
    expect(alert).toBeInTheDocument();
    expect(
      within(confirm).getByRole("link", { name: "Demo program" }),
    ).toHaveAttribute("href", "/programs/demo");
    expect(
      within(confirm).getByRole("link", { name: "Demo pack" }),
    ).toBeVisible();
    await expectNoAxeViolations(document.body);
  });

  test("a deletion closes the dialog and announces it", async () => {
    const { user, dialog, requests } = await openPhoto({
      [`DELETE ${PHOTO_PATH}`]: { status: 204 },
    });

    await user.click(within(dialog).getByRole("button", { name: "Delete" }));
    const confirm = await screen.findByRole("dialog", {
      name: "Delete Team photo?",
    });
    await user.click(within(confirm).getByRole("button", { name: "Delete" }));

    expect(await screen.findByText("Deleted Team photo.")).toBeInTheDocument();
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
    expect(requestsTo(requests, "DELETE", PHOTO_PATH)).toHaveLength(1);
    await waitFor(() =>
      expect(requestsTo(requests, "GET", LIST).length).toBeGreaterThan(1),
    );
  });
});

describe("Add to draft", () => {
  const CAPTIONS_PATH = `${LIST}/${CAPTIONS.id}`;
  const ATTACH = `${DRAFTS}/${DRAFT.id}/media`;
  const attached: PackDraft = { ...DRAFT, lock_version: 5 };

  /** Chooses the draft "Demo pack" in the listbox of the dialog. */
  async function chooseDraft(
    user: ReturnType<typeof renderPage>["user"],
    dialog: HTMLElement,
  ) {
    await user.click(
      await within(dialog).findByRole("button", { name: /^Draft/ }),
    );
    await user.click(await screen.findByRole("option", { name: "Demo pack" }));
  }

  test("of a captions asset in a dialog opened after a reload sends the asset id and the path only", async () => {
    // The page renders from scratch, as after a reload of the library: no
    // file of the browser exists, and nothing goes through the upload.
    const { requests: xhr } = installFakeXhr([]);
    const { user, requests } = renderPage({
      [`GET ${LIST}`]: list([CAPTIONS]),
      [`GET ${CAPTIONS_PATH}`]: {
        status: 200,
        body: { ...CAPTIONS, uses: NO_USES },
      },
      [`GET ${DRAFTS}`]: { status: 200, body: { data: [DRAFT] } },
      [`POST ${ATTACH}`]: { status: 201, body: attached },
    });

    await user.click(
      await screen.findByRole("button", { name: "Intro captions en" }),
    );
    const dialog = await screen.findByRole("dialog", {
      name: "Intro captions en",
    });
    // Captions have no directive of their own.
    expect(
      within(dialog).queryByLabelText("Directive for a lesson"),
    ).toBeNull();
    expect(dialog).toHaveTextContent(
      "The server copies the captions into a text file of the draft at the path.",
    );
    await chooseDraft(user, dialog);
    const path = within(dialog).getByLabelText("Path in the draft");
    expect(path).toHaveValue("media/intro-captions-en.vtt");
    await expectNoAxeViolations(document.body);

    await user.click(
      within(dialog).getByRole("button", { name: "Add to draft" }),
    );

    expect(
      await within(dialog).findByText(
        /Added at media\/intro-captions-en\.vtt\./,
      ),
    ).toBeInTheDocument();
    expect(
      within(dialog).getByRole("link", { name: "Open the draft Demo pack" }),
    ).toHaveAttribute("href", `/admin/workbench/${DRAFT.id}`);
    const [post] = requestsTo(requests, "POST", ATTACH);
    expect(post.body).toEqual({
      media_asset_id: CAPTIONS.id,
      path: "media/intro-captions-en.vtt",
      lock_version: 4,
    });
    expect(post.headers.get("content-type")).toBe("application/json");
    expect(post.headers.get("x-csrf-token")).toBe("csrf-1");
    expect(xhr).toHaveLength(0);
    expect(requestsTo(requests, "POST", LIST)).toHaveLength(0);
  });

  test("repeats once with the stored lock_version of a 409 stale_draft", async () => {
    const { user, requests } = renderPage({
      [`GET ${LIST}`]: list([PHOTO]),
      [`GET ${LIST}/${PHOTO.id}`]: {
        status: 200,
        body: { ...PHOTO, uses: NO_USES },
      },
      [`GET ${DRAFTS}`]: { status: 200, body: { data: [DRAFT] } },
      [`POST ${ATTACH}`]: [
        { status: 409, body: { error: "stale_draft", lock_version: 6 } },
        { status: 201, body: { ...DRAFT, lock_version: 7 } },
      ],
    });

    await user.click(await screen.findByRole("button", { name: "Team photo" }));
    const dialog = await screen.findByRole("dialog", { name: "Team photo" });
    await chooseDraft(user, dialog);
    await user.click(
      within(dialog).getByRole("button", { name: "Add to draft" }),
    );

    expect(
      await within(dialog).findByText(/Added at media\/team-photo\.webp\./),
    ).toBeInTheDocument();
    expect(
      requestsTo(requests, "POST", ATTACH).map(
        (request) => (request.body as { lock_version: number }).lock_version,
      ),
    ).toEqual([4, 6]);
  });

  test("checks the draft and the path, and names a taken path", async () => {
    const { user, requests } = renderPage({
      [`GET ${LIST}`]: list([PHOTO]),
      [`GET ${LIST}/${PHOTO.id}`]: {
        status: 200,
        body: { ...PHOTO, uses: NO_USES },
      },
      [`GET ${DRAFTS}`]: { status: 200, body: { data: [DRAFT] } },
      [`POST ${ATTACH}`]: { status: 409, body: { error: "path_taken" } },
    });

    await user.click(await screen.findByRole("button", { name: "Team photo" }));
    const dialog = await screen.findByRole("dialog", { name: "Team photo" });
    await within(dialog).findByRole("button", { name: /^Draft/ });
    const path = within(dialog).getByLabelText("Path in the draft");
    await user.clear(path);
    await user.type(path, "media/team-photo.png");
    await user.click(
      within(dialog).getByRole("button", { name: "Add to draft" }),
    );

    expect(within(dialog).getByText("Choose a draft.")).toBeInTheDocument();
    expect(
      within(dialog).getByRole("button", { name: /^Draft/ }),
    ).toHaveAccessibleDescription("Choose a draft.");
    await expectNoAxeViolations(document.body);
    expect(path).toHaveAccessibleDescription(
      /Use media\/ with up to three folders .* ending in \.webp\./,
    );
    expect(requestsTo(requests, "POST", ATTACH)).toHaveLength(0);

    await chooseDraft(user, dialog);
    await user.clear(path);
    await user.type(path, "media/figures/team-photo.webp");
    await user.click(
      within(dialog).getByRole("button", { name: "Add to draft" }),
    );

    await waitFor(() =>
      expect(path).toHaveAccessibleDescription(
        /The draft holds a file or a media entry with this path already\./,
      ),
    );
    expect(requestsTo(requests, "POST", ATTACH)).toHaveLength(1);
  });

  test("a failed asset cannot be added", async () => {
    const { user } = renderPage({
      [`GET ${LIST}`]: list([DIAGRAM]),
      [`GET ${LIST}/${DIAGRAM.id}`]: {
        status: 200,
        body: { ...DIAGRAM, uses: NO_USES },
      },
      [`GET ${DRAFTS}`]: { status: 200, body: { data: [DRAFT] } },
    });

    await user.click(
      await screen.findByRole("button", { name: "Release checks" }),
    );
    const dialog = await screen.findByRole("dialog", {
      name: "Release checks",
    });

    expect(
      within(dialog).getByText("A failed file cannot be added to a draft."),
    ).toBeInTheDocument();
    expect(
      within(dialog).queryByRole("button", { name: "Add to draft" }),
    ).toBeNull();
    expect(dialog).toHaveTextContent(
      "The SVG file could not be rebuilt. Reason: The file holds a DOCTYPE declaration.",
    );
  });
});
