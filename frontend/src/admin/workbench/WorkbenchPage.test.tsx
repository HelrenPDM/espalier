import { fireEvent, screen, waitFor, within } from "@testing-library/react";
import { describe, expect, onTestFinished, test } from "vitest";
import type { MediaAsset } from "../../api/admin/media";
import type { DraftMediaEntry, PackDraft } from "../../api/admin/workbench";
import { expectNoAxeViolations } from "../../test/axe";
import {
  renderWithProviders,
  requestsTo,
  type RenderWithProvidersResult,
  type StubResponses,
} from "../../test/render";
import { signedInPayload } from "../../test/session";
import { WorkbenchPage } from "./WorkbenchPage";

/**
 * Task 0016a steps 12 and 15: `/admin/workbench` lists the drafts with
 * title, pack key, number of files, size and the time of the last change,
 * with a link to each draft, its download and "Delete" behind a
 * confirmation. The starting points "Empty pack", "Published program" and
 * "Zip archive" send their requests and move to the new draft; an archive
 * with skipped paths lists them with the link to the draft, a rejected
 * archive shows its report, and a 409 `draft_limit` names the limit and the
 * advice to delete a draft. Task 0018: a 409 `media_limit` names the limit
 * of media entries, a 409 `media_not_ready` names the captions files that
 * are not ready, and a download reads the draft first and holds back with
 * the reason of the draft page while a media entry is not `ready`.
 */
const uuid = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;

const ROUTE = "/admin/workbench";
const DRAFTS = "/api/admin/pack-drafts";
const UPLOADS = "/api/admin/pack-draft-uploads";
const LIMIT_TEXT =
  "The workbench holds at most 50 drafts, and this limit is reached. Delete a draft that you no longer need, then start again.";

const author = signedInPayload("mfa", { roles: ["learner", "author"] });

function draft(n: number, overrides: Partial<PackDraft> = {}): PackDraft {
  return {
    id: uuid(n),
    title: `Draft ${n}`,
    pack_key: `pack-${n}`,
    lock_version: 3,
    inserted_at: "2026-10-12T08:00:00Z",
    updated_at: "2026-10-13T09:30:00Z",
    usage: { files: 6, bytes: 1536 },
    limits: { files: 2000, file_bytes: 1_048_576, draft_bytes: 524_288_000 },
    ...overrides,
  };
}

const demo = draft(1, {
  title: "Demo pack",
  pack_key: "demo",
  usage: { files: 24, bytes: 2_500_000 },
});
const untitled = draft(2, { title: "Untitled draft", pack_key: null });
const created = draft(3, { title: "New pack", pack_key: "new-pack" });

const programs = {
  programs: [
    { slug: "demo", title: "Demo program", locale: "en" },
    { slug: "einfuehrung", title: "Einführung in die Praxis", locale: "de" },
  ],
};

function renderPage(responses: StubResponses = {}) {
  return renderWithProviders(<WorkbenchPage />, {
    route: ROUTE,
    session: author,
    responses: {
      [`GET ${DRAFTS}`]: { status: 200, body: { data: [demo, untitled] } },
      "GET /api/programs": { status: 200, body: programs },
      ...responses,
    },
  });
}

const archive = () =>
  new File(["zip archive"], "demo.zip", { type: "application/zip" });

/** The three starting points, each driven to its request. */
const starts = {
  empty: async ({ user }: RenderWithProvidersResult) => {
    await user.type(screen.getByLabelText("Name of the pack"), "New pack");
    await user.click(
      screen.getByRole("button", { name: "Start an empty pack" }),
    );
  },
  program: async ({ user }: RenderWithProvidersResult) => {
    await user.selectOptions(await screen.findByLabelText("Program"), "demo");
    await user.click(
      screen.getByRole("button", { name: "Start from the program" }),
    );
  },
  archive: async ({ user }: RenderWithProvidersResult) => {
    await user.upload(screen.getByLabelText("Pack archive (zip)"), archive());
    await user.click(
      screen.getByRole("button", { name: "Start from the archive" }),
    );
  },
};

const rowOf = async (title: string) => {
  const table = await screen.findByRole("table", { name: "Drafts" });
  const header = within(table).getByRole("rowheader", { name: title });
  const row = header.closest("tr");
  if (row === null) throw new Error(`no row for ${title}`);
  return row;
};

