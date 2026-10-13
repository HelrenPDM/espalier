import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { createMemoryRouter, RouterProvider } from "react-router";
import { afterEach, describe, expect, test } from "vitest";
import { axe } from "vitest-axe";
import { ADMIN_ROLES } from "../admin/sections";
import {
  SessionContext,
  type SessionContextValue,
} from "../auth/SessionProvider";
import i18n from "../i18n";
import { expectNoAxeViolations } from "../test/axe";
import { sessionValue } from "../test/session";
import { Layout } from "./Layout";

function renderLayout(value: SessionContextValue, path = "/") {
  const router = createMemoryRouter(
    [
      {
        path: "/",
        element: <Layout />,
        children: [
          { index: true, element: <h1>Home</h1> },
          { path: "*", element: <h1>Page</h1> },
        ],
      },
    ],
    { initialEntries: [path] },
  );
  const result = render(
    <SessionContext.Provider value={value}>
      <RouterProvider router={router} />
    </SessionContext.Provider>,
  );
  return { ...result, router };
}

const mainNav = () => screen.getByRole("navigation", { name: "Main" });

/** The links of the main navigation bar as `[name, href]`. */
const barLinks = () =>
  within(mainNav())
    .getAllByRole("link")
    .map((link) => [link.textContent, link.getAttribute("href")]);

const DEMO_BANNER =
  "Demo mode: every account here is a pseudonymous test account.";

afterEach(async () => {
  document.documentElement.classList.remove("dark");
  await i18n.changeLanguage("en");
});

describe("the demo banner", () => {
  test("appears with flags.demo true", () => {
    renderLayout(sessionValue({ flags: { demo: true } }));

    expect(screen.getByText(DEMO_BANNER)).toBeInTheDocument();
  });

  test("appears for a signed-out session with flags.demo true", () => {
    renderLayout(
      sessionValue({
        user: null,
        sessionStrength: null,
        roles: [],
        flags: { demo: true },
      }),
    );

    expect(screen.getByText(DEMO_BANNER)).toBeInTheDocument();
  });

  test("is absent otherwise", () => {
    renderLayout(sessionValue({ flags: { demo: false } }));

    expect(screen.queryByText(DEMO_BANNER)).not.toBeInTheDocument();
  });
});

test("a signed-in session shows the display name and sign-out", async () => {
  const value = sessionValue();
  renderLayout(value);

  await userEvent.click(screen.getByRole("button", { name: "Test person 1" }));
  await userEvent.click(screen.getByRole("menuitem", { name: "Sign out" }));

  expect(value.signOut).toHaveBeenCalledTimes(1);
});

test.each([
  ["demo", ["Sign out"]],
  ["mfa", ["Security", "Sign out"]],
] as const)(
  "the user menu of a %s session holds the security settings of an mfa session and sign-out",
  async (sessionStrength, items) => {
    renderLayout(sessionValue({ sessionStrength }));

    await userEvent.click(
      screen.getByRole("button", { name: "Test person 1" }),
    );

    expect(
      screen.getAllByRole("menuitem").map((item) => item.textContent),
    ).toEqual(items);
  },
);

