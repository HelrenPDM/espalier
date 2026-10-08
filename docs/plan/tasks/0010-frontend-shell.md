# 0010: Frontend shell: Tailwind, routing, i18n, API client

> Milestone: M3 Learning, Depends on: 0004

## Context to read first
- `docs/plan/README.md`, sections 3 (Playwright 1.59.1), 5 (request flow), 6.2 (pathways and session strength), 6.5 (sessions, cookies, CSRF and the CSP), 6.10 (error codes), 6.12 (shared interfaces and the owners of the OpenAPI operations), 8 (`GET /api/session`, `DELETE /api/session`, `POST /api/auth/demo`), 9 (frontend structure, admin area, UI conventions), 10 (`REGISTRAR_ENABLED` and the registrar page), 12 (`make check`, `make e2e`, `make api-types`) and 16 (Playwright and nixpkgs).
- `docs/plan/tasks/0004-accounts-sessions.md`, step 31 (the error code `cross_site_request` of the Fetch Metadata plug), step 35 (the session payload of `GET /api/session` and the request body of `POST /api/auth/demo`) and step 42 (the ownership table of `docs/security/asvs-l2.md`, which assigns the rows of this task).
- `docs/plan/tasks/0009-learner-api.md`, step 15 (the `SessionPayload` of `GET /api/session`, from which `toSession` takes its parameter type) and step 16 (`make api-types`, which writes `src/api/schema.d.ts` and puts the re-export into `src/api/paths.ts`).
- `docs/architecture/session-lifecycle.puml` (the session states that the route guards tell apart).
- `frontend/` as generated in 0001 and extended in 0002, and `frontend/src/api/schema.d.ts` once `make api-types` of 0009 has generated it. README section 6.12 assigns the OpenAPI operations of the routes of 0004 to 0009.

## Goal
The SPA has its application frame: Tailwind CSS with the default palette, a
router with learner and admin areas and an error page, route guards by session
strength and role, a session context with the CSRF token, a typed API client
that sends and renews that token, a guarded listener for browser messages,
English and German UI strings, and light and dark mode. The route `/sign-in`
exists as a placeholder that 0011 fills with the sign-in flow. Playwright runs
end-to-end tests from the nix shell, signs in through `POST /api/auth/demo` and
checks the shell with axe.

## Scope
- In: The task sets up Tailwind with the theme tokens, the layout, the router with a `/sign-in` placeholder and an error page, `SessionProvider`, the API client with its CSRF middleware, TanStack Query, i18n, `RequireAuth` and `RequireRole`, the `return_to` validation, the message listener helper and an Oxlint rule against raw HTML.
- In: It sets up Playwright with demo sign-in and axe tests, and it fills the rows of this task in `docs/security/asvs-l2.md`.
- Out: Sign-in and account pages belong to 0011, player and learner pages including the program list to 0012, policy and credential pages to 0013, and admin pages to 0015. The OpenAPI operations of the routes of 0004 and of the learner routes, and the generated `src/api/schema.d.ts`, belong to 0009. The operations of the routes of 0005, 0006 and 0007 belong to 0011 (README section 6.12).
- Out: This task adds no database table and no protected column. It registers no rotation schema under `lib/espalier/crypto/rotation/` and adds no row to `docs/security/crypto-inventory.md`.

## Security requirements
The ownership table of the verification matrix (0004 step 42) assigns these rows to this task as owner:
- ASVS 3.2.2 (extended by 0011): React renders text through its escaping, and an Oxlint rule rejects `dangerouslySetInnerHTML`.
- ASVS 3.5.5: every listener for `message` events goes through `listenMessages` (step 10). It discards a window message from another origin and every message whose content fails its parser. The shell itself registers no listener.
- ASVS 7.4.4 (extended by 0011): every page behind `RequireAuth` shows the sign-out action in the header.

The SPA code and the tests of this task also extend these rows of other tasks:
- ASVS 3.5.1 (0004, also extended by 0011): the API client sends the CSRF token of the session in the `x-csrf-token` header on every POST, PUT, PATCH and DELETE request. After a 403 with the code `csrf`, it refetches the session and repeats the request once with the new token (step 6).
- ASVS 3.7.2 (0006): `return_to` accepts only a path on the application's own origin, so the redirect after sign-in stays on that origin.

