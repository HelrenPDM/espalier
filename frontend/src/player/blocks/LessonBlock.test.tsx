import { render } from "@testing-library/react";
import { expect, expectTypeOf, test } from "vitest";
import { figureMedia, mediaBlock, videoMedia } from "../../test/media";
import type { Block } from "../runtime";
import { LessonBlock } from "./LessonBlock";

/**
 * Task 0018 step 18: `LessonBlock` renders a component for every block
 * kind of the API. Its switch ends with `const unknown: never =
 * block.kind`, so a kind without a component fails `tsc`; this list of
 * kinds must equal the union of the API, which the type checks below hold.
 */
const KINDS = [
  "text",
  "explanation",
  "example",
  "case_comparison",
  "quote",
  "callout",
  "placeholder",
  "figure",
  "video",
] as const;

type Listed = (typeof KINDS)[number];

test("the kinds of the test are exactly the block kinds of the API", () => {
  expectTypeOf<Listed>().toEqualTypeOf<Block["kind"]>();
  // @ts-expect-error: a kind outside the API is no block kind.
  const unknown: Block["kind"] = "audio";
  expect(KINDS).not.toContain(unknown);
});

test("renders a component for every kind", () => {
  for (const kind of KINDS) {
    const block: Block =
      kind === "figure"
        ? mediaBlock("figure", figureMedia())
        : kind === "video"
          ? mediaBlock("video", videoMedia())
          : mediaBlock("figure", null, { kind, body: `A ${kind} block.` });
    const { container, unmount } = render(
      <LessonBlock block={block} defaultOpen={false} onToggle={() => {}} />,
    );
    expect(
      container.querySelector(`[data-block-kind="${kind}"]`),
      kind,
    ).not.toBeNull();
    unmount();
  }
});
