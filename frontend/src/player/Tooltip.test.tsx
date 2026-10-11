import { act, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { Tooltip } from "./Tooltip";

function renderTooltip() {
  render(
    <Tooltip text="A program that continues text." lang="de">
      {(describedBy) => (
        <button type="button" aria-describedby={describedBy}>
          term
        </button>
      )}
    </Tooltip>,
  );
  return screen.getByRole("button", { name: "term" });
}

/** Lets the bubble measure `left` and `right` in a viewport `width` wide. */
function layout(left: number, right: number, width: number) {
  vi.spyOn(document.documentElement, "clientWidth", "get").mockReturnValue(
    width,
  );
  vi.spyOn(HTMLElement.prototype, "getBoundingClientRect").mockReturnValue(
    DOMRect.fromRect({ x: left, y: 0, width: right - left, height: 40 }),
  );
}

afterEach(() => {
  vi.restoreAllMocks();
});

test("a bubble that would cross the right edge moves left into the viewport", () => {
  layout(300, 500, 360);
  const trigger = renderTooltip();

  act(() => trigger.focus());

  // 500 - (360 - 8) = 148, and the bubble keeps 8 pixels to the left edge.
  expect(screen.getByTestId("tooltip")).toHaveStyle({
    transform: "translateX(-148px)",
  });
});

test("a bubble that fits stays at the trigger", () => {
  layout(20, 200, 360);
  const trigger = renderTooltip();

  act(() => trigger.focus());

  expect(screen.getByTestId("tooltip").style.transform).toBe("");
});

test("a bubble never moves past the left edge", () => {
  layout(30, 600, 360);
  const trigger = renderTooltip();

  act(() => trigger.focus());

  expect(screen.getByTestId("tooltip")).toHaveStyle({
    transform: "translateX(-22px)",
  });
});

test("the description and the bubble carry the language of the text", () => {
  const trigger = renderTooltip();
  fireEvent.focus(trigger);

  expect(trigger).toHaveAccessibleDescription("A program that continues text.");
  const description = document.getElementById(
    trigger.getAttribute("aria-describedby")!,
  );
  expect(description).toHaveAttribute("lang", "de");
  expect(screen.getByTestId("tooltip").querySelector("[lang]")).toHaveAttribute(
    "lang",
    "de",
  );
});