## Steps
1. Install in `frontend/`: `tailwindcss`, `@tailwindcss/vite`, `@tailwindcss/typography`, `react-router`, `@tanstack/react-query`, `@headlessui/react`, `@heroicons/react`, `i18next`, `react-i18next`, `i18next-browser-languagedetector` and `openapi-fetch` (already present when 0009 has landed). Add `tailwindcss()` from `@tailwindcss/vite` to the Vite plugins.
2. Replace the generated styles with `src/styles/app.css`:
   ```css
   @import "tailwindcss";
   @plugin "@tailwindcss/typography";
   @custom-variant dark (&:where(.dark, .dark *));

   /* The only place an adopter changes the accent color. */
   @theme {
     --color-accent-50: var(--color-indigo-50);
     --color-accent-100: var(--color-indigo-100);
     --color-accent-500: var(--color-indigo-500);
     --color-accent-600: var(--color-indigo-600);
     --color-accent-700: var(--color-indigo-700);
   }

   @media print {
     .no-print { display: none; }
   }
   ```
   Delete `App.tsx`, `App.css`, `index.css` and the template's demo assets, and delete `App.test.tsx` of 0002; the layout test of step 14 takes over its axe check.
3. Theme: `src/app/theme.ts` sets the `dark` class on `<html>` from `localStorage` (key `theme`, values `light`, `dark` and `system`, default `system`; every access in `try/catch`) and from `prefers-color-scheme` for `system`. `main.tsx` applies it before the first render. `index.html` carries no inline script, because the CSP of README section 6.5 allows scripts from `'self'` only. A toggle in the header cycles the three values.
4. Client types: `src/api/paths.ts` provides the `paths` type, and every module of the SPA imports `paths` from it. `src/api/schema.d.ts` is a generated file: `make api-types` of 0009 step 16 writes it, the `.prettierignore` of 0002 lists it, and no file of this task writes it.
   - When 0009 has landed before this task, `schema.d.ts` exists and covers the routes of 0004 (README section 6.12), and `paths.ts` consists of `export type { paths } from "./schema";`.
   - When this task lands first, `schema.d.ts` is absent, and `paths.ts` declares `paths` by hand for `GET /api/session` (200 with the session payload of 0004 step 35) and `DELETE /api/session` (204), the answers that 0009 step 15 describes for these operations. 0011 adds the 200 answer with `logout_url` (README section 6.7) to the operation of `DELETE /api/session`. The declaration has the shape that openapi-typescript generates: one path item with `parameters`, the two operations and `responses` keyed by status with `content` per media type. A comment above it names 0009 step 16 as the step that replaces it with the re-export.
5. Errors: `src/api/errors.ts` exports `CSRF_ERROR_CODE = "csrf"`, the code of README section 6.10 for a rejected anti-forgery token, and `errorCode(response: Response): Promise<string | null>`, which reads `error` from the JSON body of a clone of the response and returns `null` for any other body.
6. API client: `src/api/queryClient.ts` exports the application's `queryClient` (`new QueryClient()`). `src/api/client.ts` exports `createApiClient(queryClient, fetchImpl = globalThis.fetch)` and the application instance `api = createApiClient(queryClient)`. `createApiClient` calls `createClient<paths>({ baseUrl: "", credentials: "same-origin", fetch: fetchImpl })` and registers one middleware with `client.use()`:
   - `onRequest` sets `x-csrf-token` on every POST, PUT, PATCH and DELETE request to the `csrfToken` of the cached session (`queryClient.getQueryData(sessionQueryKey)`) and keeps `request.clone()` in a `WeakMap` keyed by the request for one retry.
   - `onResponse` invalidates the session query on a 401. On a 403 whose `errorCode` is `CSRF_ERROR_CODE`, it refetches the session with `queryClient.fetchQuery({ ...sessionQueryOptions(client), staleTime: 0 })`, sets the new token on the kept clone, sends the clone once through `fetchImpl` and returns that response. A second 403 reaches the caller unchanged. A 403 with any other code, for example `cross_site_request` from the Fetch Metadata plug of 0004 step 31, reaches the caller without a refetch.

   The CSRF token lives only in the TanStack Query cache in memory. No code writes it to `localStorage` or `sessionStorage`.
