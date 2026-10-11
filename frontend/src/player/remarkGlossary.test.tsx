import { render, screen, within } from "@testing-library/react";
import type { Paragraph, Root } from "mdast";
import { describe, expect, test } from "vitest";
import { renderPlayer, SLUG } from "../test/player";
import { Markdown } from "./Markdown";
import {
  GLOSSARY_LABEL_PROPERTY,
  GLOSSARY_SLUG_PROPERTY,
  remarkGlossary,
} from "./remarkGlossary";

/** The short text of `llm` in the glossary of the fixture program. */
const LLM_SHORT = "A program that continues text with likely words.";

const paragraph = (value: string): Root => ({
  type: "root",
  children: [{ type: "paragraph", children: [{ type: "text", value }] }],
});

const transform = (tree: Root) => {
  remarkGlossary()(tree);
  return tree;
};

describe("remarkGlossary on an mdast tree", () => {
  test("both term forms become glossaryTerm nodes with slug and label", () => {
    const tree = transform(
      paragraph("A [[term:llm|language model]] uses [[term:sampling]]."),
    );
    const [first] = tree.children as Paragraph[];

    expect(first.children).toEqual([
      { type: "text", value: "A " },
      {
        type: "glossaryTerm",
        children: [{ type: "text", value: "language model" }],
        data: {
          hName: "span",
          hProperties: {
            [GLOSSARY_SLUG_PROPERTY]: "llm",
            [GLOSSARY_LABEL_PROPERTY]: "language model",
          },
        },
      },
      { type: "text", value: " uses " },
      {
        type: "glossaryTerm",
        children: [{ type: "text", value: "sampling" }],
        data: {
          hName: "span",
          hProperties: {
            [GLOSSARY_SLUG_PROPERTY]: "sampling",
            [GLOSSARY_LABEL_PROPERTY]: "",
          },
        },
      },
      { type: "text", value: "." },
    ]);
  });

  test("a term in a code span or a code block stays text", () => {
    const tree: Root = {
      type: "root",
      children: [
        {
          type: "paragraph",
          children: [{ type: "inlineCode", value: "[[term:llm]]" }],
        },
        { type: "code", lang: null, meta: null, value: "[[term:llm]]" },
      ],
    };
    const before = structuredClone(tree);

    expect(transform(tree)).toEqual(before);
  });

  test("a text without a term stays unchanged", () => {
    const tree = paragraph("No [[term:Upper]] and no [term:llm] here.");
    const before = structuredClone(tree);

    expect(transform(tree)).toEqual(before);
  });
});

describe("glossary terms in Markdown inside a player", () => {
  test("[[term:slug]] renders a button with the glossary label and the short text as description", async () => {
    renderPlayer(<Markdown>{"A [[term:llm]] continues text."}</Markdown>);

    const term = await screen.findByRole("button", { name: "language model" });
    expect(term).toHaveAccessibleDescription(LLM_SHORT);
  });

  test("[[term:slug|label]] renders a button with the given label", async () => {
    renderPlayer(<Markdown>{"A [[term:llm|text model]] writes."}</Markdown>);

    const term = await screen.findByRole("button", { name: "text model" });
    expect(term).toHaveAccessibleDescription(LLM_SHORT);
  });

  test("activating a term navigates to its glossary entry", async () => {
    const { user, location } = renderPlayer(
      <Markdown>{"A [[term:llm]] continues text."}</Markdown>,
    );

    await user.click(
      await screen.findByRole("button", { name: "language model" }),
    );

    expect(location()).toBe(`/programs/${SLUG}/glossary#llm`);
  });

  test("a term activated with the keyboard navigates as well", async () => {
    const { user, location } = renderPlayer(
      <Markdown>{"See [[term:sampling|chance]]."}</Markdown>,
    );
    const term = await screen.findByRole("button", { name: "chance" });

    term.focus();
    await user.keyboard("{Enter}");

    expect(location()).toBe(`/programs/${SLUG}/glossary#sampling`);
  });

  test("a term in a code span stays text", async () => {
    const { container } = renderPlayer(
      <Markdown>{"Write `[[term:llm]]` to link a term."}</Markdown>,
    );

    const code = await screen.findByText("[[term:llm]]");
    expect(code.tagName).toBe("CODE");
    expect(screen.queryByRole("button")).toBeNull();
    expect(container.querySelector("code button")).toBeNull();
  });

  test("a slug that the glossary lacks renders its label as text", async () => {
    renderPlayer(
      <Markdown>
        {"An [[term:unknown-term|unknown word]] stays text."}
      </Markdown>,
    );

    expect(await screen.findByText("unknown word")).toBeInTheDocument();
    expect(screen.queryByRole("button")).toBeNull();
  });

  test("a term inside a link renders as its label without a button", async () => {
    renderPlayer(
      <Markdown>
        {"Read [the [[term:llm|model]] guide](https://example.org/guide)."}
      </Markdown>,
    );

    const link = await screen.findByRole("link", { name: "the model guide" });
    expect(within(link).queryByRole("button")).toBeNull();
    expect(screen.queryByRole("button")).toBeNull();
  });

  test("a script tag next to a term produces no element (ASVS 1.3.5)", async () => {
    const { container } = renderPlayer(
      <Markdown>
        {"A [[term:llm]] here.\n\n<script>window.injected = 1</script>\n\nEnd."}
      </Markdown>,
    );

    await screen.findByRole("button", { name: "language model" });
    expect(container.querySelector("script")).toBeNull();
    expect(
      (window as unknown as Record<string, unknown>).injected,
    ).toBeUndefined();
  });
});

describe("glossary terms in Markdown outside a player", () => {
  test("both term forms render their label as plain text", () => {
    const { container } = render(
      <Markdown>
        {"A [[term:llm]] and a [[term:sampling|chance choice]]."}
      </Markdown>,
    );

    expect(screen.queryByRole("button")).toBeNull();
    expect(container).toHaveTextContent("A llm and a chance choice.");
    expect(screen.getByText("chance choice").tagName).toBe("SPAN");
  });

  test("a script tag in the body produces no element", () => {
    const { container } = render(
      <Markdown>{"Text.\n\n<script>alert(1)</script>"}</Markdown>,
    );

    expect(container.querySelector("script")).toBeNull();
  });
});