describe("the list of drafts", () => {
  test("shows title, pack key, files, size and last change with link, download and Delete", async () => {
    const { container } = renderPage();

    const table = await screen.findByRole("table", { name: "Drafts" });
    expect(
      within(table)
        .getAllByRole("columnheader")
        .map((header) => header.textContent),
    ).toEqual(["Title", "Pack key", "Files", "Size", "Last change", "Actions"]);

    const row = await rowOf("Demo pack");
    const cells = within(row).getAllByRole("cell");
    expect(cells.slice(0, 3).map((cell) => cell.textContent)).toEqual([
      "demo",
      "24",
      "2.5 MB",
    ]);
    expect(cells[3]).toHaveTextContent("2026");
    expect(
      within(row).getByRole("link", { name: "Demo pack" }),
    ).toHaveAttribute("href", `/admin/workbench/${demo.id}`);
    expect(
      within(row).getByRole("link", { name: "Download Demo pack" }),
    ).toHaveAttribute("href", `/api/admin/pack-drafts/${demo.id}/download`);
    expect(
      within(row).getByRole("button", { name: "Delete Demo pack" }),
    ).toBeEnabled();

    const other = within(await rowOf("Untitled draft")).getAllByRole("cell");
    expect(other.slice(0, 3).map((cell) => cell.textContent)).toEqual([
      "None",
      "6",
      "1.5 kB",
    ]);

    await expectNoAxeViolations(container);
  });

  test("states that there is no draft yet", async () => {
    renderPage({ [`GET ${DRAFTS}`]: { status: 200, body: { data: [] } } });

    expect(
      await screen.findByText("There is no draft yet. Start one below."),
    ).toBeInTheDocument();
    expect(screen.queryByRole("table")).toBeNull();
  });

  test("Delete asks first, sends DELETE and moves the focus to the list", async () => {
    const view = renderPage({
      [`GET ${DRAFTS}`]: [
        { status: 200, body: { data: [demo, untitled] } },
        { status: 200, body: { data: [untitled] } },
      ],
      [`DELETE ${DRAFTS}/${demo.id}`]: { status: 204 },
    });
    const { user, requests } = view;

    await user.click(
      within(await rowOf("Demo pack")).getByRole("button", {
        name: "Delete Demo pack",
      }),
    );
    const dialog = await screen.findByRole("dialog", {
      name: "Delete this draft?",
    });
    expect(dialog).toHaveTextContent(
      "The draft Demo pack and its files are deleted.",
    );
    await expectNoAxeViolations(document.body);

    await user.click(within(dialog).getByRole("button", { name: "Cancel" }));
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
    expect(requestsTo(requests, "DELETE", `${DRAFTS}/${demo.id}`)).toHaveLength(
      0,
    );

    await user.click(
      within(await rowOf("Demo pack")).getByRole("button", {
        name: "Delete Demo pack",
      }),
    );
    await user.click(
      within(await screen.findByRole("dialog")).getByRole("button", {
        name: "Delete",
      }),
    );

    expect(
      await screen.findByText("The draft Demo pack is deleted."),
    ).toBeInTheDocument();
    const [request] = requestsTo(requests, "DELETE", `${DRAFTS}/${demo.id}`);
    expect(request.headers.get("x-csrf-token")).toBe("csrf-1");
    await waitFor(() =>
      expect(screen.queryByRole("rowheader", { name: "Demo pack" })).toBeNull(),
    );
    await waitFor(() =>
      expect(screen.getByRole("heading", { name: "Drafts" })).toHaveFocus(),
    );
  });
});

/**
 * The list carries no media, and the download answers 409
 * `media_not_ready` while a media entry is not `ready`. A click on a
 * download therefore reads the draft first and follows the link only when
 * every entry is `ready`. jsdom cannot download, so a listener on the
 * window records each click on a download link as the browser would
 * receive it and then cancels it.
 */
