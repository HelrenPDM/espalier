import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { createMemoryRouter, RouterProvider } from "react-router";
import { afterEach, describe, expect, test } from "vitest";
import { axe } from "vitest-axe";
import {
  SessionContext,
  type SessionContextValue,
} from "../auth/SessionProvider";
import i18n from "../i18n";
import { sessionValue } from "../test/session";
import { Layout } from "./Layout";

function renderLayout(value: SessionContextValue) {
  const router = createMemoryRouter([
    {
      path: "/",
      element: <Layout />,
      children: [{ index: true, element: <h1>Home</h1> }],
    },
  ]);
  return render(
    <SessionContext.Provider value={value}>
      <RouterProvider router={router} />
    </SessionContext.Provider>,
  );
}

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

test("the user menu links to the credentials and the policies (task 0013)", async () => {
  renderLayout(sessionValue());

  await userEvent.click(screen.getByRole("button", { name: "Test person 1" }));

  expect(screen.getByRole("menuitem", { name: "Credentials" })).toHaveAttribute(
    "href",
    "/me/credentials",
  );
  expect(screen.getByRole("menuitem", { name: "Policies" })).toHaveAttribute(
    "href",
    "/policies",
  );
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
