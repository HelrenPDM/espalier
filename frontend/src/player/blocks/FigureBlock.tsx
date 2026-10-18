import { PauseIcon, PlayIcon } from "@heroicons/react/20/solid";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { buttonClasses } from "../../app/formStyles";
import { useContentLang } from "../contentLang";
import { Markdown } from "../Markdown";
import type { Block, FigureSize, MediaImage, MediaPoster } from "../runtime";
import { BlockFrame } from "./BlockFrame";

/** The box of each size; a full figure takes the width of the lesson. */
const SIZE_CLASSES: Record<FigureSize, string> = {
  small: "max-w-xs",
  medium: "max-w-md",
  full: "w-full",
};

/**
 * The classes of the `<img>`. An image with transparent pixels and every
 * SVG sit on a light ground in dark mode, so dark lines stay visible.
 */
const imageClasses = (image: MediaImage) =>
  image.has_alpha || image.mime === "image/svg+xml"
    ? "h-auto max-w-full rounded-sm dark:bg-white"
    : "h-auto max-w-full";

/**
 * The `width` and `height` attributes of the `<img>`, which reserve its
 * box before it loads; none for an SVG without a fixed size, which then
 * takes the width of its box.
 */
const sizeAttributes = (image: MediaImage) =>
  image.width !== null && image.height !== null
    ? { width: image.width, height: image.height }
    : {};

/**
 * An animated image (WCAG 2.2 2.2.2): it shows its first frame and a
 * button that swaps to the animation and back. It never starts by itself,
 * whatever `prefers-reduced-motion` says. Without a first frame the box
 * keeps the size of the image until the learner presses play.
 */
function AnimatedImage({
  image,
  poster,
  alt,
}: {
  image: MediaImage;
  poster: MediaPoster | null;
  alt: string;
}) {
  const { t, i18n } = useTranslation();
  const [playing, setPlaying] = useState(false);
  const src = playing ? image.url : (poster?.url ?? null);
  return (
    <>
      {src === null ? (
        <span
          className="block max-w-full bg-gray-100 dark:bg-gray-800"
          style={
            image.width !== null && image.height !== null
              ? {
                  width: image.width,
                  aspectRatio: `${image.width} / ${image.height}`,
                }
              : undefined
          }
        />
      ) : (
        <img
          src={src}
          alt={alt}
          {...sizeAttributes(image)}
          loading="lazy"
          decoding="async"
          className={imageClasses(image)}
        />
      )}
      <button
        type="button"
        lang={i18n.resolvedLanguage}
        onClick={() => setPlaying((current) => !current)}
        className={`no-print mt-2 inline-flex items-center gap-1 ${buttonClasses("secondary")}`}
      >
        {playing ? (
          <PauseIcon aria-hidden="true" className="size-5" />
        ) : (
          <PlayIcon aria-hidden="true" className="size-5" />
        )}
        {playing ? t("media.pause") : t("media.play")}
      </button>
    </>
  );
}

/**
 * An image or an SVG of the pack (task 0018, step 18) in a `<figure>`: the
 * image in a box of its size with its alternative text (empty for a
 * decorative image), and the body of the block as the caption. The figure
 * carries the content language of the pack; the controls keep the
 * language of the interface. An SVG shows only through `<img>`, so none
 * of its content runs in the page (ASVS 1.3.4). Without an available
 * image the figure shows a notice in its place.
 */
export function FigureBlock({ block }: { block: Block }) {
  const { t, i18n } = useTranslation();
  const lang = useContentLang();
  const { media } = block;
  const image = media?.available ? media.image : null;
  const alt = media?.decorative ? "" : (media?.alt ?? "");

  return (
    <BlockFrame block={block} label={t("blocks.figure")}>
      <figure lang={lang}>
        {media === null || image === null ? (
          <p
            lang={i18n.resolvedLanguage}
            className="rounded-md border border-dashed border-gray-400 p-4 text-sm text-gray-700 dark:border-gray-500 dark:text-gray-300"
          >
            {t("media.imageUnavailable")}
          </p>
        ) : (
          <div className={SIZE_CLASSES[media.size ?? "full"]}>
            {image.animated ? (
              <AnimatedImage image={image} poster={media.poster} alt={alt} />
            ) : (
              <img
                src={image.url}
                alt={alt}
                {...sizeAttributes(image)}
                loading="lazy"
                decoding="async"
                className={imageClasses(image)}
              />
            )}
          </div>
        )}
        {block.body.trim() !== "" && (
          <figcaption className="mt-2">
            <Markdown className="text-sm">{block.body}</Markdown>
          </figcaption>
        )}
      </figure>
    </BlockFrame>
  );
}
