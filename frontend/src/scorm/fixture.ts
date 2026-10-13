import type { ScormContent } from "../runtimes/content";

/**
 * A small `content.json` for the tests of the SCORM entry: one module with
 * one lesson whose text names a glossary term, one practice item and one
 * objective.
 */
export function scormContent(): ScormContent {
  return {
    schema: 1,
    program: { slug: "demo-pack", title: "Demo pack", locale: "en" },
    module: {
      number: 1,
      title: "Basics",
      summary: "The basics.",
      phases: ["understand"],
      single_path: false,
      lessons: [
        {
          key: "intro",
          title: "Introduction",
          position: 1,
          blocks: [
            {
              kind: "text",
              body: "Write a [[term:prompt]] first.",
              provenance: "invented",
              collapsed_on: [],
              placeholder_key: null,
              cite: [],
            },
          ],
        },
      ],
      objectives: [
        {
          // Shorter than the ten characters that gitleaks reads as an API key.
          key: "m1-prompt",
          statement: "Name the parts of a prompt.",
          area: "subject",
          depth: "know",
          phase: "understand",
          domain: null,
          taught_in: ["intro"],
        },
      ],
      rules: [],
      items: [
        {
          key: "prompt-parts",
          kind: "single_choice",
          lesson: "intro",
          stem: "Which part names the task?",
          core: false,
          provenance: "invented",
          objectives: ["m1-prompt"],
          rules: [],
          reveals: [],
          cite: [],
          options: [
            { key: "task", label: "The task", correct: true, feedback: null },
            { key: "tone", label: "The tone", correct: false, feedback: null },
          ],
          config: {},
        },
      ],
      assessments: [],
      areas_elsewhere: {},
    },
    glossary: [
      { slug: "prompt", label: "Prompt", short_text: "The input to a model." },
    ],
    sources: [],
    formats: [],
    policies: {},
  };
}
