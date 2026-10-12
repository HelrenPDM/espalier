import { render, screen } from "@testing-library/react";
import { describe, expect, test } from "vitest";
import { Citations } from "./Citations";
import { ExternalLinkTargetContext } from "./externalLinks";
import type { Citation } from "./runtime";

/** A citation of a source with `url`. */
const citation = (url: string | null): Citation => ({
  locator: null,
  source: {
    key: "vendor-guide",
    title: "User guide",
    publisher: "Example Vendor",
    url,
    edition_date: "2026-03-01",
    retrieved_on: "2026-09-15",
    kind: "vendor",
  },
});

describe("SourceTitle", () => {
  test("links a source in the current tab without a provider", () => {
    render(<Citations citations={[citation("https://example.org/guide")]} />);

    const link = screen.getByRole("link", { name: "User guide" });
    expect(link).toHaveAttribute("href", "https://example.org/guide");
    expect(link).toHaveAttribute("rel", "noopener noreferrer");
    expect(link).not.toHaveAttribute("target");
  });

  test("opens the source in the target of ExternalLinkTargetContext", () => {
    render(
      <ExternalLinkTargetContext.Provider value="_blank">
        <Citations citations={[citation("https://example.org/guide")]} />
      </ExternalLinkTargetContext.Provider>,
    );

    const link = screen.getByRole("link", { name: "User guide" });
    expect(link).toHaveAttribute("target", "_blank");
    expect(link).toHaveAttribute("rel", "noopener noreferrer");
  });

  test("a source without a safe URL keeps its title without a link", () => {
    render(
      <ExternalLinkTargetContext.Provider value="_blank">
        <Citations citations={[citation("javascript:alert(1)")]} />
      </ExternalLinkTargetContext.Provider>,
    );

    expect(screen.queryByRole("link")).toBeNull();
    expect(screen.getByText("User guide").tagName).toBe("CITE");
  });
});