describe("the main navigation", () => {
  test("lists the programs, the credentials and the policies for a learner", () => {
    renderLayout(sessionValue());

    expect(barLinks()).toEqual([
      ["Programs", "/"],
      ["Credentials", "/me/credentials"],
      ["Policies", "/policies"],
    ]);
  });

  test.each(ADMIN_ROLES)("adds the administration for the role %s", (role) => {
    renderLayout(sessionValue({ roles: ["learner", role] }));

    expect(barLinks()).toEqual([
      ["Programs", "/"],
      ["Credentials", "/me/credentials"],
      ["Policies", "/policies"],
      ["Administration", "/admin"],
    ]);
  });

  test.each<[string, Parameters<typeof sessionValue>[0]]>([
    ["signed out", { user: null, sessionStrength: null, roles: [] }],
    ["in enrollment", { sessionStrength: "enrollment" }],
  ])("is absent for a session %s", (_name, overrides) => {
    renderLayout(sessionValue(overrides));

    expect(
      screen.queryByRole("navigation", { name: "Main" }),
    ).not.toBeInTheDocument();
  });

  test.each([
    ["/", "Programs"],
    ["/programs/demo", "Programs"],
    ["/programs/demo/stations/2", "Programs"],
    ["/me/credentials", "Credentials"],
    ["/me/credentials/3c5e7a9b-1d2f-4a6b-8c0d-2e4f6a8b0c1d", "Credentials"],
    ["/policies", "Policies"],
    ["/admin", "Administration"],
    ["/admin/users", "Administration"],
    ["/account/security", null],
  ])("on %s marks the section %s as the current page", (path, section) => {
    renderLayout(sessionValue({ roles: ["learner", "admin"] }), path);

    const current = within(mainNav())
      .getAllByRole("link")
      .filter((link) => link.getAttribute("aria-current") === "page")
      .map((link) => link.textContent);
    expect(current).toEqual(section === null ? [] : [section]);
  });

  test("the menu button opens the links on a narrow screen and closes after a navigation", async () => {
    const { router } = renderLayout(sessionValue());
    const button = within(mainNav()).getByRole("button", { name: "Menu" });
    expect(button).toHaveAttribute("aria-expanded", "false");

    await userEvent.click(button);

    expect(button).toHaveAttribute("aria-expanded", "true");
    const panel = document.getElementById(
      button.getAttribute("aria-controls") ?? "",
    );
    expect(panel).not.toBeNull();
    expect(mainNav()).toContainElement(panel);
    const links = within(panel as HTMLElement).getAllByRole("link");
    expect(links.map((link) => link.textContent)).toEqual([
      "Programs",
      "Credentials",
      "Policies",
    ]);
    expect(links[0]).toHaveAttribute("aria-current", "page");

    await userEvent.click(
      within(panel as HTMLElement).getByRole("link", { name: "Credentials" }),
    );

    expect(router.state.location.pathname).toBe("/me/credentials");
    expect(button).toHaveAttribute("aria-expanded", "false");
    expect(panel).not.toBeInTheDocument();
  });

  test("the menu closes on Escape and returns focus to its button", async () => {
    renderLayout(sessionValue());
    const button = within(mainNav()).getByRole("button", { name: "Menu" });

    await userEvent.click(button);
    expect(button).toHaveAttribute("aria-expanded", "true");
    await userEvent.keyboard("{Escape}");

    expect(button).toHaveAttribute("aria-expanded", "false");
    expect(button).toHaveFocus();
  });

  test("has no axe violations with the open menu in the admin area", async () => {
    const { container } = renderLayout(
      sessionValue({ roles: ["learner", "admin"] }),
      "/admin/users",
    );
    await userEvent.click(
      within(mainNav()).getByRole("button", { name: "Menu" }),
    );

    await expectNoAxeViolations(container);
  });
});

test("server values render as text, never as markup", () => {
  const markup = "<img src=x onerror=alert(1)>";
  const { container } = renderLayout(
    sessionValue({
      user: {
        id: "8a4c7a5e-2f5b-4d6e-9c1a-3b2d4e5f6a7b",
        displayName: markup,
        email: null,
      },
    }),
  );

  expect(screen.getByRole("button", { name: markup })).toBeInTheDocument();
  expect(container.querySelector("img")).toBeNull();
});

test("a signed-out session shows no user menu", () => {
  renderLayout(sessionValue({ user: null, sessionStrength: null, roles: [] }));

  expect(
    screen.queryByRole("button", { name: "Test person 1" }),
  ).not.toBeInTheDocument();
  expect(screen.getByRole("link", { name: "Skip to content" })).toHaveAttribute(
    "href",
    "#main",
  );
});

test("the language switch translates the header", async () => {
  renderLayout(sessionValue());

  await userEvent.selectOptions(
    screen.getByRole("combobox", { name: "Language" }),
    "de",
  );

  expect(
    await screen.findByRole("link", { name: "Zum Inhalt springen" }),
  ).toBeInTheDocument();
  expect(screen.getByRole("combobox", { name: "Sprache" })).toHaveValue("de");
  expect(
    screen.getByRole("button", { name: /^Farbschema:/ }),
  ).toBeInTheDocument();
  expect(document.documentElement.lang).toBe("de");
});

test("the theme toggle cycles system, light and dark", async () => {
  renderLayout(sessionValue());
  const toggle = () => screen.getByRole("button", { name: /^Color theme:/ });

  expect(toggle()).toHaveAccessibleName("Color theme: system setting");
  await userEvent.click(toggle());
  expect(toggle()).toHaveAccessibleName("Color theme: light");
  expect(document.documentElement).not.toHaveClass("dark");
  await userEvent.click(toggle());
  expect(toggle()).toHaveAccessibleName("Color theme: dark");
  expect(document.documentElement).toHaveClass("dark");
  await userEvent.click(toggle());
  expect(toggle()).toHaveAccessibleName("Color theme: system setting");
});

test.each([false, true])(
  "the layout has no axe violations (dark mode: %s)",
  async (dark) => {
    document.documentElement.classList.toggle("dark", dark);
    const { container } = renderLayout(sessionValue({ flags: { demo: true } }));

    expect(await axe(container)).toHaveNoViolations();
  },
);
