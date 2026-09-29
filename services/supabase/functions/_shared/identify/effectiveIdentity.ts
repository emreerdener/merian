import {
  identificationProvenanceContract,
  parseContract,
  parsePrimaryIdentification,
  PRIMARY_IDENTIFICATION_SCHEMA,
  type PrimaryIdentification,
} from "./contract.ts";
import { parseSpeciesReview, type SpeciesReview } from "./speciesReview.ts";

/** Trusted saved-row projection only; never apply this to client recovery JSON. */
export interface SavedIdentificationFields {
  primary_identification?: unknown;
  identification_provenance?: unknown;
  confirmed_species_identity?: unknown;
  confirmed_species_identity_revision?: unknown;
  confirmed_species_id?: string | null;
  species_id?: string | null;
  user_identification_override?: string | null;
  user_confirmed_identification?: boolean | null;
  user_review_state?: string | null;
  is_biological_subject?: boolean | null;
  candidates?: unknown;
  pet_identification?: unknown;
}
export interface EffectiveIdentification {
  source: "legacy" | "invalid" | "ai_primary" | "verified_selection";
  primary: PrimaryIdentification | null;
  rank: PrimaryIdentification["resolution"] | null;
  scientific_name: string | null;
  common_name: string | null;
  species_id: string | null;
  verified: boolean;
  pending_review: boolean;
}
function record(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}
/** Keep parity with internal.scan_effective_identification; no score or tier inference. */
export function effectiveIdentification(
  row: SavedIdentificationFields,
): EffectiveIdentification {
  const empty: EffectiveIdentification = {
    source: "invalid",
    primary: null,
    rank: null,
    scientific_name: null,
    common_name: null,
    species_id: null,
    verified: false,
    pending_review: false,
  };
  const schema = record(row.identification_provenance)?.schema;
  if (
    row.primary_identification == null &&
    schema !== PRIMARY_IDENTIFICATION_SCHEMA
  ) {
    return {
      ...empty,
      source: "legacy",
      species_id: row.confirmed_species_id ?? row.species_id ?? null,
    };
  }
  try {
    if (schema !== PRIMARY_IDENTIFICATION_SCHEMA) return empty;
    parseContract(
      identificationProvenanceContract,
      row.identification_provenance,
      "identification_provenance",
    );
    const primary = parsePrimaryIdentification(row.primary_identification);
    if (
      row.is_biological_subject !== (primary.resolution !== "non_biological")
    ) return empty;
    if (primary.resolution !== "species") {
      if (
        row.species_id != null || row.candidates != null ||
        row.pet_identification != null
      ) return empty;
    } else if (
      row.candidates != null &&
      (!Array.isArray(row.candidates) || row.candidates.length > 2 ||
        row.candidates.some((candidate) =>
          record(candidate)?.taxon_rank !== "species"
        ))
    ) return empty;
    const review: SpeciesReview = parseSpeciesReview({
      version: 1,
      revision: row.confirmed_species_identity_revision,
      identity: row.confirmed_species_identity,
      user_identification_override: row.user_identification_override,
      user_confirmed_identification: row.user_confirmed_identification,
      confirmed_species_id: row.confirmed_species_id,
      user_review_state: row.user_review_state,
    });
    if (review.identity && row.is_biological_subject === true) {
      return {
        source: "verified_selection",
        primary,
        rank: "species",
        scientific_name: review.identity.scientific_name,
        common_name: review.identity.common_name,
        species_id: review.identity.species_id,
        verified: true,
        pending_review: false,
      };
    }
    return {
      source: "ai_primary",
      primary,
      rank: primary.resolution,
      scientific_name: primary.scientific_name,
      common_name: primary.common_name,
      species_id: primary.resolution === "species" &&
          review.user_review_state !== "user_overridden"
        ? row.species_id ?? null
        : null,
      verified: false,
      pending_review: review.user_review_state !== "unreviewed",
    };
  } catch {
    return empty;
  }
}

export function identificationIsBiological(
  identity: EffectiveIdentification,
): boolean {
  return identity.source !== "invalid" && identity.source !== "legacy" &&
    identity.rank !== "non_biological";
}
