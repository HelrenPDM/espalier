import type { Root, RootContent } from "mdast";

/** A top-level paragraph that holds only bold text, such as `**Draft A**`. */
function isCaseLabel(node: RootContent): boolean {
  if (node.type !== "paragraph") return false;
  const children = node.children.filter(
    (child) => !(child.type === "text" && child.value.trim() === ""),
  );
  return children.length === 1 && children[0].type === "strong";
}

const element = (className: string[], children: RootContent[]) =>
  ({
    type: "caseColumns",
    children,
    data: { hName: "div", hProperties: { className } },
  }) as unknown as RootContent;

/**
 * The two-column layout of a `case_comparison` block: a case starts at a
 * paragraph that holds only bold text, and each case spans as many
 * top-level elements as the first one. The cases stand side by side on wide
 * screens and stacked on narrow ones; the text before the first case and
 * after the last stays full width. A body with fewer than two cases keeps
 * its flow.
 */
export function remarkCaseColumns() {
  return (tree: Root) => {
    const nodes = tree.children;
    const starts = nodes.flatMap((node, index) =>
      isCaseLabel(node) ? [index] : [],
    );
    if (starts.length < 2) return;
    const length = starts[1] - starts[0];
    const cases = starts.map((start, index) =>
      nodes.slice(
        start,
        index + 1 < starts.length
          ? starts[index + 1]
          : Math.min(start + length, nodes.length),
      ),
    );
    const end = starts[starts.length - 1] + cases[cases.length - 1].length;
    tree.children = [
      ...nodes.slice(0, starts[0]),
      element(
        ["grid", "gap-4", "md:grid-cols-2", "my-4"],
        cases.map((column) =>
          element(
            [
              "rounded-md",
              "border",
              "border-gray-200",
              "px-4",
              "dark:border-gray-700",
            ],
            column,
          ),
        ),
      ),
      ...nodes.slice(end),
    ];
  };
}
