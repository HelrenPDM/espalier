import { useLayoutEffect, useRef } from "react";
import { EditorState, StateEffect, type Extension } from "@codemirror/state";
import {
  EditorView,
  highlightSpecialChars,
  keymap,
  lineNumbers,
} from "@codemirror/view";
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands";
import { HighlightStyle, syntaxHighlighting } from "@codemirror/language";
import { yaml, yamlFrontmatter } from "@codemirror/lang-yaml";
import { markdown } from "@codemirror/lang-markdown";
import { tags } from "@lezer/highlight";

/** The language of a file of a draft (task 0016a, `Paths.language/1`). */
export type PackFileLanguage = "yaml" | "markdown";

/** A request to move the cursor to the start of a line; a new object moves it again. */
export interface GoTo {
  line: number;
}

export interface PackFileEditorProps {
  value: string;
  onChange: (value: string) => void;
  language: PackFileLanguage;
  /** The accessible name of the editor. */
  label: string;
  /** Keeps the text as it is: the editor takes no input (`aria-readonly`). */
  readOnly?: boolean;
  /** Ctrl+S and Cmd+S. */
  onSave: () => void;
  /** The position of the cursor, 1-based. */
  onCursor: (line: number, column: number) => void;
  goTo: GoTo | null;
}

interface Callbacks {
  onChange: (value: string) => void;
  onSave: () => void;
  onCursor: (line: number, column: number) => void;
}

// The colors of the editor are CSS custom properties, which the frame sets
// with Tailwind classes for the light and the dark theme. Custom properties
// inherit into the shadow tree of the frame, where the classes of the page
// do not apply.
const FRAME_CLASSES = [
  "h-[32rem] overflow-hidden rounded-md border border-gray-300 bg-white font-mono text-sm leading-6 text-gray-900",
  "focus-within:ring-2 focus-within:ring-accent-500",
  "dark:border-gray-700 dark:bg-gray-950 dark:text-gray-100",
  "[--editor-gutter-bg:var(--color-gray-50)] [--editor-gutter-fg:var(--color-gray-600)] [--editor-gutter-border:var(--color-gray-200)]",
  "dark:[--editor-gutter-bg:var(--color-gray-900)] dark:[--editor-gutter-fg:var(--color-gray-400)] dark:[--editor-gutter-border:var(--color-gray-800)]",
  "[--editor-key:var(--color-blue-700)] [--editor-string:var(--color-green-700)] [--editor-mark:var(--color-purple-700)] [--editor-comment:var(--color-gray-600)] [--editor-special:var(--color-red-700)]",
  "dark:[--editor-key:var(--color-blue-300)] dark:[--editor-string:var(--color-green-300)] dark:[--editor-mark:var(--color-purple-300)] dark:[--editor-comment:var(--color-gray-400)] dark:[--editor-special:var(--color-red-300)]",
].join(" ");

const theme = EditorView.theme({
  "&": { height: "100%", color: "inherit", backgroundColor: "transparent" },
  // The frame shows the focus with its ring.
  "&.cm-focused": { outline: "none" },
  ".cm-scroller": { fontFamily: "inherit", lineHeight: "inherit" },
  ".cm-content": { caretColor: "currentColor" },
  ".cm-gutters": {
    backgroundColor: "var(--editor-gutter-bg)",
    color: "var(--editor-gutter-fg)",
    borderColor: "var(--editor-gutter-border)",
  },
  ".cm-specialChar": { color: "var(--editor-special)" },
});

