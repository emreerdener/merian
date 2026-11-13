import { initialCanonicalText } from "../canonical.ts";
import { initialMediaHash } from "../mediaBinding.ts";

export const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const hash = "a".repeat(64);
const time = "2026-11-04T03:00:00.123456+00:00";
export function projection(cpm = true, outcome = "consumed_durable_result") {
  return {
    version: 1,
    completed_at: time,
    scan_id: id(1),
    owner_id: id(2),
    result_evidence_id: id(3),
    result_digest: hash,
    plan_used: "pro_complimentary",
    settlement: { outcome, settled_at: outcome === "none" ? null : time },
    credit_consumed: outcome === "consumed_durable_result",
    entitlement_after: {
      current_plan: "free",
      current_tier: "free",
      is_paid: false,
      entitlement_version: 1,
      in_flight_count: 0,
      scans_available_to_start: 2,
      scans_remaining: 2,
    },
    species_association: null as
      | { species_id: string; scientific_name: string }
      | null,
    scan_timestamp: time,
    timestamp_basis: "completion",
    geoprivacy: "private",
    capture_context: {
      source: cpm ? "cpm_absent_v1" : "legacy_input_v1",
      submission_digest: hash,
    },
    media: {
      kind: cpm ? "cpm_adoption_v1" : "legacy_transfer_v1",
      receipt_digest: hash,
      items: [{
        ordinal: 0,
        kind: "image",
        media_id: id(4),
        content_type: "image/jpeg",
        byte_count: 4096,
        sha256: hash,
        poster_media_id: null as string | null,
      }],
    },
  };
}
export async function receipt(p: ReturnType<typeof projection>) {
  return {
    version: 1,
    owner_id: id(2),
    operation_id: id(1),
    scan_id: id(1),
    route: "identify-multimodal",
    submission_digest: hash,
    input_schema_version: p.media.kind === "cpm_adoption_v1" ? 2 : 1,
    config_digest: hash,
    funding_binding_id: id(5),
    funding_binding_digest: hash,
    funding_binding_version: 1,
    result_evidence_id: id(3),
    result_digest: hash,
    result_schema_version: 1,
    ordered_description_digest: hash,
    ordered_description_count: 0,
    finalized_media_binding_digest: hash,
    completion_projection_digest: await initialMediaHash(
      new TextEncoder().encode(
        `merian.initial-analysis.completion-projection.v1\n${
          initialCanonicalText(p)
        }`,
      ),
    ),
  };
}
