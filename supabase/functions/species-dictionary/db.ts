import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  buildPublicSpeciesDictionaryPayload,
  firstReferenceImageUrl,
  firstReferenceImageUrlsBySpeciesId,
  type PublicReferenceImageSource,
  type PublicSimilarSpecies,
  type PublicSpeciesDictionaryPayload,
  type PublicSpeciesDictionaryRow,
  publicSpeciesProjectionForbiddenKeys,
  type PublicSpeciesReferenceImage,
  type PublicSpeciesReferenceImageRow,
  type PublicSpeciesTaxonomy,
  referenceImagesFromLegacyCache as referenceImagesFrom,
  referenceImagesFromRows,
  resolveOptionalPublicCommonName,
  resolvePublicCommonName as resolveCommonName,
  sanitizeAlternativeCommonNames,
  stringValue,
} from "../_shared/publicSpeciesProjection.ts";

export {
  firstReferenceImageUrl,
  publicSpeciesProjectionForbiddenKeys,
  referenceImagesFrom,
  referenceImagesFromRows,
  resolveCommonName,
  sanitizeAlternativeCommonNames,
};

export type ReferenceImageSource = PublicReferenceImageSource;
export type SpeciesDictionaryTaxonomy = PublicSpeciesTaxonomy;
export type SpeciesDictionaryReferenceImage = PublicSpeciesReferenceImage;
export type SpeciesDictionarySimilarSpecies = PublicSimilarSpecies;
export type SpeciesDictionaryPayload = PublicSpeciesDictionaryPayload;
export type SpeciesDictionaryRow = PublicSpeciesDictionaryRow;
export type SpeciesReferenceImageRow = PublicSpeciesReferenceImageRow;

export const buildSpeciesDictionaryPayload =
  buildPublicSpeciesDictionaryPayload;

interface LookalikeRelationRow {
  lookalike?: LookalikeSpeciesRow | LookalikeSpeciesRow[] | null;
}

interface LookalikeSpeciesRow {
  id?: string | null;
  scientific_name?: string | null;
  common_names?: Record<string, unknown> | null;
  reference_image_url?: string | null;
  iucn_red_list_status?: string | null;
}

export interface SpeciesDictionaryRequestResult {
  speciesId?: string;
  scientificName?: string;
  error?: string;
  status?: number;
}

export function parseSpeciesDictionaryRequest(
  body: Record<string, unknown>,
): SpeciesDictionaryRequestResult {
  const rawSpeciesId = body.species_id;
  if (rawSpeciesId !== undefined && rawSpeciesId !== null) {
    if (typeof rawSpeciesId !== "string") {
      return { error: "species_id must be a valid UUID.", status: 400 };
    }

    const speciesId = rawSpeciesId.trim();
    if (speciesId && !isUuid(speciesId)) {
      return { error: "species_id must be a valid UUID.", status: 400 };
    }

    if (speciesId) {
      const scientificName = normalizeOptionalScientificName(
        body.scientific_name,
      );
      if (scientificName?.error) return scientificName;
      return scientificName?.scientificName
        ? { speciesId, scientificName: scientificName.scientificName }
        : { speciesId };
    }
  }

  const rawName = body.scientific_name;
  if (typeof rawName !== "string") {
    return {
      error: "Missing required parameter: species_id or scientific_name",
      status: 400,
    };
  }

  const scientificName = rawName.trim().replace(/\s+/g, " ");
  if (!scientificName) {
    return {
      error: "Missing required parameter: species_id or scientific_name",
      status: 400,
    };
  }

  if (scientificName.length > 160) {
    return { error: "scientific_name is too long.", status: 400 };
  }

  return { scientificName };
}

export async function fetchSpeciesDictionary(
  lookup: string | { speciesId?: string; scientificName?: string },
  supabaseAdmin: SupabaseClient,
): Promise<SpeciesDictionaryPayload | null> {
  const normalizedLookup = typeof lookup === "string"
    ? { scientificName: lookup }
    : lookup;
  const query = supabaseAdmin
    .from("species_dictionary")
    .select(
      "id, scientific_name, common_names, alternative_common_names, kingdom, phylum, class, order, family, genus, wikipedia_url, reference_image_url, wikipedia_overview, hazard_type, iucn_red_list_status, habitat_description, gbif_taxon_key, group_tags",
    )
    .limit(1);

  const { data: speciesRows, error: speciesError } = normalizedLookup.speciesId
    ? await query.eq("id", normalizedLookup.speciesId)
    : await query.eq("scientific_name", normalizedLookup.scientificName ?? "");

  if (speciesError) {
    throw new Error(
      `Failed to fetch species dictionary row: ${speciesError.message}`,
    );
  }

  const row = ((speciesRows ?? []) as SpeciesDictionaryRow[])[0];
  if (!row) return null;

  const similarSpecies = await fetchSimilarSpecies(row.id, supabaseAdmin);
  const referenceImages = await fetchReferenceImages(
    row.id,
    row.reference_image_url,
    row.wikipedia_url,
    supabaseAdmin,
  );
  return buildSpeciesDictionaryPayload(row, similarSpecies, referenceImages);
}

