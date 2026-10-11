import type { Data, Nodes, Parent, PhrasingContent, Root, Text } from "mdast";

/** The element that `Markdown` renders as `GlossaryTerm`. */
export const GLOSSARY_SLUG_PROPERTY = "dataGlossarySlug";
export const GLOSSARY_LABEL_PROPERTY = "dataGlossaryLabel";

interface GlossaryTermData extends Data {
  hName: "span";
  hProperties: Record<string, string>;
}

/** `[[term:slug]]` or `[[term:slug|label]]` (README section 7, rule 9). */
export interface GlossaryTermNode extends Parent {
  type: "glossaryTerm";
  children: Text[];
  data: GlossaryTermData;
}

declare module "mdast" {
  interface PhrasingContentMap {
    glossaryTerm: GlossaryTermNode;
  }
  interface RootContentMap {
    glossaryTerm: GlossaryTermNode;
  }
}

// The slug follows the key format of content packs (0009 addendum).
const TERM = /\[\[term:([a-z0-9][a-z0-9-]*)(?:\|([^\]\n]*))?\]\]/g;

function termNode(slug: string, label: string | null): GlossaryTermNode {
  return {
    type: "glossaryTerm",
    children: [{ type: "text", value: label ?? slug }],
    data: {
      hName: "span",
      hProperties: {
        [GLOSSARY_SLUG_PROPERTY]: slug,
        [GLOSSARY_LABEL_PROPERTY]: label ?? "",
      },
    },
  };
}

/**
 * Splits a text node at every term. Inside a link, a term becomes its label
 * as text, because a link holds no button.
 */
function splitText(node: Text, insideLink: boolean): PhrasingContent[] | null {
  const parts: PhrasingContent[] = [];
  let last = 0;
  for (const match of node.value.matchAll(TERM)) {
    const [whole, slug, rawLabel] = match;
    const label = rawLabel?.trim() || null;
    if (match.index > last)
      parts.push({ type: "text", value: node.value.slice(last, match.index) });
    parts.push(
      insideLink
        ? { type: "text", value: label ?? slug }
        : termNode(slug, label),
    );
    last = match.index + whole.length;
  }
  if (last === 0) return null;
  if (last < node.value.length)
    parts.push({ type: "text", value: node.value.slice(last) });
  return parts;
}

function walk(node: Nodes, insideLink: boolean): void {
  if (!("children" in node)) return;
  const children = node.children as Nodes[];
  for (let index = 0; index < children.length; index++) {
    const child = children[index];
    if (child.type === "text") {
      const parts = splitText(child, insideLink);
      if (parts === null) continue;
      children.splice(index, 1, ...parts);
      index += parts.length - 1;
    } else {
      // Code spans and code blocks carry `value` and no children, so a term
      // inside them stays text.
      walk(
        child,
        insideLink || child.type === "link" || child.type === "linkReference",
      );
    }
  }
}

/**
 * The remark plugin of the glossary: it turns `[[term:slug]]` and
 * `[[term:slug|label]]` into a `span` element with the slug and the label,
 * which `Markdown` renders as `GlossaryTerm`.
 */
export function remarkGlossary() {
  return (tree: Root) => {
    walk(tree, false);
  };
}