const highlightStyle = HighlightStyle.define([
  {
    tag: [tags.definition(tags.propertyName), tags.propertyName],
    color: "var(--editor-key)",
  },
  {
    tag: [tags.string, tags.special(tags.string), tags.attributeValue],
    color: "var(--editor-string)",
  },
  {
    tag: [
      tags.keyword,
      tags.meta,
      tags.typeName,
      tags.labelName,
      tags.processingInstruction,
    ],
    color: "var(--editor-mark)",
  },
  { tag: tags.comment, color: "var(--editor-comment)", fontStyle: "italic" },
  { tag: tags.invalid, color: "var(--editor-special)" },
  { tag: tags.heading, color: "var(--editor-key)", fontWeight: "bold" },
  { tag: tags.emphasis, fontStyle: "italic" },
  { tag: tags.strong, fontWeight: "bold" },
  { tag: tags.strikethrough, textDecoration: "line-through" },
  { tag: [tags.link, tags.url], textDecoration: "underline" },
  { tag: tags.monospace, color: "var(--editor-string)" },
  { tag: tags.quote, fontStyle: "italic" },
]);

function languageSupport(language: PackFileLanguage): Extension {
  // A lesson starts with front matter in YAML (0008 step 5).
  return language === "yaml"
    ? yaml()
    : yamlFrontmatter({ content: markdown() });
}

/** The configuration of a view that follows the props. */
interface Settings {
  language: PackFileLanguage;
  label: string;
  readOnly: boolean;
}

/**
 * The line endings of a text that holds CRLF. CodeMirror splits a text at
 * CRLF, CR and LF and joins its lines with LF by default, so a file with
 * CRLF would differ from the stored one after any edit, and an undo would
 * never return to it. With CRLF as the separator, `sliceDoc` gives the text
 * back byte for byte, Enter inserts CRLF, and pasted or dropped text takes
 * CRLF as well.
 */
const CRLF: Extension = [
  EditorState.lineSeparator.of("\r\n"),
  EditorView.clipboardInputFilter.of((text) =>
    text.replace(/\r\n|\r|\n/g, "\r\n"),
  ),
];

const hasCrlf = (text: string) => text.includes("\r\n");

function extensions(
  { language, label, readOnly }: Settings,
  crlf: boolean,
  callbacks: { current: Callbacks },
): Extension[] {
  return [
    crlf ? CRLF : [],
    lineNumbers(),
    highlightSpecialChars(),
    history(),
    // No binding of Tab (no `indentWithTab`): Tab and Shift+Tab move the
    // focus. Mod-] and Mod-[ of defaultKeymap indent and dedent.
    keymap.of([
      {
        key: "Mod-s",
        preventDefault: true,
        run: () => {
          callbacks.current.onSave();
          return true;
        },
      },
      ...defaultKeymap,
      ...historyKeymap,
    ]),
    languageSupport(language),
    syntaxHighlighting(highlightStyle),
    theme,
    EditorState.readOnly.of(readOnly),
    // CodeMirror takes its scroller out of the tab order (tabindex -1), and
    // axe counts no contenteditable element as focusable, so a file taller
    // than the frame would be a scrollable region without a focusable
    // element (WCAG 2.1.1, `scrollable-region-focusable`). The content
    // element is in the tab order already as contenteditable, so tabindex 0
    // adds no tab stop.
    EditorView.contentAttributes.of({ "aria-label": label, tabindex: "0" }),
    EditorView.updateListener.of((update) => {
      if (update.docChanged)
        callbacks.current.onChange(update.state.sliceDoc());
      if (update.selectionSet || update.docChanged) {
        const head = update.state.selection.main.head;
        const line = update.state.doc.lineAt(head);
        callbacks.current.onCursor(line.number, head - line.from + 1);
      }
    }),
  ];
}

