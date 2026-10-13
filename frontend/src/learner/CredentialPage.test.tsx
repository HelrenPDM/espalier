import { screen, within } from "@testing-library/react";
import { afterEach, describe, expect, test, vi } from "vitest";
import type { Credential } from "../api/credentials";
import { expectNoAxeViolations } from "../test/axe";
import { renderWithProviders, type StubResponses } from "../test/render";
import { signedInPayload } from "../test/session";
import { CredentialListPage } from "./CredentialListPage";
import { CredentialPage } from "./CredentialPage";

/**
 * Task 0013 steps 23 and 25: `/me/credentials/:id` shows qualification
 * title, holder, issue date, validity, status and the unlocked tasks,
 * prints on A4, has no axe violations and renders no score, percentage or
 * comparison with other people (README section 2, principle 2).
 * `/me/credentials` lists the credentials with a link to each.
 */
const CREDENTIAL_ID = "3c5e7a9b-1d2f-4a6b-8c0d-2e4f6a8b0c1d";

const credential = (overrides: Partial<Credential> = {}): Credential => ({
  id: CREDENTIAL_ID,
  qualification_code: "basics",
  qualification_title: "AI assistant basics",
  locale: "fr",
  holder_display_name: "Ada Example",
  status: "active",
  issued_at: "2026-10-11T09:30:00Z",
  valid_until: "2027-10-11",
  unlocks_snapshot: [
    "Draft internal texts with an approved AI writing assistant",
    "Summarize non-confidential documents with an approved AI writing assistant",
  ],
  ...overrides,
});

function renderCredential(
  responses: StubResponses = {
    [`GET /api/me/credentials/${CREDENTIAL_ID}`]: {
      status: 200,
      body: credential(),
    },
  },
  id = CREDENTIAL_ID,
) {
  return renderWithProviders(<CredentialPage />, {
    route: `/me/credentials/${id}`,
    path: "/me/credentials/:id",
    session: signedInPayload("mfa"),
    responses,
  });
}

const details = (container: HTMLElement) => {
  const list = container.querySelector("dl");
  expect(list).not.toBeNull();
  const terms = [...(list as HTMLElement).querySelectorAll("dt")];
  return Object.fromEntries(
    terms.map((term) => [
      term.textContent,
      term.nextElementSibling?.textContent ?? null,
    ]),
  );
};

afterEach(() => {
  vi.restoreAllMocks();
});

