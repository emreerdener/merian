import { assertEquals, assertRejects } from "@std/assert";
import {
  createDeadlineFetchTransport,
  createResponseBodyLimitFetchTransport,
  fetchWithDeadline,
  OutboundRequestTimeoutError,
  readResponseJsonWithinLimit,
  readResponseTextWithinLimit,
} from "./outbound.ts";

Deno.test("createDeadlineFetchTransport attaches a hard deadline", async () => {
  let receivedSignal: AbortSignal | undefined;
  const transport = createDeadlineFetchTransport(
    100,
    ((_input, init) => {
      receivedSignal = (init as RequestInit | undefined)?.signal ?? undefined;
      return Promise.resolve(new Response("ok"));
    }) as typeof fetch,
  );

  await transport("https://example.test");

  assertEquals(receivedSignal instanceof AbortSignal, true);
});

Deno.test("response-limit transport rejects declared and streamed excess", async () => {
  const declaredTransport = createResponseBodyLimitFetchTransport(
    8,
    (() =>
      Promise.resolve(
        new Response("oversized", {
          headers: { "Content-Length": "9" },
        }),
      )) as typeof fetch,
  );
  await assertRejects(
    () => declaredTransport("https://example.test"),
    RangeError,
    "Response body exceeded its byte limit.",
  );

  const streamedTransport = createResponseBodyLimitFetchTransport(
    8,
    (() =>
      Promise.resolve(
        new Response(
          new ReadableStream<Uint8Array>({
            start(controller) {
              controller.enqueue(new Uint8Array(5));
              controller.enqueue(new Uint8Array(4));
              controller.close();
            },
          }),
        ),
      )) as typeof fetch,
  );
  const response = await streamedTransport("https://example.test");
  await assertRejects(
    () => response.arrayBuffer(),
    RangeError,
    "Response body exceeded its byte limit.",
  );
});

Deno.test("response-limit transport preserves bounded response metadata", async () => {
  const transport = createResponseBodyLimitFetchTransport(
    8,
    (() =>
      Promise.resolve(
        new Response("bounded", {
          status: 202,
          statusText: "Accepted",
          headers: { "X-Upstream": "preserved" },
        }),
      )) as typeof fetch,
  );

  const response = await transport("https://example.test");
  assertEquals(response.status, 202);
  assertEquals(response.statusText, "Accepted");
  assertEquals(response.headers.get("X-Upstream"), "preserved");
  assertEquals(await response.text(), "bounded");
});

Deno.test("fetchWithDeadline combines caller cancellation with a hard timeout", async () => {
  const callerController = new AbortController();
  let receivedSignal: AbortSignal | undefined;
  const fetcher = ((_input: RequestInfo | URL, init?: RequestInit) => {
    receivedSignal = init?.signal ?? undefined;
    return new Promise<Response>((_resolve, reject) => {
      receivedSignal?.addEventListener(
        "abort",
        () => reject(receivedSignal?.reason),
        { once: true },
      );
    });
  }) as typeof fetch;

  await assertRejects(
    () =>
      fetchWithDeadline(
        "https://example.test",
        { signal: callerController.signal },
        { fetcher, timeoutMs: 5 },
      ),
    OutboundRequestTimeoutError,
    "Outbound HTTP request exceeded its deadline.",
  );
  assertEquals(receivedSignal?.aborted, true);
  assertEquals(callerController.signal.aborted, false);
});

Deno.test("fetchWithDeadline preserves caller-initiated cancellation", async () => {
  const callerController = new AbortController();
  const callerError = new Error("caller cancelled");
  const fetcher =
    ((_input: RequestInfo | URL, init?: RequestInit) =>
      new Promise<Response>((_resolve, reject) => {
        init?.signal?.addEventListener(
          "abort",
          () => reject(init.signal?.reason),
          { once: true },
        );
        callerController.abort(callerError);
      })) as typeof fetch;

  await assertRejects(
    () =>
      fetchWithDeadline(
        "https://example.test",
        { signal: callerController.signal },
        { fetcher, timeoutMs: 100 },
      ),
    Error,
    "caller cancelled",
  );
});

Deno.test("readResponseTextWithinLimit enforces declared and streamed bytes", async () => {
  await assertRejects(
    () =>
      readResponseTextWithinLimit(
        new Response("oversized", {
          headers: { "Content-Length": "9" },
        }),
        8,
      ),
    RangeError,
  );

  await assertRejects(
    () =>
      readResponseTextWithinLimit(
        new Response(
          new ReadableStream<Uint8Array>({
            start(controller) {
              controller.enqueue(new Uint8Array(5));
              controller.enqueue(new Uint8Array(4));
              controller.close();
            },
          }),
        ),
        8,
      ),
    RangeError,
  );
});

Deno.test("readResponseJsonWithinLimit parses only bounded strict UTF-8 JSON", async () => {
  assertEquals(
    await readResponseJsonWithinLimit<{ value: number }>(
      new Response('{"value":7}'),
      32,
    ),
    { value: 7 },
  );

  await assertRejects(
    () =>
      readResponseJsonWithinLimit(
        new Response(new Uint8Array([0xff])),
        8,
      ),
    TypeError,
  );
});
