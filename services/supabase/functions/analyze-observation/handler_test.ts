import { assertEquals } from "@std/assert";
import { createClient } from "@supabase/supabase-js";
import { historyWorkerRPC } from "../_shared/analysisHistory/production.ts";
import { analyzeObservation } from "./handler.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const input = {
  schema_version: 1,
  observation_id: id(1),
  analysis_id: id(2),
  source_analysis_id: null,
  request_digest: "a".repeat(64),
  evidence_manifest: {
    schema_version: 1,
    captured_media: [{
      description: { _0: { freeText: "Synthetic description." } },
    }],
  },
  entitlement_protocol: 3,
  identification_protocol: 6,
  history_protocol: 7,
  expected_processor_permission: "google_gemini",
};
const req = new Request("https://example.invalid/analyze-observation", {
  method: "POST",
});
Deno.test("analysis HTTP response is a closed status projection with verified owner", async () => {
  const response = await analyzeObservation(req, input, id(3), {
    run: (owner) => {
      assertEquals(owner, id(3));
      return Promise.resolve("complete");
    },
  });
  assertEquals(response.status, 200);
  assertEquals(response.headers.get("cache-control"), "private, no-store");
  assertEquals(await response.json(), {
    schema_version: 1,
    observation_id: id(1),
    analysis_id: id(2),
    state: "complete",
  });
});
Deno.test("analysis HTTP uncertainty retains stable IDs and private failures are sanitized", async () => {
  const pending = await analyzeObservation(req, input, id(3), {
    run: () => Promise.resolve("dispatched"),
  });
  assertEquals(pending.status, 202);
  const failure = await analyzeObservation(req, input, id(3), {
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
      (await analyzeObservation(req, bad, id(3), {
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
      ["begin_owned_observation_analysis", 409],
      ["advance_owned_observation_analysis", 503],
    ] as const
  ) {
    const response = await analyzeObservation(req, input, id(3), {
      run: async () => {
        await historyWorkerRPC(client, rpc, {});
        return "complete";
      },
    });
    assertEquals(response.status, expected);
    assertEquals(response.headers.get("cache-control"), "private, no-store");
    const text = await response.text();
    assertEquals(
      text.includes("Retry with the same analysis"),
      expected === 503,
    );
    assertEquals(
      text.includes("analysis_history_operation_conflict"),
      expected === 409,
    );
  }
});
