/** Pure handoff metadata. No admission receipt, funding, registry or I/O authority. */
import {
  hex,
  initialCanonicalText,
  initialDigest,
  invalidInitialInput,
  parseInitialCanonicalText,
} from "./canonical.ts";
import {
  type InitialSchemaRule,
  matchesInitialSchema,
  validateInitialInput,
} from "./schema.ts";
import {
  type HandoffPhase,
  initialHandoffPhaseCutoffs,
} from "./handoffProfile.ts";
import {
  type PreparationOutcome,
  type PreparationTuple,
} from "./preparationExecutionContract.ts";
import {
  type QualifiedCatalogContext,
  qualifiedOutcomeDigest,
  qualifiedPreparationContext,
  validateQualifiedOutcome,
} from "./qualifiedPreparationCodec.ts";
import schema from "./admission-metadata-schema-v1.json" with { type: "json" };

export interface AdmissionMetadataScope {
  owner_id: string;
  scan_id: string;
  admission_receipt_id: string;
}
export interface AdmissionPhaseWindow extends AdmissionMetadataScope {
  version: 1;
  handoff_profile_digest: string;
  handoff_installation_digest: string;
  protocol_artifact_digest: string;
  anchor_ms: number;
  original_expires_at_ms: number;
  cutoffs: Record<HandoffPhase, number>;
}
export interface AdmissionMappingRole {
  original_object_id: string;
  destination_object_id: string;
  bytes: PreparationTuple;
}
export interface AdmissionDestinationMapping extends AdmissionMetadataScope {
  version: 2;
  assignment_digest: string;
  outcome_digest: string;
  source_backend_generation: string;
  destination_backend_generation: string;
  items: {
    index: number;
    source: AdmissionMappingRole;
    prepared: AdmissionMappingRole | null;
  }[];
  objects: { object_id: string; bytes: PreparationTuple }[];
}
export interface AdmissionMediaBinding extends AdmissionMetadataScope {
  version: 2;
  submission_digest: string;
  assignment_digest: string;
  outcome_digest: string;
  mapping_digest: string;
  destination_backend_generation: string;
  phase_window: AdmissionPhaseWindow;
  phase_window_digest: string;
}
export interface AdmissionMetadataOriginal {
  candidate: unknown;
  assignment: unknown;
  catalog: QualifiedCatalogContext;
  outcome: unknown;
  originalExpiresAtMs: number;
}
export interface AdmissionMetadataValues {
  phase_window: unknown;
  mapping: unknown;
  media_binding: unknown;
}
export type AdmissionMetadataKind =
  | "phase_window"
  | "mapping"
  | "media_binding";
const limits = {
  scope: 512,
  phase_window: 4096,
  mapping: 65536,
  media_binding: 16384,
} as const;
function canonicalShape(kind: keyof typeof schema, value: unknown): string {
  if (!Object.hasOwn(schema, kind)) invalidInitialInput();
  const text = initialCanonicalText(value);
  if (
    new TextEncoder().encode(text).length > limits[kind] ||
    !matchesInitialSchema(
      parseInitialCanonicalText(text),
      schema[kind] as InitialSchemaRule,
    )
  ) invalidInitialInput();
  return text;
}
/** Shape validation precedes hashing. A digest is not a stored authorization. */
export async function admissionMetadataDigest(
  kind: AdmissionMetadataKind,
  text: string,
): Promise<string> {
  if (
    kind !== "phase_window" && kind !== "mapping" && kind !== "media_binding"
  ) invalidInitialInput();
  canonicalShape(kind, parseInitialCanonicalText(text));
  const version = kind === "phase_window" ? 1 : 2;
  return hex(
    new Uint8Array(
      await crypto.subtle.digest(
        "SHA-256",
        new TextEncoder().encode(
          `merian.initial-analysis.handoff.${kind}.v${version}\n${text}`,
        ),
      ),
    ),
  );
}
function same(a: unknown, b: unknown): boolean {
  return initialCanonicalText(a) === initialCanonicalText(b);
}
function assertScope(
  value: AdmissionMetadataScope,
  scope: AdmissionMetadataScope,
): void {
  if (
    value.owner_id !== scope.owner_id || value.scan_id !== scope.scan_id ||
    value.admission_receipt_id !== scope.admission_receipt_id
  ) invalidInitialInput();
}

