import { parsePreparedAudioAdmission } from "./audioAdmission.ts";
import { buildObservationAnalysisAdmission } from "./intent.ts";
import {
  buildProtectedAnalysisAdmission,
  parseProtectedEvidenceManifest,
} from "./protectedManifest.ts";
import { exactObject, invalidHistory } from "./contract.ts";
import { MEDIA_BUDGETS } from "../mediaBudgets.ts";

/** Existing immutable admission contract, with provider limits before quota. */
export function parseExecutableAnalysisInput(
  value: unknown,
): Record<string, unknown> {
  const row = exactObject(value, [
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
  if (row.schema_version === 3) return parsePreparedAudioAdmission(row);
  const {
    evidence_manifest,
    entitlement_protocol,
    identification_protocol,
    history_protocol,
    expected_processor_permission,
    ...identity
  } = row;
  const claims = {
    entitlement_protocol,
    identification_protocol,
    history_protocol,
    expected_processor_permission,
  };
  if (identity.schema_version === 2) {
    const evidence = parseProtectedEvidenceManifest(evidence_manifest);
    const images = evidence.items.filter((item) => item.kind === "image");
    if (
      images.length > MEDIA_BUDGETS.maxImageCount ||
      images.some((item) =>
        !["image/jpeg", "image/png"].includes(item.content_type)
      ) ||
      evidence.items.reduce(
          (sum, item) =>
            sum + (item.kind === "description" ? item.text.length : 0),
          0,
        ) > 32_000 ||
      images.reduce((sum, item) => sum + item.byte_count, 0) >
        MEDIA_BUDGETS.maxImageRawBytes
    ) return invalidHistory();
    return JSON.parse(
      buildProtectedAnalysisAdmission(identity, evidence, claims),
    );
  }
  const evidence = exactObject(evidence_manifest, [
    "schema_version",
    "captured_media",
  ]);
  if (evidence.schema_version !== 1) return invalidHistory();
  return JSON.parse(
    buildObservationAnalysisAdmission(
      identity,
      evidence.captured_media,
      claims,
    ),
  );
}
