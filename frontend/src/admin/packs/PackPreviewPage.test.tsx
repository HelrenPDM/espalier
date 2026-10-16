import { act, screen, waitFor, within } from "@testing-library/react";
import { afterEach, describe, expect, test } from "vitest";
import { packQueryKey, type PackImport } from "../../api/admin/packs";
import { forgetEmbedConsent } from "../../player/embedConsent";
import type {
  PackPayload,
  PayloadBlock,
  PayloadItem,
} from "../../runtimes/standalone";
import { expectNoAxeViolations } from "../../test/axe";
import { renderWithProviders } from "../../test/render";
import { signedInPayload } from "../../test/session";
import { PackPreviewPage } from "./PackPreviewPage";

/**
 * Task 0015 step 11: "Preview" renders the player with `StandaloneRuntime`
 * on the payload of the import, below a visible "Preview" banner with the
 * count of blocks and items per provenance value. The player routes stay
 * below `/admin/packs/:id/preview`, so its links do not leave the preview,
 * and the module station lists the objectives of the topic. The player
 * sends no request to the server.
 */
const ID = "00000000-0000-4000-8000-000000000701";
const BASE = `/admin/packs/${ID}/preview`;
const author = signedInPayload("mfa", { roles: ["learner", "author"] });

const item = (
  overrides: Partial<PayloadItem> & Pick<PayloadItem, "key" | "kind">,
): PayloadItem => ({
  lesson: "intro",
  stem: `Stem of ${overrides.key}`,
  core: false,
  provenance: "invented",
  objectives: [],
  rules: [],
  reveals: [],
  cite: [],
  options: [],
  config: {},
  ...overrides,
});

const payload: PackPayload = {
  key: "preview-demo",
  title: "Working with text tools",
  locale: "en",
  version: "2.0.0",
  alignment: "strict",
  sources: [],
  glossary: [],
  segments: [],
  stations: [
    { kind: "overview", title: "Overview", module: null, config: {} },
    { kind: "module", title: "Checking claims", module: 1, config: {} },
  ],
  formats: [],
  modules: [
    {
      number: 1,
      title: "Checking claims",
      summary: "How to check a claim.",
      phases: ["understand"],
      single_path: false,
      lessons: [
        {
          key: "intro",
          title: "Why claims need checks",
          position: 1,
          blocks: [
            {
              kind: "text",
              body: "A claim needs a source.",
              provenance: "sourced",
              collapsed_on: [],
              placeholder_key: null,
              cite: [],
              media: null,
            },
            {
              kind: "example",
              body: "An invented example.",
              provenance: "invented",
              collapsed_on: [],
              placeholder_key: null,
              cite: [],
              media: null,
            },
            {
              kind: "callout",
              body: "An assumption.",
              provenance: "assumption",
              collapsed_on: [],
              placeholder_key: null,
              cite: [],
              media: null,
            },
          ],
        },
      ],
      objectives: [
        {
          key: "m1-subject-know",
          statement: "Name what makes a claim checkable.",
          area: "subject",
          depth: "know",
          phase: "understand",
          domain: null,
          taught_in: ["intro"],
        },
        {
          key: "m1-method-apply",
          statement: "Check a claim against a source.",
          area: "method",
          depth: "apply",
          phase: "apply",
          domain: null,
          taught_in: ["intro"],
        },
      ],
      rules: [],
      items: [
        item({
          key: "claim-choice",
          kind: "single_choice",
          objectives: ["m1-subject-know"],
          options: [
            { key: "a", label: "A source", correct: true, feedback: "Right." },
            { key: "b", label: "A feeling", correct: false, feedback: "No." },
          ],
        }),
        item({
          key: "claim-drill",
          kind: "checklist_drill",
          provenance: "sourced",
          objectives: ["m1-method-apply"],
          config: {
            checks: [{ key: "source", label: "Source named", required: true }],
          },
        }),
      ],
      assessments: [],
    },
  ],
};

const pack = (overrides: Partial<PackImport> = {}): PackImport => ({
  id: ID,
  status: "validated",
  pack_key: payload.key,
  pack_version: payload.version,
  inserted_at: "2026-10-12T09:30:00Z",
  published_at: null,
  payload: payload as unknown as PackImport["payload"],
  report: { errors: [], warnings: [] },
  alignment: { mode: "strict", matrix: [], errors: [], warnings: [] },
  media: {},
  media_policy: { external_hosts: [], embed_hosts: [], embed_consent: "click" },
  ...overrides,
});

function renderPreview(body: PackImport, route = BASE) {
  return renderWithProviders(<PackPreviewPage />, {
    route,
    path: "/admin/packs/:id/preview/*",
    session: author,
    responses: { [`GET /api/admin/packs/${ID}`]: { status: 200, body } },
  });
}