async function fetchReferenceImages(
  speciesId: string,
  legacyReferenceImageUrl: string | null | undefined,
  wikipediaUrl: string | null | undefined,
  supabaseAdmin: SupabaseClient,
): Promise<SpeciesDictionaryReferenceImage[]> {
  const { data, error } = await supabaseAdmin
    .from("species_reference_images")
    .select(
      "id, url, source, license, attribution, width, height, sort_order, created_at",
    )
    .eq("species_id", speciesId)
    .order("sort_order", { ascending: true })
    .order("created_at", { ascending: true })
    .order("id", { ascending: true });

  if (error) {
    throw new Error(
      `Failed to fetch species reference images: ${error.message}`,
    );
  }

  const normalizedImages = referenceImagesFromRows(
    data as SpeciesReferenceImageRow[] | null,
    wikipediaUrl,
  );
  return normalizedImages.length > 0
    ? normalizedImages
    : referenceImagesFrom(legacyReferenceImageUrl, wikipediaUrl);
}

async function fetchSimilarSpecies(
  speciesId: string,
  supabaseAdmin: SupabaseClient,
): Promise<SpeciesDictionarySimilarSpecies[]> {
  const { data, error } = await supabaseAdmin
    .from("species_lookalikes")
    .select(
      "lookalike:species_dictionary!lookalike_id(id, scientific_name, common_names, reference_image_url, iucn_red_list_status)",
    )
    .eq("species_id", speciesId);

  if (error) {
    throw new Error(`Failed to fetch species lookalikes: ${error.message}`);
  }

  const seen = new Set<string>();
  const rows: Array<{
    species_id: string;
    scientific_name: string;
    common_name: string | null;
    legacy_reference_image_url: string | null;
    iucn_red_list_status: string | null;
  }> = [];

  for (const row of (data ?? []) as LookalikeRelationRow[]) {
    const lookalike = relationValue(row.lookalike);
    const lookalikeId = stringValue(lookalike?.id);
    const scientificName = stringValue(lookalike?.scientific_name);
    if (!lookalikeId || !scientificName) continue;

    const key = lookalikeId.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);

    rows.push({
      species_id: lookalikeId,
      scientific_name: scientificName,
      common_name: resolveOptionalPublicCommonName(lookalike?.common_names),
      legacy_reference_image_url: stringValue(lookalike?.reference_image_url),
      iucn_red_list_status: stringValue(lookalike?.iucn_red_list_status),
    });
  }

  const firstImageBySpeciesId = await fetchFirstReferenceImagesForSpecies(
    rows.map((row) => row.species_id),
    supabaseAdmin,
  );

  return rows.map((row) => ({
    species_id: row.species_id,
    scientific_name: row.scientific_name,
    common_name: row.common_name,
    reference_image_url: firstImageBySpeciesId.get(row.species_id) ??
      firstReferenceImageUrl(row.legacy_reference_image_url),
    iucn_red_list_status: row.iucn_red_list_status,
  }));
}

async function fetchFirstReferenceImagesForSpecies(
  speciesIds: string[],
  supabaseAdmin: SupabaseClient,
): Promise<Map<string, string>> {
  const uniqueSpeciesIds = Array.from(
    new Set(speciesIds.filter((id) => id.length > 0)),
  );
  if (uniqueSpeciesIds.length === 0) return new Map();

  const { data, error } = await supabaseAdmin
    .from("species_reference_images")
    .select("id, species_id, url, sort_order, created_at")
    .in("species_id", uniqueSpeciesIds)
    .order("species_id", { ascending: true })
    .order("sort_order", { ascending: true })
    .order("created_at", { ascending: true })
    .order("id", { ascending: true });

  if (error) {
    throw new Error(
      `Failed to fetch lookalike reference images: ${error.message}`,
    );
  }

  return firstReferenceImageUrlsBySpeciesId(
    data as SpeciesReferenceImageRow[] | null,
  );
}

function relationValue<T>(value: T | T[] | null | undefined): T | undefined {
  if (Array.isArray(value)) return value[0];
  return value ?? undefined;
}

function normalizeOptionalScientificName(
  value: unknown,
): SpeciesDictionaryRequestResult | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "string") {
    return {
      error: "scientific_name must be a string when provided.",
      status: 400,
    };
  }

  const scientificName = value.trim().replace(/\s+/g, " ");
  if (!scientificName) return undefined;
  if (scientificName.length > 160) {
    return { error: "scientific_name is too long.", status: 400 };
  }

  return { scientificName };
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
    value,
  );
}
