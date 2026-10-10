import { assertEquals } from "@std/assert";
import type { User } from "@supabase/supabase-js";
import { audioUploadRoute } from "./route.ts";
const owner = "00000000-0000-4000-8000-000000000001";
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
Deno.test("private audio upload route covers preflight, auth, method and parser failures with private no-store", async () => {
  await environment(async () => {
    for (
      const [method, body, expected] of [
        ["OPTIONS", undefined, 200],
        ["GET", undefined, 405],
        ["POST", "{", 400],
        ["POST", "x".repeat(2700000 + 1029), 413],
      ] as const
    ) {
      const response = await audioUploadRoute(
        new Request("https://example.invalid", {
          method,
          body,
          headers: { "Content-Type": "application/octet-stream" },
        }),
        authenticated,
      );
      assertEquals(response.status, expected);
      assertEquals(response.headers.get("Cache-Control"), "private, no-store");
      await response.body?.cancel();
    }
    const denied = await audioUploadRoute(
      new Request("https://example.invalid", { method: "POST" }),
      () =>
        Promise.resolve({
          user: null,
          response: new Response(null, { status: 401 }),
        }),
    );
    assertEquals(denied.status, 401);
    assertEquals(denied.headers.get("Cache-Control"), "private, no-store");
    await denied.body?.cancel();
  });
});
Deno.test("private audio upload authenticated route derives owner for actual RPC and conceals foreign records", async () => {
  await environment(async () => {
    const original = globalThis.fetch;
    let calls = 0;
    const observation = "00000000-0000-4000-8000-000000000002";
    const analysis = "00000000-0000-4000-8000-000000000003";
    const media = "00000000-0000-4000-8000-000000000004";
    const metadata = new TextEncoder().encode(
      JSON.stringify({
        schema_version: 1,
        observation_id: observation,
        analysis_id: analysis,
        audio: {
          media_id: media,
          content_type: "audio/wav",
          byte_count: 46,
        },
      }),
    );
    const bytes = new Uint8Array(4 + metadata.length + 46);
    new DataView(bytes.buffer).setUint32(0, metadata.length);
    bytes.set(metadata, 4);
    const payload = bytes.subarray(4 + metadata.length),
      view = new DataView(payload.buffer, payload.byteOffset, payload.length);
    for (
      const [offset, tag] of [[0, "RIFF"], [8, "WAVE"], [12, "fmt "], [
        36,
        "data",
      ]] as const
    ) payload.set(new TextEncoder().encode(tag), offset);
    for (
      const [offset, value] of [[4, 38], [16, 16], [24, 44100], [28, 88200], [
        40,
        2,
      ]]
    ) view.setUint32(offset, value, true);
    for (const [offset, value] of [[20, 1], [22, 1], [32, 2], [34, 16]]) {
      view.setUint16(offset, value, true);
    }
    globalThis.fetch = (_url, init) => {
      calls++;
      assertEquals(
        String(_url).endsWith(
          "/rest/v1/rpc/reserve_owned_observation_audio_evidence_cohort",
        ),
        true,
      );
      const args = JSON.parse(String(init?.body));
      assertEquals([args.p_owner, args.p_observation, args.p_analysis], [
        owner,
        observation,
        analysis,
      ]);
      assertEquals(args.p_media, media);
      assertEquals(args.p_bytes, 46);
      assertEquals(typeof args.p_sha256, "string");
      assertEquals(args.p_sha256.length, 64);
      return Promise.resolve(
        new Response(
          JSON.stringify({
            code: "P0002",
            message: "analysis_history_not_found",
          }),
          { status: 404 },
        ),
      );
    };
    try {
      const response = await audioUploadRoute(
        new Request("https://example.invalid", {
          method: "POST",
          body: bytes,
          headers: { "Content-Type": "application/octet-stream" },
        }),
        authenticated,
      );
      assertEquals(response.status, 404);
      assertEquals(response.headers.get("Cache-Control"), "private, no-store");
      assertEquals((await response.json()).code, "analysis_history_not_found");
      assertEquals(calls, 1);
    } finally {
      globalThis.fetch = original;
    }
  });
});
Deno.test("private audio upload abort cancels a stalled incoming body", async () => {
  await environment(async () => {
    const controller = new AbortController();
    let cancelled = false;
    const body = new ReadableStream<Uint8Array>({
      pull() {
        controller.abort();
      },
      cancel() {
        cancelled = true;
      },
    });
    const response = await audioUploadRoute(
      new Request("https://example.invalid", {
        method: "POST",
        body,
        signal: controller.signal,
        headers: { "Content-Type": "application/octet-stream" },
      }),
      authenticated,
    );
    assertEquals(response.status, 503);
    await response.body?.cancel();
    await new Promise((resolve) => setTimeout(resolve, 0));
    assertEquals(cancelled, true);
  });
});
