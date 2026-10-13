import { render, screen, within } from "@testing-library/react";
import { createMemoryRouter, RouterProvider } from "react-router";
import { expect, test } from "vitest";
import { expectNoAxeViolations } from "../test/axe";
import { Breadcrumbs, type BreadcrumbItem } from "./Breadcrumbs";

const ITEMS: BreadcrumbItem[] = [
  { label: "Programs", to: "/" },
  { label: "KI-Grundlagen", to: "/programs/demo", lang: "de" },
  { label: "Wie Sprachmodelle arbeiten", lang: "de" },
];

function renderTrail(items: readonly BreadcrumbItem[] = ITEMS) {
  const router = createMemoryRouter(
    [{ path: "*", element: <Breadcrumbs items={items} /> }],
    { initialEntries: ["/programs/demo/stations/2"] },
  );
  return render(<RouterProvider router={router} />);
}

test("every item but the last is a link, and the last one is the current page", () => {
  renderTrail();

  const trail = screen.getByRole("navigation", { name: "Breadcrumb" });
  const items = within(trail).getAllByRole("listitem");
  expect(items.map((item) => item.textContent)).toEqual([
    "Programs",
    "KI-Grundlagen",
    "Wie Sprachmodelle arbeiten",
  ]);
  expect(
    within(trail)
      .getAllByRole("link")
      .map((link) => [link.textContent, link.getAttribute("href")]),
  ).toEqual([
    ["Programs", "/"],
    ["KI-Grundlagen", "/programs/demo"],
  ]);
  const current = within(items[2]).getByText("Wie Sprachmodelle arbeiten");
  expect(current.tagName).toBe("SPAN");
  expect(current).toHaveAttribute("aria-current", "page");
  expect(trail).toHaveClass("no-print");
});

test("pack text carries its language, and the translated labels carry none", () => {
  renderTrail();

  const trail = screen.getByRole("navigation", { name: "Breadcrumb" });
  expect(
    within(trail).getByRole("link", { name: "Programs" }),
  ).not.toHaveAttribute("lang");
  expect(
    within(trail).getByRole("link", { name: "KI-Grundlagen" }),
  ).toHaveAttribute("lang", "de");
  expect(within(trail).getByText("Wie Sprachmodelle arbeiten")).toHaveAttribute(
    "lang",
    "de",
  );
});

test("the separators are decorative", () => {
  renderTrail();

  const trail = screen.getByRole("navigation", { name: "Breadcrumb" });
  const separators = trail.querySelectorAll("svg");
  expect(separators).toHaveLength(2);
  for (const separator of separators)
    expect(separator).toHaveAttribute("aria-hidden", "true");
});

test("has no axe violations", async () => {
  const { container } = renderTrail();

  await expectNoAxeViolations(container);
});
