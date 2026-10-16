import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, test } from "vitest";
import i18n from "../../i18n";
import { expectNoAxeViolations } from "../../test/axe";
import {
  EMBED_URL,
  embedMedia,
  externalMedia,
  mediaBlock,
  mediaUrl,
  videoMedia,
} from "../../test/media";
import {
  EmbedConsentContext,
  forgetEmbedConsent,
  type EmbedConsent,
} from "../embedConsent";
import type { Block } from "../runtime";
import { VideoBlock } from "./VideoBlock";

/**
 * Task 0018 step 18: a video of the pack plays with the controls of the
 * browser, its poster and its caption tracks; an external file loads
 * nothing before play and names its host; an embed player loads only
 * after the consent of the learner, unless the setting is `auto`. No
 * video plays by itself, and a URL that `safeMediaUrl` rejects or
 * `available: false` shows a notice.
 */
afterEach(() => {
  forgetEmbedConsent();
});

function renderVideo(block: Block, consent?: EmbedConsent) {
  const user = userEvent.setup();
  const ui = <VideoBlock block={block} />;
  const result = render(
    consent === undefined ? (
      ui
    ) : (
      <EmbedConsentContext.Provider value={consent}>
        {ui}
      </EmbedConsentContext.Provider>
    ),
  );
  return { ...result, user };
}

const UNAVAILABLE = "This video is not available on this installation.";

describe("VideoBlock with a file of the pack", () => {
  test("renders the video with its poster, source, caption tracks and fallback", async () => {
    const { container } = renderVideo(mediaBlock("video", videoMedia()));

    const video = container.querySelector("video") as HTMLVideoElement;
    expect(video).not.toBeNull();
    expect(video).toHaveAttribute("controls");
    expect(video).toHaveAttribute("preload", "metadata");
    expect(video).toHaveAttribute("playsinline");
    expect(video).toHaveAttribute("poster", mediaUrl("c", "webp"));
    expect(video).toHaveAttribute("width", "640");
    expect(video).toHaveAttribute("height", "360");
    expect(video).not.toHaveAttribute("autoplay");
    expect(video.autoplay).toBe(false);

    const sources = video.querySelectorAll("source");
    expect(sources).toHaveLength(1);
    expect(sources[0]).toHaveAttribute("src", mediaUrl("b", "webm"));
    expect(sources[0]).toHaveAttribute("type", "video/webm");

    const tracks = [...video.querySelectorAll("track")];
    expect(
      tracks.map((track) => [
        track.getAttribute("kind"),
        track.getAttribute("src"),
        track.getAttribute("srclang"),
        track.getAttribute("label"),
        track.hasAttribute("default"),
      ]),
    ).toEqual([
      ["captions", mediaUrl("d", "vtt"), "en", "English", true],
      ["captions", mediaUrl("e", "vtt"), "de", "German", false],
    ]);
    expect(video).toHaveTextContent("Your browser cannot play this video.");
    expect(screen.queryByText(/Plays from/)).toBeNull();

    await expectNoAxeViolations(container);
  });

  test("the title is the label of the block, and the print line follows the video", () => {
    const { container } = renderVideo(mediaBlock("video", videoMedia()));

    const label = screen.getByText("A tour of the assistant").closest("p");
    expect(label).toHaveTextContent("Video: A tour of the assistant");
    const print = screen.getByText("Video: see the online lesson");
    expect(print).toHaveClass("hidden", "print:block");
    expect(container.querySelector("iframe")).toBeNull();
  });

  test("the caption labels follow the language of the interface", async () => {
    await i18n.changeLanguage("de");
    try {
      const { container } = renderVideo(mediaBlock("video", videoMedia()));
      expect(
        [...container.querySelectorAll("track")].map((track) =>
          track.getAttribute("label"),
        ),
      ).toEqual(["Englisch", "Deutsch"]);
    } finally {
      await i18n.changeLanguage("en");
    }
  });

  test("a non-empty body is the transcript, closed at the start", async () => {
    const { container, user } = renderVideo(
      mediaBlock("video", videoMedia(), {
        body: "The assistant opens a **draft**.",
      }),
    );

    const button = screen.getByRole("button", { name: "Transcript" });
    expect(button).toHaveAttribute("aria-expanded", "false");
    expect(screen.queryByText("draft")).toBeNull();
    await expectNoAxeViolations(container);

    await user.click(button);
    expect(button).toHaveAttribute("aria-expanded", "true");
    expect(screen.getByText("draft").tagName).toBe("STRONG");
    await expectNoAxeViolations(container);
  });

  test("an empty body shows no transcript", () => {
    renderVideo(mediaBlock("video", videoMedia(), { body: "  " }));

    expect(screen.queryByRole("button", { name: "Transcript" })).toBeNull();
  });

  test("available: false shows the notice in place of the video", async () => {
    const { container } = renderVideo(
      mediaBlock("video", videoMedia({ available: false })),
    );

    expect(container.querySelector("video")).toBeNull();
    expect(screen.getByText(UNAVAILABLE)).toBeInTheDocument();
    await expectNoAxeViolations(container);
  });
});

