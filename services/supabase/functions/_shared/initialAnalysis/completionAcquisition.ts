/** First completion acquisition from a trusted private admission-bound reader.
 * This is distinct from pinned recovery and never grants execution authority. */
import schema from "./completion-schema-v1.json" with { type: "json" };
import {
  initialCanonicalText,
  parseInitialCanonicalText,
} from "./canonical.ts";
import {
  decodeInitialCompletionDelivery,
  type InitialCompletionRequestBinding,
  snapshotInitialCompletionRequestBinding,
} from "./completionDelivery.ts";
import { mediaDigest, mediaRecord, mediaUUID } from "./mediaBinding.ts";
import { snapshotInitialResultReference } from "./resultEvidence.ts";
import { transformInitialResult } from "./resultEncoding.ts";
import { provenanceContractV1 } from "./resultSchemaV1.ts";
import { type InitialSchemaRule, matchesInitialSchema } from "./schema.ts";

/** Explicit new private acquisition scope, not a widening of v1 admission input. */
export interface InitialCompletionAdmission
  extends InitialCompletionRequestBinding {
  readonly version: 1;
  readonly owner_id: string;
  readonly scan_id: string;
  readonly submission_digest: string;
  readonly config_digest: string;
  readonly funding_binding_digest: string;
}
export const initialCompletionAdmissionKeys = Object.freeze(
  [
    "version",
    "owner_id",
    "scan_id",
    "route",
    "input_schema_version",
    "submission_digest",
    "config_digest",
    "funding_binding_id",
    "funding_binding_digest",
    "funding_binding_version",
    "ordered_description_digest",
    "ordered_description_count",
  ] as const,
);
const invalid = () => new Error("initial_completion_acquisition_invalid");
const encoder = new TextEncoder();
export function snapshotInitialCompletionAdmission(
  value: unknown,
): Readonly<InitialCompletionAdmission> {
  const canonical = initialCanonicalText(value);
  if (encoder.encode(canonical).length > 4096) throw invalid();
  const copy = parseInitialCanonicalText(canonical);
  const rule: InitialSchemaRule = {
    type: "object",
    properties: Object.fromEntries(
      initialCompletionAdmissionKeys.map((
        key,
      ) => [key, schema.receipt.properties[key]]),
    ),
  };
  if (!matchesInitialSchema(copy, rule)) throw invalid();
  const row = mediaRecord(copy, [...initialCompletionAdmissionKeys]);
  const binding = snapshotInitialCompletionRequestBinding({
    route: row.route,
    input_schema_version: row.input_schema_version,
    funding_binding_id: row.funding_binding_id,
    funding_binding_version: row.funding_binding_version,
    ordered_description_digest: row.ordered_description_digest,
    ordered_description_count: row.ordered_description_count,
  } as InitialCompletionRequestBinding);
  return Object.freeze({
    ...binding,
    version: 1,
    owner_id: mediaUUID(row.owner_id),
    scan_id: mediaUUID(row.scan_id),
    submission_digest: mediaDigest(row.submission_digest),
    config_digest: mediaDigest(row.config_digest),
    funding_binding_digest: mediaDigest(row.funding_binding_digest),
  });
}

/** Only the fixed private SQL reader may supply this envelope. Its reference and
 * provenance come from retained invocation/result rows, separately from delivery.
 * Native first trust still requires authenticated saved-operation correlation and
 * atomic durable pinning; this decoder does not implement either boundary. */
export async function decodeInitialCompletionAcquisition(
  value: unknown,
  original: InitialCompletionAdmission,
) {
  const admission = snapshotInitialCompletionAdmission(original);
  // Snapshot the outer fields without accepting getters; result canonical text
  // can exceed the generic canonical object's 1MiB cap, so validate it downstream.
  if (
    !value || typeof value !== "object" ||
    Object.getPrototypeOf(value) !== Object.prototype
  ) throw invalid();
  const fields = Object.getOwnPropertyDescriptors(value);
  const names = [
    "version",
    "outcome",
    "admission_canonical",
    "reference",
    "result_digest",
    "original_provenance",
    "delivery",
  ];
  if (
    Reflect.ownKeys(value).length !== names.length ||
    Object.keys(fields).sort().join() !== names.sort().join() ||
    Object.values(fields).some((f) => !f.enumerable || !("value" in f))
  ) throw invalid();
  const reply = Object.fromEntries(
    Object.entries(fields).map(([k, f]) => [k, f.value]),
  );
  if (
    reply.version !== 1 ||
    reply.admission_canonical !== initialCanonicalText(admission)
  ) throw invalid();
  if (
    reply.outcome === "pending" && reply.reference === null &&
    reply.result_digest === null &&
    reply.original_provenance === null && reply.delivery === null
  ) return null;
  if (reply.outcome !== "found") throw invalid();
  const reference = snapshotInitialResultReference(reply.reference);
  for (
    const key of [
      "owner_id",
      "scan_id",
      "submission_digest",
      "config_digest",
      "funding_binding_digest",
    ] as const
  ) {
    if (reference[key] !== admission[key]) throw invalid();
  }
  const digest = mediaDigest(reply.result_digest);
  const provenance = initialCanonicalText(
    transformInitialResult(
      provenanceContractV1,
      reply.original_provenance,
      "encode",
    ),
  );
  const binding = snapshotInitialCompletionRequestBinding({
    route: admission.route,
    input_schema_version: admission.input_schema_version,
    funding_binding_id: admission.funding_binding_id,
    funding_binding_version: admission.funding_binding_version,
    ordered_description_digest: admission.ordered_description_digest,
    ordered_description_count: admission.ordered_description_count,
  });
  const delivery = await decodeInitialCompletionDelivery(
    reply.delivery,
    reference,
    digest,
    provenance,
    binding,
  );
  if (!delivery) throw invalid();
  return Object.freeze({
    admission,
    reference,
    result_digest: digest,
    original_provenance_canonical: provenance,
    delivery,
  });
}
