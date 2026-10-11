import { screen } from "@testing-library/react";
import { expect, test } from "vitest";
import { emptyResumeState } from "../player/runtime";
import { fakeRuntime, IDS, programFixture, renderPlayer } from "../test/player";
import { ModuleStation } from "./ModuleStation";

const MARKUP = '<img src="x" onerror="alert(1)">';

// ASVS 1.1.2 and 1.2.1: objective statements, lesson titles and format
// titles render as React text nodes, so markup in them stays text.
test("objective statements, lesson titles and format titles render markup as text", async () => {
  const program = programFixture();
  const module = program.modules[0];
  module.objectives[0].statement = `Statement ${MARKUP}`;
  module.lessons[0].title = `Lesson ${MARKUP}`;
  program.companion_formats[0].title = `Format ${MARKUP}`;
  const runtime = fakeRuntime({
    program,
    state: { ...emptyResumeState(), completedModules: [IDS.module1] },
  });

  const { container } = renderPlayer(
    <ModuleStation station={program.stations[1]} />,
    { runtime },
  );

  expect(
    await screen.findByRole("heading", { level: 2, name: `Lesson ${MARKUP}` }),
  ).toBeInTheDocument();
  // The statement appears in the panel, in the summary and as the
  // description of the chip of its practice item.
  expect(screen.getAllByText(`Statement ${MARKUP}`)).toHaveLength(3);
  expect(
    screen.getAllByText(`Format ${MARKUP}`, { exact: false }).length,
  ).toBeGreaterThan(0);
  expect(container.querySelector("img")).toBeNull();
});
