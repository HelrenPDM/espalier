import { fireEvent, render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useState } from "react";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { PackFileEditor, type GoTo } from "./PackFileEditor";

// The view of CodeMirror lives in a shadow root of the frame (see the
// moduledoc of PackFileEditor), which the queries of `screen` do not enter.
// user-event collects the controls for Tab with `document.querySelectorAll`,
// which does not enter it either, so these tests check that the editor
// leaves Tab to the browser; editor-csp.spec.ts (Playwright) checks that
// Tab and Shift+Tab move the focus out of the editor.
//
// jsdom reports the vendor of Safari, so CodeMirror reads the selection in a
// shadow root through `document.execCommand`, which jsdom lacks. The stub
// answers that the command is not supported, and CodeMirror falls back to
// the selection of the document.
beforeAll(() => {
  Object.defineProperty(document, "execCommand", {
    configurable: true,
    value: () => false,
  });
});
afterAll(() => {
  Reflect.deleteProperty(document, "execCommand");
});

const LABEL = "Content of modules/01-first-module/objectives.yaml";
const TEXT = "- key: m1-subject\n  area: subject\n  depth: know\n";

interface HarnessProps {
  value?: string;
  onChange?: (value: string) => void;
  onSave?: () => void;
  onCursor?: (line: number, column: number) => void;
}

function Harness({
  value = TEXT,
  onChange = () => {},
  onSave = () => {},
  onCursor = () => {},
}: HarnessProps) {
  const [goTo, setGoTo] = useState<GoTo | null>(null);
  return (
    <>
      <button type="button" onClick={() => setGoTo({ line: 3 })}>
        Go to line 3
      </button>
      <PackFileEditor
        value={value}
        onChange={onChange}
        language="yaml"
        label={LABEL}
        onSave={onSave}
        onCursor={onCursor}
        goTo={goTo}
      />
      <button type="button">Next</button>
    </>
  );
}

/** The frame of the editor, the host of its shadow root. */
function frameOf(
  container: HTMLElement,
): HTMLElement & { shadowRoot: ShadowRoot } {
  const frame = Array.from(container.querySelectorAll("div")).find(
    (element) => element.shadowRoot !== null,
  );
  if (frame?.shadowRoot == null) throw new Error("The editor has no frame.");
  return frame as HTMLElement & { shadowRoot: ShadowRoot };
}

/** The content element of the editor in the shadow root of its frame. */
function editorOf(container: HTMLElement): HTMLElement {
  return within(
    frameOf(container).shadowRoot as unknown as HTMLElement,
  ).getByRole("textbox", { name: LABEL });
}

const linesOf = (editor: HTMLElement) =>
  Array.from(editor.querySelectorAll(".cm-line")).map(
    (line) => line.textContent,
  );

