/** Dormant preparation receipts. No live route imports this module. */
import {
  initialCanonicalText,
  invalidInitialInput,
  parseInitialCanonicalText,
} from "./canonical.ts";
import { matchesInitialSchema } from "./schema.ts";
import { validateInitialMediaAssignment } from "./mediaAssignment.ts";
import { initialPreparationDigest } from "./preparationCandidate.ts";
import {
  assertInitialMediaProfileMatches,
  initialMediaContractDigest,
  type InitialMediaPreparationProfile,
  type InitialSourceRole,
} from "./mediaPreparationProfile.ts";
import type { InitialMediaSourcePlan } from "./mediaSourceSemantics.ts";
import schema from "./preparation-execution-schema-v1.json" with {
  type: "json",
};

export interface PreparationTuple {
  byte_count: number;
  sha256: string;
  content_type: string;
}
export interface PreparationFacts {
  image: { width: number; height: number; format: string } | null;
  wav: {
    format: "pcm16" | "float32";
    sample_rate: number;
    channels: number;
    frames: number;
  } | null;
  mp4: { structure: "bounded_mp4_accepted" } | null;
}
export interface ExecutionIdentity {
  version: 1;
  scan_id: string;
  assignment_digest: string;
}
export interface PreparationSourceReceipt extends ExecutionIdentity {
  profile_digest: string;
  backend_generation: string;
  validator_identity: string;
  entries: {
    ordinal: number;
    object_id: string;
    bytes: PreparationTuple;
    facts: PreparationFacts;
  }[];
}
export interface PreparationOutputReceipt extends ExecutionIdentity {
  grant_id: string;
  source_digest: string;
  entries: {
    ordinal: number;
    prepared: {
      bytes: PreparationTuple;
      transform: string;
      parameters:
        InitialMediaSourcePlan["sources"][number]["transform_parameters"];
      source_identity: boolean;
    } | null;
  }[];
}
export interface PreparationResolvedManifest extends ExecutionIdentity {
  grant_id: string;
  request_digest: string;
  entries: { ordinal: number; object_id: string | null }[];
}
export interface PreparationGrant extends ExecutionIdentity {
  grant_id: string;
  source_digest: string;
  profile_digest: string;
  artifact_digest: string;
  issued_at_ms: number;
  execution_deadline_ms: number;
  registration_deadline_ms: number;
  outcome_deadline_ms: number;
}
export interface PreparationOutcome extends ExecutionIdentity {
  grant: PreparationGrant;
  source_verification: PreparationSourceReceipt;
  output_manifest: PreparationOutputReceipt;
  resolved_manifest: PreparationResolvedManifest;
  profile: InitialMediaPreparationProfile;
  retained: { ordinal: number; object_id: string; bytes: PreparationTuple }[];
}
export interface PreparationContext extends ExecutionIdentity {
  candidate: { source_plan: InitialMediaSourcePlan };
  assignment: {
    preparation: {
      profile_digest: string;
      backend_generation: string;
      source_mapping: {
        ordinal: number;
        source: InitialMediaSourcePlan["sources"][number];
        role: InitialSourceRole;
        object_id: string;
      }[];
    };
  };
  profile: InitialMediaPreparationProfile;
}
export type PreparationReceiptKind =
  | "source_verification"
  | "output_manifest"
  | "outcome";
