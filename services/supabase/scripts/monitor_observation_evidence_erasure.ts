/** Service-only aggregate observation. Never retires, claims or repairs work. */
import { createServiceRoleClientFromEnvironmentWithOptions } from "../functions/_shared/serviceRoleClient.ts";

type Shape = Record<
  string,
  "count" | "age" | "optional-age" | "boolean" | "result" | "receipt-version"
>;
const queueShape: Shape = {
  pending: "count",
  claimable: "count",
  deferred: "count",
  live_claims: "count",
  expired_claims: "count",
  unknown_age: "count",
  oldest_pending_age_seconds: "age",
  oldest_due_age_seconds: "age",
};
const retirementShape: Shape = {
  photo: "count",
  audio: "count",
  video: "count",
  orphan: "count",
  objects: "count",
  oldest_age_seconds: "age",
  expired_unretirable_objects: "count",
  expired_bound_objects: "count",
};
const workerShape: Shape = {
  enabled: "boolean",
  cron_active: "boolean",
  credentials_ready: "boolean",
  admission_enabled: "boolean",
  request_pending: "boolean",
  request_age_seconds: "optional-age",
  last_result: "result",
  consecutive_failures: "count",
  success_age_seconds: "optional-age",
  marker_success_age_seconds: "optional-age",
};
const results = new Set([
  "never",
  "pending",
  "success",
  "failure",
  "unknown",
  "configuration_unavailable",
]);

export interface EvidenceErasureHealth {
  schema_version: 1 | 2;
  capture_stage?: EvidenceErasureHealth["queue"] & { marker_failures: number };
  generated_at: string;
  queue: {
    pending: number;
    claimable: number;
    deferred: number;
    live_claims: number;
    expired_claims: number;
    unknown_age: number;
    oldest_pending_age_seconds: number;
    oldest_due_age_seconds: number;
  };
  retirement: {
    photo: number;
    audio: number;
    video: number;
    composition?: number;
    orphan: number;
    objects: number;
    oldest_age_seconds: number;
    expired_unretirable_objects: number;
    expired_bound_objects: number;
  };
  worker: {
    enabled: boolean;
    cron_active: boolean;
    credentials_ready: boolean;
    admission_enabled: boolean;
    request_pending: boolean;
    request_age_seconds: number | null;
    last_result: string;
    consecutive_failures: number;
    success_age_seconds: number | null;
    marker_success_age_seconds: number | null;
    last_receipt_schema_version?: 2 | 3 | 4 | null;
  };
}

function reject(): never {
  throw new Error("Invalid private evidence health aggregate");
}
function object(value: unknown, keys: string[]): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    reject();
  }
  const record = value as Record<string, unknown>;
  if (
    Object.keys(record).length !== keys.length ||
    keys.some((key) => !(key in record))
  ) reject();
  return record;
}
function shape(value: unknown, schema: Shape): void {
  const record = object(value, Object.keys(schema));
  for (const [key, kind] of Object.entries(schema)) {
    const item = record[key];
    if (kind === "optional-age" && item === null) continue;
    if (kind === "boolean") {
      if (typeof item !== "boolean") reject();
    } else if (kind === "receipt-version") {
      if (item !== null && item !== 2 && item !== 3 && item !== 4) reject();
    } else if (kind === "result") {
      if (typeof item !== "string" || !results.has(item)) reject();
    } else {
      if (
        typeof item !== "number" || !Number.isFinite(item) || item < 0 ||
        item > Number.MAX_SAFE_INTEGER
      ) reject();
      if (kind === "count" && !Number.isSafeInteger(item)) reject();
    }
  }
}

export function parseEvidenceErasureHealth(
  value: unknown,
  now = Date.now(),
): EvidenceErasureHealth {
  const stageHealth = value !== null && typeof value === "object" &&
    !Array.isArray(value) &&
    "schema_version" in value && value.schema_version === 2;
  const root = object(value, [
    "schema_version",
    "generated_at",
    "queue",
    "retirement",
    "worker",
    ...(stageHealth ? ["capture_stage"] : []),
  ]);
  if (
    ![1, 2].includes(root.schema_version as number) ||
    typeof root.generated_at !== "string"
  ) {
    reject();
  }
  const timestamp = Date.parse(root.generated_at);
  if (
    !Number.isFinite(timestamp) || timestamp > now + 5_000 ||
    now - timestamp > 30_000
  ) reject();
  shape(root.queue, queueShape);
  if (stageHealth) {
    shape(root.capture_stage, { ...queueShape, marker_failures: "count" });
  }
  // Schema 1 has two closed generations. Accept the additive pair together;
  // partial upgrades and arbitrary fields still fail without logging the body.
  const compositionHealth = root.retirement !== null &&
    typeof root.retirement === "object" &&
    Object.hasOwn(root.retirement, "composition");
  shape(
    root.retirement,
    compositionHealth
      ? { ...retirementShape, composition: "count" }
      : retirementShape,
  );
  shape(
    root.worker,
    compositionHealth
      ? { ...workerShape, last_receipt_schema_version: "receipt-version" }
      : workerShape,
  );
  if (stageHealth && !compositionHealth) reject();
  const health = root as unknown as EvidenceErasureHealth;
  const q = health.queue;
  const w = health.worker;
  if (
    q.pending !== q.claimable + q.deferred + q.live_claims ||
    q.unknown_age > q.pending || q.expired_claims > q.pending - q.live_claims
  ) reject();
  const stage = health.capture_stage;
  if (
    stage &&
    (stage.pending !== stage.claimable + stage.deferred + stage.live_claims ||
      stage.unknown_age > stage.pending ||
      stage.expired_claims > stage.pending - stage.live_claims ||
      stage.marker_failures > stage.pending)
  ) reject();
  if (w.request_pending !== (w.request_age_seconds !== null)) reject();
  return health;
}