7. Session: `src/api/session.ts` imports types only and exports `sessionQueryKey` (`["session"]`), `sessionQueryOptions(client)` and `toSession(payload)`. `sessionQueryOptions` returns that key and a `queryFn` that calls `GET /api/session` through the given client, throws on an error answer and returns `toSession(data)`, so the cache holds the client shape. `toSession` is the one function that maps the payload to the client shape. Its parameter type is `paths["/api/session"]["get"]["responses"][200]["content"]["application/json"]`, so it keeps compiling when 0009 regenerates the schema. Because the refetch in step 6 goes through the same client, a test with a stubbed `fetchImpl` sees it. `toSession` returns:
   - `user`: `{ id, displayName }` from `user.id` and `user.display_name`, and `null` when `user` is `null` (signed out, or a second factor is pending).
   - `roles`: the role names from `roles`.
   - `sessionStrength`: `session.strength` (`mfa`, `enrollment`, `recovery` or `demo`, README section 6.2), and `null` when `session` is `null`.
   - `csrfToken`: `csrf_token`, the value for the `x-csrf-token` header.
   - `providers`: the public provider entries of README section 6.12 as received; 0011 renders them.
   - `flags`: at least `demo` from `flags.demo`.

   `src/api/sessionHooks.ts` exports `useSessionQuery()`, which calls `useQuery(sessionQueryOptions(api))`, and `deleteSession()`, which sends `DELETE /api/session` through `api` and returns the response. `src/auth/SessionProvider.tsx` exports `SessionContext`, `SessionProvider` and `useSession()`. `SessionProvider` reads the session through `useSessionQuery()` and provides the fields above, a loading flag and `signOut()` through `SessionContext`. `signOut()` calls `deleteSession()`, treats every 2xx answer as success (204, or 200 with the `logout_url` of README section 6.7, which 0011 follows), clears the query cache, refetches the session and navigates to `/sign-in`. `useSession()` reads `SessionContext`, so component tests render the guards and the layout inside `SessionContext.Provider` with a fixed value.
8. Router: `src/app/router.tsx` with React Router's data router (`createBrowserRouter`, `RouterProvider`). The root route renders `SessionProvider` around `Layout`, so `signOut()` navigates with `useNavigate()`, and `Layout` wraps every route. `main.tsx` imports `src/i18n/index.ts` and renders `QueryClientProvider` with the `queryClient` of `src/api/queryClient.ts` around `RouterProvider`. The routes are `/sign-in` (a placeholder page with a heading and one sentence, which 0011 replaces with the sign-in flow), `/` (a home placeholder until 0012 adds the program list), `/programs/:slug` and `/programs/:slug/stations/:position` (placeholders until 0012), `/me/credentials` and `/me/credentials/:id` (placeholders until 0013), `/admin/*` (placeholder until 0015) and a not-found page. The root route sets `errorElement` to `src/app/ErrorPage.tsx`, which shows a translated message and a link to `/`. Every route except `/sign-in` and the not-found page sits under `RequireAuth`.
   - `RequireAuth` renders a loading state in a `role="status"` region while the session query loads, and it redirects nothing during that time. It renders its children when `user` is set and `sessionStrength` is `mfa` or `demo`. Every other state redirects to `/sign-in?return_to=<encodeURIComponent(pathname + search)>`. This includes a session that waits for a second factor, an enrollment session and a recovery session (`session-lifecycle.puml`), whose flows 0011 continues on `/sign-in`.
   - `RequireRole` takes `anyOf` (a list of role names) and renders a 403 page when the session holds none of them. `/admin/*` uses `anyOf={["author", "admin", "facilitator", "analyst", "registrar"]}`, the roles that the admin navigation of 0015 step 5 serves: packs for authors, the administration pages for admins, attendance for facilitators, the reports of 0014 for analysts and the credential list for registrars. The registrar page `/admin/registrar` belongs to the admin area of README section 9, and README section 10 ties it to `REGISTRAR_ENABLED`. 0015 shows each section only to its role.
   - `src/auth/returnTo.ts` exports `safeReturnTo(value: string | null): string`. It returns the value when the value starts with `/`, its second character is a character other than `/`, and it contains no backslash and no character below U+0020. In every other case it returns `/`. 0011 reads `return_to` through this function.
