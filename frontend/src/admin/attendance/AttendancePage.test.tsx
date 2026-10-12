import { fireEvent, screen, waitFor, within } from "@testing-library/react";
import { describe, expect, test } from "vitest";
import { utcToday } from "../../api/admin/attendance";
import type { ProgramSummary } from "../../api/programs";
import { expectNoAxeViolations } from "../../test/axe";
import {
  renderWithProviders,
  requestsTo,
  type StubResponses,
} from "../../test/render";
import { signedInPayload } from "../../test/session";
import { AttendancePage } from "./AttendancePage";

/**
 * Task 0015 step 17: `/admin/attendance` offers the formats with
 * `attendance_counts: true` of a published program, a day from 2000-01-01
 * to today, and people found by the exact address through
 * `POST /api/facilitator/user-lookups` (the address in the body). It sends
 * `POST /api/formats/:id/attendance` and shows the result per person, and
 * it shows the 422 `validation_failed` of the route with `fields.held_on`
 * `["future"]` or `["past"]` at the date field.
 */
const WORKSHOP = "3c1d2e3f-4a5b-4c6d-8e7f-9a0b1c2d3e4f";
const NEWSLETTER = "4d2e3f4a-5b6c-4d7e-9f8a-0b1c2d3e4f5a";
const ADA = "5b1f7c2e-3d4a-4e6b-8c9d-0e1f2a3b4c5d";
const BEN = "6c2a8d3f-4e5b-4f7c-9d0e-1f2a3b4c5d6e";
const LOOKUP = "/api/facilitator/user-lookups";
const ATTENDANCE = `/api/formats/${WORKSHOP}/attendance`;

const programs: ProgramSummary[] = [
  { slug: "demo", title: "Demo-Programm", locale: "de" },
];

/** The members of `ProgramView` that the page reads. */
const program = {
  id: "7e3f4a5b-6c7d-4e8f-8a9b-0c1d2e3f4a5b",
  slug: "demo",
  title: "Demo-Programm",
  locale: "de",
  pack_version: "1.0.0",
  modules: [],
  segments: [],
  stations: [],
  companion_formats: [
    {
      id: WORKSHOP,
      key: "workshop",
      title: "Praxis-Workshop",
      description: "Ein Workshop vor Ort.",
      phases: ["apply"],
      attendance_counts: true,
    },
    {
      id: NEWSLETTER,
      key: "newsletter",
      title: "Newsletter",
      description: "Ein Newsletter.",
      phases: ["update"],
      attendance_counts: false,
    },
  ],
};

const people: Record<string, unknown> = {
  "ada@example.test": {
    id: ADA,
    display_name: "Ada Example",
    org_unit: "Newsroom",
  },
  "ben@example.test": { id: BEN, display_name: null, org_unit: null },
};

const facilitator = signedInPayload("mfa", {
  roles: ["learner", "facilitator"],
});

function renderPage(responses: StubResponses = {}) {
  return renderWithProviders(<AttendancePage />, {
    route: "/admin/attendance",
    session: facilitator,
    responses: {
      "GET /api/programs": { status: 200, body: { programs } },
      "GET /api/programs/demo": { status: 200, body: program },
      [`POST ${LOOKUP}`]: (request) => {
        const { email } = request.body as { email: string };
        const person = people[email.trim().toLowerCase()];
        return person === undefined
          ? { status: 404, body: { error: "not_found" } }
          : { status: 200, body: person };
      },
      ...responses,
    },
  });
}

const formatField = () => screen.findByRole("combobox", { name: "Format" });
const dateField = () => screen.getByLabelText("Day of the session");
const emailField = () =>
  screen.getByRole("textbox", { name: "E-mail address" });

/** Sets the value of the date field, as the browser's date picker does. */
const setDay = (value: string) =>
  fireEvent.change(dateField(), { target: { value } });

async function addPerson(
  user: ReturnType<typeof renderPage>["user"],
  email: string,
) {
  await user.clear(emailField());
  await user.type(emailField(), email);
  await user.click(screen.getByRole("button", { name: "Add the person" }));
}

