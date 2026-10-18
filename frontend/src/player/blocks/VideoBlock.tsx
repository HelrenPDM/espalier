import {
  Disclosure,
  DisclosureButton,
  DisclosurePanel,
} from "@headlessui/react";
import { ChevronDownIcon, FilmIcon } from "@heroicons/react/20/solid";
import { useEffect, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import { buttonClasses, FOCUS_RING, linkClasses } from "../../app/formStyles";
import { useContentLang } from "../contentLang";
import { agreeToEmbed, useEmbedAgreed, useEmbedConsent } from "../embedConsent";
import { safeMediaUrl } from "../format";
import { Markdown } from "../Markdown";
import type { Block, MediaCaption, MediaPoster, MediaVideo } from "../runtime";
import { BlockFrame } from "./BlockFrame";

/** The attributes of the iframe of an embed player (task 0018, step 18). */
const EMBED_SANDBOX =
  "allow-scripts allow-same-origin allow-presentation allow-popups allow-popups-to-escape-sandbox";
const EMBED_ALLOW = "fullscreen; picture-in-picture; encrypted-media";

/** The name of the language `tag` in the language of the interface. */
function languageName(tag: string, language: string): string {
  try {
    return (
      new Intl.DisplayNames([language], { type: "language" }).of(tag) ?? tag
    );
  } catch {
    return tag;
  }
}

function Unavailable() {
  const { t } = useTranslation();
  return (
    <p className="rounded-md border border-dashed border-gray-400 p-4 text-sm text-gray-700 dark:border-gray-500 dark:text-gray-300">
      {t("media.unavailable")}
    </p>
  );
}

/**
 * A video file with the controls of the browser. A file of the pack loads
 * its metadata with the page; an external file loads nothing before the
 * learner presses play (`preload="none"`) and names its host. Captions
 * become `<track>` elements, the first one the default. Nothing plays by
 * itself (WCAG 2.2 2.2.2).
 */
function VideoFile({
  video,
  src,
  poster,
  captions,
}: {
  video: MediaVideo;
  /** `video.url`, for an external file after `safeMediaUrl`. */
  src: string;
  poster: MediaPoster | null;
  captions: MediaCaption[];
}) {
  const { t, i18n } = useTranslation();
  const language = i18n.resolvedLanguage ?? "en";
  return (
    <>
      <video
        controls
        preload={video.external ? "none" : "metadata"}
        playsInline
        poster={poster?.url}
        width={video.width ?? undefined}
        height={video.height ?? undefined}
        className={`h-auto w-full rounded-md bg-black ${video.width === null || video.height === null ? "aspect-video" : ""}`}
      >
        <source src={src} type={video.mime} />
        {captions.map((caption, index) => (
          <track
            key={`${caption.lang}-${caption.url}`}
            kind="captions"
            src={caption.url}
            srcLang={caption.lang}
            label={languageName(caption.lang, language)}
            default={index === 0}
          />
        ))}
        {t("media.fallback")}
      </video>
      {video.external && (
        <p className="mt-2 text-sm text-gray-700 dark:text-gray-300">
          {t("media.playsFrom", { host: new URL(src).host })}
        </p>
      )}
    </>
  );
}

/**
 * The player of a streaming service in a sandboxed iframe. With the
 * consent setting `click` it first shows a notice that names the host,
 * because loading the player sends the address of the device and browser
 * data there, with "Load video" and a link that opens the player in a new
 * tab. After "Load video", or at once with `auto` or once the learner
 * agreed to the host on this page, the iframe loads.
 */
function EmbedPlayer({ src, title }: { src: string; title: string }) {
  const { t } = useTranslation();
  const consent = useEmbedConsent();
  const host = new URL(src).host;
  const agreed = useEmbedAgreed(host);
  const [clicked, setClicked] = useState(false);
  const frame = useRef<HTMLIFrameElement>(null);

  // The button that took the focus is gone; the player takes it.
  useEffect(() => {
    if (clicked) frame.current?.focus();
  }, [clicked]);

  if (consent === "auto" || agreed)
    return (
      <div className="aspect-video w-full">
        <iframe
          ref={frame}
          src={src}
          title={title}
          sandbox={EMBED_SANDBOX}
          allow={EMBED_ALLOW}
          referrerPolicy="strict-origin-when-cross-origin"
          loading="lazy"
          className="size-full rounded-md border-0"
        />
      </div>
    );

  return (
    <div className="no-print rounded-md border border-gray-300 bg-gray-50 p-4 dark:border-gray-700 dark:bg-gray-900">
      <p className="text-sm text-gray-800 dark:text-gray-200">
        {t("media.embedNotice", { host })}
      </p>
      <div className="mt-3 flex flex-wrap items-center gap-x-4 gap-y-2">
        <button
          type="button"
          onClick={() => {
            setClicked(true);
            agreeToEmbed(host);
          }}
          className={buttonClasses("primary")}
        >
          {t("media.loadVideo")}
        </button>
        <a
          href={src}
          target="_blank"
          rel="noopener noreferrer"
          className={`text-sm ${linkClasses}`}
        >
          {t("media.openOn", { host })}
        </a>
      </div>
    </div>
  );
}

/**
 * A video (task 0018, step 18): a file of the pack, an external file on an
 * allowlisted host, or the player of a streaming service, with the title
 * as the label. An external URL reaches the page only through
 * `safeMediaUrl` (ASVS 1.2.2); a rejected URL and `available: false` show
 * a notice in place of the video. A non-empty body is the transcript in a
 * disclosure, closed at the start. In print the video gives way to the
 * line "Video: see the online lesson".
 */
export function VideoBlock({ block }: { block: Block }) {
  const { t } = useTranslation();
  const lang = useContentLang();
  const { media } = block;
  const title = media?.title ?? null;

  let content = <Unavailable />;
  if (media !== null && media.available) {
    if (media.embed !== null) {
      const src = safeMediaUrl(media.embed.url);
      if (src !== null)
        content = <EmbedPlayer src={src} title={title ?? t("blocks.video")} />;
    } else if (media.video !== null) {
      const src = media.video.external
        ? safeMediaUrl(media.video.url)
        : media.video.url;
      if (src !== null)
        content = (
          <VideoFile
            video={media.video}
            src={src}
            poster={media.poster}
            captions={media.captions}
          />
        );
    }
  }

  return (
    <BlockFrame
      block={block}
      label={
        <span className="inline-flex items-center gap-1">
          <FilmIcon aria-hidden="true" className="size-5 shrink-0" />
          {title === null ? (
            t("blocks.video")
          ) : (
            <>
              <span className="sr-only">{`${t("blocks.video")}: `}</span>
              <span lang={lang}>{title}</span>
            </>
          )}
        </span>
      }
    >
      {content}
      <p className="hidden text-sm print:block">{t("media.printNote")}</p>
      {block.body.trim() !== "" && (
        <Disclosure
          as="div"
          className="mt-3 rounded-md border border-gray-300 dark:border-gray-700"
        >
          {({ open }) => (
            <>
              <DisclosureButton
                className={`flex min-h-6 w-full items-center gap-1 rounded-md px-4 py-2 text-left text-sm font-semibold text-gray-900 hover:text-accent-700 dark:text-gray-100 dark:hover:text-accent-100 ${FOCUS_RING}`}
              >
                <ChevronDownIcon
                  aria-hidden="true"
                  className={`size-5 transition-transform ${open ? "rotate-180" : ""}`}
                />
                {t("media.transcript")}
              </DisclosureButton>
              <DisclosurePanel className="px-4 pb-4">
                <Markdown>{block.body}</Markdown>
              </DisclosurePanel>
            </>
          )}
        </Disclosure>
      )}
    </BlockFrame>
  );
}