9. Layout: `src/app/Layout.tsx` with a skip link, a header (product name from `VITE_PRODUCT_NAME` with default `Espalier`, theme toggle, language switch, and for a signed-in session a user menu with the display name and sign-out), `<main id="main">`, and a demo banner on every page, including `/sign-in`, when `flags.demo` is true (README section 6.2, rule 5). Use only Tailwind utilities, neutral grays and `accent` for interactive states.
10. Messages: `src/app/messages.ts` exports `listenMessages<T>(target: Window | BroadcastChannel, parse: (data: unknown) => T | null, handler: (message: T) => void): () => void`. It adds one `message` listener to `target`. For a `Window` target it drops every event whose `origin` differs from `window.location.origin`. A `BroadcastChannel` delivers messages from the same origin only (HTML Living Standard, section "Broadcasting to other browsing contexts"). For every target it drops the event when `parse(event.data)` returns `null` and otherwise calls `handler` with the parsed value. The returned function removes the listener. Every `message` listener of the SPA uses this function.
11. i18n: `src/i18n/index.ts` with `en.json` and `de.json`. `i18next-browser-languagedetector` runs with `order: ["localStorage", "navigator"]` and `caches: ["localStorage"]`, so the choice stays under the detector's default key `i18nextLng`; the fallback language is `en`. Every UI string in this task goes through `t()`.
12. Lint: add `"react/no-danger": "error"` to `rules` in `frontend/.oxlintrc.json`. The `react-ts` template writes that file with the `react` plugin enabled, and Oxlint reports a violation as `react(no-danger)`.
13. Playwright: run `nix-shell --run "npm --prefix frontend install --save-dev --save-exact @playwright/test@1.59.1"` (1.59.1 is the version of `playwright-driver` in the pinned nixpkgs; never upgrade one side alone) and `nix-shell --run "npm --prefix frontend install --save-dev @axe-core/playwright"`. Write `playwright.config.ts` with `testDir: "e2e"`, `use: { baseURL: "http://localhost:5173" }`, one Chromium project, and a `webServer` with `command: "make run"`, `cwd: ".."`, `url: "http://localhost:5173/health"`, `reuseExistingServer: true` and `timeout: 180_000`. The Vite proxy forwards `/health` to Phoenix, so the URL answers 200 once both servers run. Add `playwright.config.ts` and `e2e/` to the `include` list of `tsconfig.node.json`, so that `tsc -b` checks them, and set `test.include` in `vite.config.ts` to `["src/**/*.test.{ts,tsx}"]`, so that Vitest leaves the specs in `e2e/` to Playwright. Write `e2e/support/demo.ts` with `signInAsDemo(page, slot)`. The helper opens `/sign-in`, runs `page.evaluate` there and makes two same-origin `fetch` calls inside the page: `GET /api/session` for the CSRF token, then `POST /api/auth/demo` with `content-type: application/json`, the `x-csrf-token` header and the body `{"slot": slot}` (a slot from 1 to 20, 0004 step 35). It throws on a status outside 200 to 299. The browser therefore sends the session cookie and the `Origin` and `Sec-Fetch-Site` headers in the same way as for the SPA. Write `e2e/shell.spec.ts` with four tests:
    - Opening `/programs/demo` while signed out lands on `/sign-in?return_to=%2Fprograms%2Fdemo`.
    - After `signInAsDemo(page, 1)`, opening `/` shows the home heading, the display name `Test person 1` in the user menu and the demo banner.
    - After sign-in, choosing sign-out in the user menu leads to `/sign-in`, and opening `/` afterwards redirects to `/sign-in` again.
    - With the color scheme emulated as light and then as dark (`page.emulateMedia({ colorScheme })` before each navigation), `/sign-in` while signed out and `/` after `signInAsDemo(page, 2)` show no violations in `new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"]).analyze()`.

    Add the Makefile target `e2e` with the help comment `## Run the Playwright tests against make run`, which runs `$(NIX) "cd frontend && npx playwright test"`.
