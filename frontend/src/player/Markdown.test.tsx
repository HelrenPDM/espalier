import { render, screen } from "@testing-library/react";
import { describe, expect, test } from "vitest";
import { ExternalLinkTargetContext } from "./externalLinks";
import { Markdown } from "./Markdown";

/** Every `href` and `src` in `container`. */
const urls = (container: Element) =>
  [...container.querySelectorAll("[href], [src]")].flatMap((element) =>
    ["href", "src"].flatMap((name) => {
      const value = element.getAttribute(name);
      return value === null ? [] : [value];
    }),
  );

describe("Markdown", () => {
  test("wraps its output in the prose classes and adds className", () => {
    const { container } = render(
      <Markdown className="mt-2">{"Some **bold** text."}</Markdown>,
    );

    const wrapper = container.firstElementChild;
    expect(wrapper).toHaveClass("prose", "dark:prose-invert", "mt-2");
    expect(screen.getByText("bold").tagName).toBe("STRONG");
  });

  test("renders GitHub tables through remark-gfm", () => {
    render(<Markdown>{"| A | B |\n|---|---|\n| 1 | 2 |"}</Markdown>);

    expect(screen.getByRole("table")).toBeInTheDocument();
    expect(screen.getAllByRole("columnheader")).toHaveLength(2);
  });
});

describe("Markdown without raw HTML (ASVS 1.3.5)", () => {
  test("a script tag produces no script element", () => {
    const { container } = render(
      <Markdown>
        {
          "Before.\n\n<script>alert(1)</script>\n\nInline <script>alert(2)</script> too."
        }
      </Markdown>,
    );

    expect(container.querySelector("script")).toBeNull();
    expect(screen.getByText("Before.")).toBeInTheDocument();
  });

  test("an img tag with an event handler produces no img element", () => {
    const { container } = render(
      <Markdown>
        {
          "<img src=x onerror=alert(1)>\n\nText <img src=y onerror=alert(2)> inline."
        }
      </Markdown>,
    );

    expect(container.querySelector("img")).toBeNull();
    expect(container.querySelector("[onerror]")).toBeNull();
  });

  test("an inline Markdown image renders its alternative text in a span and no img element (task 0018)", () => {
    const { container } = render(
      <Markdown>
        {
          "Before ![A chart of the checks](https://example.org/chart.png) after.\n\n![](media/photo.webp)\n\n![Reference image][ref]\n\n[ref]: https://example.org/ref.png"
        }
      </Markdown>,
    );

    expect(container.querySelector("img")).toBeNull();
    expect(container.querySelector("[src]")).toBeNull();
    const text = screen.getByText("A chart of the checks");
    expect(text.tagName).toBe("SPAN");
    expect(text.parentElement).toHaveTextContent(
      "Before A chart of the checks after.",
    );
    expect(screen.getByText("Reference image").tagName).toBe("SPAN");
  });

  test("other raw HTML tags produce no element", () => {
    const { container } = render(
      <Markdown>
        {
          '<a href="javascript:alert(1)">x</a>\n\n<iframe src="https://example.org"></iframe>\n\n<div onclick="alert(1)">y</div>'
        }
      </Markdown>,
    );

    expect(container.querySelector("a, iframe, [onclick]")).toBeNull();
    expect(container.querySelectorAll("div")).toHaveLength(1);
  });
});

describe("Markdown link targets (ASVS 1.2.2)", () => {
  test("a javascript: link renders no javascript: href", () => {
    const { container } = render(
      <Markdown>{"[x](javascript:alert(1))"}</Markdown>,
    );

    expect(screen.getByText("x")).toBeInTheDocument();
    expect(container.querySelector('[href^="javascript:" i]')).toBeNull();
    for (const url of urls(container))
      expect(url).not.toMatch(/^\s*javascript:/i);
  });

  test("unsafe protocols in every link form render no unsafe target", () => {
    const { container } = render(
      <Markdown>
        {[
          "[upper](JavaScript:alert(1))",
          "[encoded](jav&#x61;script:alert(1))",
          "[vb](vbscript:msgbox(1))",
          "[data](data:text/html;base64,PHNjcmlwdD4=)",
          "<javascript:alert(1)>",
          "[ref][unsafe]",
          "![image](javascript:alert(1))",
          "",
          "[unsafe]: javascript:alert(1)",
        ].join("\n\n")}
      </Markdown>,
    );

    const all = urls(container);
    expect(all.length).toBeGreaterThan(0);
    for (const url of all)
      expect(url).not.toMatch(/^\s*(javascript|vbscript|data):/i);
  });

  test("a safe link keeps its target", () => {
    render(
      <Markdown>
        {
          "[guide](https://example.org/guide) and [mail](mailto:a@example.org) and [page](/programs/demo)"
        }
      </Markdown>,
    );

    expect(screen.getByRole("link", { name: "guide" })).toHaveAttribute(
      "href",
      "https://example.org/guide",
    );
    expect(screen.getByRole("link", { name: "mail" })).toHaveAttribute(
      "href",
      "mailto:a@example.org",
    );
    expect(screen.getByRole("link", { name: "page" })).toHaveAttribute(
      "href",
      "/programs/demo",
    );
  });
});