export function executionCanonical(
  kind: keyof typeof schema,
  value: unknown,
): string {
  const text = initialCanonicalText(value);
  if (
    new TextEncoder().encode(text).length > 131072 ||
    !matchesInitialSchema(parseInitialCanonicalText(text), schema[kind])
  ) return invalidInitialInput();
  return text;
}
export async function executionDigest(
  kind: PreparationReceiptKind,
  text: string,
): Promise<string> {
  parseInitialCanonicalText(text);
  const bytes = new TextEncoder().encode(
    `merian.initial-analysis.preparation-execution.${kind}.v1\n${text}`,
  );
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map(
    (b) => b.toString(16).padStart(2, "0"),
  ).join("");
}
export function sameExecutionValue(a: unknown, b: unknown): boolean {
  return initialCanonicalText(a) === initialCanonicalText(b);
}
function identity(ctx: ExecutionIdentity, v: ExecutionIdentity): void {
  if (
    v.version !== 1 || v.scan_id !== ctx.scan_id ||
    v.assignment_digest !== ctx.assignment_digest
  ) invalidInitialInput();
}
export async function preparationContext(
  scan: string,
  candidate: unknown,
  assignment: unknown,
  profile: unknown,
): Promise<PreparationContext> {
  // Validate/snapshot each independently bounded component before any await.
  // Context is an internal container, not another canonical wire document.
  const snapshot = {
    candidate: JSON.parse(initialCanonicalText(candidate)),
    assignment: JSON.parse(initialCanonicalText(assignment)),
    profile: JSON.parse(initialCanonicalText(profile)),
  };
  candidate = snapshot.candidate;
  assignment = snapshot.assignment;
  profile = snapshot.profile;
  const a = await validateInitialMediaAssignment(candidate, assignment);
  await assertInitialMediaProfileMatches(candidate, profile);
  const saved = JSON.parse(a) as PreparationContext["assignment"];
  if (
    saved.preparation.profile_digest !==
      await initialMediaContractDigest(
        "profile",
        initialCanonicalText(profile),
      ) ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(scan)
  ) invalidInitialInput();
  return {
    version: 1,
    scan_id: scan,
    assignment_digest: await initialPreparationDigest("assignment", a),
    candidate: snapshot.candidate,
    assignment: saved,
    profile: snapshot.profile,
  };
}
export function validateSourceReceipt(
  ctx: PreparationContext,
  value: unknown,
): string {
  const text = executionCanonical("source_verification", value),
    v = JSON.parse(text) as PreparationSourceReceipt,
    p = ctx.assignment.preparation;
  identity(ctx, v);
  if (
    v.profile_digest !== p.profile_digest ||
    v.backend_generation !== p.backend_generation ||
    v.validator_identity !== ctx.profile.spec.identities.validator ||
    v.entries.length !== p.source_mapping.length
  ) invalidInitialInput();
  for (const [i, e] of v.entries.entries()) {
    const m = p.source_mapping[i], s = m.source, f = e.facts;
    if (
      e.ordinal !== i || e.object_id !== m.object_id ||
      !sameExecutionValue(e.bytes, {
        byte_count: s.source_byte_count,
        sha256: s.source_sha256,
        content_type: s.source_content_type,
      })
    ) invalidInitialInput();
    if (s.kind === "image") {
      if (
        f.image === null || f.wav !== null || f.mp4 !== null ||
        `image/${f.image.format}` !== s.source_content_type
      ) invalidInitialInput();
    } else if (s.kind === "audio") {
      if (
        f.image !== null || f.wav === null || f.mp4 !== null ||
        f.wav.frames * f.wav.channels * (f.wav.format === "pcm16" ? 2 : 4) >
          s.source_byte_count
      ) invalidInitialInput();
    } else if (f.image !== null || f.wav !== null || f.mp4 === null) {
      invalidInitialInput();
    }
  }
  return text;
}
/** Sum the frozen per-role caps for the actual ordered cohort. */
export function preparationWallMs(ctx: PreparationContext): number {
  const wall = ctx.assignment.preparation.source_mapping.reduce(
    (sum, entry) => {
      const rule = ctx.profile.spec.rules.find((r) => r.role === entry.role);
      if (!rule) return invalidInitialInput();
      return sum + rule.limits.wall_ms;
    },
    0,
  );
  if (
    !Number.isSafeInteger(wall) || wall <= 0 ||
    wall > ctx.profile.spec.limits.wall_ms
  ) invalidInitialInput();
  return wall;
}
export function preparationReference(g: PreparationGrant) {
  return { grant_id: g.grant_id, source_digest: g.source_digest };
}
export function validateGrant(
  ctx: PreparationContext,
  sourceDigest: string,
  value: unknown,
): string {
  const text = executionCanonical("grant", value),
    g = JSON.parse(text) as PreparationGrant;
  identity(ctx, g);
  const wall = preparationWallMs(ctx);
  if (
    g.source_digest !== sourceDigest ||
    g.profile_digest !== ctx.assignment.preparation.profile_digest ||
    g.artifact_digest !== ctx.profile.spec.artifact.sha256 ||
    g.execution_deadline_ms !== g.issued_at_ms + 5000 + wall ||
    g.registration_deadline_ms !== g.execution_deadline_ms + 5000 ||
    g.outcome_deadline_ms !== g.registration_deadline_ms + 35000
  ) invalidInitialInput();
  return text;
}
export function validateOutputReceipt(
  ctx: PreparationContext,
  grant: PreparationGrant,
  value: unknown,
): string {
  const text = executionCanonical("output_manifest", value),
    v = JSON.parse(text) as PreparationOutputReceipt,
    mapping = ctx.assignment.preparation.source_mapping;
  identity(ctx, v);
  if (
    v.grant_id !== grant.grant_id || v.source_digest !== grant.source_digest ||
    v.entries.length !== mapping.length
  ) invalidInitialInput();
  let total = 0;
  for (const [i, e] of v.entries.entries()) {
    const m = mapping[i], s = m.source, p = e.prepared;
    if (e.ordinal !== i || (m.role === "raw_video") !== (p === null)) {
      invalidInitialInput();
    }
    if (p === null) continue;
    const rule = ctx.profile.spec.rules.find((r) => r.role === m.role)!;
    if (
      p.transform !== s.transform ||
      !sameExecutionValue(p.parameters, s.transform_parameters) ||
      p.bytes.byte_count > rule.limits.output_bytes ||
      p.bytes.content_type !==
        (s.kind === "audio" ? "audio/wav" : s.source_content_type)
    ) invalidInitialInput();
    const original = {
      byte_count: s.source_byte_count,
      sha256: s.source_sha256,
      content_type: s.source_content_type,
    };
    if (p.source_identity && !sameExecutionValue(p.bytes, original)) {
      invalidInitialInput();
    }
    // Identity and preselected video frames are byte-preserving in this contract.
    if (
      s.kind === "image" &&
      (!p.source_identity || !sameExecutionValue(p.bytes, original))
    ) invalidInitialInput();
    total += p.bytes.byte_count;
  }
  if (total > ctx.profile.spec.limits.output_bytes) invalidInitialInput();
  return text;
}
export async function validateResolvedManifest(
  ctx: PreparationContext,
  output: PreparationOutputReceipt,
  value: unknown,
): Promise<string> {
  const text = executionCanonical("resolved_manifest", value),
    v = JSON.parse(text) as PreparationResolvedManifest;
  identity(ctx, v);
  if (
    v.grant_id !== output.grant_id ||
    v.request_digest !==
      await executionDigest(
        "output_manifest",
        executionCanonical("output_manifest", output),
      ) ||
    v.entries.length !== output.entries.length
  ) invalidInitialInput();
  const seen = new Set<string>(),
    sources = new Set(
      ctx.assignment.preparation.source_mapping.map((m) => m.object_id),
    );
  for (const [i, e] of v.entries.entries()) {
    const p = output.entries[i].prepared;
    if (e.ordinal !== i || (e.object_id === null) !== (p === null)) {
      invalidInitialInput();
    }
    if (e.object_id === null || p === null) continue;
    if (
      seen.has(e.object_id) ||
      (p.source_identity
        ? e.object_id !== ctx.assignment.preparation.source_mapping[i].object_id
        : sources.has(e.object_id))
    ) invalidInitialInput();
    seen.add(e.object_id);
  }
  return text;
}
export async function validatePreparationOutcome(
  ctx: PreparationContext,
  value: unknown,
): Promise<string> {
  const text = executionCanonical("outcome", value),
    v = JSON.parse(text) as PreparationOutcome;
  identity(ctx, v);
  const sourceText = validateSourceReceipt(ctx, v.source_verification);
  validateGrant(
    ctx,
    await executionDigest("source_verification", sourceText),
    v.grant,
  );
  validateOutputReceipt(ctx, v.grant, v.output_manifest);
  await validateResolvedManifest(ctx, v.output_manifest, v.resolved_manifest);
  if (!sameExecutionValue(v.profile, ctx.profile)) invalidInitialInput();
  const expected = v.output_manifest.entries.flatMap((e, i) =>
    e.prepared === null ? [] : [{
      ordinal: i,
      object_id: v.resolved_manifest.entries[i].object_id,
      bytes: e.prepared.bytes,
    }]
  );
  if (!sameExecutionValue(v.retained, expected)) invalidInitialInput();
  return text;
}

/** Closed reply envelopes share their schema with the SQL constructors. */
export function validatePreparationReply(
  value: unknown,
): Record<string, unknown> {
  const text = initialCanonicalText(value);
  const v = JSON.parse(text);
  const shapes: Record<string, keyof typeof schema> = {
    held: "reply_held",
    status: "reply_status",
    verified: "reply_verified",
    granted: "reply_granted",
    registered: "reply_registered",
    outcome_ready: "reply_outcome_ready",
  };
  if (
    !v || typeof v !== "object" || Array.isArray(v) ||
    !Object.hasOwn(shapes, v.outcome) ||
    new TextEncoder().encode(text).length > 524288 ||
    !matchesInitialSchema(v, schema[shapes[v.outcome]])
  ) invalidInitialInput();
  if (v.outcome === "status") {
    const phase = [
      "allocated",
      "verified",
      "issued",
      "output_registered",
      "outcome_ready",
    ].indexOf(v.phase);
    if (
      (v.source !== null) !== (phase >= 1) ||
      (v.execution_reference !== null) !== (phase >= 2) ||
      (v.output !== null) !== (phase >= 3) ||
      (v.result !== null) !== (phase >= 4)
    ) invalidInitialInput();
  }
  return v;
}
