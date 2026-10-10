import { assertEquals } from "@std/assert";
import type { User } from "@supabase/supabase-js";
import { videoUploadRoute } from "./route.ts";
import { VIDEO_UPLOAD_WIRE_MAX_BYTES } from "./handler.ts";
import { videoByteFixture } from "../_shared/analysisHistory/videoByteTestFixtures.ts";
import { frame } from "./testFixtures.ts";
const owner = "00000000-0000-4000-8000-000000000900";
const authenticated = () =>
  Promise.resolve({ user: { id: owner } as User, response: null });
async function environment(work: () => Promise<void>) {
  const saved = new Map(
    ["SUPABASE_URL", "SUPABASE_SERVER_API_KEY"].map((
      key,
    ) => [key, Deno.env.get(key)]),
  );
  Deno.env.set("SUPABASE_URL", "https://synthetic.invalid");
  Deno.env.set(
    "SUPABASE_SERVER_API_KEY",
    "sb_secret_" + "synthetic_test_only".repeat(3),
  );
  try {
    await work();
  } finally {
    for (const [key, value] of saved) {
      if (value === undefined) Deno.env.delete(key);
      else Deno.env.set(key, value);
    }
  }
}

Deno.test("video route preflight authentication method MIME and declared length use private envelopes", async () => {
  await environment(async () => {
    for (
      const [method, type, length, status] of [
        ["OPTIONS", "application/octet-stream", null, 200],
        ["GET", "application/octet-stream", null, 405],
        ["POST", "application/json", null, 415],
        [
          "POST",
          "application/octet-stream",
          String(VIDEO_UPLOAD_WIRE_MAX_BYTES + 1),
          413,
        ],
        ["POST", "application/octet-stream", null, 400],
      ] as const
    ) {
      const headers = new Headers({ "content-type": type });
      if (length) headers.set("content-length", length);
      const response = await videoUploadRoute(
        new Request("https://example.invalid", {
          method,
          headers,
          body: method === "POST" ? new Uint8Array([1]) : undefined,
        }),
        authenticated,
      );
      assertEquals(response.status, status);
      assertEquals(response.headers.get("cache-control"), "private, no-store");
      await response.body?.cancel();
    }
    let cancelled = false;
    const body = new ReadableStream<Uint8Array>({
      cancel() {
        cancelled = true;
      },
    });
    const request = new Request("https://example.invalid", {
      method: "POST",
      body,
    });
    const denied = await videoUploadRoute(
      request,
      () =>
        Promise.resolve({
          user: null,
          response: new Response(null, { status: 401 }),
        }),
    );
    assertEquals(denied.status, 401);
    assertEquals(request.bodyUsed, false);
    await denied.body?.cancel();
    await request.body?.cancel();
    assertEquals(cancelled, true);
  });
});
Deno.test("video route actual bounded RPC derives owner reader12 and preserves ready replay", async () => {
  await environment(async () => {
    const f = await videoByteFixture(true);
    const body = frame({
      schema_version: 1,
      reader_version: 12,
      candidate: f.input,
      media_id: f.receipt.items[0].media_id,
    }, f.bytes[0]);
    const original = globalThis.fetch;
    let calls = 0;
    globalThis.fetch = (url, init) => {
      calls++;
      assertEquals(
        String(url).endsWith(
          "/rest/v1/rpc/reserve_owned_observation_video_evidence",
        ),
        true,
      );
      const args = JSON.parse(String(init?.body));
      assertEquals(args.p_owner, owner);
      assertEquals(args.p_reader, 12);
      assertEquals(args.p_request.fingerprint, f.input.fingerprint);
      return Promise.resolve(
        new Response(JSON.stringify(f.receipt), {
          headers: { "content-type": "application/json" },
        }),
      );
    };
    try {
      const response = await videoUploadRoute(
        new Request("https://example.invalid", {
          method: "POST",
          headers: { "content-type": "application/octet-stream" },
          body,
        }),
        authenticated,
      );
      assertEquals(response.status, 200);
      assertEquals(await response.json(), f.receipt);
      assertEquals(calls, 1);
    } finally {
      globalThis.fetch = original;
    }
  });
});
Deno.test("video route cancellation stops stalled auth and body without storage", async () => {
  await environment(async () => {
    for (const stage of ["auth", "body"]) {
      const controller = new AbortController();
      let cancelled = false;
      const body = new ReadableStream<Uint8Array>({
        pull() {
          if (stage === "body") controller.abort();
        },
        cancel() {
          cancelled = true;
        },
      }, { highWaterMark: 0 });
      const request = new Request("https://example.invalid", {
        method: "POST",
        headers: { "content-type": "application/octet-stream" },
        body,
        signal: controller.signal,
      });
      const response = await videoUploadRoute(
        request,
        stage === "auth"
          ? () => {
            controller.abort();
            return new Promise(() => {});
          }
          : authenticated,
      );
      assertEquals(response.status, 503);
      await response.body?.cancel();
      await new Promise((resolve) => setTimeout(resolve, 0));
      if (stage === "body") assertEquals(cancelled, true);
      else await request.body?.cancel();
    }
  });
});
Deno.test("video route conceals denied records bounds actual RPC replies and preserves conflict", async () => {
  await environment(async () => {
    const f = await videoByteFixture(false);
    const body = frame({
      schema_version: 1,
      reader_version: 12,
      candidate: f.input,
      media_id: f.receipt.items[0].media_id,
    }, f.bytes[0]);
    const original = globalThis.fetch;
    try {
      for (const mode of ["denied", "oversize", "conflict", "foreign"]) {
        let calls = 0;
        globalThis.fetch = () => {
          calls++;
          return Promise.resolve(
            new Response(
              mode === "oversize" ? " ".repeat(8193) : JSON.stringify(
                mode === "foreign"
                  ? { ...f.receipt, owner_id: f.receipt.analysis_id }
                  : {
                    code: "P0001",
                    message: mode === "conflict"
                      ? "analysis_history_operation_conflict"
                      : "analysis_history_not_found",
                  },
              ),
              {
                status: mode === "denied" || mode === "conflict" ? 400 : 200,
                headers: { "content-type": "application/json" },
              },
            ),
          );
        };
        const response = await videoUploadRoute(
          new Request("https://example.invalid", {
            method: "POST",
            headers: { "content-type": "application/octet-stream" },
            body,
          }),
          authenticated,
        );
        assertEquals(response.status, mode === "conflict" ? 409 : 503);
        assertEquals(calls, 1);
        await response.body?.cancel();
      }
    } finally {
      globalThis.fetch = original;
    }
  });
});
Deno.test("video route enforces actual streamed bytes and declared length mismatch", async () => {
  await environment(async () => {
    for (const oversize of [true, false]) {
      let cancelled = false;
      const body = new ReadableStream<Uint8Array>({
        start(c) {
          c.enqueue(
            new Uint8Array(oversize ? VIDEO_UPLOAD_WIRE_MAX_BYTES + 1 : 2),
          );
          if (!oversize) c.close();
        },
        cancel() {
          cancelled = true;
        },
      });
      const headers = new Headers({
        "content-type": "application/octet-stream",
      });
      if (!oversize) headers.set("content-length", "1");
      const response = await videoUploadRoute(
        new Request("https://example.invalid", {
          method: "POST",
          headers,
          body,
        }),
        authenticated,
      );
      assertEquals(response.status, oversize ? 413 : 400);
      await response.body?.cancel();
      await new Promise((r) => setTimeout(r, 0));
      if (oversize) assertEquals(cancelled, true);
    }
  });
});