describe("Markdown links that leave the page (ExternalLinkTargetContext)", () => {
  const body = [
    "[guide](https://example.org/guide), [page](/programs/demo),",
    "https://example.org/plain, [section](#lesson-intro) and",
    "[mail](mailto:a@example.org).",
  ].join("\n");

  test("without a provider, no link gets a target or a rel", () => {
    const { container } = render(<Markdown>{body}</Markdown>);

    expect(container.querySelectorAll("a")).toHaveLength(5);
    expect(container.querySelector("[target], [rel]")).toBeNull();
  });

  test('with "_blank", a link that leaves the page opens in a new tab', () => {
    render(
      <ExternalLinkTargetContext.Provider value="_blank">
        <Markdown>{body}</Markdown>
      </ExternalLinkTargetContext.Provider>,
    );

    for (const name of ["guide", "page", "https://example.org/plain"]) {
      const link = screen.getByRole("link", { name });
      expect(link).toHaveAttribute("target", "_blank");
      expect(link).toHaveAttribute("rel", "noopener noreferrer");
    }
    expect(screen.getByRole("link", { name: "guide" })).toHaveAttribute(
      "href",
      "https://example.org/guide",
    );
    for (const name of ["section", "mail"]) {
      const link = screen.getByRole("link", { name });
      expect(link).not.toHaveAttribute("target");
      expect(link).not.toHaveAttribute("rel");
    }
  });

  // react-markdown empties a target with an unknown or unsafe scheme, and
  // href="" would reload the SCO document and end the LMS session.
  const emptied = "[empty]() [phone](tel:+49301234) [script](javascript:x)";

  test('with "_blank", a link whose target was emptied renders without href', () => {
    const { container } = render(
      <ExternalLinkTargetContext.Provider value="_blank">
        <Markdown>{emptied}</Markdown>
      </ExternalLinkTargetContext.Provider>,
    );

    const anchors = [...container.querySelectorAll("a")];
    expect(anchors.map((anchor) => anchor.textContent)).toEqual([
      "empty",
      "phone",
      "script",
    ]);
    for (const anchor of anchors) {
      expect(anchor).not.toHaveAttribute("href");
      expect(anchor).not.toHaveAttribute("target");
    }
  });

  test('without a provider, a link whose target was emptied keeps href=""', () => {
    const { container } = render(<Markdown>{emptied}</Markdown>);

    const anchors = [...container.querySelectorAll("a")];
    expect(anchors).toHaveLength(3);
    for (const anchor of anchors) expect(anchor).toHaveAttribute("href", "");
  });
});

describe("Markdown with caseColumns (remarkCaseColumns)", () => {
  const twoCases = "**Draft A**\n\nA\n\n**Draft B**\n\nB\n\nRest";

  test("puts two cases into a two-column grid and leaves the rest outside", () => {
    const { container } = render(<Markdown caseColumns>{twoCases}</Markdown>);

    const grids = container.querySelectorAll(".md\\:grid-cols-2");
    expect(grids).toHaveLength(1);
    const [grid] = grids;
    expect(grid).toHaveClass("grid");

    const columns = [...grid.children];
    expect(columns).toHaveLength(2);
    expect(columns[0]).toHaveTextContent(/^Draft A\s*A$/);
    expect(columns[1]).toHaveTextContent(/^Draft B\s*B$/);
    expect(columns[0].querySelector("strong")).toHaveTextContent("Draft A");
    expect(columns[1].querySelector("strong")).toHaveTextContent("Draft B");

    const rest = screen.getByText("Rest");
    expect(grid.contains(rest)).toBe(false);
    expect(
      grid.compareDocumentPosition(rest) & Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
  });

  test("keeps text before the first case outside the grid", () => {
    const { container } = render(
      <Markdown caseColumns>{`Intro\n\n${twoCases}`}</Markdown>,
    );

    const grid = container.querySelector(".md\\:grid-cols-2");
    expect(grid).not.toBeNull();
    expect(grid?.contains(screen.getByText("Intro"))).toBe(false);
    expect(grid?.children).toHaveLength(2);
  });

  test("a body with one bold label keeps its flow", () => {
    const { container } = render(
      <Markdown caseColumns>{"**Draft A**\n\nA\n\nRest"}</Markdown>,
    );

    expect(container.querySelector(".md\\:grid-cols-2")).toBeNull();
    const prose = container.firstElementChild;
    expect([...(prose?.children ?? [])].map((child) => child.tagName)).toEqual([
      "P",
      "P",
      "P",
    ]);
  });

  test("without caseColumns, two cases keep their flow", () => {
    const { container } = render(<Markdown>{twoCases}</Markdown>);

    expect(container.querySelector(".md\\:grid-cols-2")).toBeNull();
    expect(container.querySelectorAll("p")).toHaveLength(5);
  });
});