/**
 * The editor of a file of a draft (task 0016a, step 1): CodeMirror 6 with
 * the language of the file, line numbers, the default keymap with history,
 * and Mod-s for `onSave`. The content element is a multi-line textbox with
 * the accessible name `label`.
 *
 * The view lives in a shadow root of the frame. CodeMirror adds its styles
 * through `StyleModule.mount` of style-mod, which uses a constructed
 * stylesheet in `adoptedStyleSheets` for a shadow root and a `<style>`
 * element for a document; the CSP `style-src 'self'` (README section 6.5)
 * blocks such an element, and a constructed stylesheet is no inline style.
 *
 * Outside the shadow tree, the focused element of the editor is the frame.
 * A Headless UI dialog records that element and focuses it again when it
 * closes, such as the conflict dialog or the step-up dialog that Ctrl+S
 * opens. The shadow root therefore delegates the focus of the frame
 * (`delegatesFocus`), and a focus that lands on another element of the
 * shadow tree than the content, such as the scroller, which Chromium picks
 * as the first focusable element, moves on to the content. The frame takes
 * no tabindex, so Tab and Shift+Tab reach the content once and leave it.
 */
export function PackFileEditor({
  value,
  onChange,
  language,
  label,
  readOnly = false,
  onSave,
  onCursor,
  goTo,
}: PackFileEditorProps) {
  const frame = useRef<HTMLDivElement>(null);
  const view = useRef<EditorView | null>(null);
  // The props of the last render, which the listeners of the view and the
  // effects below read.
  const latest = useRef({
    value,
    settings: { language, label, readOnly },
    onChange,
    onSave,
    onCursor,
  });
  const configured = useRef<Settings>({ language, label, readOnly });

  // The effects are layout effects: React renders and commits an update in
  // one task, so the value of a render is the value of the last `onChange`
  // when the effect compares it with the document. A passive effect can run
  // after further keystrokes and would take the echo of an earlier
  // `onChange` for a value from outside.
  useLayoutEffect(() => {
    latest.current = {
      value,
      settings: { language, label, readOnly },
      onChange,
      onSave,
      onCursor,
    };
  });

  // The view is created once; the effects below follow the props.
  useLayoutEffect(() => {
    const host = frame.current;
    if (host === null) return;
    const { value, settings } = latest.current;
    const root =
      host.shadowRoot ??
      host.attachShadow({ mode: "open", delegatesFocus: true });
    const created = new EditorView({
      state: EditorState.create({
        doc: value,
        extensions: extensions(settings, hasCrlf(value), latest),
      }),
      parent: root,
    });
    view.current = created;
    configured.current = settings;
    const toContent = (event: Event) => {
      if (!created.contentDOM.contains(event.target as Node)) created.focus();
    };
    root.addEventListener("focusin", toContent);
    return () => {
      root.removeEventListener("focusin", toContent);
      created.destroy();
      view.current = null;
    };
  }, []);

  useLayoutEffect(() => {
    const current = view.current;
    const previous = configured.current;
    if (
      current === null ||
      (previous.language === language &&
        previous.label === label &&
        previous.readOnly === readOnly)
    )
      return;
    configured.current = { language, label, readOnly };
    current.dispatch({
      effects: StateEffect.reconfigure.of(
        extensions(
          configured.current,
          current.state.lineBreak === "\r\n",
          latest,
        ),
      ),
    });
  }, [language, label, readOnly]);

  // A value from outside, such as the stored version after a conflict,
  // replaces the document with a new state and history, with the line
  // endings of the new value.
  useLayoutEffect(() => {
    const current = view.current;
    if (current === null || current.state.sliceDoc() === value) return;
    current.setState(
      EditorState.create({
        doc: value,
        extensions: extensions(latest.current.settings, hasCrlf(value), latest),
      }),
    );
    latest.current.onCursor(1, 1);
  }, [value]);

  // goTo is a new object for each request.
  useLayoutEffect(() => {
    const current = view.current;
    if (goTo === null || current === null) return;
    const doc = current.state.doc;
    const line = doc.line(Math.min(Math.max(goTo.line, 1), doc.lines));
    current.dispatch({
      selection: { anchor: line.from },
      effects: EditorView.scrollIntoView(line.from, { y: "center" }),
    });
    current.focus();
  }, [goTo]);

  return <div ref={frame} className={FRAME_CLASSES} />;
}