describe("the download of a draft", () => {
  const DOWNLOAD = `${DRAFTS}/${demo.id}/download`;
  const PENDING =
    "Media files are still converted. The download becomes possible when every media file is ready.";
  const FAILED =
    "A media file of the draft failed. Remove its entry or replace it with a ready file, then download the draft.";

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
      url: `/media/${String(n).repeat(64)}.webp`,
      poster_url: null,
      inserted_at: "2026-10-12T08:00:00Z",
      updated_at: "2026-10-13T09:30:00Z",
      ...overrides,
    };
  }

  const entry = (n: number, overrides: Partial<MediaAsset> = {}) =>
    ({
      id: uuid(900 + n),
      path: `media/asset-${n}.webp`,
      asset: asset(n, overrides),
    }) satisfies DraftMediaEntry;

  const PHOTO = entry(1);
  const CLIP = entry(2, {
    kind: "video",
    status: "processing",
    progress: 40,
    ext: null,
    bytes: null,
    url: null,
  });
  const BROKEN = entry(3, {
    kind: "svg",
    status: "failed",
    failure: "invalid_svg",
    failure_detail: "css",
    ext: null,
    url: null,
  });

  /** The draft view of `demo` with the media entries `media`. */
  const view = (media: DraftMediaEntry[]) => ({
    status: 200,
    body: { ...demo, files: [], media },
  });

  /** The clicks on download links that reach the window, in their order. */
  function recordDownloads() {
    const clicks: { href: string | null; prevented: boolean }[] = [];
    const record = (event: MouseEvent) => {
      const link =
        event.target instanceof Element ? event.target.closest("a") : null;
      const href = link?.getAttribute("href") ?? null;
      if (href === null || !href.endsWith("/download")) return;
      clicks.push({ href, prevented: event.defaultPrevented });
      event.preventDefault();
    };
    window.addEventListener("click", record);
    onTestFinished(() => window.removeEventListener("click", record));
    return clicks;
  }

  const downloadLink = async () =>
    within(await rowOf("Demo pack")).getByRole("link", {
      name: "Download Demo pack",
    });

  test.each([
    ["converted", CLIP, PENDING],
    ["failed", BROKEN, FAILED],
  ] as const)(
    "a %s media entry holds the download back with the reason of the draft page",
    async (_state, waiting, reason) => {
      const clicks = recordDownloads();
      const { user, requests, container } = renderPage({
        [`GET ${DRAFTS}/${demo.id}`]: view([PHOTO, waiting]),
      });

      const link = await downloadLink();
      await user.click(link);

      const notice = await screen.findByText(reason);
      expect(notice.closest('[role="alert"]')).not.toBeNull();
      expect(link).toHaveFocus();
      expect(clicks).toEqual([{ href: DOWNLOAD, prevented: true }]);
      expect(requestsTo(requests, "GET", `${DRAFTS}/${demo.id}`)).toHaveLength(
        1,
      );
      await expectNoAxeViolations(container);
    },
  );

  test("a draft whose media entries are ready follows the link, also from the keyboard", async () => {
    const clicks = recordDownloads();
    const { user, requests } = renderPage({
      [`GET ${DRAFTS}/${demo.id}`]: view([PHOTO]),
    });

    const link = await downloadLink();
    link.focus();
    await user.keyboard("{Enter}");

    await waitFor(() =>
      expect(clicks).toEqual([
        { href: DOWNLOAD, prevented: true },
        { href: DOWNLOAD, prevented: false },
      ]),
    );
    expect(requestsTo(requests, "GET", `${DRAFTS}/${demo.id}`)).toHaveLength(1);
    for (const alert of screen.getAllByRole("alert"))
      expect(alert).toBeEmptyDOMElement();
  });

  test("a second click while the check runs reads the draft once and downloads once", async () => {
    const clicks = recordDownloads();
    let answer: (value: { status: number; body: unknown }) => void = () => {};
    const { user, requests } = renderPage({
      [`GET ${DRAFTS}/${demo.id}`]: () =>
        new Promise((resolve) => {
          answer = resolve;
        }),
    });

    const link = await downloadLink();
    await user.click(link);
    await user.click(link);
    await waitFor(() =>
      expect(requestsTo(requests, "GET", `${DRAFTS}/${demo.id}`)).toHaveLength(
        1,
      ),
    );
    answer(view([PHOTO]));

    await waitFor(() => expect(clicks).toHaveLength(3));
    expect(clicks.map((click) => click.prevented)).toEqual([true, true, false]);
    expect(requestsTo(requests, "GET", `${DRAFTS}/${demo.id}`)).toHaveLength(1);
  });

  test("a draft that is gone names the failure and reads the list again", async () => {
    const clicks = recordDownloads();
    const { user, requests } = renderPage({
      [`GET ${DRAFTS}`]: [
        { status: 200, body: { data: [demo, untitled] } },
        { status: 200, body: { data: [untitled] } },
      ],
      [`GET ${DRAFTS}/${demo.id}`]: {
        status: 404,
        body: { error: "not_found" },
      },
    });

    await user.click(await downloadLink());

    const notice = await screen.findByText(
      "The entry no longer exists. Reload the page.",
    );
    expect(notice.closest('[role="alert"]')).not.toBeNull();
    await waitFor(() =>
      expect(screen.queryByRole("rowheader", { name: "Demo pack" })).toBeNull(),
    );
    expect(clicks).toEqual([{ href: DOWNLOAD, prevented: true }]);
    expect(requestsTo(requests, "GET", DRAFTS)).toHaveLength(2);
  });
});

