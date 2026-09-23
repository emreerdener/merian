import { estimateCost } from "./profiles.ts";
import type { Pricing, StoredUsage } from "./runContracts.ts";
import { fields, integer, requireCondition as check } from "./validation.ts";

export const APP_MEASUREMENT_MARKER = "[⏱ BENCH] Identification measurement ";
const SPANS = new Set([
  "auth",
  "body_read",
  "tier",
  "pre_gemini_db",
  "gemini",
  "quota_commit",
  "provider",
  "video_promotion",
  "primary_enrichment",
  "database_finalization",
  "dictionary",
  "post_gemini",
  "edge_total",
]);
const TOKEN_FIELDS = [
  "promptTokens",
  "candidateTokens",
  "thinkingTokens",
  "totalTokens",
  "cachedTokens",
  "toolTokens",
] as const;

export interface AppMeasurement {
  version:
    | "identification_app_measurement_v1"
    | "identification_app_measurement_v2";
  contextProfile?: "audio-minimal-v1" | null;
  status: number;
  delivery: "fresh" | "replay" | "unavailable";
  app: {
    version: string | null;
    build: string | null;
    sourceRevision: string | null;
    sourceFingerprint: string | null;
    sourceState: "clean" | "dirty" | null;
  };
  diagnostics: {
    version: 1;
    provider: "gemini";
    requestedModel: "gemini-2.5-flash" | "gemini-2.5-pro";
    returnedModel: string | null;
    backendBundleSha256: string;
    usage: Omit<StoredUsage, "modalities"> | null;
  } | null;
  // Optional for compatibility with measurements from the original app build.
  timingStatus?:
    | "valid"
    | "absent"
    | "oversized"
    | "too_many_metrics"
    | "invalid_syntax"
    | "unknown_metric"
    | "duplicate_metric"
    | "invalid_duration";
  serverTimingMs: Record<string, number>;
  otherEdgeMs: number | null;
}

function matching(value: unknown, pattern: RegExp): void {
  check(
    typeof value === "string" && value.length <= 128 &&
      value.match(pattern)?.[0] === value,
  );
}
function duration(value: unknown): asserts value is number {
  check(
    typeof value === "number" && Number.isFinite(value) && value >= 0 &&
      value <= 600_000,
  );
}

