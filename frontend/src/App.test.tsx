import { render } from "@testing-library/react";
import { expect, test } from "vitest";
import { axe } from "vitest-axe";
import App from "./App";

test("App renders without axe violations", async () => {
  const { container } = render(<App />);

  expect(await axe(container)).toHaveNoViolations();
});
