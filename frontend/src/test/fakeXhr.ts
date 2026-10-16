import { vi } from "vitest";

/** A stubbed answer of `FakeXhr`; `network` fails the request instead. */
export interface XhrAnswer {
  status: number;
  body?: unknown;
  headers?: Record<string, string>;
  network?: boolean;
}

/** A request as `FakeXhr` saw it. */
export interface XhrRequest {
  method: string;
  url: string;
  /** The request headers by lower-case name. */
  headers: Record<string, string>;
  body: FormData | null;
}

/**
 * A stand-in for `XMLHttpRequest` in jsdom, for the media upload of task
 * 0018: it records each request, reports the progress of the body in two
 * steps on `upload`, and answers in a later task with the next answer of
 * `answers` (the last one repeats). `installFakeXhr` replaces the global
 * class until `vi.unstubAllGlobals()`.
 */
export function installFakeXhr(answers: readonly XhrAnswer[]) {
  const requests: XhrRequest[] = [];
  let calls = 0;

  class FakeXhr {
    readonly upload = new EventTarget();
    readonly #events = new EventTarget();
    #request: XhrRequest = { method: "", url: "", headers: {}, body: null };
    #responseHeaders: Record<string, string> = {};
    status = 0;
    responseText = "";

    open(method: string, url: string) {
      this.#request = { method, url, headers: {}, body: null };
    }

    setRequestHeader(name: string, value: string) {
      this.#request.headers[name.toLowerCase()] = value;
    }

    addEventListener(type: string, listener: EventListener) {
      this.#events.addEventListener(type, listener);
    }

    getAllResponseHeaders() {
      return Object.entries(this.#responseHeaders)
        .map(([name, value]) => `${name}: ${value}`)
        .join("\r\n");
    }

    send(body: FormData | null) {
      this.#request.body = body;
      requests.push(this.#request);
      const answer = answers[Math.min(calls, answers.length - 1)];
      calls += 1;
      const file = body?.get("file");
      const total = file instanceof File ? file.size : 0;
      setTimeout(() => {
        if (answer.network) {
          this.#events.dispatchEvent(new Event("error"));
          return;
        }
        for (const loaded of [Math.floor(total / 2), total])
          this.upload.dispatchEvent(
            new ProgressEvent("progress", {
              loaded,
              total,
              lengthComputable: true,
            }),
          );
        this.status = answer.status;
        this.responseText =
          answer.body === undefined ? "" : JSON.stringify(answer.body);
        this.#responseHeaders = {
          ...(answer.body === undefined
            ? {}
            : { "content-type": "application/json" }),
          ...answer.headers,
        };
        this.#events.dispatchEvent(new Event("load"));
      }, 0);
    }
  }

  vi.stubGlobal("XMLHttpRequest", FakeXhr);
  return { requests };
}