/** Revalidate before retention; no arbitrary app or provider fields survive. */
export function parseAppMeasurement(value: unknown): AppMeasurement {
  const hasTimingStatus = value !== null && typeof value === "object" &&
    Object.hasOwn(value, "timingStatus");
  const v2 = value !== null && typeof value === "object" &&
    "version" in value && value.version === "identification_app_measurement_v2";
  const v = fields(value, [
    "version",
    "status",
    "delivery",
    "app",
    "diagnostics",
    "serverTimingMs",
    "otherEdgeMs",
    ...(hasTimingStatus ? ["timingStatus"] : []),
    ...(v2 ? ["contextProfile"] : []),
  ]);
  check(v2 || v.version === "identification_app_measurement_v1");
  if (v2) {
    check(hasTimingStatus);
    check(v.contextProfile === null || v.contextProfile === "audio-minimal-v1");
    check(
      v.contextProfile === null || (v.status === 200 && v.delivery === "fresh"),
    );
  }
  integer(v.status, 100, 599);
  check(["fresh", "replay", "unavailable"].includes(String(v.delivery)));
  const app = fields(v.app, [
    "version",
    "build",
    "sourceRevision",
    "sourceFingerprint",
    "sourceState",
  ]);
  if (app.version !== null) {
    matching(app.version, /^[0-9]{1,5}(\.[0-9]{1,5}){0,3}$/);
  }
  if (app.build !== null) {
    matching(app.build, /^[0-9]{1,10}(\.[0-9]{1,5}){0,2}$/);
  }
  if (app.sourceRevision !== null) {
    matching(app.sourceRevision, /^[0-9a-f]{40}([0-9a-f]{24})?$/);
  }
  if (app.sourceFingerprint !== null) {
    matching(app.sourceFingerprint, /^[0-9a-f]{64}$/);
  }
  check(
    app.sourceState === null || app.sourceState === "clean" ||
      app.sourceState === "dirty",
  );
  if (v.diagnostics !== null) {
    check(v.delivery === "fresh" && v.status === 200);
    const d = fields(v.diagnostics, [
      "version",
      "provider",
      "requestedModel",
      "returnedModel",
      "backendBundleSha256",
      "usage",
    ]);
    check(d.version === 1 && d.provider === "gemini");
    check(
      d.requestedModel === "gemini-2.5-flash" ||
        d.requestedModel === "gemini-2.5-pro",
    );
    if (d.returnedModel !== null) {
      matching(d.returnedModel, /^gemini-[a-zA-Z0-9.-]{1,100}$/);
    }
    matching(d.backendBundleSha256, /^[0-9a-f]{64}$/);
    if (d.usage !== null) {
      const usage = fields(d.usage, TOKEN_FIELDS);
      for (const count of Object.values(usage)) {
        if (count !== null) integer(count, 0, 10_000_000);
      }
    }
  } else check(v.delivery !== "fresh");
  check(
    v.serverTimingMs !== null && typeof v.serverTimingMs === "object" &&
      !Array.isArray(v.serverTimingMs),
  );
  const spans = v.serverTimingMs as Record<string, unknown>;
  if (hasTimingStatus) {
    check([
      "valid",
      "absent",
      "oversized",
      "too_many_metrics",
      "invalid_syntax",
      "unknown_metric",
      "duplicate_metric",
      "invalid_duration",
    ].includes(String(v.timingStatus)));
    check(v.timingStatus === "valid" || Object.keys(spans).length === 0);
  }
  for (const [name, value] of Object.entries(spans)) {
    check(SPANS.has(name));
    duration(value);
  }
  const expectedOther = typeof spans.edge_total === "number" &&
      typeof spans.provider === "number" && spans.edge_total >= spans.provider
    ? spans.edge_total - spans.provider
    : null;
  if (v.otherEdgeMs !== null) duration(v.otherEdgeMs);
  check(v.otherEdgeMs === expectedOther);
  return structuredClone(v) as unknown as AppMeasurement;
}

/** A necessary per-response check, not case association or UI outcome proof.
 * The operator still needs one complete sequential observation window per case.
 * No historical v1 or missing identity can be promoted by a run annotation.
 */
export function requireFixedAudioMeasurement(value: unknown, expected: {
  app: AppMeasurement["app"];
  backendBundleSha256: string;
  requestedModel: "gemini-2.5-flash" | "gemini-2.5-pro";
}): AppMeasurement {
  const record = parseAppMeasurement(value);
  check(record.version === "identification_app_measurement_v2");
  check(record.contextProfile === "audio-minimal-v1");
  check(record.delivery === "fresh" && record.status === 200);
  check(record.timingStatus === "valid");
  check(record.otherEdgeMs !== null);
  for (
    const key of Object.keys(record.app) as (keyof AppMeasurement["app"])[]
  ) {
    check(record.app[key] !== null && record.app[key] === expected.app[key]);
  }
  check(
    record.diagnostics?.backendBundleSha256 === expected.backendBundleSha256,
  );
  check(record.diagnostics?.requestedModel === expected.requestedModel);
  check(record.diagnostics?.returnedModel === expected.requestedModel);
  return record;
}

/** Existing conservative price policy, scoped to this observed primary attempt.
 * A missing returned model, stale rates or incomplete usage is never zero cost.
 */
export function appMeasurementCost(
  value: AppMeasurement,
  pricing: Pricing | null,
  now: number,
) {
  let reason = "metadata_unavailable";
  let estimatedPrimaryUpperUsd: number | null = null;
  const d = value.diagnostics;
  if (value.delivery === "replay") reason = "replay_original_cost_unknown";
  else if (d) {
    if (!pricing) reason = "pricing_missing";
    else if (
      !Number.isFinite(now) || now < Date.parse(pricing.retrievedAt) ||
      now - Date.parse(pricing.retrievedAt) > 7 * 86400000
    ) reason = "pricing_stale";
    else if (d.returnedModel !== d.requestedModel) {
      reason = "model_price_unverified";
    } else {
      estimatedPrimaryUpperUsd = estimateCost(
        pricing,
        d.requestedModel,
        d.usage ? { ...d.usage, modalities: null } : null,
      );
      reason = estimatedPrimaryUpperUsd === null
        ? "usage_incomplete"
        : "estimated_primary_only";
    }
  }
  return {
    estimatedPrimaryUpperUsd,
    reason,
    scope: "observed_primary_attempt_only" as const,
    invoiceExact: false as const,
  };
}