/** Snapshots every caller object before any await; the returned strings are evidence
 * of metadata coherence only. No current selector, time, registry or byte read. */
export async function validateInitialAdmissionMetadata(
  original: AdmissionMetadataOriginal,
  scopeValue: AdmissionMetadataScope,
  values: AdmissionMetadataValues,
): Promise<{
  canonicalInput: string;
  submissionDigest: string;
  descriptionsDigest: string;
  canonicalPhaseWindow: string;
  phaseWindowDigest: string;
  canonicalMapping: string;
  mappingDigest: string;
  canonicalMediaBinding: string;
  mediaBindingDigest: string;
}> {
  const scope: AdmissionMetadataScope = JSON.parse(
    canonicalShape("scope", scopeValue),
  );
  // Separate snapshots retain each existing canonical resource ceiling. A large
  // combined wrapper would spuriously reject a valid maximum source topology.
  const candidate = JSON.parse(initialCanonicalText(original.candidate));
  const assignment = JSON.parse(initialCanonicalText(original.assignment));
  const outcome = JSON.parse(initialCanonicalText(original.outcome));
  const catalog: QualifiedCatalogContext = {
    installation: JSON.parse(
      initialCanonicalText(original.catalog.installation),
    ),
    protocol: JSON.parse(initialCanonicalText(original.catalog.protocol)),
    preparation: JSON.parse(initialCanonicalText(original.catalog.preparation)),
    destination: JSON.parse(initialCanonicalText(original.catalog.destination)),
  };
  const expiry = original.originalExpiresAtMs;
  const canonicalPhaseWindow = canonicalShape(
    "phase_window",
    values.phase_window,
  );
  const canonicalMapping = canonicalShape("mapping", values.mapping);
  const canonicalMediaBinding = canonicalShape(
    "media_binding",
    values.media_binding,
  );
  const window: AdmissionPhaseWindow = JSON.parse(canonicalPhaseWindow);
  const mapping: AdmissionDestinationMapping = JSON.parse(canonicalMapping);
  const binding: AdmissionMediaBinding = JSON.parse(canonicalMediaBinding);
  const ctx = await qualifiedPreparationContext(
    scope.scan_id,
    candidate,
    assignment,
    catalog,
    expiry,
  );
  const canonicalOutcome = await validateQualifiedOutcome(ctx, outcome);
  // Only nested v1 portions are used here; the qualified grant/outcome versions
  // were checked above, and are never relabeled or returned as legacy receipts.
  const proof = JSON.parse(canonicalOutcome) as Omit<
    PreparationOutcome,
    "version" | "grant"
  >;
  const outcomeDigest = await qualifiedOutcomeDigest(canonicalOutcome);
  for (const value of [window, mapping, binding]) assertScope(value, scope);
  if (
    window.handoff_profile_digest !== ctx.handoffProfileDigest ||
    window.handoff_installation_digest !== ctx.handoffInstallationDigest ||
    window.protocol_artifact_digest !== ctx.handoff.protocol_artifact_digest ||
    window.original_expires_at_ms !== expiry ||
    window.anchor_ms < outcome.grant.issued_at_ms
  ) invalidInitialInput();
  const cutoffs = await initialHandoffPhaseCutoffs(
    ctx.handoff,
    catalog.protocol,
    window.anchor_ms,
    expiry,
  );
  if (!same(window.cutoffs, cutoffs)) invalidInitialInput();

  // Preserve every nonmedia field and media index. The original closed parser
  // decides whether this exact source/output combination is a supported input.
  const { sources, ...input } = candidate.source_plan;
  const media = ctx.receipts.candidate.source_plan.sources.map(
    (source, index) => {
      const { prepared_output: _prepared, ...retained } = source;
      const bytes = proof.output_manifest.entries[index].prepared?.bytes ??
        proof.source_verification.entries[index].bytes;
      return {
        ...retained,
        content_type: bytes.content_type,
        byte_count: bytes.byte_count,
        sha256: bytes.sha256,
      };
    },
  );
  if (sources.length !== media.length) invalidInitialInput();
  const canonicalInput = validateInitialInput({ ...input, media });
  const submissionDigest = await initialDigest("input", canonicalInput);
  const descriptionsDigest = await initialDigest(
    "descriptions",
    initialCanonicalText(input.ordered_descriptions),
  );
  if (
    mapping.assignment_digest !== ctx.receipts.assignment_digest ||
    mapping.outcome_digest !== outcomeDigest ||
    mapping.source_backend_generation !==
      ctx.handoff.source_backend_generation ||
    mapping.destination_backend_generation !==
      ctx.handoff.destination_backend_generation ||
    mapping.items.length !== media.length || mapping.items.length === 0 ||
    mapping.items.length > ctx.handoff.cohort_limits.max_ordinals
  ) invalidInitialInput();
  const originalIDs = new Set([
    ...proof.source_verification.entries.map((entry) => entry.object_id),
    ...proof.resolved_manifest.entries.map((entry) => entry.object_id).filter((
      id,
    ): id is string => id !== null),
    ...proof.retained.map((entry) => entry.object_id),
  ]);
  const destinations = new Map<
    string,
    { index: number; bytes: PreparationTuple }
  >();
  for (const [index, item] of mapping.items.entries()) {
    const source = proof.source_verification.entries[index];
    const prepared = proof.output_manifest.entries[index].prepared;
    const resolved = proof.resolved_manifest.entries[index].object_id;
    if (
      item.index !== index ||
      item.source.original_object_id !== source.object_id ||
      !same(item.source.bytes, source.bytes) ||
      (prepared === null) !== (item.prepared === null)
    ) invalidInitialInput();
    if (
      item.prepared !== null &&
      (!prepared || item.prepared.original_object_id !== resolved ||
        !same(item.prepared.bytes, prepared.bytes))
    ) invalidInitialInput();
    if (
      item.prepared !== null &&
      (item.source.destination_object_id ===
          item.prepared.destination_object_id) !==
        same(item.source.bytes, item.prepared.bytes)
    ) invalidInitialInput();
    const kind = media[index].kind;
    if (
      !ctx.handoff.cohort_limits.content_type_pairs.some((pair) =>
        pair.kind === kind &&
        pair.source_content_type === item.source.bytes.content_type &&
        pair.prepared_content_type ===
          (item.prepared?.bytes.content_type ?? null)
      )
    ) invalidInitialInput();
    for (const role of [item.source, item.prepared]) {
      if (role === null) continue;
      if (originalIDs.has(role.destination_object_id)) invalidInitialInput();
      const previous = destinations.get(role.destination_object_id);
      if (
        previous &&
        (previous.index !== index || !same(previous.bytes, role.bytes))
      ) invalidInitialInput();
      destinations.set(role.destination_object_id, {
        index,
        bytes: role.bytes,
      });
    }
  }
  const objects = [...destinations].sort(([a], [b]) =>
    a < b ? -1 : a > b ? 1 : 0
  ).map(([object_id, value]) => ({ object_id, bytes: value.bytes }));
  const totalBytes = objects.reduce(
    (sum, object) => sum + object.bytes.byte_count,
    0,
  );
  if (
    !same(mapping.objects, objects) || objects.length > 10 ||
    objects.length > ctx.handoff.cohort_limits.max_unique_objects ||
    !Number.isSafeInteger(totalBytes) || totalBytes > 28625792 ||
    totalBytes > ctx.handoff.cohort_limits.max_unique_bytes
  ) invalidInitialInput();
  const phaseWindowDigest = await admissionMetadataDigest(
    "phase_window",
    canonicalPhaseWindow,
  );
  const mappingDigest = await admissionMetadataDigest(
    "mapping",
    canonicalMapping,
  );
  if (
    binding.submission_digest !== submissionDigest ||
    binding.assignment_digest !== ctx.receipts.assignment_digest ||
    binding.outcome_digest !== outcomeDigest ||
    binding.mapping_digest !== mappingDigest ||
    binding.destination_backend_generation !==
      mapping.destination_backend_generation ||
    !same(binding.phase_window, window) ||
    binding.phase_window_digest !== phaseWindowDigest
  ) invalidInitialInput();
  return {
    canonicalInput,
    submissionDigest,
    descriptionsDigest,
    canonicalPhaseWindow,
    phaseWindowDigest,
    canonicalMapping,
    mappingDigest,
    canonicalMediaBinding,
    mediaBindingDigest: await admissionMetadataDigest(
      "media_binding",
      canonicalMediaBinding,
    ),
  };
}
