import type {
  AIAttemptSnapshot,
  AIRequest,
} from "../../_shared/ai/contracts.ts";
import { buildGeminiRequestParameters } from "../../_shared/ai/geminiRequest.ts";
import {
  type AIQuotaReservation,
  deriveAIRequestId,
} from "../../_shared/aiQuota.ts";
import { encodeBase64 } from "../../_shared/encoding.ts";
import {
  PRO_DIAGNOSTIC_TRIGGER,
  PRO_POSSIBLE,
  PRO_STRONG,
} from "../../_shared/identify/thresholds.ts";
import { IDENTIFICATION_BUNDLE_SHA256 } from "../deploymentIdentity.ts";
import { processMultimodalWAV } from "../audio.ts";
import { decodeBase64 } from "../../_shared/encoding.ts";
import { fingerprintBytes, fingerprintJson } from "./fingerprint.ts";
import {
  AUDIO_PROMPT_COMPARISON_PLAN,
  AUDIO_PROMPT_COMPARISON_PLAN_SHA256,
} from "./promptPlan.ts";

export const AUDIO_PROMPT_COMPARISON_CONFIG_ENV =
  "IDENTIFICATION_AUDIO_PROMPT_COMPARISON_V1";
export const AUDIO_PROMPT_COMPARISON_HEADER =
  "X-Merian-Audio-Prompt-Comparison";
// Fixed namespace survives marker loss, recovery, expiry and config removal.
// It is reserved only by this endpoint; ordinary UUIDs retain their semantics.
const SCAN_PREFIX = "ac0b0001-";
const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const WINDOW_START = Date.parse(AUDIO_PROMPT_COMPARISON_PLAN.startsNotBefore);
const RETENTION_END = Date.parse(AUDIO_PROMPT_COMPARISON_PLAN.expiresNotAfter);
interface Assignment {
  readonly slot: number;
  readonly caseId: string;
  readonly arm: "A" | "B";
  readonly block: number;
  readonly repeat: number;
  readonly sourceWavSha256: string;
  readonly sourceByteLength: number;
  readonly processedWavSha256: string;
  readonly providerRequestSha256: string;
  readonly policySha256: string;
  readonly confidenceSha256: string;
}
export interface AudioPromptComparison {
  readonly assignment: Assignment;
  readonly expiresAt: number;
}

export class AudioPromptComparisonError extends Error {
  constructor(
    readonly code:
      | "audio_prompt_comparison_unavailable"
      | "audio_prompt_comparison_mismatch"
      | "audio_prompt_comparison_excluded",
  ) {
    super(code);
  }
}

function check(
  condition: unknown,
  code: AudioPromptComparisonError["code"] = "audio_prompt_comparison_mismatch",
): asserts condition {
  if (!condition) throw new AudioPromptComparisonError(code);
}
function object(value: unknown): Record<string, unknown> {
  check(value !== null && typeof value === "object" && !Array.isArray(value));
  return value as Record<string, unknown>;
}
function exactKeys(value: Record<string, unknown>, keys: string[]) {
  check(Object.keys(value).sort().join(",") === keys.sort().join(","));
}

export function promptComparisonRequested(
  body: Record<string, unknown>,
  scanId: string,
): boolean {
  return Object.hasOwn(body, "audio_prompt_comparison") ||
    (scanId.startsWith(SCAN_PREFIX) && scanId[14] === "8");
}

/** Fixed across activations of this plan; never use a fresh UUID to retry a slot. */
export async function audioPromptComparisonScanId(
  slot: number,
): Promise<string> {
  check(Number.isInteger(slot) && slot >= 1 && slot <= 36);
  const id = await deriveAIRequestId(
    "ac0b0001-0000-8000-8000-000000000001",
    `${AUDIO_PROMPT_COMPARISON_PLAN_SHA256}:${slot}`,
  );
  return SCAN_PREFIX + id.slice(SCAN_PREFIX.length);
}

/** Before any recovery, replay lookup, media resolution or quota side effect.
 * An absent/malformed config affects only marked or reserved-ID requests.
 */
