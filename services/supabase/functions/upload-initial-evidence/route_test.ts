import { assertEquals } from "@std/assert";
import type { User } from "@supabase/supabase-js";
import { initialEvidenceUploadRoute } from "./route.ts";
import { INITIAL_UPLOAD_WIRE_MAX_BYTES } from "./handler.ts";
import { fixture, frame, id } from "./testFixtures.ts";

async function environment(work: () => Promise<void>) {
  const values = {
    SUPABASE_URL: "https://synthetic.invalid",
    SUPABASE_SERVER_API_KEY: "sb_secret_" + "synthetic_test_only".repeat(3),
  };
  const saved = new Map(
    Object.keys(values).map((key) => [key, Deno.env.get(key)]),
  );
  try {
    for (const [key, value] of Object.entries(values)) Deno.env.set(key, value);
    await work();
  } finally {
    for (const [key, value] of saved) {
      if (value === undefined) Deno.env.delete(key);
      else Deno.env.set(key, value);
    }
  }
}
const authenticated = () =>
  Promise.resolve({ user: { id: id(9) } as User, response: null });

Deno.test("initial upload authenticates before reading and keeps method MIME length failures private", async () => {
  await environment(async () => {
    let reads = 0, factories = 0;
    const body = new ReadableStream<Uint8Array>({
      pull() {
        reads++;
      },
    }, { highWaterMark: 0 });
    const denied = await initialEvidenceUploadRoute(
      new Request("https://example.invalid", { method: "POST", body }),
      () =>
        Promise.resolve({
          user: null,
          response: new Response(null, { status: 401 }),
        }),
      () => {
        factories++;
        throw new Error("unexpected");
      },
    );
    assertEquals(denied.status, 401);
    assertEquals(reads, 0);
    assertEquals(factories, 0);
    await denied.body?.cancel();
    await body.cancel();
    for (
      const [method, type, length, expected] of [
        ["OPTIONS", "application/octet-stream", null, 200],
        ["GET", "application/octet-stream", null, 405],
        ["POST", "application/json", null, 415],
        [
          "POST",
          "application/octet-stream",
          String(INITIAL_UPLOAD_WIRE_MAX_BYTES + 1),
          413,
        ],
      ] as const
    ) {
      const headers = new Headers({ "content-type": type });
      if (length) headers.set("content-length", length);
      const response = await initialEvidenceUploadRoute(
        new Request("https://example.invalid", {
          method,
          headers,
          body: method === "POST" ? new Uint8Array([1]) : undefined,
        }),
        authenticated,
        () => {
          factories++;
          throw new Error("unexpected");
        },
      );
      assertEquals(response.status, expected);
      assertEquals(response.headers.get("cache-control"), "private, no-store");
      await response.body?.cancel();
    }
    assertEquals(factories, 0);
  });
});

Deno.test("initial upload route uses authenticated owner and complete admitted manifest", async () => {
  await environment(async () => {
    const f = await fixture(), reserve = f.dependencies.repository.reserve;
    f.dependencies.repository.reserve = (owner, request, signal) => {
      assertEquals(owner, f.owner);
      assertEquals(request, f.request);
      return reserve(owner, request, signal);
    };
    const response = await initialEvidenceUploadRoute(
      new Request("https://example.invalid", {
        method: "POST",
        headers: { "content-type": "application/octet-stream" },
        body: frame(f.metadata, f.source),
      }),
      authenticated,
      () => f.dependencies,
    );
    assertEquals(response.status, 200);
    assertEquals(await response.json(), f.receipt);
    assertEquals(f.events, ["reserve", "write", "read", "complete"]);
  });
});

Deno.test("initial upload abort joins body cancellation before storage construction", async () => {
  await environment(async () => {
    let cancelled = false, factories = 0;
    const controller = new AbortController();
    const body = new ReadableStream<Uint8Array>({
      pull() {
        controller.abort();
      },
      cancel() {
        cancelled = true;
      },
    }, { highWaterMark: 0 });
    const response = await initialEvidenceUploadRoute(
      new Request("https://example.invalid", {
        method: "POST",
        body,
        signal: controller.signal,
        headers: { "content-type": "application/octet-stream" },
      }),
      authenticated,
      () => {
        factories++;
        throw new Error("unexpected");
      },
    );
    assertEquals(response.status, 503);
    await response.body?.cancel();
    assertEquals(cancelled, true);
    assertEquals(factories, 0);
  });
});
