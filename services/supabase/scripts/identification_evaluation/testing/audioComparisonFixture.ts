// Synthetic metadata only; shared by pure and isolated filesystem tests.
import { AUDIO_COMPARISON_EVENT_VERSION } from "../audioComparisonObservation.ts";
import { AUDIO_COMPARISON_PLAN_SHA256 } from "../../../functions/identify-multimodal/comparison/plan.ts";

export function audioComparisonObservationFixture() {
  const app = {
    version: "1.0.3",
    build: "300",
    sourceRevision: "a".repeat(40),
    sourceFingerprint: "b".repeat(64),
    sourceState: "clean",
  };
  const expected = { slot: 1, app, backendBundleSha256: "c".repeat(64) };
  const measurement = {
    version: "identification_app_measurement_v2",
    contextProfile: "audio-minimal-v1",
    status: 200,
    delivery: "fresh",
    app,
    diagnostics: {
      version: 1,
      provider: "gemini",
      requestedModel: "gemini-2.5-pro",
      returnedModel: "gemini-2.5-pro",
      backendBundleSha256: expected.backendBundleSha256,
      usage: null,
    },
    timingStatus: "valid",
    serverTimingMs: { provider: 10, edge_total: 20 },
    otherEdgeMs: 10,
  };
  const proof = (event: string) => ({
    version: AUDIO_COMPARISON_EVENT_VERSION,
    event,
    planSha256: AUDIO_COMPARISON_PLAN_SHA256,
    slot: 1,
    measurementSha256: "d".repeat(64),
    ...(event === "finalized"
      ? { confidenceScore: 0.95, isBiological: true, persistence: "saved" }
      : {}),
  });
  const events = [
    {
      event: "http_identification",
      authSeconds: 0.1,
      transferAndServerSeconds: 1,
      status: 200,
    },
    measurement,
    proof("receipt"),
    proof("rendered"),
    { event: "tap_to_first_rendered_frame_seconds", value: 2, unit: "seconds" },
    proof("finalized"),
  ];
  const rows: Record<string, unknown>[] = [
    {
      version: "identification_app_observation_v2",
      startedAt: "2026-09-23T00:00:00.000Z",
      maxSeconds: 120,
      shutdownGraceSeconds: 30,
      maxEvents: 100,
      automaticSubmissions: 0,
      pricing: null,
      caseAssociation: "requires_observed_sequential_ui_actions",
      costScope: "observed_primary_attempts_only",
    },
    { readyAt: "2026-09-23T00:00:01.000Z", status: "observer_ready" },
    ...events.map((measurement) => ({
      observedAt: "2026-09-23T00:00:03.000Z",
      observedAfterSeconds: 3,
      measurement,
      measurementSha256: "version" in measurement &&
          measurement.version === "identification_app_measurement_v2"
        ? "d".repeat(64)
        : null,
      cost: null,
    })),
    {
      finishedAt: "2026-09-23T00:02:00.000Z",
      status: "window_completed",
      events: events.length,
      ready: true,
      stopReason: "collector_exit",
      collectorExitCode: 0,
      collectorSignal: null,
      unprojectedRows: 2,
      oversizedRows: 0,
      rejectedProofRows: 0,
    },
  ];
  return { expected, measurement, proof, rows };
}
