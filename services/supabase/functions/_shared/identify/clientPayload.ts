import { CachedSpeciesRow, ClientPayload } from "./types.ts";

type WireHazardType =
  | "none"
  | "poisonous"
  | "venomous"
  | "allergenic"
  | "irritant";

const allowedHazardTypes = new Set<WireHazardType>([
  "none",
  "poisonous",
  "venomous",
  "allergenic",
  "irritant",
]);

export function normalizeWireHazardType(
  value: string | null,
): WireHazardType {
  return value && allowedHazardTypes.has(value as WireHazardType)
    ? value as WireHazardType
    : "none";
}

export function isNewToMerianDictionary(
  isIdentifiedBiologicalSubject: boolean,
  cachedSpecies: CachedSpeciesRow | null,
): boolean {
  return isIdentifiedBiologicalSubject && cachedSpecies === null;
}

function filterAlternativeCommonNames(
  primaryName: string | null | undefined,
  alternativeCommonNames: string[] | null,
): string[] | null {
  if (!alternativeCommonNames?.length) return null;

  const primaryEn = (primaryName ?? "").toLowerCase();
  const filtered = alternativeCommonNames.filter((name) =>
    name.toLowerCase() !== primaryEn
  );

  return filtered.length > 0 ? filtered : null;
}

export function hydratePayloadFromCachedSpecies(
  payload: ClientPayload,
  cachedSpecies: CachedSpeciesRow,
): ClientPayload {
  const hydrated: ClientPayload = { ...payload };

  if (cachedSpecies.common_names?.en) {
    hydrated.common_name = cachedSpecies.common_names.en;
  }

  hydrated.alternative_common_names = filterAlternativeCommonNames(
    hydrated.common_name,
    cachedSpecies.alternative_common_names,
  );
  hydrated.reference_image_url = cachedSpecies.reference_image_url;
  hydrated.wikipedia_url = cachedSpecies.wikipedia_url;
  hydrated.wikipedia_overview = cachedSpecies.wikipedia_overview;
  hydrated.taxonomy = {
    kingdom: cachedSpecies.kingdom ?? "Unknown",
    phylum: cachedSpecies.phylum ?? "Unknown",
    class: cachedSpecies.class ?? "Unknown",
    order: cachedSpecies.order ?? "Unknown",
    family: cachedSpecies.family ?? "Unknown",
    genus: cachedSpecies.genus ?? "Unknown",
  };
  hydrated.iucn_red_list_status = cachedSpecies.iucn_red_list_status ??
    "not_evaluated";
  const aiReasoning = hydrated.insight_data?.ai_reasoning ??
    hydrated.ai_reasoning ?? "Reasoning omitted.";
  hydrated.insight_data = {
    ai_reasoning: aiReasoning,
    hazard_type: normalizeWireHazardType(cachedSpecies.hazard_type),
  };

  if (cachedSpecies.group_tags?.length) {
    hydrated.group_tags = cachedSpecies.group_tags;
  }

  if (cachedSpecies.gbif_taxon_key != null) {
    hydrated.gbif_taxon_key = cachedSpecies.gbif_taxon_key;
  }

  if (cachedSpecies.habitat_description) {
    hydrated.species_insights = {
      habitat_description: cachedSpecies.habitat_description,
    };
  } else {
    delete hydrated.species_insights;
  }

  return hydrated;
}
