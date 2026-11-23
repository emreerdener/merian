import { assertEquals } from "@std/assert";
import type { User } from "@supabase/supabase-js";
import { captureStageUploadRoute } from "./route.ts";
import {
  CAPTURE_STAGE_METADATA_BYTES,
  CAPTURE_STAGE_WIRE_BYTES,
  uploadCaptureStage,
} from "./handler.ts";
import { evidenceDigest } from "../_shared/analysisHistory/evidence.ts";
import { initialCaptureAudioStageRequest } from "../_shared/analysisHistory/initialCaptureAudioStaging.ts";
import type { InitialEvidenceCapturePlan } from "../_shared/analysisHistory/initialEvidenceCapturePlan.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
function frame(metadata: unknown, bytes: Uint8Array) {
  const text = new TextEncoder().encode(JSON.stringify(metadata)),
    result = new Uint8Array(4 + text.length + bytes.length);
  new DataView(result.buffer).setUint32(0, text.length);
  result.set(text, 4);
  result.set(bytes, 4 + text.length);
  return result;
}
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
  Promise.resolve({ user: { id: id(1) } as User, response: null });
Deno.test("capture ingress authenticates before reading and rejects unsupported method MIME and oversize bodies", async () => {
  await environment(async () => {
    let reads = 0, factories = 0;
    const body = new ReadableStream<Uint8Array>({
      pull() {
        reads++;
      },
    }, { highWaterMark: 0 });
    const factory = () => {
      factories++;
      throw new Error("unexpected_factory");
    };
    const denied = await captureStageUploadRoute(
      new Request("https://example.invalid", { method: "POST", body }),
      () =>
        Promise.resolve({
          user: null,
          response: new Response(null, { status: 401 }),
        }),
      factory,
    );
    assertEquals(denied.status, 401);
    assertEquals(reads, 0);
    await body.cancel();
    await denied.body?.cancel();
    for (
      const [method, type, length, status] of [
        ["OPTIONS", "application/octet-stream", null, 200],
        ["GET", "application/octet-stream", null, 405],
        ["POST", "application/json", null, 415],
        [
          "POST",
          "application/octet-stream",
          String(CAPTURE_STAGE_WIRE_BYTES + 1),
          413,
        ],
      ] as const
    ) {
      const headers = new Headers({ "content-type": type });
      if (length) headers.set("content-length", length);
      const response = await captureStageUploadRoute(
        new Request("https://example.invalid", {
          method,
          headers,
          body: method === "POST" ? new Uint8Array([1]) : undefined,
        }),
        authenticated,
        factory,
      );
      assertEquals(response.status, status);
      assertEquals(response.headers.get("cache-control"), "private, no-store");
      await response.body?.cancel();
    }
    assertEquals(factories, 0);
  });
});
Deno.test("capture ingress binds authenticated owner, hides storage identifiers, and rejects open or mismatched metadata", async () => {
  await environment(async () => {
    const bytes = new Uint8Array(100).fill(1), events: string[] = [];
    const plan = {
      schema_version: 1,
      scan_id: id(2),
      generation: id(3),
      items: [{
        kind: "audio",
        source: {
          media_id: id(4),
          content_type: "audio/wav",
          byte_count: bytes.length,
          sha256: await evidenceDigest(bytes),
        },
        prepared_media_id: id(5),
      }],
    };
    const metadata = { schema_version: 1, plan, media_id: id(4) };
    const factory = async (bound: InitialEvidenceCapturePlan) => {
      assertEquals(bound.ownerID, id(1));
      assertEquals(bound.uploads[0].media_id, id(4));
      events.push("factory");
      const request = await initialCaptureAudioStageRequest(bound);
      const row = {
        request_sha256: request.request_sha256,
        object_id: id(6),
        artifact: bound.uploads[0],
        write_issued: false,
        ready: false,
      };
      return {
        repository: {
          reserve: () => {
            events.push("reserve");
            return Promise.resolve({ ...row });
          },
          authorize: (_media: string, action: string) => {
            events.push(action);
            return Promise.resolve(true);
          },
          complete: () => {
            events.push("complete");
            return Promise.resolve({ ...row, write_issued: true, ready: true });
          },
        },
        storage: {
          writeOnce: () => {
            events.push("put");
            return Promise.resolve();
          },
          openBoundStream: () => {
            events.push("readback");
            return Promise.resolve(
              new ReadableStream<Uint8Array>({
                start(c) {
                  c.enqueue(bytes);
                  c.close();
                },
              }),
            );
          },
        },
      };
    };
    const response = await captureStageUploadRoute(
      new Request("https://example.invalid", {
        method: "POST",
        headers: { "content-type": "application/octet-stream" },
        body: frame(metadata, bytes),
      }),
      authenticated,
      factory,
    );
    assertEquals(response.status, 200);
    const result = await response.json();
    assertEquals(Object.keys(result).sort(), [
      "generation",
      "media_id",
      "ready",
      "request_sha256",
      "scan_id",
      "schema_version",
    ]);
    assertEquals(events, [
      "factory",
      "reserve",
      "write",
      "put",
      "verify",
      "readback",
      "complete",
    ]);
    events.length = 0;
    const oversized = frame(metadata, bytes);
    new DataView(oversized.buffer).setUint32(
      0,
      CAPTURE_STAGE_METADATA_BYTES + 1,
    );
    for (
      const value of [
        new Uint8Array(),
        oversized,
        new Uint8Array([0, 0, 0, 1, 255, 1]),
        frame({ ...metadata, owner_id: id(1) }, bytes),
        frame({ ...metadata, object_id: id(6) }, bytes),
        frame({ ...metadata, schema_version: 2 }, bytes),
        frame({ ...metadata, media_id: id(5) }, bytes),
        frame(metadata, bytes.subarray(1)),
        frame(metadata, new Uint8Array(100).fill(9)),
      ]
    ) {
      const result = await uploadCaptureStage(
        new Request("https://example.invalid", { method: "POST" }),
        value,
        id(1),
        factory,
        new AbortController().signal,
      );
      assertEquals(result.status, 400);
      await result.body?.cancel();
    }
    assertEquals(events, []);
  });
});
Deno.test("capture ingress cancels a stalled body before private service construction", async () => {
  await environment(async () => {
    const controller = new AbortController();
    let cancelled = false, factories = 0;
    const body = new ReadableStream<Uint8Array>({
      pull() {
        controller.abort();
      },
      cancel() {
        cancelled = true;
      },
    }, { highWaterMark: 0 });
    const response = await captureStageUploadRoute(
      new Request("https://example.invalid", {
        method: "POST",
        headers: { "content-type": "application/octet-stream" },
        body,
        signal: controller.signal,
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