describe("the attendance page", () => {
  test("offers only the formats whose attendance counts, in the language of the program", async () => {
    renderPage();

    const formats = await formatField();
    expect(
      within(formats)
        .getAllByRole("option")
        .map((option) => [option.textContent, option.getAttribute("lang")]),
    ).toEqual([
      ["Choose a format", null],
      ["Praxis-Workshop", "de"],
    ]);
    expect(
      screen.getByRole("combobox", { name: "Program" }),
    ).toHaveDisplayValue("Demo-Programm");
    expect(dateField()).toHaveAttribute("min", "2000-01-01");
    expect(dateField()).toHaveAttribute("max", utcToday());
    expect(dateField()).toHaveAccessibleDescription(
      "A day from Jan 1, 2000 to today.",
    );
  });

  test("looks people up by the address in the body and lists them", async () => {
    const { user, requests } = renderPage();
    await formatField();

    await addPerson(user, " Ada@Example.test ");
    expect(
      await screen.findByText("Ada Example is added to the list."),
    ).toBeInTheDocument();
    await addPerson(user, "ben@example.test");
    await screen.findByText("ben@example.test is added to the list.");

    const lookups = requestsTo(requests, "POST", LOOKUP);
    expect(lookups.map((request) => request.body)).toEqual([
      { email: "Ada@Example.test" },
      { email: "ben@example.test" },
    ]);
    expect(lookups[0].headers.get("x-csrf-token")).toBe("csrf-1");
    const list = screen.getByRole("list", { name: "2 people on the list" });
    expect(
      within(list)
        .getAllByRole("listitem")
        .map((item) => item.textContent),
    ).toEqual([
      "Ada ExampleNewsroom, Ada@Example.testRemove Ada Example",
      "ben@example.testben@example.testRemove ben@example.test",
    ]);

    // An unknown address and a second lookup of a listed person add nobody.
    await addPerson(user, "nobody@example.test");
    expect(emailField()).toHaveAccessibleDescription(
      expect.stringContaining("No active account has this address."),
    );
    await addPerson(user, "ada@example.test");
    expect(emailField()).toHaveAccessibleDescription(
      expect.stringContaining("Ada Example is already on the list."),
    );
    expect(within(list).getAllByRole("listitem")).toHaveLength(2);

    await user.click(
      within(list).getByRole("button", { name: "Remove Ada Example" }),
    );
    expect(
      screen.getByRole("list", { name: "1 person on the list" }),
    ).toBeInTheDocument();
    expect(emailField()).toHaveFocus();
  });

  test("records the attendance and shows the result per person", async () => {
    const { user, requests } = renderPage({
      [`POST ${ATTENDANCE}`]: {
        status: 200,
        body: {
          results: [
            { user_id: ADA, result: "issued" },
            { user_id: BEN, result: "exists" },
          ],
        },
      },
    });
    await user.selectOptions(await formatField(), WORKSHOP);
    setDay("2026-10-01");
    await addPerson(user, "ada@example.test");
    await screen.findByText("Ada Example is added to the list.");
    await addPerson(user, "ben@example.test");
    await screen.findByText("ben@example.test is added to the list.");

    await user.click(screen.getByRole("button", { name: "Record attendance" }));

    const results = await screen.findByRole("table", { name: "Result" });
    expect(
      within(results)
        .getAllByRole("row")
        .slice(1)
        .map((row) => row.textContent),
    ).toEqual([
      "Ada ExampleCertificate issued",
      "ben@example.testAlready recorded for this format and day",
    ]);
    expect(
      screen.getByText("The attendance of 2 people is processed."),
    ).toBeInTheDocument();
    const [post] = requestsTo(requests, "POST", ATTENDANCE);
    expect(post.body).toEqual({ user_ids: [ADA, BEN], held_on: "2026-10-01" });
    expect(post.headers.get("x-csrf-token")).toBe("csrf-1");
  });

  test("checks format, day and people before it sends", async () => {
    const { user, requests } = renderPage();
    await formatField();

    await user.click(screen.getByRole("button", { name: "Record attendance" }));
    expect(await formatField()).toHaveAccessibleDescription("Choose a format.");
    expect(dateField()).toHaveAccessibleDescription(
      expect.stringContaining("Enter the day of the session."),
    );
    expect(screen.getByText("Add at least one person.")).toBeInTheDocument();
    expect(screen.getByRole("alert")).toHaveTextContent(
      "Check the marked fields.",
    );

    // The day lies between 2000-01-01 and today.
    setDay("2999-01-01");
    await user.click(screen.getByRole("button", { name: "Record attendance" }));
    expect(dateField()).toHaveAttribute("aria-invalid", "true");
    expect(dateField()).toHaveAccessibleDescription(
      expect.stringContaining("The day of the session cannot be after today."),
    );
    setDay("1999-12-31");
    await user.click(screen.getByRole("button", { name: "Record attendance" }));
    expect(dateField()).toHaveAccessibleDescription(
      expect.stringContaining(
        "Attendance records start on Jan 1, 2000. Enter a later day.",
      ),
    );
    expect(requests.filter((request) => request.path === ATTENDANCE)).toEqual(
      [],
    );
  });

  test.each([
    ["future", "The day of the session cannot be after today."],
    ["past", "Attendance records start on Jan 1, 2000. Enter a later day."],
  ])(
    "shows the 422 answer with held_on %s at the date field",
    async (code, message) => {
      const { user } = renderPage({
        [`POST ${ATTENDANCE}`]: {
          status: 422,
          body: { error: "validation_failed", fields: { held_on: [code] } },
        },
      });
      await user.selectOptions(await formatField(), WORKSHOP);
      // The server decides on its own clock, so the page shows its answer.
      setDay(utcToday());
      await addPerson(user, "ada@example.test");
      await screen.findByText("Ada Example is added to the list.");

      await user.click(
        screen.getByRole("button", { name: "Record attendance" }),
      );

      await waitFor(() =>
        expect(dateField()).toHaveAttribute("aria-invalid", "true"),
      );
      expect(dateField()).toHaveAccessibleDescription(
        expect.stringContaining(message),
      );
      expect(
        screen.queryByRole("table", { name: "Result" }),
      ).not.toBeInTheDocument();
    },
  );

  test("says when the program has no format whose attendance counts", async () => {
    renderPage({
      "GET /api/programs/demo": {
        status: 200,
        body: {
          ...program,
          companion_formats: program.companion_formats.slice(1),
        },
      },
    });

    expect(
      await screen.findByText(
        "This program has no format whose attendance counts as evidence.",
      ),
    ).toBeInTheDocument();
  });

  test("has no axe violations with a list and its results", async () => {
    const { container, user } = renderPage({
      [`POST ${ATTENDANCE}`]: {
        status: 200,
        body: { results: [{ user_id: ADA, result: "not_found" }] },
      },
    });
    await user.selectOptions(await formatField(), WORKSHOP);
    setDay("2026-10-01");
    await addPerson(user, "ada@example.test");
    await screen.findByText("Ada Example is added to the list.");
    await user.click(screen.getByRole("button", { name: "Record attendance" }));
    await screen.findByText("No active account, nothing recorded");

    await expectNoAxeViolations(container);
  });
});
