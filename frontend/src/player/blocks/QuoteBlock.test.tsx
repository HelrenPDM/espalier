import { render, screen } from "@testing-library/react";
import { expect, test } from "vitest";
import type { Block } from "../runtime";
import { QuoteBlock } from "./QuoteBlock";

const source = (key: string, title: string) => ({
  key,
  title,
  publisher: `${title} publisher`,
  url: null,
  edition_date: "2026-03-01",
  retrieved_on: "2026-09-15",
  kind: "study" as const,
});

const block: Block = {
  id: "00000000-0000-4000-8000-000000000026",
  kind: "quote",
  body: "I read every paragraph as if a new colleague wrote it.",
  provenance: "sourced",
  collapsed_on: [],
  placeholder_key: null,
  citations: [
    { locator: "Interviews", source: source("office-study", "Office study") },
    { locator: null, source: source("second-study", "Second study") },
  ],
};

test("a quote has one caption with the full citation of each source", () => {
  render(<QuoteBlock block={block} />);

  const figure = screen.getByRole("figure");
  const captions = figure.querySelectorAll("figcaption");
  expect(captions).toHaveLength(1);
  expect(captions[0]).toHaveTextContent(
    "Office study, Office study publisher, edition of Mar 1, 2026, retrieved on Sep 15, 2026. Section: Interviews.",
  );
  expect(captions[0]).toHaveTextContent(
    "Second study, Second study publisher, edition of Mar 1, 2026, retrieved on Sep 15, 2026.",
  );
  expect(figure).toHaveTextContent("I read every paragraph");
});

test("a quote without citations has no caption", () => {
  render(<QuoteBlock block={{ ...block, citations: [] }} />);

  expect(screen.getByRole("figure").querySelector("figcaption")).toBeNull();
});
