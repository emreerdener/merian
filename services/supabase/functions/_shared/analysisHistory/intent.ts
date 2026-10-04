import { parseCapturedMediaWireV1 } from "../capturedMediaContract.ts";
import {
  buildObservationAnalysisAppend,
  type ResolvedAnalysisSpecies,
} from "./append.ts";
import {
  exactObject,
  HISTORY_MAX_RESULT_BYTES,
  invalidHistory,
  parseAnalysisIdentity,
} from "./contract.ts";

/** Actual submitting-client claims; never synthesized by a recovery worker. */
export function buildObservationAnalysisAdmission(
  identity: unknown,
  capturedMedia: unknown,
  capabilities: unknown,
) {
  const binding = parseAnalysisIdentity(identity);
  const claim = exactObject(capabilities, [
    "entitlement_protocol",
    "identification_protocol",
    "history_protocol",
    "expected_processor_permission",
  ]);
  if (
    claim.entitlement_protocol !== 3 || claim.identification_protocol !== 6 ||
    claim.history_protocol !== 7 ||
    !["google_gemini", "openai"].includes(
      claim.expected_processor_permission as string,
    )
  ) return invalidHistory();
  const media = parseCapturedMediaWireV1(capturedMedia);
  if (media.length < 1 || media.some((item) => !("description" in item))) {
    return invalidHistory();
  }
  const input = {
    ...binding,
    evidence_manifest: { schema_version: 1, captured_media: media },
    ...claim,
  };
  if (
    new TextEncoder().encode(JSON.stringify(input)).length >
      HISTORY_MAX_RESULT_BYTES - 4096
  ) return invalidHistory();
  // Serialized once before admission; provider recovery reads the saved bytes,
  // never mutable scan notes or a newly assembled request.
  return JSON.stringify(input);
}

/** Canonical draft producer. SQL binds this draft to admission and dispatch. */
export function buildAdmittedObservationDraft(
  admittedInput: string,
  result: unknown,
  species: ResolvedAnalysisSpecies | null,
) {
  if (
    typeof admittedInput !== "string" ||
    new TextEncoder().encode(admittedInput).length > HISTORY_MAX_RESULT_BYTES
  ) return invalidHistory();
  let input: Record<string, unknown>;
  try {
    input = exactObject(JSON.parse(admittedInput), [
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
  } = input;
  const evidence = exactObject(evidence_manifest, [
    "schema_version",
    "captured_media",
  ]);
  if (evidence.schema_version !== 1) return invalidHistory();
  buildObservationAnalysisAdmission(identity, evidence.captured_media, {
    entitlement_protocol,
    identification_protocol,
    history_protocol,
    expected_processor_permission,
  });
  return buildObservationAnalysisAppend(
    identity,
    result,
    evidence.captured_media,
    species,
  );
}
