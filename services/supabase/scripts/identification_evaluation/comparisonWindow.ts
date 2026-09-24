import {
  type AppMeasurement,
  appMeasurementCost,
  requireFixedAudioMeasurement,
} from "./appObservation.ts";
import type { NumericAppEvent } from "./audioComparisonObservation.ts";
import { fields, integer, requireCondition as check } from "./validation.ts";
import { parsePricing } from "./runContracts.ts";

export interface ComparisonWindowExpectation {
  slot: number;
  app: AppMeasurement["app"];
  backendBundleSha256: string;
}

export function parseComparisonWindowExpectation(
  value: unknown,
  maxSlot: number,
): ComparisonWindowExpectation {
  const v = fields(value, ["slot", "app", "backendBundleSha256"]);
  integer(v.slot, 1, maxSlot);
  const app = fields(v.app, [
    "version",
    "build",
    "sourceRevision",
    "sourceFingerprint",
    "sourceState",
  ]);
  const patterns: Record<string, RegExp> = {
    version: /^[0-9]{1,5}(\.[0-9]{1,5}){0,3}$/,
    build: /^[0-9]{1,10}(\.[0-9]{1,5}){0,2}$/,
    sourceRevision: /^[0-9a-f]{40}([0-9a-f]{24})?$/,
    sourceFingerprint: /^[0-9a-f]{64}$/,
    sourceState: /^(clean|dirty)$/,
  };
  for (const [key, pattern] of Object.entries(patterns)) {
    check(typeof app[key] === "string" && pattern.test(app[key] as string));
  }
  check(
    typeof v.backendBundleSha256 === "string" &&
      /^[0-9a-f]{64}$/.test(v.backendBundleSha256),
  );
  return structuredClone(v) as unknown as ComparisonWindowExpectation;
}

function timestamp(value: unknown): number {
  check(
    typeof value === "string" &&
      /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(value),
  );
  const result = Date.parse(value);
  check(Number.isFinite(result) && new Date(result).toISOString() === value);
  return result;
}

/** Admission, not an accuracy score or invoice. Never upgrades old profile-only
 * evidence. The observer must see one exact slot, a fresh response, finalized
 * native persistence and the exact UIKit draw in one normally closed window. */
