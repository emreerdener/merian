/** Closed private completion documents. No route, SQL authority or native DTO.
 * Retain canonical originals; never re-create a completion from current scans.
 */
import schema from "./completion-schema-v1.json" with { type: "json" };
import {
  initialCanonicalText,
  parseInitialCanonicalText,
} from "./canonical.ts";
import { initialMediaHash, mediaRecord } from "./mediaBinding.ts";
import { type InitialSchemaRule, matchesInitialSchema } from "./schema.ts";

const encoder = new TextEncoder();
function invalid(): never {
  throw new Error("initial_analysis_completion_invalid");
}
function jsonbSpacing(value: unknown): number {
  // JSONB text adds one space after each comma and object colon. Key order
  // changes no byte count; strings and safe integers use the same escaping.
  if (Array.isArray(value)) {
    return Math.max(0, value.length - 1) +
      value.reduce((n, item) => n + jsonbSpacing(item), 0);
  }
  if (value !== null && typeof value === "object") {
    const children = Object.values(value);
    return children.length + Math.max(0, children.length - 1) +
      children.reduce<number>((n, item) => n + jsonbSpacing(item), 0);
  }
  return 0;
}
function document(value: unknown, kind: "receipt" | "projection") {
  const canonical = initialCanonicalText(value);
  const limit = kind === "receipt" ? 16384 : 65536;
  const length = encoder.encode(canonical).length;
  if (length > limit) {
    return invalid();
  }
  const copy = parseInitialCanonicalText(canonical);
  if (
    length + jsonbSpacing(copy) > limit ||
    !matchesInitialSchema(copy, schema[kind] as InitialSchemaRule)
  ) {
    return invalid();
  }
  return {
    canonical,
    row: mediaRecord(copy, Object.keys(schema[kind].properties)),
  };
}
function timestamp(value: unknown) {
  if (typeof value !== "string") return invalid();
  // PostgreSQL keeps microseconds. Date is only a calendar check; its rounded
  // milliseconds never replace the original digest-bearing timestamp string.
  const truncated = value.replace(/(\.\d{3})\d+/, "$1");
  const date = new Date(truncated);
  if (
    !Number.isFinite(date.valueOf()) ||
    date.toISOString().slice(0, 19) !== value.slice(0, 19)
  ) {
    return invalid();
  }
}

/** Compare both immutable documents before exposing either. The transport must
 * separately bind their owner/operation to the authenticated saved request.
 * The digest is a consistency check, not authorization or proof of byte IO.
 */
export async function snapshotInitialCompletionDocuments(
  receiptValue: unknown,
  projectionValue: unknown,
) {
  const receipt = document(receiptValue, "receipt");
  const projection = document(projectionValue, "projection");
  const r = receipt.row, p = projection.row;
  const context = mediaRecord(p.capture_context, [
    "source",
    "submission_digest",
  ]);
  const media = mediaRecord(p.media, ["kind", "receipt_digest", "items"]);
  const settlement = mediaRecord(p.settlement, ["outcome", "settled_at"]);
  const cpm = media.kind === "cpm_adoption_v1";
  if (
    r.operation_id !== r.scan_id ||
    ["owner_id", "scan_id", "result_evidence_id", "result_digest"].some((key) =>
      r[key] !== p[key]
    ) ||
    r.submission_digest !== context.submission_digest ||
    r.finalized_media_binding_digest !== media.receipt_digest ||
    r.input_schema_version !== (cpm ? 2 : 1) ||
    context.source !== (cpm ? "cpm_absent_v1" : "legacy_input_v1") ||
    p.credit_consumed !== (settlement.outcome === "consumed_durable_result") ||
    (settlement.settled_at === null) !== (settlement.outcome === "none") ||
    (p.timestamp_basis === "completion" &&
      p.scan_timestamp !== p.completed_at) ||
    (cpm && (p.timestamp_basis !== "completion" || p.geoprivacy !== "private"))
  ) return invalid();
  timestamp(p.completed_at);
  timestamp(p.scan_timestamp);
  if (settlement.settled_at !== null) timestamp(settlement.settled_at);
  if (
    !Array.isArray(media.items) || media.items.length < 1 ||
    (cpm && media.items.length > 2)
  ) {
    return invalid();
  }
  const ids = new Set<unknown>();
  for (let index = 0; index < media.items.length; index++) {
    const item = mediaRecord(media.items[index], [
      "ordinal",
      "kind",
      "media_id",
      "content_type",
      "byte_count",
      "sha256",
      "poster_media_id",
    ]);
    if (
      item.ordinal !== index || ids.has(item.media_id) ||
      (item.kind !== "video" && item.poster_media_id !== null) ||
      (item.kind === "audio" && item.content_type !== "audio/wav") ||
      (item.kind === "video" && item.content_type !== "video/mp4") ||
      (item.kind === "image" &&
        (typeof item.content_type !== "string" ||
          !item.content_type.startsWith("image/"))) ||
      (cpm &&
        (item.kind !== "image" || item.content_type !== "image/jpeg" ||
          typeof item.byte_count !== "number" || item.byte_count > 4194304))
    ) return invalid();
    ids.add(item.media_id);
  }
  const digest = await initialMediaHash(encoder.encode(
    `merian.initial-analysis.completion-projection.v1\n${projection.canonical}`,
  ));
  if (r.completion_projection_digest !== digest) return invalid();
  return Object.freeze({
    receipt_canonical: receipt.canonical,
    projection_canonical: projection.canonical,
  });
}
