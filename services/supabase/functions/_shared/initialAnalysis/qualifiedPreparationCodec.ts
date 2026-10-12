/** Inactive qualified codecs. No resolver, issuance, funding or I/O authority. */
import {
  initialCanonicalText,
  invalidInitialInput,
  parseInitialCanonicalText,
} from "./canonical.ts";
import { type InitialSchemaRule, matchesInitialSchema } from "./schema.ts";
import { validateInitialMediaAssignment } from "./mediaAssignment.ts";
import { initialPreparationDigest } from "./preparationCandidate.ts";
import { assertInitialMediaProfileMatches } from "./mediaPreparationProfile.ts";
import {
  initialHandoffCatalogDigest,
  validateInitialHandoffInstallation,
} from "./handoffCatalog.ts";
import type { InitialHandoffProfile } from "./handoffProfile.ts";
import {
  executionDigest,
  type PreparationContext,
  preparationContext,
  type PreparationGrant,
  preparationWallMs,
  validateGrant,
  validatePreparationOutcome,
  validatePreparationReply,
  validateSourceReceipt,
} from "./preparationExecutionContract.ts";
import assignmentSchema from "./media-assignment-schema-v3.json" with {
  type: "json",
};
import responseSchema from "./media-preparation-response-schema-v3.json" with {
  type: "json",
};
import executionSchema from "./preparation-execution-schema-v2.json" with {
  type: "json",
};