describe("the credential page", () => {
  test("shows qualification title, holder, status, issue date, validity and the unlocked tasks", async () => {
    const { container } = renderCredential();

    expect(
      await screen.findByRole("heading", {
        level: 1,
        name: "AI assistant basics",
      }),
    ).toBeInTheDocument();
    expect(details(container)).toEqual({
      Holder: "Ada Example",
      Status: "Active",
      "Issued on": "Oct 11, 2026",
      "Valid until": "Oct 11, 2027",
    });
    const tasks = screen.getByRole("region", {
      name: "The holder may carry out these tasks",
    });
    expect(
      within(tasks)
        .getAllByRole("listitem")
        .map((item) => item.textContent),
    ).toEqual(credential().unlocks_snapshot);
    // Title and tasks are pack text in the language of the program.
    expect(
      screen.getByRole("heading", { level: 1, name: "AI assistant basics" }),
    ).toHaveAttribute("lang", "fr");
    expect(within(tasks).getByRole("list")).toHaveAttribute("lang", "fr");
  });

  test("the breadcrumbs lead back to the credential list and end with the qualification title", async () => {
    renderCredential();

    await screen.findByRole("heading", {
      level: 1,
      name: "AI assistant basics",
    });
    const trail = screen.getByRole("navigation", { name: "Breadcrumb" });
    expect(within(trail).getByRole("link")).toHaveAttribute(
      "href",
      "/me/credentials",
    );
    expect(within(trail).getByRole("link")).toHaveTextContent("Credentials");
    const current = within(trail).getByText("AI assistant basics");
    expect(current).toHaveAttribute("aria-current", "page");
    expect(current).toHaveAttribute("lang", "fr");
    expect(
      screen.queryByRole("link", { name: "Back to the credentials" }),
    ).not.toBeInTheDocument();
  });

  test("renders no score, percentage or comparison with other people", async () => {
    const { container } = renderCredential();

    await screen.findByRole("heading", {
      level: 1,
      name: "AI assistant basics",
    });
    const text = container.textContent ?? "";
    expect(text).not.toMatch(/%|percent|score|points|rank|average|of \d+/i);
    expect(container.querySelector("progress, meter")).toBeNull();
  });

  test("has no axe violations", async () => {
    const { container } = renderCredential();

    await screen.findByRole("heading", {
      level: 1,
      name: "AI assistant basics",
    });
    await expectNoAxeViolations(container);
  });

  test("the print button opens the print dialog; the navigation does not print", async () => {
    const print = vi.spyOn(window, "print").mockImplementation(() => {});
    const { user, container } = renderCredential();

    const button = await screen.findByRole("button", { name: "Print" });
    await user.click(button);

    expect(print).toHaveBeenCalledTimes(1);
    expect(button).toHaveClass("no-print");
    expect(
      screen
        .getByRole("navigation", { name: "Breadcrumb" })
        .closest(".no-print"),
    ).not.toBeNull();
    expect(container.querySelector("article.credential-sheet")).not.toBeNull();
  });

  test("a credential without validity date, without display name and with a refresher due says so", async () => {
    const { container } = renderCredential({
      [`GET /api/me/credentials/${CREDENTIAL_ID}`]: {
        status: 200,
        body: credential({
          holder_display_name: null,
          valid_until: null,
          status: "refresh_due",
        }),
      },
    });

    await screen.findByRole("heading", {
      level: 1,
      name: "AI assistant basics",
    });
    expect(details(container)).toMatchObject({
      Holder: "No display name recorded",
      Status: "Refresher due",
      "Valid until": "No expiry date",
    });
    expect(
      screen.getByText(
        "A refresher is due. The credential stays in force until the grace period ends.",
      ),
    ).toBeInTheDocument();
  });

  test("the credential of another person answers 404 and shows not found", async () => {
    renderCredential({}, "4d6f8a0b-2e3f-4b7c-9d1e-3f5a7b9c1d2e");

    expect(
      await screen.findByRole("heading", {
        level: 1,
        name: "Credential not found",
      }),
    ).toBeInTheDocument();
    expect(screen.getByRole("alert")).toHaveTextContent(
      "No credential of yours exists at this address.",
    );
    const trail = screen.getByRole("navigation", { name: "Breadcrumb" });
    expect(
      within(trail).getByRole("link", { name: "Credentials" }),
    ).toHaveAttribute("href", "/me/credentials");
    expect(within(trail).getByText("Credential not found")).toHaveAttribute(
      "aria-current",
      "page",
    );
  });
});

describe("the credential list", () => {
  test("lists each credential with status, dates and a link to its page", async () => {
    renderWithProviders(<CredentialListPage />, {
      route: "/me/credentials",
      session: signedInPayload("mfa"),
      responses: {
        "GET /api/me/credentials": {
          status: 200,
          body: {
            credentials: [
              credential(),
              credential({
                id: "5e7a9b1d-3f4a-4c8d-8e2f-4a6b8c0d2e3f",
                qualification_code: "workshop",
                qualification_title: "AI assistants in the team",
                valid_until: null,
                status: "revoked",
              }),
            ],
          },
        },
      },
    });

    const items = await screen.findAllByRole("listitem");
    expect(items).toHaveLength(2);
    expect(
      within(items[0]).getByRole("link", { name: "AI assistant basics" }),
    ).toHaveAttribute("href", `/me/credentials/${CREDENTIAL_ID}`);
    expect(items[0]).toHaveTextContent("Active");
    expect(items[0]).toHaveTextContent("Valid untilOct 11, 2027");
    expect(items[1]).toHaveTextContent("Revoked");
    expect(items[1]).toHaveTextContent("No expiry date");
  });

  test("without a credential, says so", async () => {
    renderWithProviders(<CredentialListPage />, {
      route: "/me/credentials",
      session: signedInPayload("mfa"),
      responses: {
        "GET /api/me/credentials": { status: 200, body: { credentials: [] } },
      },
    });

    expect(
      await screen.findByText(/You hold no credential yet\./),
    ).toBeInTheDocument();
  });
});