export function evaluateEvidenceErasureHealth(health: EvidenceErasureHealth) {
  const critical: string[] = [];
  const warning: string[] = [];
  const { queue: q, retirement: r, worker: w } = health;
  if (
    !w.enabled || !w.cron_active || !w.credentials_ready || !w.admission_enabled
  ) critical.push("drain_not_ready");
  if (w.last_result === "unknown" || (w.request_age_seconds ?? 0) >= 180) {
    critical.push("dispatch_outcome_unknown");
  }
  if (w.success_age_seconds === null || w.success_age_seconds >= 300) {
    critical.push("successful_heartbeat_missing");
  }
  if (
    r.composition !== undefined &&
    ![3, 4].includes(w.last_receipt_schema_version ?? 0)
  ) {
    critical.push("composition_receipt_unverified");
  }
  if (
    w.consecutive_failures > 0 ||
    ["failure", "configuration_unavailable"].includes(w.last_result)
  ) critical.push("worker_failure");
  const stage = health.capture_stage;
  if (stage && w.last_receipt_schema_version !== 4) {
    critical.push("capture_stage_receipt_unverified");
  }
  if (stage && stage.marker_failures > 0) {
    critical.push("capture_stage_marker_failure");
  }
  if (stage && stage.expired_claims > 0) {
    critical.push("capture_stage_claim_outcome_unknown");
  }
  if (q.unknown_age > 0 || (stage?.unknown_age ?? 0) > 0) {
    critical.push("historical_backlog_age_unknown");
  }
  if (r.expired_unretirable_objects > 0) {
    warning.push("expired_evidence_requires_classification");
  }
  const age = Math.max(
    q.oldest_pending_age_seconds,
    q.oldest_due_age_seconds,
    r.oldest_age_seconds,
    stage?.oldest_pending_age_seconds ?? 0,
    stage?.oldest_due_age_seconds ?? 0,
  );
  const backlog = q.pending + r.objects + (stage?.pending ?? 0);
  if (age >= 1800 || backlog >= 180) {
    critical.push("drain_capacity_or_age_exceeded");
  } else if (age >= 600 || backlog >= 60) {
    warning.push("drain_capacity_or_age_warning");
  }
  return {
    status: critical.length ? "critical" : warning.length ? "warning" : "ok",
    critical,
    warning,
    health,
  };
}

export async function runEvidenceErasureMonitor(
  args: string[],
): Promise<number> {
  // Closed CLI: no arbitrary output path or URL/credential override.
  if (
    args.length > 1 ||
    (args.length === 1 &&
      !["--fail-on=warning", "--fail-on=critical"].includes(args[0]))
  ) {
    console.error("Expected --fail-on=warning or --fail-on=critical");
    return 2;
  }
  try {
    const client = createServiceRoleClientFromEnvironmentWithOptions({
      requestTimeoutMs: 15_000,
      maximumResponseBytes: 16_384,
    });
    const { data, error } = await client.rpc(
      "get_observation_evidence_erasure_health",
    );
    if (error) throw new Error("Health unavailable");
    const summary = evaluateEvidenceErasureHealth(
      parseEvidenceErasureHealth(data),
    );
    console.log(JSON.stringify(summary));
    return summary.status === "critical" ||
        (summary.status === "warning" && args[0] !== "--fail-on=critical")
      ? 1
      : 0;
  } catch {
    // Provider errors and invalid bodies can contain private details. Do not log.
    console.error(
      "Private evidence health unavailable or invalid; status=critical",
    );
    return 1;
  }
}

if (import.meta.main) Deno.exit(await runEvidenceErasureMonitor(Deno.args));
