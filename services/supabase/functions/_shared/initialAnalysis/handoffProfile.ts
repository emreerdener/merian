/** Pure metadata validation. No catalog, installation, eligibility or authority. */
import {
  initialCanonicalText,
  invalidInitialInput,
  parseInitialCanonicalText,
} from "./canonical.ts";
import { matchesInitialSchema } from "./schema.ts";
import schema from "./handoff-profile-schema-v1.json" with { type: "json" };

export const HANDOFF_PHASES = [
  "admission",
  "copy",
  "verification_claim",
  "verification",
  "verification_settlement",
  "transfer",
  "reconciliation",
  "protocol_margin",
] as const;
export type HandoffPhase = typeof HANDOFF_PHASES[number];
export interface InitialHandoffProfile {
  version: 1;
  generation: string;
  source_backend_generation: string;
  source_backend_config_digest: string;
  destination_backend_generation: string;
  destination_backend_config_digest: string;
  protocol_artifact_digest: string;
  copy_adapter_digest: string;
  verification_adapter_digest: string;
  cohort_limits: {
    max_ordinals: number;
    max_unique_objects: number;
    max_unique_bytes: number;
    content_type_pairs: {
      kind: "image" | "audio" | "video";
      source_content_type: string;
      prepared_content_type: string | null;
    }[];
    alias_policy: "same_ordinal_exact_bytes_only";
    video_policy: "source_only";
  };
  phase_ms: Record<HandoffPhase, number>;
  total_ms: number;
  execution_model: "sequential_whole_cohort";
}

export async function initialHandoffDigest(
  domain: "protocol_artifact" | "profile",
  canonical: string,
): Promise<string> {
  // Never hash a noncanonical spelling or accept a caller-chosen digest domain.
  if (domain !== "protocol_artifact" && domain !== "profile") {
    invalidInitialInput();
  }
  parseInitialCanonicalText(canonical);
  const bytes = new TextEncoder().encode(
    `merian.initial-analysis.handoff.${domain}.v1\n${canonical}`,
  );
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))]
    .map((b) => b.toString(16).padStart(2, "0")).join("");
}

function canonicalShape(kind: keyof typeof schema, value: unknown): string {
  const canonical = initialCanonicalText(value);
  if (
    new TextEncoder().encode(canonical).length > 16384 ||
    !matchesInitialSchema(parseInitialCanonicalText(canonical), schema[kind])
  ) invalidInitialInput();
  return canonical;
}

/** A digest binds component identities; this does not verify installed bytes. */
export function validateInitialHandoffProtocol(value: unknown): string {
  return canonicalShape("protocol_artifact", value);
}

/** Closed whole-cohort bounds, not proof that any adapter meets those bounds. */
export async function validateInitialHandoffProfile(
  value: unknown,
  protocolArtifact: unknown,
): Promise<string> {
  const protocol = validateInitialHandoffProtocol(protocolArtifact);
  const canonical = canonicalShape("profile", value);
  const p = JSON.parse(canonical) as InitialHandoffProfile;
  const pairs = p.cohort_limits.content_type_pairs;
  if (
    p.protocol_artifact_digest !==
      await initialHandoffDigest("protocol_artifact", protocol) ||
    HANDOFF_PHASES.reduce((sum, phase) => sum + p.phase_ms[phase], 0) !==
      p.total_ms ||
    pairs.length === 0 ||
    p.cohort_limits.max_unique_objects < p.cohort_limits.max_ordinals ||
    new Set(pairs.map((pair) => initialCanonicalText(pair))).size !==
      pairs.length
  ) invalidInitialInput();
  for (const pair of pairs) {
    const source = pair.source_content_type,
      prepared = pair.prepared_content_type;
    const valid = pair.kind === "video"
      ? source === "video/mp4" && prepared === null
      : pair.kind === "audio"
      ? source === "audio/wav" && prepared === "audio/wav"
      : ["image/jpeg", "image/png", "image/webp", "image/heic", "image/heif"]
        .includes(source) && prepared === source;
    if (!valid) invalidInitialInput();
  }
  return canonical;
}

function timeWindow(nowMs: number, expiresAtMs: number): void {
  if (
    !Number.isSafeInteger(nowMs) || !Number.isSafeInteger(expiresAtMs) ||
    nowMs < 0 || Object.is(nowMs, -0) || expiresAtMs <= nowMs ||
    expiresAtMs - nowMs > 300000
  ) invalidInitialInput();
}
function budgetUnavailable(): never {
  throw new Error("initial_analysis_handoff_budget_unavailable");
}

/** Arithmetic only; callers still need original SQL identity/eligibility locks. */
export async function assertInitialHandoffIssueBudget(
  profile: unknown,
  protocolArtifact: unknown,
  nowMs: number,
  expiresAtMs: number,
  preparationWallMs: number,
): Promise<void> {
  const p = JSON.parse(
    await validateInitialHandoffProfile(profile, protocolArtifact),
  ) as InitialHandoffProfile;
  timeWindow(nowMs, expiresAtMs);
  if (
    !Number.isSafeInteger(preparationWallMs) || preparationWallMs <= 0 ||
    preparationWallMs > 300000
  ) invalidInitialInput();
  // Subtract first: epoch addition near MAX_SAFE_INTEGER must not lose a ms.
  if (45000 + preparationWallMs + p.total_ms >= expiresAtMs - nowMs) {
    budgetUnavailable();
  }
}

/** Fixed cumulative cutoffs, without renewing the original five-minute expiry. */
export async function initialHandoffPhaseCutoffs(
  profile: unknown,
  protocolArtifact: unknown,
  anchorMs: number,
  expiresAtMs: number,
): Promise<Record<HandoffPhase, number>> {
  const p = JSON.parse(
    await validateInitialHandoffProfile(profile, protocolArtifact),
  ) as InitialHandoffProfile;
  timeWindow(anchorMs, expiresAtMs);
  if (p.total_ms >= expiresAtMs - anchorMs) budgetUnavailable();
  let cutoff = anchorMs;
  const entries = HANDOFF_PHASES.map((phase) => {
    cutoff += p.phase_ms[phase];
    return [phase, cutoff] as const;
  });
  return Object.fromEntries(entries) as Record<HandoffPhase, number>;
}