describe("VideoBlock with an external file", () => {
  test("loads nothing before play and names its host", async () => {
    const { container } = renderVideo(mediaBlock("video", externalMedia()));

    const video = container.querySelector("video");
    expect(video).toHaveAttribute("preload", "none");
    expect(video).not.toHaveAttribute("autoplay");
    expect(video?.querySelector("source")).toHaveAttribute(
      "src",
      "https://cdn.example.org/clips/intro.mp4",
    );
    expect(video?.querySelector("source")).toHaveAttribute("type", "video/mp4");
    expect(screen.getByText("Plays from cdn.example.org")).toBeInTheDocument();
    await expectNoAxeViolations(container);
  });

  test.each([
    ["http:", "http://cdn.example.org/clips/intro.mp4"],
    ["javascript:", "javascript:alert(1)"],
    ["user info", "https://user:pw@cdn.example.org/clips/intro.mp4"],
    ["a relative URL", "/clips/intro.mp4"],
  ])("a URL with %s shows the notice", (_case, url) => {
    const { container } = renderVideo(mediaBlock("video", externalMedia(url)));

    expect(container.querySelector("video")).toBeNull();
    expect(container.querySelector("source")).toBeNull();
    expect(screen.getByText(UNAVAILABLE)).toBeInTheDocument();
  });
});

