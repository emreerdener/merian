import { assertEquals } from "@std/assert";
import { createClient } from "@supabase/supabase-js";
import { historyWorkerRPC } from "../_shared/analysisHistory/production.ts";
import { analyzeObservationVideo } from "./handler.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const vectors = JSON.parse(
  await Deno.readTextFile(
    new URL(
      "../_shared/analysisHistory/fixtures/video-request-v4.json",
      import.meta.url,
    ),
  ),
);
const input = vectors[0].input;
const req = new Request("https://example.invalid/analyze-observation", {
  method: "POST",
});
Deno.test("analysis HTTP response is a closed status projection with verified owner", async () => {
  const response = await analyzeObservationVideo(req, input, id(3), {
    run: (owner) => {
      assertEquals(owner, id(3));
      return Promise.resolve("complete");
    },
  });
  assertEquals(response.status, 200);
  assertEquals(response.headers.get("cache-control"), "private, no-store");
  assertEquals(await response.json(), {
    schema_version: 1,
    observation_id: input.observation_id,
    analysis_id: input.analysis_id,
    state: "complete",
  });
});
Deno.test("analysis HTTP uncertainty retains stable IDs and private failures are sanitized", async () => {
  const pending = await analyzeObservationVideo(req, input, id(3), {
    run: () => Promise.resolve("dispatched"),
  });
  assertEquals(pending.status, 202);
  const failure = await analyzeObservationVideo(req, input, id(3), {
    run: () => Promise.reject(new Error("synthetic private diagnostics")),
  });
  assertEquals(failure.status, 503);
  assertEquals((await failure.text()).includes("private diagnostics"), false);
});
Deno.test("analysis HTTP rejects caller ownership and unsupported protocols before any work", async () => {
  let calls = 0;
  for (
    const bad of [{ ...input, owner_id: id(4) }, {
      ...input,
      history_protocol: 6,
    }]
  ) {
    assertEquals(
      (await analyzeObservationVideo(req, bad, id(3), {
        run: () => {
          calls++;
          return Promise.resolve("complete");
        },
      })).status,
      400,
    );
  }
  assertEquals(calls, 0);
});

Deno.test("admission identity conflicts are permanent but worker claim conflicts remain recoverable", async () => {
  const client = createClient("https://example.invalid", "synthetic-test-key", {
    auth: { persistSession: false, autoRefreshToken: false },
    global: {
      fetch: () =>
        Promise.resolve(
          new Response(
            JSON.stringify({
              code: "22023",
              message: "analysis_history_operation_conflict",
              details: null,
              hint: null,
            }),
            { status: 400, headers: { "Content-Type": "application/json" } },
          ),
        ),
    },
  });
  for (
    const [rpc, expected] of [
      ["begin_owned_observation_video_analysis", 409],
      ["advance_owned_observation_video_analysis", 503],
    ] as const
  ) {
    const response = await analyzeObservationVideo(req, input, id(3), {
      run: async () => {
        await historyWorkerRPC(client, rpc, {});
        return "complete";
      },
    });
    assertEquals(response.status, expected);
    assertEquals(response.headers.get("cache-control"), "private, no-store");
    const text = await response.text();
    assertEquals(
      text.includes("Recover this analysis using its saved identity"),
      expected === 503,
    );
    assertEquals(
      text.includes("analysis_history_operation_conflict"),
      expected === 409,
    );
  }
});
