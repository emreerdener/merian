import { assertEquals, assertThrows } from "@std/assert";
import {
  APP_MEASUREMENT_MARKER,
  appMeasurementCost,
  boundedLogLines,
  parseAppMeasurement,
  projectAppLog,
} from "./identification_evaluation/appObservation.ts";
import {
  MODELS,
  parsePricing,
} from "./identification_evaluation/runContracts.ts";
import {
  IDENTIFICATION_DIAGNOSTICS_HEADER,
  identificationDiagnosticHeaders,
} from "../functions/identify-multimodal/diagnostics.ts";
import { diagnosticFixture } from "../functions/identify-multimodal/diagnostics_test.ts";

function fixture() {
  return parseAppMeasurement({
    version: "identification_app_measurement_v1",
    status: 200,
    delivery: "fresh",
    app: {
      version: "1.0.3",
      build: "275",
      sourceRevision: "a".repeat(40),
      sourceFingerprint: "b".repeat(64),
      sourceState: "dirty",
    },
    diagnostics: JSON.parse(
      identificationDiagnosticHeaders(
        diagnosticFixture(),
      )[IDENTIFICATION_DIAGNOSTICS_HEADER],
    ),
    serverTimingMs: { provider: 20, edge_total: 100, gemini: 25 },
    otherEdgeMs: 80,
  });
}
const pricing = parsePricing({
  version: "evaluation_pricing_v1",
  currency: "USD",
  service: "paid_standard_synchronous",
  retrievedAt: "2026-09-22T00:00:00.000Z",
  sourceUrl: "https://ai.google.dev/gemini-api/docs/pricing",
  reviewRef: "synthetic-review",
  includesReasoning: true,
  models: MODELS.map((model) => ({
    model,
    inputPerMillion: { text: 1, image: 2, audio: 3, cached: 1 },
    outputPerMillion: 4,
    maxInputTokens: 10000,
    maxBillableOutputTokens: 20000,
    limitsEvidenceRef: "synthetic-limits",
  })),
});
const now = Date.parse("2026-09-22T01:00:00Z");

Deno.test("observer accepts backend projection plus native measurement contract and computes primary cost", () => {
  const v = fixture();
  const line = JSON.stringify({
    subsystem: "com.merian.app",
    eventMessage: APP_MEASUREMENT_MARKER + JSON.stringify(v),
    ignoredPrivateField: "synthetic-private",
  });
  assertEquals(projectAppLog(line), v);
  // Highest input price, no cache discount, output includes thinking.
  assertEquals(
    appMeasurementCost(v, pricing, now).estimatedPrimaryUpperUsd,
    0.0004,
  );
  assertEquals(
    appMeasurementCost(v, pricing, now).scope,
    "observed_primary_attempt_only",
  );
});

Deno.test("observer keeps unpriced, stale, replayed, unknown and incomplete calls unknown", () => {
  const v = fixture();
  assertEquals(appMeasurementCost(v, null, now).estimatedPrimaryUpperUsd, null);
  assertEquals(
    appMeasurementCost(v, pricing, now + 8 * 86400000).reason,
    "pricing_stale",
  );
  v.diagnostics!.returnedModel = "gemini-2.5-pro";
  assertEquals(
    appMeasurementCost(v, pricing, now).reason,
    "model_price_unverified",
  );
  v.diagnostics!.returnedModel = "gemini-2.5-flash";
  v.diagnostics!.usage!.thinkingTokens = null;
  assertEquals(appMeasurementCost(v, pricing, now).reason, "usage_incomplete");
  v.diagnostics = null;
  v.delivery = "replay";
  assertEquals(
    appMeasurementCost(v, pricing, now).reason,
    "replay_original_cost_unknown",
  );
  v.delivery = "unavailable";
  assertEquals(
    appMeasurementCost(v, pricing, now).estimatedPrimaryUpperUsd,
    null,
  );
});

Deno.test("observer rejects unexpected content, impossible timings and false freshness", () => {
  const v = fixture();
  assertThrows(() =>
    parseAppMeasurement({ ...v, rawContent: "synthetic-private" })
  );
  assertThrows(() => parseAppMeasurement({ ...v, status: 503 }));
  assertThrows(() => parseAppMeasurement({ ...v, delivery: "replay" }));
  assertThrows(() => parseAppMeasurement({ ...v, otherEdgeMs: 0 }));
  assertThrows(() =>
    parseAppMeasurement({
      ...v,
      serverTimingMs: { ...v.serverTimingMs, unknown: 1 },
    })
  );
  for (const value of [-1, 1.2, 10_000_001, true]) {
    assertThrows(() =>
      parseAppMeasurement({
        ...v,
        diagnostics: {
          ...v.diagnostics,
          usage: { ...v.diagnostics!.usage, promptTokens: value },
        },
      })
    );
  }
  assertEquals(
    projectAppLog(
      JSON.stringify({
        subsystem: "unrelated",
        eventMessage: APP_MEASUREMENT_MARKER + JSON.stringify(v),
      }),
    ),
    null,
  );
  assertEquals(
    projectAppLog(
      JSON.stringify({
        subsystem: "com.merian.app",
        eventMessage: APP_MEASUREMENT_MARKER + "unstructured-private-message",
      }),
    ),
    null,
  );
});

Deno.test("observer projects legacy numeric timing only and rejects suffixes", () => {
  const line = (text: string) =>
    JSON.stringify({ subsystem: "com.merian.app", eventMessage: text });
  assertEquals(projectAppLog(line("[⏱ BENCH] Total pipeline: 2.123s")), {
    event: "total_pipeline_seconds",
    value: 2.123,
    unit: "seconds",
  });
  assertEquals(
    projectAppLog(line("[⏱ BENCH] Total pipeline: 2.123s private")),
    null,
  );
  assertEquals(
    projectAppLog(
      line(
        "[⏱ BENCH] HTTP identify-multimodal auth=0.001s transfer+server=2.123s status=200 requestBytes=12 responseBytes=34",
      ),
    ),
    {
      event: "http_identification",
      authSeconds: 0.001,
      transferAndServerSeconds: 2.123,
      status: 200,
    },
  );
  assertEquals(
    projectAppLog(line("[⏱ BENCH] Server-Timing private-content")),
    null,
  );
});

Deno.test("observer streaming decoder drops oversized lines and resumes after boundaries", async () => {
  const parts = [
    "hello",
    "\n" + "x".repeat(40000),
    "x".repeat(40000) + "\nnext",
    "\n",
  ];
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      for (const p of parts) controller.enqueue(new TextEncoder().encode(p));
      controller.close();
    },
  });
  const lines = [];
  for await (const line of boundedLogLines(stream)) lines.push(line);
  assertEquals(lines, ["hello", "next"]);
});
