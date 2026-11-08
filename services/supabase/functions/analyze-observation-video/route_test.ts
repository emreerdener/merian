import { assertEquals } from "@std/assert";
import type { User } from "@supabase/supabase-js";
import { analyzeVideoRoute } from "./route.ts";
const owner = "00000000-0000-4000-8000-000000000001";
const authenticated = () =>
  Promise.resolve({ user: { id: owner } as User, response: null });
const input = JSON.parse(
  await Deno.readTextFile(
    new URL(
      "../_shared/analysisHistory/fixtures/video-request-v4.json",
      import.meta.url,
    ),
  ),
)[0].input;
async function environment(work: () => Promise<void>) {
  const saved = new Map(
    ["SUPABASE_URL", "SUPABASE_SERVER_API_KEY"].map(
      (key) => [key, Deno.env.get(key)],
    ),
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
Deno.test("video route authenticates before body and rejects method malformed oversized and owner-injected requests", async () => {
  await environment(async () => {
    const original = globalThis.fetch;
    globalThis.fetch = () => {
      throw new Error("unexpected RPC");
    };
    try {
      for (
        const [method, body, expected] of [
          ["OPTIONS", undefined, 200],
          ["GET", undefined, 405],
          ["POST", "{", 400],
          ["POST", "x".repeat(1_048_577), 413],
          ["POST", JSON.stringify({ ...input, owner_id: owner }), 400],
          ["POST", JSON.stringify({ ...input, schema_version: 3 }), 400],
        ] as const
      ) {
        const response = await analyzeVideoRoute(
          new Request("https://example.invalid", {
            method,
            body,
            headers: { "Content-Type": "application/json" },
          }),
          authenticated,
        );
        assertEquals(response.status, expected);
        assertEquals(
          response.headers.get("Cache-Control"),
          "private, no-store",
        );
        await response.body?.cancel();
      }
      const denied = await analyzeVideoRoute(
        new Request("https://example.invalid", { method: "POST", body: "{" }),
        () =>
          Promise.resolve({
            user: null,
            response: new Response(null, { status: 401 }),
          }),
      );
      assertEquals(denied.status, 401);
      await denied.body?.cancel();
    } finally {
      globalThis.fetch = original;
    }
  });
});
Deno.test("video route sends only verified owner to begin and returns a closed held status", async () => {
  await environment(async () => {
    const original = globalThis.fetch;
    let calls = 0;
    globalThis.fetch = (url, init) => {
      calls++;
      assertEquals(
        String(url).endsWith("/rpc/begin_owned_observation_video_analysis"),
        true,
      );
      const args = JSON.parse(String(init?.body));
      assertEquals(args.p_owner, owner);
      assertEquals(args.p_input, input);
      return Promise.resolve(
        new Response(JSON.stringify({ state: "dispatched", claimed: false }), {
          headers: { "Content-Type": "application/json" },
        }),
      );
    };
    try {
      const response = await analyzeVideoRoute(
        new Request("https://example.invalid", {
          method: "POST",
          body: JSON.stringify(input),
          headers: { "Content-Type": "application/json" },
        }),
        authenticated,
      );
      assertEquals(response.status, 202);
      assertEquals(await response.json(), {
        schema_version: 1,
        observation_id: input.observation_id,
        analysis_id: input.analysis_id,
        state: "dispatched",
      });
      assertEquals(calls, 1);
    } finally {
      globalThis.fetch = original;
    }
  });
});
Deno.test("video route cancels stalled body before admission", async () => {
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
    const response = await analyzeVideoRoute(
      new Request("https://example.invalid", {
        method: "POST",
        body,
        signal: controller.signal,
        headers: { "Content-Type": "application/json" },
      }),
      authenticated,
    );
    assertEquals(response.status, 503);
    await response.body?.cancel();
    await new Promise((resolve) => setTimeout(resolve, 0));
    assertEquals(cancelled, true);
  });
});
Deno.test("video request abort during begin retains admitted work without materializing or dispatching", async () => {
  await environment(async () => {
    const original = globalThis.fetch, controller = new AbortController();
    const calls: string[] = [];
    globalThis.fetch = (url, init) => {
      if (String(url).endsWith("/rpc/begin_owned_observation_video_analysis")) {
        calls.push("begin");
        controller.abort();
        return Promise.resolve(
          new Response(JSON.stringify({
            state: "admitted",
            claimed: true,
            work_token: owner,
            input,
            quota: {
              reservation_id: owner,
              lease_token: owner,
              request_id: input.analysis_id,
              original_analysis_id: input.analysis_id,
              attempt_count: 1,
              policy_version: 7,
              effective_tier: "free",
              model: "gemini-2.5-flash",
              provider: "gemini",
              binding: "gemini_baseline_v1",
              processor_permission: "google_gemini",
              input_profile: input.evidence_manifest.provenance.audio
                ? "multimodal_video_audio_v1"
                : "multimodal_video_frames_v1",
            },
          })),
        );
      }
      assertEquals(
        String(url).endsWith("/rpc/advance_owned_observation_video_analysis"),
        true,
      );
      const args = JSON.parse(String(init?.body));
      calls.push(args.p_operation);
      assertEquals(args.p_operation, "release");
      return Promise.resolve(new Response("{}"));
    };
    try {
      const response = await analyzeVideoRoute(
        new Request("https://example.invalid", {
          method: "POST",
          body: JSON.stringify(input),
          signal: controller.signal,
          headers: { "Content-Type": "application/json" },
        }),
        authenticated,
      );
      assertEquals(response.status, 503);
      await response.body?.cancel();
      assertEquals(calls, ["begin"]);
    } finally {
      globalThis.fetch = original;
    }
  });
});
Deno.test("video stalled begin abort cancels transport without a second admission", async () => {
  await environment(async () => {
    const original = globalThis.fetch, controller = new AbortController();
    let calls = 0, cancelled = false;
    globalThis.fetch = (_url, init) => {
      calls++;
      return new Promise((_resolve, reject) => {
        init?.signal?.addEventListener("abort", () => {
          cancelled = true;
          reject(new Error("cancelled"));
        }, { once: true });
        controller.abort();
      });
    };
    try {
      const response = await analyzeVideoRoute(
        new Request("https://example.invalid", {
          method: "POST",
          body: JSON.stringify(input),
          signal: controller.signal,
          headers: { "Content-Type": "application/json" },
        }),
        authenticated,
      );
      assertEquals(response.status, 503);
      await response.body?.cancel();
      assertEquals(calls, 1);
      assertEquals(cancelled, true);
    } finally {
      globalThis.fetch = original;
    }
  });
});
