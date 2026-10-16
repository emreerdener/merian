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
    [
      "SUPABASE_URL",
      "SUPABASE_SERVER_API_KEY",
      "R2_ACCOUNT_ID",
      "R2_HISTORY_BUCKET_NAME",
      "R2_BUCKET_NAME",
      "R2_HISTORY_WRITE_ACCESS_KEY_ID",
      "R2_HISTORY_WRITE_SECRET_ACCESS_KEY",
    ].map((
      key,
    ) => [key, Deno.env.get(key)]),
  );
  Deno.env.set("SUPABASE_URL", "https://synthetic.invalid");
  Deno.env.set(
    "SUPABASE_SERVER_API_KEY",
    "sb_secret_" + "synthetic_test_only".repeat(3),
  );
  Deno.env.set("R2_ACCOUNT_ID", "0".repeat(32));
  Deno.env.set("R2_HISTORY_BUCKET_NAME", "synthetic-private-history");
  Deno.env.set("R2_BUCKET_NAME", "synthetic-public-scans");
  Deno.env.set("R2_HISTORY_WRITE_ACCESS_KEY_ID", "synthetic-test-only");
  Deno.env.set("R2_HISTORY_WRITE_SECRET_ACCESS_KEY", "synthetic-test-only");
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
    const original = globalThis.fetch;
    let calls = 0;
    globalThis.fetch = () => {
      calls++;
      throw new Error("Unexpected storage or RPC call during cancellation");
    };
    try {
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
        assertEquals(calls, 0);
        await response.body?.cancel();
        await new Promise((resolve) => setTimeout(resolve, 0));
        if (stage === "body") assertEquals(cancelled, true);
        else await request.body?.cancel();
      }
      assertEquals(calls, 0);
    } finally {
      globalThis.fetch = original;
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

Deno.test("video route allocated write HEAD and completion preserve exact cohort across lost replies", async () => {
  await environment(async () => {
    for (
      const mode of [
        "source",
        "frame",
        "audio",
        "existing",
        "bad-head",
        "erased",
        "lost-complete",
      ]
    ) {
      const f = await videoByteFixture(true);
      const index = mode === "frame" ? 1 : mode === "audio" ? 6 : 0;
      const item = f.receipt.items[index];
      const allocated = {
        ...f.receipt,
        state: "allocated",
        expires_at: "2099-01-01T00:00:00.000Z",
        items: f.receipt.items.map((item) => ({
          ...item,
          ready_at: null as string | null,
        })),
      };
      const completed = {
        ...allocated,
        items: allocated.items.map((item, i) => ({
          ...item,
          ready_at: i === index ? "2026-01-01T00:00:00.000Z" : null,
        })),
      };
      const body = frame({
        schema_version: 1,
        reader_version: 12,
        candidate: f.input,
        media_id: item.media_id,
      }, f.bytes[index]);
      const events: string[] = [];
      const original = globalThis.fetch;
      let durable = false;
      globalThis.fetch = async (input, init) => {
        const request = new Request(input, init);
        const url = new URL(request.url);
        if (
          url.pathname.endsWith("/reserve_owned_observation_video_evidence")
        ) {
          events.push("reserve");
          const args = await request.json();
          assertEquals(args.p_owner, owner);
          assertEquals(args.p_reader, 12);
          assertEquals(args.p_request.fingerprint, f.input.fingerprint);
          return new Response(JSON.stringify(durable ? completed : allocated), {
            headers: { "content-type": "application/json" },
          });
        }
        if (url.hostname.endsWith(".r2.cloudflarestorage.com")) {
          assertEquals(url.pathname.includes(item.object_id), true);
          assertEquals(
            url.pathname.startsWith("/synthetic-private-history/"),
            true,
          );
          events.push(request.method);
          if (request.method === "PUT") {
            assertEquals(request.headers.get("if-none-match"), "*");
            assertEquals(
              request.headers.get("content-type"),
              item.content_type,
            );
            assertEquals(request.headers.get("x-amz-meta-sha256"), item.sha256);
            assertEquals(
              new Uint8Array(await request.arrayBuffer()),
              f.bytes[index],
            );
            return new Response(null, {
              status: mode === "existing" ? 412 : 200,
            });
          }
          assertEquals(request.method, "HEAD");
          return new Response(null, {
            headers: {
              "content-type": item.content_type,
              "content-length": String(
                mode === "bad-head" ? item.byte_count + 1 : item.byte_count,
              ),
              "x-amz-meta-sha256": item.sha256,
              ...(mode === "erased" ? { "x-amz-meta-erased": "true" } : {}),
            },
          });
        }
        assertEquals(
          url.pathname.endsWith("/complete_owned_observation_video_evidence"),
          true,
        );
        events.push("complete");
        const args = await request.json();
        assertEquals(args.p_owner, owner);
        assertEquals(args.p_reader, 12);
        assertEquals(args.p_media, item.media_id);
        assertEquals(args.p_object, item.object_id);
        assertEquals(args.p_request.fingerprint, f.input.fingerprint);
        assertEquals(Object.hasOwn(args, "p_ready_at"), false);
        durable = true;
        if (mode === "lost-complete") {
          throw new TypeError("synthetic lost reply");
        }
        return new Response(JSON.stringify(completed), {
          headers: { "content-type": "application/json" },
        });
      };
      try {
        const call = () =>
          videoUploadRoute(
            new Request("https://example.invalid", {
              method: "POST",
              headers: { "content-type": "application/octet-stream" },
              body,
            }),
            authenticated,
          );
        const response = await call();
        const failed = ["bad-head", "erased", "lost-complete"].includes(mode);
        assertEquals(response.status, failed ? 503 : 200);
        assertEquals(
          response.headers.get("cache-control"),
          "private, no-store",
        );
        if (!failed) assertEquals(await response.json(), completed);
        else await response.body?.cancel();
        assertEquals(events, [
          "reserve",
          "PUT",
          "HEAD",
          ...(["bad-head", "erased"].includes(mode) ? [] : ["complete"]),
        ]);
        if (mode === "lost-complete") {
          events.length = 0;
          const replay = await call();
          assertEquals(replay.status, 200);
          assertEquals(await replay.json(), completed);
          assertEquals(events, ["reserve"]);
        }
      } finally {
        globalThis.fetch = original;
      }
    }
  });
});
