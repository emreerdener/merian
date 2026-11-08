/** Private immutable delivery decoding. No native owner or serving route. */
import schema from "./completion-schema-v1.json" with { type: "json" };
import {
  initialCanonicalText,
  parseInitialCanonicalText,
} from "./canonical.ts";
import { snapshotInitialCompletionDocuments } from "./completionContract.ts";
import { mediaDigest, mediaRecord, mediaUUID } from "./mediaBinding.ts";
import { type InitialSchemaRule, matchesInitialSchema } from "./schema.ts";
import {
  type CapturedInitialResult,
  decodeInitialResult,
  type InitialResultReference,
  snapshotCapturedInitialResult,
  snapshotInitialResultReference,
} from "./resultEvidence.ts";

/** Facts from the saved original admission/input, never inferred from a reply. */
export interface InitialCompletionRequestBinding {
  readonly route: "identify" | "identify-describe" | "identify-multimodal";
  readonly input_schema_version: 1 | 2;
  readonly funding_binding_id: string;
  readonly funding_binding_version: 1;
  readonly ordered_description_digest: string;
  readonly ordered_description_count: number;
}
export interface InitialCompletionDelivery {
  readonly receipt_canonical: string;
  readonly projection_canonical: string;
  readonly result: Readonly<CapturedInitialResult>;
}
const invalid = () => new Error("initial_completion_delivery_invalid");
const bytes = new TextEncoder();
const bindingKeys = [
  "route",
  "input_schema_version",
  "funding_binding_id",
  "funding_binding_version",
  "ordered_description_digest",
  "ordered_description_count",
] as const;
export function snapshotInitialCompletionRequestBinding(
  value: InitialCompletionRequestBinding,
): Readonly<InitialCompletionRequestBinding> {
  const copy = parseInitialCanonicalText(initialCanonicalText(value));
  const rule: InitialSchemaRule = {
    type: "object",
    properties: Object.fromEntries(
      bindingKeys.map((key) => [key, schema.receipt.properties[key]]),
    ),
  };
  if (!matchesInitialSchema(copy, rule)) throw invalid();
  const row = mediaRecord(copy, [...bindingKeys]);
  if (
    (row.route !== "identify" && row.route !== "identify-describe" &&
      row.route !== "identify-multimodal") ||
    (row.input_schema_version !== 1 && row.input_schema_version !== 2) ||
    row.funding_binding_version !== 1 ||
    typeof row.ordered_description_count !== "number"
  ) throw invalid();
  return Object.freeze({
    route: row.route,
    input_schema_version: row.input_schema_version,
    funding_binding_id: mediaUUID(row.funding_binding_id),
    funding_binding_version: row.funding_binding_version,
    ordered_description_digest: mediaDigest(row.ordered_description_digest),
    ordered_description_count: row.ordered_description_count,
  });
}
function envelope(
  value: unknown,
  keys: readonly string[],
): Record<string, unknown> {
  if (
    !value || typeof value !== "object" ||
    Object.getPrototypeOf(value) !== Object.prototype
  ) throw invalid();
  const fields = Object.getOwnPropertyDescriptors(value);
  if (
    Reflect.ownKeys(value).length !== keys.length ||
    Object.keys(fields).sort().join() !== [...keys].sort().join() ||
    Object.values(fields).some((field) =>
      !field.enumerable || !("value" in field)
    )
  ) throw invalid();
  return Object.fromEntries(keys.map((key) => [key, fields[key].value]));
}

/** Caller supplies independently retained original bindings and provenance.
 * Null observes missing completion only: it never authorizes execution/settlement.
 */
export async function decodeInitialCompletionDelivery(
  value: unknown,
  expectedReference: InitialResultReference,
  expectedResultDigest: string,
  originalProvenanceCanonical: string,
  originalBinding: InitialCompletionRequestBinding,
): Promise<Readonly<InitialCompletionDelivery> | null> {
  const expected = snapshotInitialResultReference(expectedReference);
  const digest = mediaDigest(expectedResultDigest);
  const binding = snapshotInitialCompletionRequestBinding(originalBinding);
  const reply = envelope(value, [
    "version",
    "outcome",
    "reference",
    "completion",
    "result",
  ]);
  if (
    reply.version !== 1 ||
    initialCanonicalText(snapshotInitialResultReference(reply.reference)) !==
      initialCanonicalText(expected)
  ) throw invalid();
  if (
    reply.outcome === "absent" && reply.completion === null &&
    reply.result === null
  ) return null;
  if (reply.outcome !== "found") throw invalid();
  const documents = envelope(reply.completion, [
    "receipt_canonical",
    "projection_canonical",
  ]);
  const r = documents.receipt_canonical, p = documents.projection_canonical;
  if (
    typeof r !== "string" || typeof p !== "string" ||
    bytes.encode(r).length > 16384 || bytes.encode(p).length > 65536
  ) throw invalid();
  const receipt = mediaRecord(
    parseInitialCanonicalText(r),
    Object.keys(schema.receipt.properties),
  );
  const projection = parseInitialCanonicalText(p);
  const evidence = snapshotCapturedInitialResult(reply.result);
  if (
    bindingKeys.some((key) => receipt[key] !== binding[key]) ||
    ([
      "owner_id",
      "scan_id",
      "submission_digest",
      "config_digest",
      "funding_binding_digest",
      "result_evidence_id",
    ] as const).some((key) => receipt[key] !== expected[key]) ||
    receipt.result_digest !== digest || evidence.result_digest !== digest ||
    initialCanonicalText(evidence.reference) !== initialCanonicalText(expected)
  ) throw invalid();
  // All mutable caller objects were copied above, before the first suspension.
  const completion = await snapshotInitialCompletionDocuments(
    receipt,
    projection,
  );
  await decodeInitialResult(evidence, expected, originalProvenanceCanonical);
  return Object.freeze({ ...completion, result: evidence });
}