describe("PackFileEditor", () => {
  it("is a multi-line textbox with the accessible name of its label", () => {
    const { container } = render(<Harness />);
    const editor = editorOf(container);

    expect(editor).toHaveAttribute("aria-multiline", "true");
    expect(editor).toHaveAccessibleName(LABEL);
    expect(linesOf(editor)).toEqual([
      "- key: m1-subject",
      "  area: subject",
      "  depth: know",
      "",
    ]);
  });

  it("leaves Tab and Shift+Tab to the browser, so they move the focus", () => {
    const onChange = vi.fn();
    const { container } = render(<Harness onChange={onChange} />);
    const editor = editorOf(container);

    // fireEvent returns false when a handler prevents the default action.
    expect(fireEvent.keyDown(editor, { key: "Tab", code: "Tab" })).toBe(true);
    expect(
      fireEvent.keyDown(editor, { key: "Tab", code: "Tab", shiftKey: true }),
    ).toBe(true);
    expect(onChange).not.toHaveBeenCalled();
    expect(linesOf(editor)[0]).toBe("- key: m1-subject");
  });

  it("indents the line with Ctrl+] and dedents it with Ctrl+[", () => {
    const onChange = vi.fn();
    const { container } = render(<Harness onChange={onChange} />);
    const editor = editorOf(container);

    expect(
      fireEvent.keyDown(editor, {
        key: "]",
        code: "BracketRight",
        ctrlKey: true,
      }),
    ).toBe(false);
    expect(linesOf(editor)[0]).toBe("  - key: m1-subject");
    expect(onChange).toHaveBeenLastCalledWith(`  ${TEXT}`);

    fireEvent.keyDown(editor, { key: "[", code: "BracketLeft", ctrlKey: true });
    expect(linesOf(editor)[0]).toBe("- key: m1-subject");
    expect(onChange).toHaveBeenLastCalledWith(TEXT);
  });

  it("calls onSave on Ctrl+S and prevents the save dialog of the browser", () => {
    const onSave = vi.fn();
    const { container } = render(<Harness onSave={onSave} />);
    const editor = editorOf(container);

    expect(
      fireEvent.keyDown(editor, { key: "s", code: "KeyS", ctrlKey: true }),
    ).toBe(false);
    expect(onSave).toHaveBeenCalledTimes(1);
  });

  it("moves the cursor to the start of the line of goTo", async () => {
    const user = userEvent.setup();
    const onCursor = vi.fn();
    render(<Harness onCursor={onCursor} />);

    await user.click(screen.getByRole("button", { name: "Go to line 3" }));

    expect(onCursor).toHaveBeenLastCalledWith(3, 1);
  });

  it("keeps the tab stop on the content, which the scroller leaves out", () => {
    const { container } = render(<Harness />);
    const editor = editorOf(container);

    // axe counts no contenteditable element as focusable; with tabindex 0
    // the scroller of a file taller than the frame holds a focusable element.
    expect(editor).toHaveAttribute("tabindex", "0");
    expect(
      frameOf(container).shadowRoot.querySelector(".cm-scroller"),
    ).toHaveAttribute("tabindex", "-1");
  });

  it("moves a focus of its frame to the content, as a closing dialog gives it", () => {
    const attach = vi.spyOn(Element.prototype, "attachShadow");
    const { container } = render(<Harness />);
    const editor = editorOf(container);
    const { shadowRoot } = frameOf(container);

    // The shadow root delegates a focus of the frame, such as the focus that
    // a Headless UI dialog returns to the element it recorded, into the
    // shadow tree. jsdom does not delegate; Chromium focuses the scroller,
    // the first focusable element there, and the editor moves the focus on
    // to the content (editor-csp.spec.ts checks the round trip).
    expect(attach).toHaveBeenCalledWith({ mode: "open", delegatesFocus: true });
    attach.mockRestore();
    shadowRoot.querySelector<HTMLElement>(".cm-scroller")!.focus();
    expect(shadowRoot.activeElement).toBe(editor);
  });

  it("keeps CRLF line endings byte for byte through an edit and its undo", () => {
    const CRLF = "a: 1\r\nb: 2\r\n";
    const onChange = vi.fn();
    const { container } = render(<Harness value={CRLF} onChange={onChange} />);
    const editor = editorOf(container);
    expect(linesOf(editor)).toEqual(["a: 1", "b: 2", ""]);

    fireEvent.keyDown(editor, {
      key: "]",
      code: "BracketRight",
      ctrlKey: true,
    });
    expect(onChange).toHaveBeenLastCalledWith("  a: 1\r\nb: 2\r\n");

    fireEvent.keyDown(editor, { key: "z", code: "KeyZ", ctrlKey: true });
    expect(onChange).toHaveBeenLastCalledWith(CRLF);
  });

  it("takes the line endings of a new value that replaces the document", () => {
    const onChange = vi.fn();
    const { container, rerender } = render(<Harness onChange={onChange} />);

    rerender(<Harness value={"a: 1\r\nb: 2\r\n"} onChange={onChange} />);
    const editor = editorOf(container);
    expect(linesOf(editor)).toEqual(["a: 1", "b: 2", ""]);
    expect(onChange).not.toHaveBeenCalled();

    fireEvent.keyDown(editor, {
      key: "]",
      code: "BracketRight",
      ctrlKey: true,
    });
    expect(onChange).toHaveBeenLastCalledWith("  a: 1\r\nb: 2\r\n");
  });

  it("replaces its text with a new value without calling onChange", () => {
    const onChange = vi.fn();
    const { container, rerender } = render(<Harness onChange={onChange} />);

    rerender(<Harness value={"pack: stored\n"} onChange={onChange} />);

    expect(linesOf(editorOf(container))).toEqual(["pack: stored", ""]);
    expect(onChange).not.toHaveBeenCalled();
  });
});