describe("PackPreviewPage", () => {
  test("shows the banner with the provenance overview and opens the program below the preview", async () => {
    const { container, location, requests } = renderPreview(pack());

    const banner = await screen.findByRole("region", { name: "Preview" });
    expect(banner).toHaveTextContent(
      "Preview of Working with text tools, version 2.0.0",
    );
    const overview = within(banner).getByRole("table", {
      name: "Provenance overview",
    });
    const counts = within(overview)
      .getAllByRole("row")
      .slice(1)
      .map((row) =>
        [
          within(row).getByRole("rowheader").textContent,
          ...within(row)
            .getAllByRole("cell")
            .map((cell) => cell.textContent),
        ].join(" "),
      );
    expect(counts).toEqual([
      "Invented 1 1",
      "Sourced 1 1",
      "Vendor statement 0 0",
      "Assumption 1 0",
      "Placeholder 0 0",
    ]);

    expect(
      await screen.findByRole("heading", {
        level: 1,
        name: "Working with text tools",
      }),
    ).toBeInTheDocument();
    expect(location()).toBe(`${BASE}/programs/preview-demo`);
    const stations = screen.getByRole("link", { name: /Checking claims/ });
    expect(stations).toHaveAttribute(
      "href",
      `${BASE}/programs/preview-demo/stations/2`,
    );

    await expectNoAxeViolations(container);
    expect(requests.map((request) => request.path)).toEqual([
      `/api/admin/packs/${ID}`,
    ]);
  });

  test("the module station lists the objectives of the topic and evaluates answers in the browser", async () => {
    const { user, location, requests } = renderPreview(pack());

    await user.click(
      await screen.findByRole("link", { name: /Checking claims/ }),
    );
    await waitFor(() =>
      expect(location()).toBe(`${BASE}/programs/preview-demo/stations/2`),
    );
    const panel = await screen.findByRole("region", {
      name: "Objectives of this topic",
    });
    expect(panel).toHaveTextContent("Name what makes a claim checkable.");
    expect(panel).toHaveTextContent("Check a claim against a source.");

    await user.click(screen.getByRole("radio", { name: "A source" }));
    const [check] = screen.getAllByRole("button", { name: "Check answer" });
    await user.click(check);
    expect(await screen.findByText("Correct.")).toBeInTheDocument();

    expect(
      screen.getByRole("link", { name: "Back to Working with text tools" }),
    ).toHaveAttribute("href", `${BASE}/programs/preview-demo`);
    expect(requests.map((request) => request.path)).toEqual([
      `/api/admin/packs/${ID}`,
    ]);
  });

  describe("with media (task 0018)", () => {
    afterEach(() => {
      forgetEmbedConsent();
    });

    const mediaBlock = (media: PayloadBlock["media"]): PayloadBlock => ({
      kind: media !== null && "alt" in media ? "figure" : "video",
      body: "",
      provenance: "invented",
      collapsed_on: [],
      placeholder_key: null,
      cite: [],
      media,
    });
    const embed = (url: string, title: string) =>
      mediaBlock({ src: null, embed: url, title, poster: null, captions: [] });

    const [module] = payload.modules;
    const mediaPayload: PackPayload = {
      ...payload,
      modules: [
        {
          ...module,
          lessons: [
            {
              ...module.lessons[0],
              blocks: [
                mediaBlock({
                  src: "media/desk.png",
                  alt: "A desk with two screens",
                  decorative: null,
                  size: "medium",
                }),
                embed("https://player.example.org/watch/1", "Allowed talk"),
                embed("https://videos.example.net/embed/7", "Other talk"),
              ],
            },
          ],
        },
      ],
    };
    const desk = `/media/${"a".repeat(64)}.webp`;
    const media: PackImport["media"] = {
      "media/desk.png": {
        kind: "image",
        status: "ready",
        failure: null,
        failure_detail: null,
        url: desk,
        mime: "image/webp",
        width: 1200,
        height: 800,
        duration_ms: null,
        progress: 100,
        has_audio: false,
        has_alpha: false,
        animated: false,
        poster_url: null,
      },
    };

    async function openStation(consent: "click" | "auto") {
      const result = renderPreview(
        pack({
          payload: mediaPayload as unknown as PackImport["payload"],
          media,
          media_policy: {
            external_hosts: [],
            embed_hosts: ["player.example.org"],
            embed_consent: consent,
          },
        }),
        `${BASE}/programs/preview-demo/stations/2`,
      );
      await screen.findByRole("heading", { name: "Why claims need checks" });
      return result;
    }

    test("resolves the media of the import and applies the allowlist of the policy", async () => {
      const { container, requests } = await openStation("click");

      expect(
        screen.getByRole("img", { name: "A desk with two screens" }),
      ).toHaveAttribute("src", desk);
      expect(container.querySelector("iframe")).toBeNull();
      expect(
        screen.getByRole("link", { name: "Open on player.example.org" }),
      ).toBeInTheDocument();
      expect(
        screen.getAllByText(
          "This video is not available on this installation.",
        ),
      ).toHaveLength(1);
      expect(requests.map((request) => request.path)).toEqual([
        `/api/admin/packs/${ID}`,
      ]);
    });

    test("a read with a new progress keeps the player, and a ready file renews it once", async () => {
      const clipPayload: PackPayload = {
        ...payload,
        modules: [
          {
            ...module,
            lessons: [
              {
                ...module.lessons[0],
                blocks: [
                  {
                    kind: "explanation",
                    body: "A source makes a claim checkable.",
                    provenance: "sourced",
                    collapsed_on: [],
                    placeholder_key: null,
                    cite: [],
                    media: null,
                  },
                  mediaBlock({
                    src: "media/clip.mp4",
                    embed: null,
                    title: "A clip",
                    poster: null,
                    captions: [],
                  }),
                ],
              },
            ],
          },
        ],
      };
      const clip = (
        overrides: Partial<PackImport["media"][string]>,
      ): PackImport["media"] => ({
        "media/clip.mp4": {
          kind: "video",
          status: "processing",
          failure: null,
          failure_detail: null,
          url: null,
          mime: null,
          width: null,
          height: null,
          duration_ms: null,
          progress: 40,
          has_audio: false,
          has_alpha: false,
          animated: false,
          poster_url: null,
          ...overrides,
        },
      });
      // Every read of the import, the polling included, answers the
      // current state of the conversion.
      let current = pack({
        payload: clipPayload as unknown as PackImport["payload"],
        media: clip({}),
      });
      const { container, queryClient, user } = renderWithProviders(
        <PackPreviewPage />,
        {
          route: `${BASE}/programs/preview-demo/stations/2`,
          path: "/admin/packs/:id/preview/*",
          session: author,
          responses: {
            [`GET /api/admin/packs/${ID}`]: () => ({
              status: 200,
              body: current,
            }),
          },
        },
      );
      const read = async (media: PackImport["media"]) => {
        current = { ...current, media };
        await act(() =>
          queryClient.refetchQueries({ queryKey: packQueryKey(ID) }),
        );
        // The load of a new runtime would end in a later task.
        await act(() => new Promise((resolve) => setTimeout(resolve, 0)));
      };

      const heading = await screen.findByRole("heading", {
        name: "Why claims need checks",
      });
      const explanation = screen.getByRole("button", { name: "Explanation" });
      expect(explanation).toHaveAttribute("aria-expanded", "true");
      await user.click(explanation);
      expect(explanation).toHaveAttribute("aria-expanded", "false");
      expect(
        screen.getByText("This video is not available on this installation."),
      ).toBeInTheDocument();

      await read(clip({ progress: 60 }));

      expect(
        queryClient.getQueryData<PackImport>(packQueryKey(ID))?.media[
          "media/clip.mp4"
        ].progress,
      ).toBe(60);
      expect(heading).toBeInTheDocument();
      expect(explanation).toBeInTheDocument();
      expect(explanation).toHaveAttribute("aria-expanded", "false");

      await read(
        clip({
          status: "ready",
          progress: 100,
          url: `/media/${"b".repeat(64)}.webm`,
          mime: "video/webm",
          width: 640,
          height: 360,
          duration_ms: 8000,
          has_audio: true,
        }),
      );

      await waitFor(() =>
        expect(container.querySelector("video source")).toHaveAttribute(
          "src",
          `/media/${"b".repeat(64)}.webm`,
        ),
      );
      expect(
        screen.queryByText("This video is not available on this installation."),
      ).toBeNull();
    });

    test("with embed_consent auto, the allowed player loads with the page", async () => {
      const { container } = await openStation("auto");

      const frames = container.querySelectorAll("iframe");
      expect(frames).toHaveLength(1);
      expect(frames[0]).toHaveAttribute("title", "Allowed talk");
      expect(screen.queryByRole("button", { name: "Load video" })).toBeNull();
    });
  });

  test("an import without a payload shows a notice", async () => {
    renderPreview(pack({ status: "failed", payload: null }));

    expect(
      await screen.findByText(
        "This import holds no pack to preview. Only a validated import can be previewed.",
      ),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("link", { name: "Back to the import" }),
    ).toHaveAttribute("href", `/admin/packs/${ID}`);
  });
});
