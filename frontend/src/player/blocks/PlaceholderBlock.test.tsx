import { render, screen } from "@testing-library/react";
import { describe, expect, test } from "vitest";
import { expectNoAxeViolations } from "../../test/axe";
import { fakeRuntime, programFixture, renderPlayer } from "../../test/player";
import type { Block } from "../runtime";
import { PlaceholderBlock } from "./PlaceholderBlock";

/**
 * Task 0013 step 25 and README section 7, rule 8: a placeholder block
 * renders the current version of its policy with the policy as its
 * provenance, and its own body with the `placeholder` badge until the
 * organization publishes a version. The policy text is text of the
 * organization and inherits the language of the document; the body of the
 * block is pack text and carries the language of the program.
 */
const PLACEHOLDER_BODY = "Your organization adds its rules for inputs here.";
const POLICY_BODY = "Enter no personal data into an assistant.";

const block = (policy: Block["policy"]): Block => ({
  id: "00000000-0000-4000-8000-000000000023",
  kind: "placeholder",
  body: PLACEHOLDER_BODY,
  provenance: "placeholder",
  collapsed_on: [],
  placeholder_key: "input-rules",
  policy,
  citations: [
    {
      locator: null,
      source: {
        key: "template",
        title: "Template for input rules",
        publisher: "Example publisher",
        url: null,
        edition_date: "2026-03-01",
        retrieved_on: "2026-09-15",
        kind: "other",
      },
    },
  ],
});

/** Renders `block` inside the player of a German program. */
const renderInGermanProgram = (block: Block) =>
  renderPlayer(<PlaceholderBlock block={block} />, {
    runtime: fakeRuntime({ program: { ...programFixture(), locale: "de" } }),
  });

const policy = {
  key: "input-rules",
  number: 3,
  effective_from: "2026-10-01",
  body: `**Inputs**\n\n${POLICY_BODY}`,
};

describe("PlaceholderBlock", () => {
  test("without a policy, shows its own body with the placeholder badge and its key", () => {
    const { container } = render(<PlaceholderBlock block={block(null)} />);

    expect(screen.getByText("Rules of your organization")).toBeInTheDocument();
    expect(screen.getByText(PLACEHOLDER_BODY)).toBeInTheDocument();
    expect(
      screen.getByText("Placeholder: input-rules", { exact: false }),
    ).toBeInTheDocument();
    expect(screen.queryByText(/Policy of your organization/)).toBeNull();
    expect(container).toHaveTextContent("Template for input rules");
  });

  test("with a policy, shows the policy text with its version and the policy as provenance", async () => {
    const { container } = render(<PlaceholderBlock block={block(policy)} />);

    expect(screen.getByText("Rules of your organization")).toBeInTheDocument();
    expect(screen.getByText(POLICY_BODY)).toBeInTheDocument();
    expect(screen.getByText("Inputs", { selector: "strong" })).toBeVisible();
    expect(
      screen.getByText("Version 3, in effect from Oct 1, 2026."),
    ).toBeInTheDocument();
    expect(
      screen.getByText("Policy of your organization: input-rules", {
        exact: false,
      }),
    ).toBeInTheDocument();

    // The pack text, the placeholder badge and the citations of the pack
    // give way to the policy.
    expect(screen.queryByText(PLACEHOLDER_BODY)).toBeNull();
    expect(container).not.toHaveTextContent("Placeholder");
    expect(container).not.toHaveTextContent("Template for input rules");
    await expectNoAxeViolations(container);
  });

  test("the policy text renders Markdown without raw HTML", () => {
    const { container } = render(
      <PlaceholderBlock
        block={block({
          ...policy,
          body: 'Rule <img src="x" onerror="alert(1)"> [link](javascript:alert(1))',
        })}
      />,
    );

    expect(container.querySelector("img")).toBeNull();
    expect(screen.getByText("link").getAttribute("href") ?? "").not.toMatch(
      /javascript/,
    );
  });

  test("without a policy, the body carries the language of the program", async () => {
    renderInGermanProgram(block(null));

    const body = await screen.findByText(PLACEHOLDER_BODY);
    expect(body.closest("[lang]")).toHaveAttribute("lang", "de");
  });

  test("with a policy, the policy text carries no lang and inherits the language of the document", async () => {
    renderInGermanProgram(block(policy));

    const text = await screen.findByText(POLICY_BODY);
    expect(text.closest("[lang]")).toBe(document.documentElement);
    expect(
      screen.getByText("Inputs", { selector: "strong" }).closest("[lang]"),
    ).toBe(document.documentElement);
  });
});
