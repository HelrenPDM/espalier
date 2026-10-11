import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import { createMemoryRouter, Outlet, RouterProvider } from "react-router";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { SessionContext } from "../auth/SessionProvider";
import i18n from "../i18n";
import { sessionValue } from "../test/session";
import { appRoutes, createRoutes } from "./router";

function renderAt(path: string) {
  const Thrower = () => {
    throw new Error("route failed");
  };
  const router = createMemoryRouter(
    createRoutes(<Outlet />, [
      ...appRoutes,
      { path: "boom", Component: Thrower },
    ]),
    { initialEntries: [path] },
  );
  render(
    <QueryClientProvider client={new QueryClient()}>
      <SessionContext.Provider
        value={sessionValue({
          roles: ["learner"],
          ...(path === "/sign-in"
            ? { user: null, sessionStrength: null, roles: [] }
            : {}),
        })}
      >
        <RouterProvider router={router} />
      </SessionContext.Provider>
    </QueryClientProvider>,
  );
}

beforeEach(async () => {
  await i18n.changeLanguage("de");
});

afterEach(async () => {
  await i18n.changeLanguage("en");
});

test.each([
  [
    "/sign-in",
    "Anmelden",
    "Kein Zugriff mehr auf Ihre Anmeldemethoden?",
    false,
  ],
  [
    "/admin",
    "Kein Zugriff",
    "Ihre Rollen schließen diesen Bereich nicht ein.",
    true,
  ],
  [
    "/no/such/page",
    "Seite nicht gefunden",
    "Unter dieser Adresse gibt es keine Seite.",
    true,
  ],
  [
    "/boom",
    "Ein Fehler ist aufgetreten",
    "Die Seite konnte nicht angezeigt werden. Bitte versuchen Sie es später erneut.",
    true,
  ],
])("%s renders in German", (path, title, text, homeLink) => {
  const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
  renderAt(path);

  expect(
    screen.getByRole("heading", { level: 1, name: title }),
  ).toBeInTheDocument();
  expect(screen.getByText(text)).toBeInTheDocument();
  if (homeLink) {
    expect(
      screen.getByRole("link", { name: "Zur Startseite" }),
    ).toBeInTheDocument();
  }
  consoleError.mockRestore();
});
