import { screen, waitFor, within } from "@testing-library/react";
import { useState } from "react";
import { afterEach, describe, expect, test, vi } from "vitest";
import { productName } from "../app/product";
import { expectNoAxeViolations } from "../test/axe";
import { renderWithProviders } from "../test/render";
import { signedInPayload } from "../test/session";
import { RecoveryCodesPanel } from "./RecoveryCodesPanel";
import { takeReturnTo } from "../auth/returnTo";

/** Ten codes in the display form of 0005 step 11. */
const CODES = [
  "ABCD-EFGH-IJKL-MNOP-QRST-UVWX-YZ",
  "BCDE-FGHI-JKLM-NOPQ-RSTU-VWXY-Z2",
  "CDEF-GHIJ-KLMN-OPQR-STUV-WXYZ-23",
  "DEFG-HIJK-LMNO-PQRS-TUVW-XYZ2-34",
  "EFGH-IJKL-MNOP-QRST-UVWX-YZ23-45",
  "FGHI-JKLM-NOPQ-RSTU-VWXY-Z234-56",
  "GHIJ-KLMN-OPQR-STUV-WXYZ-2345-67",
  "HIJK-LMNO-PQRS-TUVW-XYZ2-3456-7A",
  "IJKL-MNOP-QRST-UVWX-YZ23-4567-AB",
  "JKLM-NOPQ-RSTU-VWXY-Z234-567A-BC",
];

/** Holds the codes in state, as the callers do, and clears them in `onDone`. */
function Holder({ onDone }: { onDone?: () => void }) {
  const [codes, setCodes] = useState<string[] | null>(CODES);
  if (codes === null) return <p>Codes cleared</p>;
  return (
    <RecoveryCodesPanel
      codes={codes}
      onDone={() => {
        setCodes(null);
        onDone?.();
      }}
    />
  );
}

const renderPanel = (onDone?: () => void) =>
  renderWithProviders(<Holder onDone={onDone} />, {
    route: "/enroll",
    session: signedInPayload("mfa"),
  });

/**
 * Replaces the clipboard stub of user-event, which `renderWithProviders`
 * attaches, so call it after the render.
 */
function mockClipboard() {
  const writeText = vi.fn(async (_text: string) => {});
  Object.defineProperty(navigator, "clipboard", {
    configurable: true,
    value: { writeText },
  });
  return writeText;
}

const urlMembers = ["createObjectURL", "revokeObjectURL"] as const;
const realUrlMembers = urlMembers.map((key) =>
  Object.getOwnPropertyDescriptor(URL, key),
);

/** jsdom has no object URLs; this mock records every Blob it receives. */
function mockObjectUrls() {
  const blobs: Blob[] = [];
  const createObjectURL = vi.fn((blob: Blob) => {
    blobs.push(blob);
    return "blob:http://localhost:3000/recovery-codes";
  });
  const revokeObjectURL = vi.fn((_url: string) => {});
  Object.defineProperty(URL, "createObjectURL", {
    configurable: true,
    writable: true,
    value: createObjectURL,
  });
  Object.defineProperty(URL, "revokeObjectURL", {
    configurable: true,
    writable: true,
    value: revokeObjectURL,
  });
  return { blobs, createObjectURL, revokeObjectURL };
}

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
  takeReturnTo();
  Reflect.deleteProperty(navigator, "clipboard");
  urlMembers.forEach((key, index) => {
    const real = realUrlMembers[index];
    if (real) Object.defineProperty(URL, key, real);
    else Reflect.deleteProperty(URL, key);
  });
});

test("the codes render in an ordered list below the heading", () => {
  renderPanel();

  expect(
    screen.getByRole("heading", { name: "Save your recovery codes" }),
  ).toBeInTheDocument();
  const list = screen.getByRole("list");
  expect(list.tagName).toBe("OL");
  expect(
    within(list)
      .getAllByRole("listitem")
      .map((item) => item.textContent),
  ).toEqual(CODES);
});

test("Continue stays disabled until the checkbox is set", async () => {
  const onDone = vi.fn();
  const { user } = renderPanel(onDone);
  const proceed = screen.getByRole("button", { name: "Continue" });

  expect(proceed).toBeDisabled();
  await user.click(proceed);
  expect(onDone).not.toHaveBeenCalled();

  await user.click(
    screen.getByRole("checkbox", { name: "I have saved these codes" }),
  );
  expect(proceed).toBeEnabled();

  await user.click(
    screen.getByRole("checkbox", { name: "I have saved these codes" }),
  );
  expect(proceed).toBeDisabled();
});

test("Copy writes the codes, one per line, and announces it in a status region", async () => {
  const { user } = renderPanel();
  const writeText = mockClipboard();

  await user.click(screen.getByRole("button", { name: "Copy" }));

  expect(writeText).toHaveBeenCalledTimes(1);
  expect(writeText).toHaveBeenCalledWith(CODES.join("\n"));
  await waitFor(() =>
    expect(screen.getByRole("status")).toHaveTextContent(
      "The codes were copied.",
    ),
  );
});

describe("Download", () => {
  test("saves a text file with the product, the host, an empty line and the ten codes", async () => {
    const { user } = renderPanel();
    const { blobs, createObjectURL, revokeObjectURL } = mockObjectUrls();
    const clicked: { download: string; href: string; attached: boolean }[] = [];
    const order: string[] = [];
    vi.spyOn(HTMLAnchorElement.prototype, "click").mockImplementation(function (
      this: HTMLAnchorElement,
    ) {
      order.push("click");
      clicked.push({
        download: this.download,
        href: this.href,
        attached: this.isConnected,
      });
    });
    revokeObjectURL.mockImplementation(() => {
      order.push("revoke");
    });

    await user.click(screen.getByRole("button", { name: "Download" }));

    expect(createObjectURL).toHaveBeenCalledTimes(1);
    expect(blobs).toHaveLength(1);
    expect(blobs[0].type).toBe("text/plain;charset=utf-8");
    const lines = (await blobs[0].text()).trimEnd().split("\n");
    expect(lines[0]).toBe(
      `Recovery codes for ${productName} at ${window.location.host}`,
    );
    expect(lines[0]).toContain(productName);
    expect(lines[0]).toContain(window.location.host);
    expect(lines[1]).toBe("");
    expect(lines.slice(2)).toEqual(CODES);

    expect(clicked).toEqual([
      {
        download: "recovery-codes.txt",
        href: "blob:http://localhost:3000/recovery-codes",
        attached: true,
      },
    ]);
    expect(revokeObjectURL).toHaveBeenCalledWith(
      "blob:http://localhost:3000/recovery-codes",
    );
    expect(order).toEqual(["click", "revoke"]);
    expect(document.querySelector("a[download]")).toBeNull();
  });
});

test("the codes leave the DOM after Continue", async () => {
  const onDone = vi.fn();
  const { user, container } = renderPanel(onDone);

  await user.click(
    screen.getByRole("checkbox", { name: "I have saved these codes" }),
  );
  await user.click(screen.getByRole("button", { name: "Continue" }));

  expect(onDone).toHaveBeenCalledTimes(1);
  expect(await screen.findByText("Codes cleared")).toBeInTheDocument();
  expect(container.querySelector("ol")).toBeNull();
  for (const code of CODES)
    expect(document.body.textContent).not.toContain(code);
});

test("the panel has no axe violations in light, dark and German", async () => {
  const { container } = renderPanel();
  await screen.findByRole("heading", { name: "Save your recovery codes" });

  await expectNoAxeViolations(container);
});
