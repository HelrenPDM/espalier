import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, test } from "vitest";
import { expectNoAxeViolations } from "../../test/axe";
import { figureMedia, mediaBlock, mediaUrl } from "../../test/media";
import { fakeRuntime, programFixture, renderPlayer } from "../../test/player";
import { FigureBlock } from "./FigureBlock";

/**
 * Task 0018 step 18: a figure shows its image with the alternative text in
 * a box of its size, the body as the caption, a light ground in dark mode
 * for an image with transparent pixels and every SVG, and an animated
 * image only after the learner presses play.
 */
const animated = () =>
  figureMedia({
    image: {
      url: mediaUrl("a", "webp"),
      mime: "image/webp",
      width: 400,
      height: 300,
      has_alpha: false,
      animated: true,
    },
    poster: { url: mediaUrl("f", "webp"), width: 400, height: 300 },
    alt: "A cursor moves through the checklist",
  });

describe("FigureBlock", () => {
  test("shows the image with its facts in a full-width box and the body as the caption", async () => {
    const { container } = render(
      <FigureBlock
        block={mediaBlock("figure", figureMedia(), {
          body: "The checks run **in order**.",
        })}
      />,
    );

    const figure = screen.getByRole("figure");
    const image = within(figure).getByRole("img", {
      name: "Four release checks in a row",
    });
    expect(image).toHaveAttribute("src", mediaUrl("a", "webp"));
    expect(image).toHaveAttribute("width", "800");
    expect(image).toHaveAttribute("height", "600");
    expect(image).toHaveAttribute("loading", "lazy");
    expect(image).toHaveAttribute("decoding", "async");
    expect(image).toHaveClass("h-auto", "max-w-full");
    expect(image).not.toHaveClass("dark:bg-white");
    expect(image.parentElement).toHaveClass("w-full");
    const caption = figure.querySelector("figcaption");
    expect(caption).toHaveTextContent("The checks run in order.");
    expect(within(caption as HTMLElement).getByText("in order").tagName).toBe(
      "STRONG",
    );
    expect(screen.getByText("Figure")).toBeInTheDocument();

    await expectNoAxeViolations(container);
  });

  test("sets the box of the size and leaves out an empty caption", () => {
    const { rerender } = render(
      <FigureBlock
        block={mediaBlock("figure", figureMedia({ size: "small" }))}
      />,
    );
    expect(screen.getByRole("img").parentElement).toHaveClass("max-w-xs");
    expect(screen.getByRole("figure").querySelector("figcaption")).toBeNull();

    rerender(
      <FigureBlock
        block={mediaBlock("figure", figureMedia({ size: "medium" }))}
      />,
    );
    expect(screen.getByRole("img").parentElement).toHaveClass("max-w-md");
  });

  test("a decorative image has an empty alternative text", async () => {
    const { container } = render(
      <FigureBlock
        block={mediaBlock(
          "figure",
          figureMedia({ alt: null, decorative: true }),
          { body: "A caption." },
        )}
      />,
    );

    const image = container.querySelector("img");
    expect(image).toHaveAttribute("alt", "");
    expect(screen.queryByRole("img")).toBeNull();
    await expectNoAxeViolations(container);
  });

  test("an SVG and an image with transparent pixels sit on a light ground in dark mode", () => {
    const svg = figureMedia({
      image: {
        url: mediaUrl("a", "svg"),
        mime: "image/svg+xml",
        width: 640,
        height: 320,
        has_alpha: false,
        animated: false,
      },
    });
    const { rerender } = render(
      <FigureBlock block={mediaBlock("figure", svg)} />,
    );
    expect(screen.getByRole("img")).toHaveClass("dark:bg-white");
    expect(screen.getByRole("img")).toHaveAttribute(
      "src",
      mediaUrl("a", "svg"),
    );

    const alpha = figureMedia();
    alpha.image = {
      ...(alpha.image as NonNullable<typeof alpha.image>),
      has_alpha: true,
    };
    rerender(<FigureBlock block={mediaBlock("figure", alpha)} />);
    expect(screen.getByRole("img")).toHaveClass("dark:bg-white");
  });

  test("an SVG without a fixed size renders without size attributes in its box", async () => {
    const { container } = render(
      <FigureBlock
        block={mediaBlock(
          "figure",
          figureMedia({
            image: {
              url: mediaUrl("b", "svg"),
              mime: "image/svg+xml",
              width: null,
              height: null,
              has_alpha: false,
              animated: false,
            },
            alt: "A sketch of the release flow",
            size: "medium",
          }),
        )}
      />,
    );

    const image = screen.getByRole("img", {
      name: "A sketch of the release flow",
    });
    expect(image).toHaveAttribute("src", mediaUrl("b", "svg"));
    expect(image).not.toHaveAttribute("width");
    expect(image).not.toHaveAttribute("height");
    expect(image).toHaveClass("h-auto", "max-w-full", "dark:bg-white");
    expect(image.parentElement).toHaveClass("max-w-md");
    await expectNoAxeViolations(container);
  });

  test("an animated image shows its first frame until play and again after pause", async () => {
    const user = userEvent.setup();
    const { container } = render(
      <FigureBlock block={mediaBlock("figure", animated())} />,
    );

    const image = () =>
      screen.getByRole("img", { name: "A cursor moves through the checklist" });
    expect(image()).toHaveAttribute("src", mediaUrl("f", "webp"));
    await expectNoAxeViolations(container);

    await user.click(screen.getByRole("button", { name: "Play animation" }));
    expect(image()).toHaveAttribute("src", mediaUrl("a", "webp"));
    const pause = screen.getByRole("button", { name: "Pause animation" });
    expect(pause).toHaveFocus();
    await expectNoAxeViolations(container);

    await user.click(pause);
    expect(image()).toHaveAttribute("src", mediaUrl("f", "webp"));
    expect(
      screen.getByRole("button", { name: "Play animation" }),
    ).toBeInTheDocument();
  });

  test("an animated image without a first frame keeps its box until play", async () => {
    const user = userEvent.setup();
    render(
      <FigureBlock
        block={mediaBlock("figure", { ...animated(), poster: null })}
      />,
    );

    expect(screen.queryByRole("img")).toBeNull();
    await user.click(screen.getByRole("button", { name: "Play animation" }));
    expect(
      screen.getByRole("img", { name: "A cursor moves through the checklist" }),
    ).toHaveAttribute("src", mediaUrl("a", "webp"));
  });

  test("a figure without an available image shows a notice", async () => {
    const { container, rerender } = render(
      <FigureBlock
        block={mediaBlock("figure", figureMedia({ available: false }), {
          body: "The caption stays.",
        })}
      />,
    );

    expect(container.querySelector("img")).toBeNull();
    expect(
      screen.getByText("This image is not available on this installation."),
    ).toBeInTheDocument();
    expect(screen.getByText("The caption stays.")).toBeInTheDocument();
    await expectNoAxeViolations(container);

    rerender(<FigureBlock block={mediaBlock("figure", null)} />);
    expect(container.querySelector("img")).toBeNull();
  });

  test("the figure carries the content language and the button the interface language", async () => {
    const program = { ...programFixture(), locale: "de" };
    renderPlayer(<FigureBlock block={mediaBlock("figure", animated())} />, {
      runtime: fakeRuntime({ program }),
    });

    const figure = await screen.findByRole("figure");
    expect(figure).toHaveAttribute("lang", "de");
    expect(
      within(figure).getByRole("button", { name: "Play animation" }),
    ).toHaveAttribute("lang", "en");
  });
});
