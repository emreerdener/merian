/** Frozen v2 semantic rules. Public Identify changes do not change recovery. */
import type { ContractNode } from "../identify/contract.ts";
import {
  dataContractV2,
  type InitialPrimaryV2,
  type InitialResultDataV2,
  primaryContractV2,
} from "./resultSchemaV2.ts";
import {
  invalidInitialResult,
  transformInitialResult,
} from "./resultEncoding.ts";
function primaryContractError(_field: string, _message: string): never {
  throw invalidInitialResult();
}
function deepFreezeJson<T>(value: T): T {
  if (value !== null && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const child of Object.values(value)) deepFreezeJson(child);
  }
  return value;
}
function parseV2(contract: ContractNode, value: unknown) {
  return transformInitialResult(
    contract,
    transformInitialResult(contract, value, "encode"),
    "decode",
  );
}
export function parseInitialResultDataV2(value: unknown): InitialResultDataV2 {
  // The structural traversal validates every field against this exact frozen type.
  const data = parseV2(dataContractV2, value) as InitialResultDataV2;
  if (
    data.identification_provenance?.version === 3 &&
    (!("returned_model" in data.identification_provenance) ||
      data.identification_provenance.returned_model !==
        data.identification_provenance.model)
  ) throw invalidInitialResult();
  validatePrimaryIdentificationResult(data);
  return deepFreezeJson(data);
}
function parsePrimaryIdentification(
  value: unknown,
): InitialPrimaryV2 {
  const primary = parseV2(primaryContractV2, value) as InitialPrimaryV2;
  if (new TextEncoder().encode(JSON.stringify(primary)).byteLength > 4096) {
    primaryContractError(
      "primary_identification",
      "Snapshot exceeds byte limit.",
    );
  }
  for (const key of ["scientific_name", "common_name"] as const) {
    const name = primary[key];
    if (
      name !== null &&
      (name !== name.trim() || Array.from(name).some((character) => {
        const code = character.charCodeAt(0);
        return code <= 31 || code === 127;
      }))
    ) {
      primaryContractError(
        `primary_identification.${key}`,
        "Name must be sanitized.",
      );
    }
  }
  if (
    (["species", "genus", "family"].includes(primary.resolution) &&
      primary.scientific_name === null) ||
    (primary.resolution === "unresolved_biological" &&
      primary.scientific_name !== null)
  ) {
    primaryContractError(
      "primary_identification",
      "Name contradicts resolution.",
    );
  }
  return deepFreezeJson(primary);
}

function validatePrimaryIdentificationResult(data: InitialResultDataV2): void {
  const required =
    data.identification_provenance?.schema === "merian_identify_primary_v1";
  const primary = data.primary_identification;
  if (required !== (primary !== undefined)) {
    primaryContractError(
      "primary_identification",
      "Snapshot and execution schema must agree.",
    );
  }
  if (primary === undefined) {
    if (
      data.candidates?.some((candidate) => candidate.taxon_rank !== undefined)
    ) {
      primaryContractError(
        "candidates",
        "Explicit candidate rank requires a primary snapshot.",
      );
    }
    return;
  }
  parsePrimaryIdentification(primary);
  if (
    data.is_biological_subject !== (primary.resolution !== "non_biological") ||
    data.scientific_name !== primary.scientific_name ||
    data.common_name !== primary.common_name
  ) {
    primaryContractError(
      "primary_identification",
      "Top-level identity contradicts snapshot.",
    );
  }
  if (primary.resolution === "species") {
    if (
      (data.candidates?.length ?? 0) > 2 ||
      data.candidates?.some((candidate) => candidate.taxon_rank !== "species")
    ) {
      primaryContractError(
        "candidates",
        "Explicit species alternatives require species rank and at most two entries.",
      );
    }
    return;
  }
  if (
    data.candidates !== null || data.pet_identification !== null ||
    data.is_new_to_merian_dictionary !== false
  ) {
    primaryContractError(
      "primary_identification",
      "Non-species result contains species effects.",
    );
  }
  for (
    const key of [
      "gbif_taxon_key",
      "reference_image_url",
      "wikipedia_url",
      "wikipedia_overview",
      "species_insights",
      "iucn_red_list_status",
      "alternative_common_names",
    ] as const
  ) {
    if (data[key] != null) {
      primaryContractError(
        key,
        "Species enrichment requires species resolution.",
      );
    }
  }
  if (primary.resolution === "family" && data.taxonomy?.genus != null) {
    primaryContractError(
      "taxonomy.genus",
      "Family resolution cannot assert a genus.",
    );
  }
}
