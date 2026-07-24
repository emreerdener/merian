import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  isExplicitPublicErrorResponse,
  jsonResponse,
  parseJsonBody,
  publicErrorResponse,
  readBoundedJsonBody,
  readByteStreamWithinLimit,
  requestIdFor,
} from "./http.ts";

Deno.test("jsonResponse merges extra headers with default JSON headers", async () => {
  const response = jsonResponse({ ok: true }, 200, {
    "Cache-Control": "public, max-age=300",
    "Vary": "Accept-Encoding",
  });

  assertEquals(response.status, 200);
  assertEquals(response.headers.get("Content-Type"), "application/json");
  assertEquals(response.headers.get("Cache-Control"), "public, max-age=300");
  assertEquals(response.headers.get("Vary"), "Accept-Encoding");
  assertEquals(await response.json(), { ok: true });
});

Deno.test("readBoundedJsonBody accepts JSON and structured JSON media types", async () => {
  for (
    const contentType of [
      "application/json; charset=utf-8",
      "application/problem+json",
    ]
  ) {
    const result = await readBoundedJsonBody<{ ok: boolean }>(
      new Request("https://example.test", {
        method: "POST",
        headers: { "Content-Type": contentType },
        body: JSON.stringify({ ok: true }),
      }),
      { limit: "small" },
    );
    assertEquals(result, { value: { ok: true } });
  }
});

Deno.test("readBoundedJsonBody rejects missing or unsupported content types", async () => {
  for (const contentType of [null, "text/plain"]) {
    const headers = contentType ? { "Content-Type": contentType } : undefined;
    const result = await readBoundedJsonBody(
      new Request("https://example.test", {
        method: "POST",
        headers,
        body: "{}",
      }),
      { limit: "small" },
    );
    assertEquals(result.error, {
      status: 415,
      code: "unsupported_media_type",
      message: "Content-Type must be application/json.",
    });
  }
});

Deno.test("readBoundedJsonBody rejects an oversized declaration before reading", async () => {
  const request = new Request("https://example.test", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Content-Length": "17",
    },
    body: "{}",
  });
  const result = await readBoundedJsonBody(
    request,
    { limit: "small", maxBytes: 16 },
  );

  assertEquals(result.error?.code, "payload_too_large");
  assertEquals(request.bodyUsed, false);
});

Deno.test("readBoundedJsonBody rejects streamed bytes above the endpoint limit", async () => {
  const result = await readBoundedJsonBody(
    new Request("https://example.test", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: new ReadableStream<Uint8Array>({
        start(controller) {
          controller.enqueue(new Uint8Array(9));
          controller.enqueue(new Uint8Array(8));
          controller.close();
        },
      }),
    }),
    { limit: "small", maxBytes: 16 },
  );

  assertEquals(result.error?.code, "payload_too_large");
});

Deno.test("bounded byte streams keep memory proportional across tiny chunks", async () => {
  const byteCount = 2_049;
  let nextByte = 0;
  const result = await readByteStreamWithinLimit(
    new ReadableStream<Uint8Array>({
      pull(controller) {
        if (nextByte >= byteCount) {
          controller.close();
          return;
        }
        controller.enqueue(Uint8Array.of(nextByte % 251));
        nextByte += 1;
      },
    }),
    byteCount,
  );

  assertEquals(result.exceeded, undefined);
  assertEquals(result.bytes?.byteLength, byteCount);
  assertEquals(result.bytes?.[0], 0);
  assertEquals(result.bytes?.[byteCount - 1], (byteCount - 1) % 251);
});

Deno.test("bounded byte streams reject oversize even if cancellation races", async () => {
  const result = await readByteStreamWithinLimit(
    new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(new Uint8Array(3));
      },
      cancel() {
        throw new Error("peer disconnected");
      },
    }),
    2,
  );

  assertEquals(result, { exceeded: true });
});

Deno.test("readBoundedJsonBody validates declared and actual byte counts", async () => {
  const result = await readBoundedJsonBody(
    new Request("https://example.test", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Content-Length": "0",
      },
      body: "{}",
    }),
    { limit: "small" },
  );

  assertEquals(result.error?.code, "invalid_content_length");
});

Deno.test("readBoundedJsonBody rejects malformed UTF-8 and non-object JSON", async () => {
  const invalidUtf8 = await readBoundedJsonBody(
    new Request("https://example.test", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: new Uint8Array([0xc3, 0x28]),
    }),
    { limit: "small" },
  );
  assertEquals(invalidUtf8.error?.code, "invalid_json");

  const array = await readBoundedJsonBody(
    new Request("https://example.test", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: "[]",
    }),
    { limit: "small" },
  );
  assertEquals(array.error?.code, "invalid_json_object");
});

Deno.test("parseJsonBody returns stable parser errors with one request id", async () => {
  const request = new Request("https://example.test", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: "{",
  });
  const result = await parseJsonBody(request, { limit: "small" });
  assertEquals(result instanceof Response, true);
  const response = result as Response;
  const payload = await response.json();

  assertEquals(response.status, 400);
  assertEquals(payload.code, "invalid_json");
  assertEquals(payload.request_id, requestIdFor(request));
  assertEquals(response.headers.get("X-Request-ID"), payload.request_id);
});

Deno.test("publicErrorResponse does not accept a caller-supplied request id", async () => {
  const request = new Request("https://example.test", {
    headers: { "X-Request-ID": "attacker-controlled" },
  });
  const response = publicErrorResponse(
    request,
    429,
    "rate_limited",
    "Try later.",
    { retryAfterSeconds: 30 },
  );
  const payload = await response.json();

  assertEquals(payload.request_id === "attacker-controlled", false);
  assertEquals(response.headers.get("Retry-After"), "30");
  assertEquals(payload.retry_after_seconds, 30);
  assertEquals(isExplicitPublicErrorResponse(response), true);
});

Deno.test("publicErrorResponse rejects invalid public contracts", () => {
  const request = new Request("https://example.test");

  assertThrows(
    () =>
      publicErrorResponse(
        request,
        200,
        "not_an_error",
        "Invalid status.",
      ),
    TypeError,
  );
  assertThrows(
    () =>
      publicErrorResponse(
        request,
        503,
        "INVALID-CODE",
        "Invalid code.",
      ),
    TypeError,
  );
  assertThrows(
    () =>
      publicErrorResponse(
        request,
        429,
        "rate_limited",
        "Invalid retry.",
        { retryAfterSeconds: 100_000 },
      ),
    TypeError,
  );
});
