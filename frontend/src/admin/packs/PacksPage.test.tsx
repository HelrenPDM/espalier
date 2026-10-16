import { screen, waitFor } from "@testing-library/react";
import { describe, expect, test } from "vitest";
import type { PackImport } from "../../api/admin/packs";
import { renderWithProviders, requestsTo } from "../../test/render";
import { signedInPayload } from "../../test/session";
import { PacksPage } from "./PacksPage";

/**
 * Task 0015 step 11: the upload form of `/admin/packs`. The archive goes to
 * `POST /api/admin/packs` as `multipart/form-data` with the field `file` and
 * the CSRF header of the session; after an upload the page moves to
 * `/admin/packs/:id`. A 413, a 415 and a 422 `archive_rejected` with its
 * report stay on the page with a message.
 */
const ID = "00000000-0000-4000-8000-000000000601";
const author = signedInPayload("mfa", { roles: ["learner", "author"] });

const created: PackImport = {
  id: ID,
  status: "failed",
  pack_key: "demo",
  pack_version: "1.0.0",
  inserted_at: "2026-10-12T09:30:00Z",
  published_at: null,
  payload: null,
  report: { errors: [], warnings: [] },
  alignment: { mode: null, matrix: null, errors: [], warnings: [] },
  media: {},
  media_policy: { external_hosts: [], embed_hosts: [], embed_consent: "click" },
};

function renderPage(answer: { status: number; body?: unknown }) {
  return renderWithProviders(<PacksPage />, {
    route: "/admin/packs",
    session: author,
    responses: { "POST /api/admin/packs": answer },
  });
}

const archive = () =>
  new File(["zip archive"], "demo.zip", { type: "application/zip" });

describe("PacksPage", () => {
  test("uploads the archive as multipart/form-data and moves to the import", async () => {
    const { user, requests, location } = renderPage({
      status: 201,
      body: created,
    });

    await user.upload(screen.getByLabelText("Pack archive (zip)"), archive());
    await user.click(screen.getByRole("button", { name: "Upload" }));

    await waitFor(() => expect(location()).toBe(`/admin/packs/${ID}`));
    const [upload] = requestsTo(requests, "POST", "/api/admin/packs");
    expect(upload.headers.get("content-type")).toMatch(
      /^multipart\/form-data; boundary=/,
    );
    expect(upload.headers.get("x-csrf-token")).toBe("csrf-1");
    expect(String(upload.body)).toMatch(
      /Content-Disposition: form-data; name="file"/,
    );
  });

  test("asks for an archive before it sends anything", async () => {
    const { user, requests } = renderPage({ status: 201, body: created });

    await user.click(screen.getByRole("button", { name: "Upload" }));

    expect(screen.getByRole("alert")).toHaveTextContent(
      "Choose a zip archive.",
    );
    expect(screen.getByLabelText("Pack archive (zip)")).toHaveAttribute(
      "aria-invalid",
      "true",
    );
    expect(requestsTo(requests, "POST", "/api/admin/packs")).toHaveLength(0);
  });

  test("shows the report of a rejected archive", async () => {
    const { user, location } = renderPage({
      status: 422,
      body: {
        error: "archive_rejected",
        report: {
          errors: [
            {
              file: "../../etc/passwd",
              line: null,
              message: "the entry name contains a `..` component",
            },
          ],
          warnings: [],
        },
      },
    });

    await user.upload(screen.getByLabelText("Pack archive (zip)"), archive());
    await user.click(screen.getByRole("button", { name: "Upload" }));

    const alert = await screen.findByRole("alert");
    await waitFor(() =>
      expect(alert).toHaveTextContent(
        "The archive was rejected before its extraction:",
      ),
    );
    expect(alert).toHaveTextContent(
      "../../etc/passwd, no line: the entry name contains a `..` component",
    );
    expect(location()).toBe("/admin/packs");
  });

  test.each([
    [413, "The archive exceeds the upload limit of this instance."],
    [
      415,
      "The server accepts the pack only as a zip archive in a form upload.",
    ],
  ])("a %i answer shows its message", async (status, message) => {
    const { user } = renderPage({
      status,
      body: {
        error: status === 413 ? "request_too_large" : "unsupported_media_type",
      },
    });

    await user.upload(screen.getByLabelText("Pack archive (zip)"), archive());
    await user.click(screen.getByRole("button", { name: "Upload" }));

    await waitFor(() =>
      expect(screen.getByRole("alert")).toHaveTextContent(message),
    );
  });
});