14. Component tests with Vitest and Testing Library:
    - `src/api/client.test.ts` uses a stubbed `fetchImpl`. It checks that POST, PUT, PATCH and DELETE requests carry `x-csrf-token` and that a GET request goes out without that header. It checks that a 403 with `CSRF_ERROR_CODE` triggers one session refetch and one retry with the new token, that a 403 with `cross_site_request` triggers neither, and that a 401 invalidates the session query.
    - `src/auth/returnTo.test.ts` checks that `/programs/demo?x=1` passes unchanged, and that `//evil.example`, `/\evil.example`, `https://evil.example`, `javascript:alert(1)`, a value with a tab character and `null` each yield `/`.
    - `src/app/messages.test.ts` dispatches `MessageEvent`s on `window`. It checks that a valid message from `window.location.origin` reaches the handler once, that a message from `https://evil.example` and a same-origin message that the parser rejects never reach it, and that no message reaches it after the returned function has run.
    - `src/app/guards.test.tsx` renders the guards inside `SessionContext.Provider`. It checks that `RequireAuth` shows the loading state while the session loads, redirects a signed-out session with the encoded `return_to`, redirects a `recovery` session, and renders its children for `mfa` and `demo`. It checks that `RequireRole` renders the 403 page for a learner on `/admin`, renders the admin placeholder for an analyst and for a registrar, and that a route component that throws renders the error page.
    - `src/app/Layout.test.tsx` checks that the demo banner appears with `flags.demo: true` and is absent otherwise, that a signed-in session shows sign-out, and that the layout has no axe violations in light and dark mode.
15. Verification matrix: update the rows of `docs/security/asvs-l2.md` that the ownership table of 0004 step 42 names for this task. The rows 3.2.2, 3.5.5 and 7.4.4 list this task first, and the rows 3.5.1 and 3.7.2 list it after 0004 and 0006. Each row names the code and the test of this task, and its `Notes` state what this task delivers and what remains for the other tasks the row names. The row 3.5.5 names no other task and takes the status `verified`. Every other row keeps the status that 0004 step 42 prescribes until each task it names has added its part.

## Deliverables
- `frontend/src/{app,api,auth,i18n,styles}/`, among them `src/api/paths.ts`, `queryClient.ts`, `client.ts`, `errors.ts`, `session.ts` and `sessionHooks.ts`; updated `main.tsx`, `vite.config.ts`, `tsconfig.node.json`, `package.json` and `.oxlintrc.json`.
- `frontend/playwright.config.ts`, `frontend/e2e/support/demo.ts`, `frontend/e2e/shell.spec.ts`, Makefile target `e2e`.
- The rows 3.2.2, 3.5.5 and 7.4.4 of `docs/security/asvs-l2.md` with this task as owner, and the code and the tests of this task in the rows 3.5.1 and 3.7.2.

