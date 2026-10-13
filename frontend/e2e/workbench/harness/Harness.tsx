import { useState } from "react";
import {
  PackFileEditor,
  type GoTo,
  type PackFileLanguage,
} from "../../../src/admin/workbench/PackFileEditor";
import { WorkbenchDialog } from "../../../src/admin/workbench/WorkbenchDialog";

// The harness of the editor spike (task 0016a, step 1): editor-csp.spec.ts
// builds this page with Vite and serves it with the CSP of Phoenix. Each
// editor sits between two buttons, so that Tab and Shift+Tab can leave it,
// and shows the cursor status, the number of saves and the length of its
// value, which the spec reads. The third editor holds a file taller than
// its frame, and Ctrl+S opens a dialog there, as a conflict or a step-up
// does on the draft page.

const YAML_TEXT = `# The objectives of the first module.
- key: m1-subject
  statement: "Learners can name the subject of this module."
  area: subject
  depth: know
  taught_in:
    - 01-first-lesson
- key: m1-method
  statement: Learners can name the method that this module practises.
  area: method
  depth: know
  core: true
  weight: 2
`;

const MARKDOWN_TEXT = `---
title: First lesson
position: 1
---

# A heading

Some *emphasis*, some **strong text** and \`code\`.

:::text{provenance=invented}
Replace this text with the first lesson.
:::
`;

// Fifteen items of three lines each: taller than the frame of the editor.
const TALL_TEXT = Array.from(
  { length: 15 },
  (_, index) =>
    `- key: m1-question-${index + 1}\n  objective: m1-subject\n  kind: single_choice\n`,
).join("");

interface EditorCaseProps {
  id: string;
  title: string;
  path: string;
  language: PackFileLanguage;
  initial: string;
  /** Ctrl+S opens a dialog, which returns the focus when it closes. */
  dialogOnSave?: boolean;
}

function EditorCase({
  id,
  title,
  path,
  language,
  initial,
  dialogOnSave = false,
}: EditorCaseProps) {
  const [value, setValue] = useState(initial);
  const [cursor, setCursor] = useState({ line: 1, column: 1 });
  const [saves, setSaves] = useState(0);
  const [goTo, setGoTo] = useState<GoTo | null>(null);
  const [dialog, setDialog] = useState(false);

  return (
    <section aria-labelledby={`${id}-heading`} className="space-y-2">
      <h2 id={`${id}-heading`} className="text-lg font-semibold">
        {title}
      </h2>
      <button
        type="button"
        className="rounded border border-gray-300 px-2 py-1 dark:border-gray-700"
        onClick={() => setGoTo({ line: 4 })}
      >
        Go to line 4 of {path}
      </button>
      <PackFileEditor
        value={value}
        onChange={setValue}
        language={language}
        label={`Content of ${path}`}
        onSave={() => {
          setSaves((count) => count + 1);
          if (dialogOnSave) setDialog(true);
        }}
        onCursor={(line, column) => setCursor({ line, column })}
        goTo={goTo}
      />
      <p data-testid={`${id}-cursor`}>
        Line {cursor.line}, column {cursor.column}
      </p>
      <p data-testid={`${id}-saves`}>Saves: {saves}</p>
      <p data-testid={`${id}-length`}>Characters: {value.length}</p>
      <button
        type="button"
        className="rounded border border-gray-300 px-2 py-1 dark:border-gray-700"
        onClick={() => setValue(initial)}
      >
        Reset {path}
      </button>
      <WorkbenchDialog
        open={dialog}
        title={`Saved ${path}`}
        onClose={() => setDialog(false)}
        actions={
          <button
            type="button"
            className="rounded border border-gray-300 px-2 py-1 dark:border-gray-700"
            onClick={() => setDialog(false)}
            data-autofocus
          >
            Close
          </button>
        }
      >
        <p>Closing this dialog returns the focus to the editor.</p>
      </WorkbenchDialog>
    </section>
  );
}

export function Harness() {
  return (
    <main className="mx-auto max-w-3xl space-y-8 p-4">
      <h1 className="text-xl font-bold">Editor harness</h1>
      <EditorCase
        id="yaml"
        title="YAML"
        path="modules/01-first-module/objectives.yaml"
        language="yaml"
        initial={YAML_TEXT}
      />
      <EditorCase
        id="markdown"
        title="Markdown"
        path="modules/01-first-module/lessons/01-first-lesson.md"
        language="markdown"
        initial={MARKDOWN_TEXT}
      />
      <EditorCase
        id="tall"
        title="YAML taller than the frame"
        path="modules/01-first-module/items.yaml"
        language="yaml"
        initial={TALL_TEXT}
        dialogOnSave
      />
    </main>
  );
}
