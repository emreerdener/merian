import {
  buildCanonicalAnalysisResult,
  type ResolvedAnalysisSpecies,
} from "./append.ts";
import {
  exactObject,
  HISTORY_MAX_RESULT_BYTES,
  historyUUID,
  invalidHistory,
  parseAnalysisIdentity,
} from "./contract.ts";
import { EVIDENCE_MAX_BYTES, type EvidenceReceipt } from "./evidence.ts";

export type ProtectedEvidenceItem = { kind: "description"; text: string } | {
  kind: "image";
  media_id: string;
  content_type: string;
  byte_count: number;
  sha256: string;
};
/** A private durable content reference. This is NOT proof of a ready object. */
export function parseProtectedEvidenceManifest(value: unknown) {
  const row = exactObject(value, ["schema_version", "items"]);
  if (
    row.schema_version !== 2 || !Array.isArray(row.items) ||
    row.items.length < 1 || row.items.length > 64
  ) return invalidHistory();
  const seen = new Set<string>();
  let bytes = 0;
  const items: ProtectedEvidenceItem[] = row.items.map((value) => {
    if (typeof value !== "object" || value === null || Array.isArray(value)) {
      return invalidHistory();
    }
    if ("kind" in value && value.kind === "description") {
      const item = exactObject(value, ["kind", "text"]);
      if (
        typeof item.text !== "string" || !item.text.trim() ||
        item.text.length > 16384 ||
        [...item.text].length > 8192
      ) return invalidHistory();
      return { kind: "description", text: item.text };
    }
    const item = exactObject(value, [
      "kind",
      "media_id",
      "content_type",
      "byte_count",
      "sha256",
    ]);
    const id = historyUUID(item.media_id);
    if (
      item.kind !== "image" || seen.has(id) ||
      typeof item.content_type !== "string" ||
      !["image/jpeg", "image/png", "image/heic"].includes(item.content_type) ||
      typeof item.byte_count !== "number" ||
      !Number.isSafeInteger(item.byte_count) || item.byte_count < 1 ||
      item.byte_count > EVIDENCE_MAX_BYTES ||
      typeof item.sha256 !== "string" || !/^[0-9a-f]{64}$/.test(item.sha256)
    ) return invalidHistory();
    seen.add(id);
    bytes += item.byte_count;
    return {
      kind: "image",
      media_id: id,
      content_type: item.content_type,
      byte_count: item.byte_count,
      sha256: item.sha256,
    };
  });
  if (!seen.size || bytes > EVIDENCE_MAX_BYTES) return invalidHistory();
  return { schema_version: 2 as const, items };
}
/** Strip all delivery/owner/object fields from a validated internal receipt. */
export function protectedImageReference(
  receipt: EvidenceReceipt,
): ProtectedEvidenceItem {
  if (receipt.ready_at === null) return invalidHistory();
  return parseProtectedEvidenceManifest({
    schema_version: 2,
    items: [{
      kind: "image",
      media_id: receipt.media_id,
      content_type: receipt.content_type,
      byte_count: receipt.byte_count,
      sha256: receipt.sha256,
    }],
  }).items[0];
}
function identityV2(value: unknown) {
  const row = exactObject(value, [
    "schema_version",
    "observation_id",
    "analysis_id",
    "source_analysis_id",
    "request_digest",
  ]);
  if (row.schema_version !== 2) return invalidHistory();
  return {
    ...parseAnalysisIdentity({ ...row, schema_version: 1 }),
    schema_version: 2 as const,
  };
}
/** Prepared private admission; no HTTP admission/provider caller exists. */
export function buildProtectedAnalysisAdmission(
  identity: unknown,
  manifest: unknown,
  capabilities: unknown,
) {
  const binding = identityV2(identity),
    evidence = parseProtectedEvidenceManifest(manifest);
  if (
    evidence.items.some((item) =>
      item.kind === "image" &&
      [binding.observation_id, binding.analysis_id].includes(item.media_id)
    )
  ) return invalidHistory();
  const claims = exactObject(capabilities, [
    "entitlement_protocol",
    "identification_protocol",
    "history_protocol",
    "expected_processor_permission",
  ]);
  if (
    claims.entitlement_protocol !== 3 || claims.identification_protocol !== 6 ||
    claims.history_protocol !== 8 ||
    !["google_gemini", "openai"].includes(
      claims.expected_processor_permission as string,
    )
  ) return invalidHistory();
  const input = { ...binding, evidence_manifest: evidence, ...claims };
  const bytes = JSON.stringify(input);
  if (
    new TextEncoder().encode(bytes).length > HISTORY_MAX_RESULT_BYTES - 4096
  ) return invalidHistory();
  return bytes;
}
export function buildProtectedAnalysisDraft(
  inputBytes: string,
  result: unknown,
  species: ResolvedAnalysisSpecies | null,
) {
  if (
    typeof inputBytes !== "string" ||
    new TextEncoder().encode(inputBytes).length > HISTORY_MAX_RESULT_BYTES
  ) return invalidHistory();
  let row: Record<string, unknown>;
  try {
    row = exactObject(JSON.parse(inputBytes), [
      "schema_version",
      "observation_id",
      "analysis_id",
      "source_analysis_id",
      "request_digest",
      "evidence_manifest",
      "entitlement_protocol",
      "identification_protocol",
      "history_protocol",
      "expected_processor_permission",
    ]);
  } catch {
    return invalidHistory();
  }
  const {
    evidence_manifest,
    entitlement_protocol,
    identification_protocol,
    history_protocol,
    expected_processor_permission,
    ...identity
  } = row;
  buildProtectedAnalysisAdmission(identity, evidence_manifest, {
    entitlement_protocol,
    identification_protocol,
    history_protocol,
    expected_processor_permission,
  });
  const draft = {
    ...identityV2(identity),
    evidence_manifest: parseProtectedEvidenceManifest(evidence_manifest),
    result_snapshot: buildCanonicalAnalysisResult(
      historyUUID(row.observation_id),
      result,
      species,
    ),
  };
  if (
    new TextEncoder().encode(JSON.stringify(draft)).length >
      HISTORY_MAX_RESULT_BYTES - 4096
  ) return invalidHistory();
  return Object.freeze(draft);
}
