import { assertEquals } from "@std/assert";
import { recoverVideoRoute } from "./route.ts";
const key = "sb_secret_" + "synthetic_test_only".repeat(3);
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
async function environment(work: () => Promise<void>) {
  const names = [
    "SUPABASE_URL",
    "SUPABASE_SERVER_API_KEY",
    "MERIAN_SUPABASE_SERVER_API_KEY",
    "SUPABASE_SECRET_KEYS",
    "SUPABASE_SECRET_KEY",
    "SUPABASE_SERVICE_ROLE_KEY",
  ];
  const saved = new Map(names.map((name) => [name, Deno.env.get(name)]));
  for (const name of names) Deno.env.delete(name);
  Deno.env.set("SUPABASE_URL", "https://synthetic.invalid");
  Deno.env.set("SUPABASE_SERVER_API_KEY", key);
  try {
    await work();
  } finally {
    for (const [name, value] of saved) {
      if (value === undefined) Deno.env.delete(name);
      else Deno.env.set(name, value);
    }
  }
}
function request(body = "{}", valid = true) {
  return new Request("https://example.invalid", {
    method: "POST",
    body,
    headers: {
      apikey: valid ? key : "invalid",
      "Content-Type": "application/json",
    },
  });
}
Deno.test("video recovery service auth and closed bounded body precede all RPCs", async () => {
  await environment(async () => {
    const original = globalThis.fetch;
    let calls = 0;
    globalThis.fetch = () => {
      calls++;
      throw new Error("unexpected RPC");
    };
    try {
      for (
        const [body, valid, status] of [["{", false, 401], ["{", true, 400], [
          "x".repeat(1025),
          true,
          413,
        ], [JSON.stringify({ limit: 32 }), true, 503]] as const
      ) {
        const response = await recoverVideoRoute(request(body, valid));
        assertEquals(response.status, status);
        await response.body?.cancel();
      }
      assertEquals(calls, 0);
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
      const response = await recoverVideoRoute(
        new Request("https://example.invalid", {
          method: "POST",
          body,
          signal: controller.signal,
          headers: { apikey: key, "Content-Type": "application/json" },
        }),
      );
      assertEquals(response.status, 503);
      await response.body?.cancel();
      await new Promise((resolve) => setTimeout(resolve, 0));
      assertEquals(cancelled, true);
    } finally {
      globalThis.fetch = original;
    }
  });
});
Deno.test("video recovery admits at most32 and never prepares unclaimed or initial claims", async () => {
  await environment(async () => {
    const original = globalThis.fetch;
    try {
      for (const count of [0, 32, 33]) {
        let claims = 0;
        globalThis.fetch = (url) => {
          const path = String(url);
          if (path.endsWith("/rpc/list_observation_video_analysis_recovery")) {
            return Promise.resolve(
              new Response(
                JSON.stringify(
                  Array.from(
                    { length: count },
                    (_, i) => ({
                      owner_id: id(1),
                      observation_id: id(2),
                      analysis_id: id(i + 3),
                    }),
                  ),
                ),
              ),
            );
          }
          assertEquals(
            path.endsWith("/rpc/claim_observation_video_analysis_recovery"),
            true,
          );
          claims++;
          return Promise.resolve(
            new Response(JSON.stringify(
              claims % 2
                ? { claimed: false, state: "dispatched" }
                : { claimed: true, state: "admitted" },
            )),
          );
        };
        const response = await recoverVideoRoute(request());
        assertEquals(response.status, count === 33 ? 503 : 200);
        if (count !== 33) {
          assertEquals(await response.json(), {
            attempted: count,
            completed: 0,
          });
        } else await response.body?.cancel();
        assertEquals(claims, count === 33 ? 0 : count);
      }
    } finally {
      globalThis.fetch = original;
    }
  });
});
Deno.test("video recovery settles saved refusal without storage provider or fresh admission", async () => {
  await environment(async () => {
    const input = JSON.parse(
      await Deno.readTextFile(
        new URL(
          "../_shared/analysisHistory/fixtures/video-request-v4.json",
          import.meta.url,
        ),
      ),
    )[0].input;
    const original = globalThis.fetch, calls: string[] = [];
    globalThis.fetch = (url, init) => {
      const path = String(url);
      if (path.endsWith("/rpc/list_observation_video_analysis_recovery")) {
        return Promise.resolve(
          new Response(
            JSON.stringify([{
              owner_id: id(1),
              observation_id: input.observation_id,
              analysis_id: input.analysis_id,
            }]),
          ),
        );
      }
      if (path.endsWith("/rpc/claim_observation_video_analysis_recovery")) {
        return Promise.resolve(
          new Response(JSON.stringify({
            state: "dispatched",
            claimed: true,
            work_token: id(4),
            input,
            quota: {
              reservation_id: id(5),
              lease_token: id(6),
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
            provider_outcome: {
              schema_version: 1,
              provenance: {},
              usage: null,
              outcome: { kind: "refusal" },
            },
            draft: null,
          })),
        );
      }
      assertEquals(
        path.endsWith("/rpc/advance_owned_observation_video_analysis"),
        true,
      );
      const args = JSON.parse(String(init?.body));
      assertEquals(args.p_owner, id(1));
      assertEquals(args.p_work, id(4));
      calls.push(args.p_operation);
      return Promise.resolve(new Response("{}"));
    };
    try {
      const response = await recoverVideoRoute(request());
      assertEquals(response.status, 200);
      assertEquals(await response.json(), { attempted: 1, completed: 1 });
      assertEquals(calls, ["fail", "release"]);
    } finally {
      globalThis.fetch = original;
    }
  });
});