export async function resolveAudioPromptComparison(input: {
  body: Record<string, unknown>;
  scanId: string;
  userId: string;
  internalReplayAttempt?: number;
  configuration?: string;
  now?: number;
}): Promise<AudioPromptComparison | null> {
  const { body, scanId, userId } = input;
  if (!promptComparisonRequested(body, scanId)) return null;
  check(
    input.internalReplayAttempt == null,
    "audio_prompt_comparison_excluded",
  );
  let config: Record<string, unknown>;
  try {
    check(input.configuration && input.configuration.length <= 1024);
    config = object(JSON.parse(input.configuration));
    exactKeys(config, [
      "version",
      "block",
      "ownerId",
      "startsAt",
      "expiresAt",
      "planSha256",
      "backendBundleSha256",
    ]);
    check(
      config.version === 1 && [1, 2, 3].includes(Number(config.block)) &&
        typeof config.block === "number" &&
        config.planSha256 === AUDIO_PROMPT_COMPARISON_PLAN_SHA256,
    );
    check(config.backendBundleSha256 === IDENTIFICATION_BUNDLE_SHA256);
    check(
      typeof config.ownerId === "string" && UUID.test(config.ownerId) &&
        config.ownerId === userId,
    );
    const instant = (value: unknown) => {
      check(
        typeof value === "string" &&
          /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(value),
      );
      const date = Date.parse(value);
      check(Number.isFinite(date) && new Date(date).toISOString() === value);
      return date;
    };
    const start = instant(config.startsAt), end = instant(config.expiresAt);
    const now = input.now ?? Date.now();
    // The fixed lifetime is < quota's 30-day retention. Re-enabling cannot
    // resurrect a pruned reservation or reset an assignment's attempt count.
    check(
      start >= WINDOW_START && end <= RETENTION_END && end > start &&
        end - start <= 7_200_000 &&
        RETENTION_END - WINDOW_START < 30 * 86_400_000,
    );
    check(now >= start && now < end);
  } catch {
    throw new AudioPromptComparisonError("audio_prompt_comparison_unavailable");
  }
  const handle = object(body.audio_prompt_comparison);
  exactKeys(handle, ["planSha256", "slot"]);
  check(handle.planSha256 === AUDIO_PROMPT_COMPARISON_PLAN_SHA256);
  const assignment = AUDIO_PROMPT_COMPARISON_PLAN.assignments.find((a) =>
    a.slot === handle.slot
  );
  check(
    assignment && assignment.block === config.block &&
      scanId === await audioPromptComparisonScanId(assignment.slot),
  );
  exactKeys(body, [
    "user_id",
    "client_scan_id",
    "geoprivacy",
    "mimeType",
    "deviceLocale",
    "deviceTimeZone",
    "currentMonth",
    "timeOfDay",
    "audioBase64s",
    "audioMediaItems",
    "ownerMediaTimeline",
    "audio_prompt_comparison",
  ]);
  check(body.user_id === userId && body.client_scan_id === scanId);
  check(
    body.deviceLocale === "en" && body.deviceTimeZone === "UTC" &&
      body.currentMonth === 1 && body.timeOfDay === "12:00 PM",
  );
  check(
    body.mimeType === "image/webp" && typeof body.geoprivacy === "string" &&
      ["private", "obscured", "open"].includes(String(body.geoprivacy)),
  );
  check(
    Array.isArray(body.audioBase64s) && body.audioBase64s.length === 1 &&
      typeof body.audioBase64s[0] === "string" &&
      body.audioBase64s[0].length > 0,
  );
  check(
    await fingerprintJson(body.audioMediaItems) ===
      await fingerprintJson([{ kind: "audio", sourceIndex: 0 }]),
  );
  check(
    await fingerprintJson(body.ownerMediaTimeline) ===
      await fingerprintJson([{
        kind: "audio",
        sourceIndex: 0,
        audioInputIndex: 0,
      }]),
  );
  return { assignment, expiresAt: Date.parse(String(config.expiresAt)) };
}

/** Hash the actual source and current DSP output; both prompt arms share it. */
export async function processPromptComparisonAudio(
  comparison: AudioPromptComparison,
  buffer: ArrayBuffer,
): Promise<string> {
  const a = comparison.assignment, bytes = new Uint8Array(buffer);
  check(
    bytes.length === a.sourceByteLength &&
      await fingerprintBytes(bytes) === a.sourceWavSha256,
  );
  const processed = decodeBase64(
    processMultimodalWAV(buffer, { kind: "audio", sourceIndex: 0 }, {
      present: true,
      error: null,
      timeline: [{ kind: "audio", sourceIndex: 0, audioInputIndex: 0 }],
    }),
  );
  check(await fingerprintBytes(processed) === a.processedWavSha256);
  return encodeBase64(processed);
}

export function requirePromptComparisonReservation(
  comparison: AudioPromptComparison,
  reservation:
    & Pick<AIQuotaReservation, "attemptCount" | "model" | "flashFallbackUsed">
    & {
      tier: Pick<AIQuotaReservation["tier"], "effective_tier">;
    },
  now = Date.now(),
): void {
  check(now < comparison.expiresAt, "audio_prompt_comparison_unavailable");
  check(reservation.attemptCount === 1, "audio_prompt_comparison_excluded");
  check(
    reservation.model === "gemini-2.5-pro" &&
      reservation.tier.effective_tier === "pro" &&
      !reservation.flashFallbackUsed,
  );
}

/** The same production builders used by the actual prepared Gemini execution.
 * Validate settings as well as media before commitment, without retaining bodies.
 */
export async function verifyPromptComparisonExecution(
  comparison: AudioPromptComparison,
  request: AIRequest,
  snapshot: AIAttemptSnapshot,
): Promise<void> {
  const a = comparison.assignment;
  check(request.task === "identify" && request.variant === "multimodal");
  check(
    await fingerprintJson(buildGeminiRequestParameters(request, snapshot)) ===
      a.providerRequestSha256,
  );
  check(await fingerprintJson(snapshot) === a.policySha256);
  check(
    await fingerprintJson({
      possible: PRO_POSSIBLE,
      strong: PRO_STRONG,
      diagnostic: PRO_DIAGNOSTIC_TRIGGER,
    }) === a.confidenceSha256,
  );
}

/** Only the final fresh durable-success branch may expose this receipt.
 * Proof of server processing/persistence; not UI display or formal qualification.
 */
export function audioPromptComparisonReceipt(
  comparison: AudioPromptComparison,
): string {
  const a = comparison.assignment;
  return JSON.stringify({
    version: 1,
    planSha256: AUDIO_PROMPT_COMPARISON_PLAN_SHA256,
    slot: a.slot,
    block: a.block,
    repeat: a.repeat,
    caseId: a.caseId,
    arm: a.arm,
    sourceWavSha256: a.sourceWavSha256,
    processedWavSha256: a.processedWavSha256,
    providerRequestSha256: a.providerRequestSha256,
    policySha256: a.policySha256,
    confidenceSha256: a.confidenceSha256,
  });
}
