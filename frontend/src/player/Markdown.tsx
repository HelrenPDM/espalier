import type { ComponentProps } from "react";
import ReactMarkdown, {
  type Components,
  type ExtraProps,
} from "react-markdown";
import remarkGfm from "remark-gfm";
import { useContentLang } from "./contentLang";
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

const components: Components = { span: Span };
const remarkPlugins = [remarkGfm, remarkGlossary];
const caseRemarkPlugins = [...remarkPlugins, remarkCaseColumns];

/**
 * Renders the Markdown of lessons, the handbook and policies (ASVS 1.3.5)
 * with the `prose` classes of `@tailwindcss/typography`. Raw HTML stays
 * disabled: the renderer runs without `rehype-raw`, so an HTML tag in the
 * text produces no element. It passes no `urlTransform`, so the default
 * transform of `react-markdown` replaces a link target with an unsafe
 * protocol, such as `javascript:`, by an empty string (ASVS 1.2.2).
 * `[[term:slug]]` and `[[term:slug|label]]` render as `GlossaryTerm`.
 * `caseColumns` lays the cases of a case comparison out in two columns.
 * Inside a player the text carries the language of the program.
 */
export function Markdown({
  children,
  className = "",
  caseColumns = false,
}: {
  children: string;
  className?: string;
  caseColumns?: boolean;
}) {
  const lang = useContentLang();
  return (
    <div
      lang={lang}
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