export function admitComparisonWindowEvidence(
  rows: unknown[],
  expected: ComparisonWindowExpectation,
  proof: {
    version: string;
    parse: (value: unknown) => NumericAppEvent;
    exactSeconds?: number;
  },
) {
  check(rows.length >= 8 && rows.length <= 103);
  const header = fields(rows[0], [
    "version",
    "startedAt",
    "maxSeconds",
    "shutdownGraceSeconds",
    "maxEvents",
    "automaticSubmissions",
    "pricing",
    "caseAssociation",
    "costScope",
  ]);
  check(header.version === "identification_app_observation_v2");
  integer(header.maxSeconds, 1, 300);
  if (proof.exactSeconds !== undefined) {
    check(header.maxSeconds === proof.exactSeconds);
  }
  check(
    header.shutdownGraceSeconds === 30 && header.maxEvents === 100 &&
      header.automaticSubmissions === 0,
  );
  check(
    header.caseAssociation === "requires_observed_sequential_ui_actions" &&
      header.costScope === "observed_primary_attempts_only",
  );
  const pricing = header.pricing === null ? null : parsePricing(header.pricing);
  const started = timestamp(header.startedAt);
  const ready = fields(rows[1], ["readyAt", "status"]);
  check(ready.status === "observer_ready");
  const readyAt = timestamp(ready.readyAt);
  const finished = fields(rows.at(-1), [
    "finishedAt",
    "status",
    "events",
    "ready",
    "stopReason",
    "collectorExitCode",
    "collectorSignal",
    "unprojectedRows",
    "oversizedRows",
    "rejectedProofRows",
  ]);
  const finishedAt = timestamp(finished.finishedAt);
  check(
    finished.status === "window_completed" && finished.ready === true &&
      finished.stopReason === "collector_exit" &&
      finished.collectorExitCode === 0 && finished.collectorSignal === null,
  );
  check(finished.oversizedRows === 0 && finished.rejectedProofRows === 0);
  integer(finished.unprojectedRows, 0, 100_000);
  check(
    finished.events === rows.length - 3 && (finished.events as number) < 100,
  );
  check(started <= readyAt && readyAt <= finishedAt);
  check(
    finishedAt - started >= header.maxSeconds * 1000 &&
      finishedAt - started <= (header.maxSeconds + 31) * 1000,
  );
  let lastTime = readyAt, lastElapsed = 0;
  const events = rows.slice(2, -1).map((row) => {
    const v = fields(row, [
      "observedAt",
      "observedAfterSeconds",
      "measurement",
      "measurementSha256",
      "cost",
    ]);
    const time = timestamp(v.observedAt);
    check(time >= lastTime && time <= finishedAt);
    lastTime = time;
    check(
      typeof v.observedAfterSeconds === "number" &&
        Number.isFinite(v.observedAfterSeconds) &&
        v.observedAfterSeconds >= lastElapsed &&
        v.observedAfterSeconds <= (header.maxSeconds as number) + 31,
    );
    lastElapsed = v.observedAfterSeconds as number;
    check(
      v.measurement !== null && typeof v.measurement === "object" &&
        !Array.isArray(v.measurement),
    );
    return {
      observedAt: v.observedAt,
      measurementSha256: v.measurementSha256,
      measurement: v.measurement as Record<string, unknown>,
    };
  });
  const measurements = events.filter((e) =>
    e.measurement.version?.toString().startsWith(
      "identification_app_measurement_",
    )
  );
  check(measurements.length === 1);
  const row = measurements[0];
  check(
    typeof row.measurementSha256 === "string" &&
      /^[0-9a-f]{64}$/.test(row.measurementSha256),
  );
  const measurement = requireFixedAudioMeasurement(row.measurement, {
    ...expected,
    requestedModel: "gemini-2.5-pro",
  });
  const proofs = events.filter((e) => e.measurement.version === proof.version);
  check(proofs.length === 3);
  check(events.every((e) =>
    !("version" in e.measurement) ||
    e.measurement.version === row.measurement.version ||
    e.measurement.version === proof.version
  ));
  const parsed = proofs.map((e) => proof.parse(e.measurement));
  check(new Set(parsed.map((e) => e.event)).size === 3);
  check(
    parsed.every((e) =>
      e.slot === expected.slot && e.measurementSha256 === row.measurementSha256
    ),
  );
  check(
    parsed[0].event === "receipt" &&
      events.indexOf(proofs[0]) > events.indexOf(row),
  );
  const http = events.filter((e) =>
    e.measurement.event === "http_identification"
  );
  check(
    http.length === 1 && http[0].measurement.status === 200 &&
      events.indexOf(http[0]) < events.indexOf(row),
  );
  const render = events.filter((e) =>
    e.measurement.event === "tap_to_first_rendered_frame_seconds"
  );
  check(
    render.length === 1 && typeof render[0].measurement.value === "number" &&
      render[0].measurement.value >= 0 && render[0].measurement.value <= 600 &&
      render[0].measurement.unit === "seconds",
  );
  // The exact draw proof is emitted by the same callback before its timing.
  check(
    events.indexOf(render[0]) > events.indexOf(
      proofs[parsed.findIndex((p) => p.event === "rendered")],
    ),
  );
  const outcome = parsed.find((p) => p.event === "finalized")!;
  return {
    measurement,
    measurementSha256: row.measurementSha256,
    outcome,
    tapToFirstRenderedFrameSeconds: render[0].measurement.value,
    primaryCost: appMeasurementCost(
      measurement,
      pricing,
      timestamp(row.observedAt),
    ),
    scope:
      "single_foreground_slot_saved_or_completed_without_record_and_rendered",
    accuracyScored: false,
    automaticSubmissions: 0,
  };
}