describe("VideoBlock with an embed player", () => {
  const frameOf = (container: HTMLElement) => container.querySelector("iframe");

  test("with click, asks before it loads the player, and loads it after Load video", async () => {
    const { container, user } = renderVideo(
      mediaBlock("video", embedMedia()),
      "click",
    );

    expect(frameOf(container)).toBeNull();
    expect(
      screen.getByText(
        "This video plays in a player of player.example.org. Loading it sends the address of your device and data of your browser to player.example.org.",
      ),
    ).toBeInTheDocument();
    const open = screen.getByRole("link", {
      name: "Open on player.example.org",
    });
    expect(open).toHaveAttribute("href", EMBED_URL);
    expect(open).toHaveAttribute("target", "_blank");
    expect(open).toHaveAttribute("rel", "noopener noreferrer");
    await expectNoAxeViolations(container);

    await user.click(screen.getByRole("button", { name: "Load video" }));

    const frame = frameOf(container);
    expect(frame).not.toBeNull();
    expect(frame).toHaveAttribute("src", EMBED_URL);
    expect(frame).toHaveAttribute("title", "A talk on checking sources");
    expect(frame).toHaveAttribute(
      "sandbox",
      "allow-scripts allow-same-origin allow-presentation allow-popups allow-popups-to-escape-sandbox",
    );
    expect(frame).toHaveAttribute(
      "allow",
      "fullscreen; picture-in-picture; encrypted-media",
    );
    expect(frame).toHaveAttribute(
      "referrerpolicy",
      "strict-origin-when-cross-origin",
    );
    expect(frame).toHaveAttribute("loading", "lazy");
    expect(frame?.parentElement).toHaveClass("aspect-video", "w-full");
    expect(frame).toHaveFocus();
    expect(screen.queryByRole("button", { name: "Load video" })).toBeNull();
    await expectNoAxeViolations(container, { iframes: false });
  });

  test("without a provider, the setting is click", () => {
    const { container } = renderVideo(mediaBlock("video", embedMedia()));

    expect(frameOf(container)).toBeNull();
    expect(
      screen.getByRole("button", { name: "Load video" }),
    ).toBeInTheDocument();
  });

  test("after consent, another embed of the same host loads at once, one of another host still asks", async () => {
    const { user, unmount } = renderVideo(
      mediaBlock("video", embedMedia()),
      "click",
    );
    await user.click(screen.getByRole("button", { name: "Load video" }));
    unmount();

    const { container } = render(
      <EmbedConsentContext.Provider value="click">
        <VideoBlock
          block={mediaBlock(
            "video",
            embedMedia("https://PLAYER.example.org/watch/other"),
          )}
        />
        <VideoBlock
          block={mediaBlock(
            "video",
            embedMedia("https://videos.example.net/embed/7"),
            { id: "00000000-0000-4000-8000-000000000083" },
          )}
        />
      </EmbedConsentContext.Provider>,
    );

    const frames = container.querySelectorAll("iframe");
    expect(frames).toHaveLength(1);
    expect(frames[0]).toHaveAttribute(
      "src",
      "https://player.example.org/watch/other",
    );
    expect(
      screen.getByRole("button", { name: "Load video" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("link", { name: "Open on videos.example.net" }),
    ).toBeInTheDocument();
  });

  test("consent in one block loads the other embeds of that host on the page", async () => {
    const { container, user } = renderVideo(
      mediaBlock("video", embedMedia()),
      "click",
    );
    render(
      <VideoBlock
        block={mediaBlock(
          "video",
          embedMedia("https://player.example.org/watch/second"),
          { id: "00000000-0000-4000-8000-000000000084" },
        )}
      />,
      { container: container.appendChild(document.createElement("div")) },
    );
    expect(container.querySelectorAll("iframe")).toHaveLength(0);

    const [first] = screen.getAllByRole("button", { name: "Load video" });
    await user.click(first);

    expect(container.querySelectorAll("iframe")).toHaveLength(2);
  });

  test("with auto, the player loads with the page", async () => {
    const { container } = renderVideo(
      mediaBlock("video", embedMedia()),
      "auto",
    );

    expect(frameOf(container)).toHaveAttribute("src", EMBED_URL);
    expect(screen.queryByRole("button", { name: "Load video" })).toBeNull();
    expect(frameOf(container)).not.toHaveFocus();
    await expectNoAxeViolations(container, { iframes: false });
  });

  test.each([
    ["http:", "http://player.example.org/watch/intro"],
    ["javascript:", "javascript:alert(1)"],
    ["user info", "https://user@player.example.org/watch/intro"],
  ])("a URL with %s shows the notice, also with auto", (_case, url) => {
    const { container } = renderVideo(
      mediaBlock("video", embedMedia(url)),
      "auto",
    );

    expect(frameOf(container)).toBeNull();
    expect(screen.queryByRole("button", { name: "Load video" })).toBeNull();
    expect(screen.getByText(UNAVAILABLE)).toBeInTheDocument();
  });

  test("available: false shows the notice and no consent request", () => {
    const { container } = renderVideo(
      mediaBlock("video", embedMedia(EMBED_URL, { available: false })),
      "auto",
    );

    expect(frameOf(container)).toBeNull();
    expect(screen.getByText(UNAVAILABLE)).toBeInTheDocument();
  });

  test("the notice and the link name the host in German", async () => {
    await i18n.changeLanguage("de");
    try {
      renderVideo(mediaBlock("video", embedMedia()), "click");
      const notice = screen.getByText(/Wenn Sie es laden/);
      expect(notice).toHaveTextContent("player.example.org");
      expect(
        within(notice.parentElement as HTMLElement).getByRole("link", {
          name: "Auf player.example.org öffnen",
        }),
      ).toBeInTheDocument();
      expect(
        screen.getByRole("button", { name: "Video laden" }),
      ).toBeInTheDocument();
    } finally {
      await i18n.changeLanguage("en");
    }
  });
});
