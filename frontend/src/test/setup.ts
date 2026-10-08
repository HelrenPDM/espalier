import "@testing-library/jest-dom/vitest";
import { cleanup } from "@testing-library/react";
import { afterEach, expect } from "vitest";
import type { AxeMatchers } from "vitest-axe/matchers";
import * as axeMatchers from "vitest-axe/matchers";

// vitest-axe 0.1.0 declares its matcher types for the `Vi` namespace of
// Vitest before 0.31. Current Vitest reads custom matcher types from
// `Matchers`, whose type parameters this declaration repeats.
declare module "vitest" {
  interface Matchers<
    R extends void | Promise<void> = void | Promise<void>,
    T = unknown,
  > extends AxeMatchers {}
}

expect.extend(axeMatchers);

// Testing Library unmounts after each test by itself only when Vitest runs
// with `globals: true`.
afterEach(() => {
  cleanup();
});
