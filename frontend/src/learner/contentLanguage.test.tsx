import { screen, within } from "@testing-library/react";
import { expect, test } from "vitest";
import { emptyResumeState } from "../player/runtime";
import { fakeRuntime, IDS, programFixture, renderPlayer } from "../test/player";
import { ModuleStation } from "./ModuleStation";

// The program is German and the UI English: pack text carries `lang="de"`,
// and the translated controls keep the language of the document.
test("pack text carries the language of the program, controls carry none", async () => {
  const program = { ...programFixture(), locale: "de" };
  const runtime = fakeRuntime({
    program,
    state: { ...emptyResumeState(), completedModules: [IDS.module1] },
  });
  renderPlayer(<ModuleStation station={program.stations[1]} />, { runtime });

  const lesson = await screen.findByRole("heading", {
    level: 2,
    name: "What a language model does",
  });
  expect(lesson).toHaveAttribute("lang", "de");

  const content = [
    // Objective statement in the panel and in the summary.
    ...screen.getAllByText("Learners can explain how a model continues text."),
    // Item stem and option label.
    screen.getByText("How does a language model write?"),
    screen.getByText("It continues the text with likely words."),
    // Rule statement and action of the recap.
    screen.getByText("Generated text carries no check of its own."),
    screen.getByText("Treat every generated statement as a draft."),
    // Exam title and the format named in the summary.
    screen.getByRole("heading", { level: 2, name: "Exam of module 1" }),
    ...screen.getAllByText("Team workshop"),
  ];
  for (const element of content)
    expect(element.closest("[lang]")).toHaveAttribute("lang", "de");

  // Markdown of a block.
  const glossaryTerm = screen.getByRole("button", { name: "language model" });
  expect(glossaryTerm.closest("[lang]")).toHaveAttribute("lang", "de");

  // Translated controls and headings inherit the UI language of <html>.
  for (const control of [
    screen.getByRole("heading", { name: "Objectives of this topic" }),
    within(
      screen.getByRole("group", { name: "How does a language model write?" }),
    ).getByRole("button", { name: "Check answer" }),
    screen.getByRole("heading", { name: "Module complete" }),
    screen.getByRole("radio", { name: "Short path" }),
  ])
    expect(control.closest("[lang]")).toBe(document.documentElement);
});