describe("the starting points", () => {
  test("Empty pack sends the name and moves to the draft", async () => {
    const view = renderPage({
      [`POST ${DRAFTS}`]: { status: 201, body: created },
    });
    await starts.empty(view);

    await waitFor(() =>
      expect(view.location()).toBe(`/admin/workbench/${created.id}`),
    );
    const [request] = requestsTo(view.requests, "POST", DRAFTS);
    expect(request.body).toEqual({ source: "empty", name: "New pack" });
    expect(request.headers.get("x-csrf-token")).toBe("csrf-1");
  });

  test("Empty pack counts the name in code points, as the server does", async () => {
    const view = renderPage({
      [`POST ${DRAFTS}`]: { status: 201, body: created },
    });
    const field = screen.getByLabelText("Name of the pack");
    // 255 emoji are 255 code points and 510 UTF-16 code units.
    const name = "\u{1F4DA}".repeat(255);
    fireEvent.change(field, { target: { value: name } });
    await view.user.click(
      screen.getByRole("button", { name: "Start an empty pack" }),
    );

    await waitFor(() =>
      expect(view.location()).toBe(`/admin/workbench/${created.id}`),
    );
    const [request] = requestsTo(view.requests, "POST", DRAFTS);
    expect(request.body).toEqual({ source: "empty", name });
  });

  test("Empty pack refuses a name of 256 code points before it sends anything", async () => {
    const { user, requests } = renderPage();
    const field = screen.getByLabelText("Name of the pack");
    fireEvent.change(field, { target: { value: "\u{1F4DA}".repeat(256) } });

    await user.click(
      screen.getByRole("button", { name: "Start an empty pack" }),
    );

    expect(field).toHaveAttribute("aria-invalid", "true");
    expect(requestsTo(requests, "POST", DRAFTS)).toHaveLength(0);
  });

  test("Empty pack asks for a name before it sends anything", async () => {
    const { user, requests } = renderPage();

    await user.click(
      screen.getByRole("button", { name: "Start an empty pack" }),
    );

    const field = screen.getByLabelText("Name of the pack");
    expect(field).toHaveAttribute("aria-invalid", "true");
    expect(field).toHaveAccessibleDescription(
      expect.stringContaining("Enter a name of 1 to 255 characters."),
    );
    expect(field).toHaveFocus();
    expect(requestsTo(requests, "POST", DRAFTS)).toHaveLength(0);
  });

  test("Published program sends the slug of the chosen program and moves to the draft", async () => {
    const view = renderPage({
      [`POST ${DRAFTS}`]: { status: 201, body: created },
    });

    const select = await screen.findByLabelText("Program");
    expect(
      within(select)
        .getAllByRole("option")
        .map((option) => option.textContent),
    ).toEqual(["Choose a program", "Demo program", "Einführung in die Praxis"]);
    expect(
      within(select).getByRole("option", { name: "Einführung in die Praxis" }),
    ).toHaveAttribute("lang", "de");
    await starts.program(view);

    await waitFor(() =>
      expect(view.location()).toBe(`/admin/workbench/${created.id}`),
    );
    const [request] = requestsTo(view.requests, "POST", DRAFTS);
    expect(request.body).toEqual({ source: "program", program_slug: "demo" });
  });

  test("Published program asks for a program before it sends anything", async () => {
    const { user, requests } = renderPage();

    await screen.findByLabelText("Program");
    await user.click(
      screen.getByRole("button", { name: "Start from the program" }),
    );

    const select = screen.getByLabelText("Program");
    expect(select).toHaveAttribute("aria-invalid", "true");
    expect(select).toHaveAccessibleDescription("Choose a program.");
    expect(requestsTo(requests, "POST", DRAFTS)).toHaveLength(0);
  });

  test("Zip archive sends the archive as multipart/form-data and moves to a draft without skipped paths", async () => {
    const view = renderPage({
      [`POST ${UPLOADS}`]: {
        status: 201,
        body: { ...created, skipped: { paths: [], omitted: 0 } },
      },
    });
    await starts.archive(view);

    await waitFor(() =>
      expect(view.location()).toBe(`/admin/workbench/${created.id}`),
    );
    const [upload] = requestsTo(view.requests, "POST", UPLOADS);
    expect(upload.headers.get("content-type")).toMatch(
      /^multipart\/form-data; boundary=/,
    );
    expect(upload.headers.get("x-csrf-token")).toBe("csrf-1");
    expect(String(upload.body)).toMatch(
      /Content-Disposition: form-data; name="file"/,
    );
  });

  test("Zip archive lists the skipped paths with the link to the draft", async () => {
    const view = renderPage({
      [`POST ${UPLOADS}`]: {
        status: 201,
        body: {
          ...created,
          skipped: { paths: ["README.md", "modules/a/notes.txt"], omitted: 3 },
        },
      },
    });
    await starts.archive(view);

    const heading = await screen.findByRole("heading", {
      name: "Draft New pack created",
    });
    await waitFor(() => expect(heading).toHaveFocus());
    const panel = screen.getByRole("region", {
      name: "Draft New pack created",
    });
    expect(panel).toHaveTextContent(
      "The archive held files outside the pack layout. The draft leaves them out:",
    );
    expect(
      within(panel)
        .getAllByRole("listitem")
        .map((item) => item.textContent),
    ).toEqual(["README.md", "modules/a/notes.txt"]);
    expect(panel).toHaveTextContent("and 3 further paths.");
    expect(
      within(panel).getByRole("link", { name: "Open the draft" }),
    ).toHaveAttribute("href", `/admin/workbench/${created.id}`);
    expect(view.location()).toBe(ROUTE);

    await expectNoAxeViolations(view.container);
  });

  test("Zip archive shows the report of a rejected archive", async () => {
    const view = renderPage({
      [`POST ${UPLOADS}`]: {
        status: 422,
        body: {
          error: "archive_rejected",
          report: {
            errors: [
              {
                file: "modules/01-a/lessons/01-b.md",
                line: null,
                message: "the file is no valid UTF-8",
              },
            ],
            warnings: [],
          },
        },
      },
    });
    await starts.archive(view);

    const message = await screen.findByText("The archive was rejected:");
    const alert = message.closest('[role="alert"]');
    expect(alert).toHaveTextContent(
      "modules/01-a/lessons/01-b.md, no line: the file is no valid UTF-8",
    );
    expect(view.location()).toBe(ROUTE);
  });

  test("Zip archive asks for an archive before it sends anything", async () => {
    const { user, requests } = renderPage();

    await user.click(
      screen.getByRole("button", { name: "Start from the archive" }),
    );

    expect(
      await screen.findByText("Choose a zip archive."),
    ).toBeInTheDocument();
    expect(screen.getByLabelText("Pack archive (zip)")).toHaveAttribute(
      "aria-invalid",
      "true",
    );
    expect(requestsTo(requests, "POST", UPLOADS)).toHaveLength(0);
  });

  test.each([
    ["empty", DRAFTS],
    ["program", DRAFTS],
    ["archive", UPLOADS],
  ] as const)(
    "a 409 draft_limit on %s names the limit and the advice to delete a draft",
    async (start, path) => {
      const view = renderPage({
        [`POST ${path}`]: {
          status: 409,
          body: { error: "draft_limit", max_drafts: 50 },
        },
      });
      await starts[start](view);

      const notice = await screen.findByText(LIMIT_TEXT);
      expect(notice.closest('[role="alert"]')).not.toBeNull();
      expect(view.location()).toBe(ROUTE);
    },
  );

  test.each([
    ["program", DRAFTS],
    ["archive", UPLOADS],
  ] as const)(
    "a 409 media_limit on %s names the limit of media files",
    async (start, path) => {
      const view = renderPage({
        [`POST ${path}`]: { status: 409, body: { error: "media_limit" } },
      });
      await starts[start](view);

      const notice = await screen.findByText(
        "The pack has more media files than a draft may hold. A draft holds at most 500 media files.",
      );
      expect(notice.closest('[role="alert"]')).not.toBeNull();
      expect(view.location()).toBe(ROUTE);
    },
  );

  test("a 409 media_not_ready on program names the captions files and asks to wait", async () => {
    const view = renderPage({
      [`POST ${DRAFTS}`]: {
        status: 409,
        body: {
          error: "media_not_ready",
          media: [
            { path: "media/intro-en.vtt", status: "processing", failure: null },
            { path: "media/intro-de.vtt", status: "queued", failure: null },
          ],
        },
      },
    });
    await starts.program(view);

    const notice = await screen.findByText(
      "The draft cannot start yet, because these captions files of the pack are not ready: media/intro-en.vtt (Processing), media/intro-de.vtt (Queued). Wait until their conversion has finished, then start again. A failed or missing file has to be replaced in the pack first.",
    );
    expect(notice.closest('[role="alert"]')).not.toBeNull();
    expect(view.location()).toBe(ROUTE);
  });
});