/** Keep observer costing version-aware while numeric timing events have no cost. */
export function projectedMeasurementCost(
  value: AppMeasurement | Record<string, string | number>,
  pricing: Pricing | null,
  now: number,
) {
  return value.version === "identification_app_measurement_v1" ||
      value.version === "identification_app_measurement_v2"
    ? appMeasurementCost(parseAppMeasurement(value), pricing, now)
    : null;
}

const NUMBER = "([0-9]{1,6}(?:\\.[0-9]{1,6})?)";
const TIMING_MARKERS = {
  "Pre-flight (encode+auth)": "preflight_seconds",
  "Analyze tap to first rendered frame": "tap_to_first_rendered_frame_seconds",
  "Response to first-result state": "response_to_first_result_state_seconds",
  "Post-flight (parse+save+state)": "postflight_seconds",
  "Total pipeline": "total_pipeline_seconds",
};

/** Consumes one OS log row in memory; never returns the original row or message. */
export function projectAppLog(
  line: string,
): AppMeasurement | Record<string, string | number> | null {
  if (line.length > 65536) return null;
  try {
    const row = JSON.parse(line);
    if (
      row.subsystem !== "com.merian.app" ||
      typeof row.eventMessage !== "string" || row.eventMessage.length > 4096
    ) return null;
    const message: string = row.eventMessage;
    if (message.startsWith(APP_MEASUREMENT_MARKER)) {
      return parseAppMeasurement(
        JSON.parse(message.slice(APP_MEASUREMENT_MARKER.length)),
      );
    }
    for (const [label, metric] of Object.entries(TIMING_MARKERS)) {
      const prefix = `[⏱ BENCH] ${label}: `;
      if (!message.startsWith(prefix)) continue;
      const match = message.slice(prefix.length).match(
        new RegExp(`^${NUMBER}s$`),
      );
      if (!match || match[0] !== message.slice(prefix.length)) return null;
      const value = Number(match[1]);
      duration(value);
      return { event: metric, value, unit: "seconds" };
    }
    const http = message.match(
      new RegExp(
        `^\\[⏱ BENCH\\] HTTP identify-multimodal auth=${NUMBER}s transfer\\+server=${NUMBER}s status=([1-5][0-9]{2}) requestBytes=[0-9]{1,10} responseBytes=[0-9]{1,10}$`,
      ),
    );
    if (http && http[0] === message) {
      duration(Number(http[1]));
      duration(Number(http[2]));
      return {
        event: "http_identification",
        authSeconds: Number(http[1]),
        transferAndServerSeconds: Number(http[2]),
        status: Number(http[3]),
      };
    }
    return null;
  } catch {
    return null;
  }
}

/** Bounded newline decoder: oversized log rows are discarded without buffering
 * the entire row. Only one <=64 KiB row is retained at a time. */
export async function* boundedLogLines(
  stream: ReadableStream<Uint8Array>,
  options: { signal?: AbortSignal; onOversize?: () => void } = {},
): AsyncGenerator<string> {
  const reader = stream.getReader();
  const cancel = () => {
    void reader.cancel().catch(() => {});
  };
  options.signal?.addEventListener("abort", cancel, { once: true });
  if (options.signal?.aborted) cancel();
  let pending: number[] = [], dropping = false;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      for (const byte of value) {
        if (options.signal?.aborted) return;
        if (byte === 10) {
          if (!dropping) {
            yield new TextDecoder().decode(new Uint8Array(pending));
          }
          pending = [];
          dropping = false;
        } else if (!dropping) {
          if (pending.length === 65536) {
            options.onOversize?.();
            pending = [];
            dropping = true;
          } else pending.push(byte);
        }
      }
    }
  } finally {
    options.signal?.removeEventListener("abort", cancel);
    await reader.cancel().catch(() => {});
    reader.releaseLock();
  }
}
