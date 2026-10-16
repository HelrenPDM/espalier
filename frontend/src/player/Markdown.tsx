import type { ComponentProps } from "react";
import ReactMarkdown, {
  type Components,
  type ExtraProps,
} from "react-markdown";
import remarkGfm from "remark-gfm";
import { useContentLang } from "./contentLang";
import { leavesPage, useExternalLinkTarget } from "./externalLinks";
import { GlossaryTerm } from "./GlossaryTerm";
import { remarkCaseColumns } from "./remarkCaseColumns";
import {
  GLOSSARY_LABEL_PROPERTY,
  GLOSSARY_SLUG_PROPERTY,
  remarkGlossary,
} from "./remarkGlossary";

function Span({ node, ...props }: ComponentProps<"span"> & ExtraProps) {
  const slug = node?.properties[GLOSSARY_SLUG_PROPERTY];
  if (typeof slug !== "string") return <span {...props} />;
  const label = node?.properties[GLOSSARY_LABEL_PROPERTY];
  return (
    <GlossaryTerm
      slug={slug}
      label={typeof label === "string" && label !== "" ? label : null}
    />
  );
}

/**
 * A link of the text. A link that leaves the page opens in the target of
 * `ExternalLinkTargetContext`, when one is set, without access to the page
 * (`noopener noreferrer`); a fragment of the page keeps its default. With a
 * target set, a link without a target URL renders without `href`: the
 * default `urlTransform` empties an unsafe or unknown scheme (`tel:`,
 * `javascript:`), and `href=""` would reload the document, which fires
 * `pagehide` and ends the LMS session of a SCORM package.
 */
function Anchor({ node: _node, ...props }: ComponentProps<"a"> & ExtraProps) {
  const target = useExternalLinkTarget();
  if (target === undefined) return <a {...props} />;
  if (props.href === undefined || props.href === "") {
    const { href: _href, ...rest } = props;
    return <a {...rest} />;
  }
  if (!leavesPage(props.href)) return <a {...props} />;
  return <a {...props} target={target} rel="noopener noreferrer" />;
}

/**
 * An inline Markdown image (`![alt](src)`) of older text renders as its
 * alternative text, so no `img` element comes from Markdown (ASVS 1.3.5);
 * a lesson places an image with a `figure` block (task 0018).
 */
function ImageText({ alt }: ComponentProps<"img"> & ExtraProps) {
  return <span>{alt}</span>;
}

const components: Components = { a: Anchor, span: Span, img: ImageText };
const remarkPlugins = [remarkGfm, remarkGlossary];
const caseRemarkPlugins = [...remarkPlugins, remarkCaseColumns];

/**
 * Renders the Markdown of lessons, the handbook and policies (ASVS 1.3.5)
 * with the `prose` classes of `@tailwindcss/typography`. Raw HTML stays
 * disabled: the renderer runs without `rehype-raw`, so an HTML tag in the
 * text produces no element. It passes no `urlTransform`, so the default
 * transform of `react-markdown` replaces a link target with an unsafe
 * protocol, such as `javascript:`, by an empty string (ASVS 1.2.2).
 * An inline image renders as a `<span>` with its alternative text.
 * `[[term:slug]]` and `[[term:slug|label]]` render as `GlossaryTerm`.
 * `caseColumns` lays the cases of a case comparison out in two columns. A
 * link that leaves the page opens in the target of
 * `ExternalLinkTargetContext`, which the SCORM package sets to `"_blank"`.
 *
 * Without `lang`, the text carries the language of the program inside a
 * player, because pack text is written in the language of the pack. A
 * string as `lang` sets that language instead. `null` renders no `lang`,
 * so the text inherits the language of the document; text of the
 * organization, such as the body of a policy, passes `null`, because the
 * organization writes it independently of the language of the pack.
 */
export function Markdown({
  children,
  className = "",
  caseColumns = false,
  lang,
}: {
  children: string;
  className?: string;
  caseColumns?: boolean;
  lang?: string | null;
}) {
  const contentLang = useContentLang();
  return (
    <div
      lang={lang === undefined ? contentLang : (lang ?? undefined)}
      className={`prose prose-gray max-w-none dark:prose-invert ${className}`}
    >
      <ReactMarkdown
        remarkPlugins={caseColumns ? caseRemarkPlugins : remarkPlugins}
        components={components}
      >
        {children}
      </ReactMarkdown>
    </div>
  );
}