## Acceptance
- [ ] `make check` passes (type check, Oxlint, Prettier, Vitest).
- [ ] With `AUTH_DEMO=true`, `make e2e` passes the four tests of `e2e/shell.spec.ts`, including the axe checks in light and dark mode.
- [ ] `nix-shell --run "npm --prefix frontend run test -- --run src/api/client.test.ts"` passes, including the retry after a 403 with `CSRF_ERROR_CODE`.
- [ ] Adding `<div dangerouslySetInnerHTML={{ __html: "x" }} />` to a component makes `nix-shell --run "npm --prefix frontend run lint"` exit 1 with `react(no-danger)`; reverting it makes the command exit 0.
- [ ] Switching the language changes every visible string on the `/sign-in` placeholder, the 403 page, the not-found page, the error page and the header.
- [ ] Changing the `--color-accent-*` values in `app.css` to another Tailwind color changes every accent in the UI, and `grep -rn "#[0-9a-fA-F]\{3,6\}" frontend/src` finds nothing.
- [ ] Keyboard only: the skip link, the theme toggle, the language switch and the user menu with sign-out are reachable and operable.
- [ ] `grep -rn -E "localStorage|sessionStorage" frontend/src` lists only the theme setting and the language detection.
- [ ] `grep -rn -E "addEventListener\(\s*[\"']message[\"']|onmessage" frontend/src` lists only `src/app/messages.ts`.
- [ ] `grep -rn "api/client" frontend/src` finds no import, because only modules inside `src/api/` import the client, as `./client`.
- [ ] `frontend/package.json` lists `@playwright/test` with the exact version `1.59.1`.
- [ ] No file of this task writes `src/api/schema.d.ts`. When that file exists, `src/api/paths.ts` consists of `export type { paths } from "./schema";`. When it is absent, `paths.ts` declares `paths` by hand for `GET /api/session` and `DELETE /api/session`.
- [ ] The rows 3.2.2, 3.5.5 and 7.4.4 of `docs/security/asvs-l2.md` list this task first with its code and test, the rows 3.5.1 and 3.7.2 list this task after their owners 0004 and 0006 and name its code and test, and the row 3.5.5 has the status `verified`.

## Notes
- React Router ships major versions often; README section 3 names 8.4. Use the data router API of the installed version and follow its SPA guide; the route list above stays the same.
- Keep all fetch calls of the application inside `src/api/`. Components use query hooks. Only modules inside `src/api/` import `src/api/client.ts`: `SessionProvider` uses `src/api/sessionHooks.ts`, and `main.tsx` takes `queryClient` from `src/api/queryClient.ts`. The check of 0012 step 15 (`src/test/boundaries.test.ts`), under which no file under `src/player/` or `src/learner/` imports `src/api/client.ts`, therefore holds from the start. The Playwright helper calls `fetch` inside the page on purpose, so that its requests carry the headers the browser sets for the SPA.
- `RequireAuth` and `RequireRole` decide what the SPA shows. The server enforces every role check (0004, ASVS 8.3.1), and a hidden link grants no access.
- The server check of the `x-csrf-token` header belongs to 0004, the owner of the rows 3.5.1 to 3.5.3 in the ownership table of 0004 step 42. This task extends the row 3.5.1 with the client of step 6, which sends the token that this check expects, and 0011 extends it with the refetch after every session change and across tabs.
- The server rotates the CSRF token at sign-in (README section 6.4, `session-lifecycle.puml`) and issues a new session token at every sign-in, step-up and role change (README section 6.5). 0011 refetches the session after each of its sign-in and step-up steps, and the retry after a 403 covers a token that went stale, for example in another tab. `Plug.CSRFProtection` rejects the request in the router pipeline before any controller runs (0004 step 33, `protect_api_from_forgery`), so the single retry cannot apply a change twice.
- `toSession()`, `CSRF_ERROR_CODE` and the demo request body are the only places that depend on names fixed outside this task: the session payload and the demo body of 0004 step 35, and the error code `csrf` of README section 6.10.
- Playwright starts the `webServer` command with an open standard input pipe. In playwright 1.59.1, `lib/plugins/webServerPlugin.js` passes `stdio: "stdin"` to `launchProcess`, and in playwright-core 1.59.1, `lib/server/utils/processLauncher.js` turns every value other than `"pipe"` into `["pipe", "pipe", "pipe"]`. The `iex` session of `make run` therefore keeps running. IEx stops the node when its standard input reaches end of file, so `make run < /dev/null` ends the server at once.
- Playwright stays at 1.59.1 to match `playwright-driver` in the pinned nixpkgs (README section 3). The passkey tests of 0011 use the Chromium DevTools virtual authenticator, because the cross-browser `browserContext.credentials` API needs Playwright 1.61 (README section 16).