export interface QualifiedCatalogContext {
  installation: unknown;
  protocol: unknown;
  preparation: unknown;
  destination: unknown;
}
export interface QualifiedPreparationContext {
  /** V1 nested receipt identity, carrying the ORIGINAL v3 assignment digest. */
  receipts: PreparationContext;
  handoff: InitialHandoffProfile;
  handoffProfileDigest: string;
  handoffInstallationDigest: string;
  /** Trusted original server expiry context; no clock or authority is inferred. */
  originalExpiresAtMs: number;
}
export interface QualifiedPreparationGrant
  extends Omit<PreparationGrant, "version"> {
  version: 2;
  handoff_profile_digest: string;
  handoff_installation_digest: string;
  protocol_artifact_digest: string;
  handoff_total_ms: number;
  preparation_expires_at_ms: number;
  preparation_wall_ms: number;
}
function shape(value: unknown, schema: InitialSchemaRule, max: number): string {
  const text = initialCanonicalText(value);
  if (
    new TextEncoder().encode(text).length > max ||
    !matchesInitialSchema(parseInitialCanonicalText(text), schema)
  ) invalidInitialInput();
  return text;
}
function legacyAssignment(value: unknown): unknown {
  const a = JSON.parse(initialCanonicalText(value));
  delete a.handoff;
  a.version = 2;
  return a;
}
/** Internal validation projection only; never returned as an original receipt. */
function legacyGrant(value: QualifiedPreparationGrant): PreparationGrant {
  const g = JSON.parse(initialCanonicalText(value));
  for (
    const k of [
      "handoff_profile_digest",
      "handoff_installation_digest",
      "protocol_artifact_digest",
      "handoff_total_ms",
      "preparation_expires_at_ms",
      "preparation_wall_ms",
    ]
  ) delete g[k];
  g.version = 1;
  return g;
}
function legacyOutcome(value: unknown): unknown {
  const o = JSON.parse(initialCanonicalText(value));
  o.version = 1;
  o.grant = legacyGrant(o.grant);
  return o;
}
export async function validateQualifiedMediaAssignment(
  candidate: unknown,
  assignment: unknown,
  catalog: QualifiedCatalogContext,
): Promise<string> {
  const snapshot = JSON.parse(
    initialCanonicalText({ candidate, assignment, catalog }),
  );
  candidate = snapshot.candidate;
  assignment = snapshot.assignment;
  catalog = snapshot.catalog;
  const text = shape(assignment, assignmentSchema, 65536), a = JSON.parse(text);
  await validateInitialMediaAssignment(candidate, legacyAssignment(a));
  const installation = await validateInitialHandoffInstallation(
    catalog.installation,
    a.handoff.profile,
    catalog.protocol,
    catalog.preparation,
    catalog.destination,
  );
  const i = JSON.parse(installation);
  if (
    a.handoff.profile_digest !== i.profile_digest ||
    a.handoff.installation_digest !==
      await initialHandoffCatalogDigest("installation", installation) ||
    a.preparation.profile_digest !== i.preparation_profile_digest ||
    a.preparation.backend_generation !== i.source_backend_generation
  ) invalidInitialInput();
  await assertInitialMediaProfileMatches(candidate, catalog.preparation);
  return text;
}
export async function qualifiedPreparationContext(
  scan: string,
  candidate: unknown,
  assignment: unknown,
  catalog: QualifiedCatalogContext,
  originalExpiresAtMs: number,
): Promise<QualifiedPreparationContext> {
  // Snapshot all caller data before the first asynchronous validation.
  const snapshot = JSON.parse(
    initialCanonicalText({ candidate, assignment, catalog }),
  );
  const text = await validateQualifiedMediaAssignment(
    snapshot.candidate,
    snapshot.assignment,
    snapshot.catalog,
  );
  if (
    !Number.isSafeInteger(originalExpiresAtMs) || originalExpiresAtMs < 300000
  ) invalidInitialInput();
  const a = JSON.parse(text);
  const receipts = await preparationContext(
    scan,
    snapshot.candidate,
    legacyAssignment(a),
    snapshot.catalog.preparation,
  );
  receipts.assignment_digest = await initialPreparationDigest(
    "assignment",
    text,
  );
  return {
    receipts,
    handoff: a.handoff.profile,
    handoffProfileDigest: a.handoff.profile_digest,
    handoffInstallationDigest: a.handoff.installation_digest,
    originalExpiresAtMs,
  };
}
export function qualifiedExecutionCanonical(
  kind: keyof typeof executionSchema,
  value: unknown,
): string {
  if (!Object.hasOwn(executionSchema, kind)) invalidInitialInput();
  return shape(
    value,
    executionSchema[kind],
    kind.startsWith("reply_") ? 524288 : 131072,
  );
}
export async function qualifiedOutcomeDigest(text: string): Promise<string> {
  const value = parseInitialCanonicalText(text);
  qualifiedExecutionCanonical("outcome", value);
  const bytes = new TextEncoder().encode(
    `merian.initial-analysis.preparation-execution.outcome.v2\n${text}`,
  );
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map(
    (x) => x.toString(16).padStart(2, "0"),
  ).join("");
}
export function validateQualifiedGrant(
  ctx: QualifiedPreparationContext,
  sourceDigest: string,
  value: unknown,
): string {
  const text = qualifiedExecutionCanonical("grant", value),
    g = JSON.parse(text) as QualifiedPreparationGrant;
  validateGrant(ctx.receipts, sourceDigest, legacyGrant(g));
  const wall = preparationWallMs(ctx.receipts),
    end = g.issued_at_ms + 45000 + wall + ctx.handoff.total_ms;
  if (
    g.handoff_profile_digest !== ctx.handoffProfileDigest ||
    g.handoff_installation_digest !== ctx.handoffInstallationDigest ||
    g.protocol_artifact_digest !== ctx.handoff.protocol_artifact_digest ||
    g.handoff_total_ms !== ctx.handoff.total_ms ||
    g.preparation_wall_ms !== wall ||
    g.preparation_expires_at_ms !== ctx.originalExpiresAtMs ||
    g.issued_at_ms < ctx.originalExpiresAtMs - 300000 ||
    !Number.isSafeInteger(end) || end >= ctx.originalExpiresAtMs
  ) invalidInitialInput();
  return text;
}
export async function validateQualifiedOutcome(
  ctx: QualifiedPreparationContext,
  value: unknown,
): Promise<string> {
  ctx = structuredClone(ctx);
  const text = qualifiedExecutionCanonical("outcome", value),
    o = JSON.parse(text);
  const source = validateSourceReceipt(ctx.receipts, o.source_verification);
  validateQualifiedGrant(
    ctx,
    await executionDigest("source_verification", source),
    o.grant,
  );
  await validatePreparationOutcome(ctx.receipts, legacyOutcome(o));
  return text;
}
export async function validateQualifiedAllocation(
  candidate: unknown,
  response: unknown,
  catalog: QualifiedCatalogContext,
): Promise<string> {
  const text = initialCanonicalText(response),
    v = parseInitialCanonicalText(text) as Record<string, unknown>;
  if (!v || typeof v !== "object" || Array.isArray(v)) invalidInitialInput();
  shape(
    v,
    v.outcome === "expired" ? responseSchema.expired : responseSchema.allocated,
    131072,
  );
  if (v.outcome === "expired") return text;
  const a = await validateQualifiedMediaAssignment(
    candidate,
    v.assignment,
    catalog,
  );
  if (
    v.candidate_digest !== JSON.parse(a).candidate_digest ||
    v.assignment_digest !== await initialPreparationDigest("assignment", a) ||
    !Number.isFinite(Date.parse(String(v.expires_at)))
  ) invalidInitialInput();
  return text;
}
/** Shape/phase decoder only, like the existing v1 decoder; no receipt authority. */
export function validateQualifiedReply(
  value: unknown,
): Record<string, unknown> {
  const text = initialCanonicalText(value), v = JSON.parse(text);
  const shapes = {
    held: "reply_held",
    status: "reply_status",
    verified: "reply_verified",
    granted: "reply_granted",
    registered: "reply_registered",
    outcome_ready: "reply_outcome_ready",
  } as const;
  if (
    !v || typeof v !== "object" || Array.isArray(v) ||
    !Object.hasOwn(shapes, v.outcome)
  ) invalidInitialInput();
  qualifiedExecutionCanonical(shapes[v.outcome as keyof typeof shapes], v);
  if (v.outcome !== "held") {
    const projection = JSON.parse(text);
    projection.version = 1;
    if (projection.grant) projection.grant = legacyGrant(projection.grant);
    if (projection.result) projection.result = legacyOutcome(projection.result);
    validatePreparationReply(projection);
  }
  return v;
}
