import { SupabaseClient } from "@supabase/supabase-js";
import {
  legacyReferenceImageUrls,
  stringValue,
} from "./publicSpeciesProjection.ts";

export type SpeciesContentKey =
  | "common_names"
  | "alternative_common_names"
  | "taxonomy"
  | "wikipedia_url"
  | "wikipedia_overview"
  | "habitat_description"
  | "gbif_taxon_key"
  | "reference_images"
  | "lookalikes"
  | "group_tags"
  | "iucn_red_list_status"
  | "hazard_type";

export type SpeciesContentSource =
  | "gbif"
  | "wikipedia"
  | "model_enrichment"
  | "user_review"
  | "manual_curation"
  | "system_backfill"
  | "taxonomy_trigger"
  | "mixed"
  | "unknown";

export interface SpeciesContentProvenanceRow {
  species_id: string;
  content_key: SpeciesContentKey;
  source: SpeciesContentSource;
  source_detail?: string | null;
  confidence?: number | null;
  metadata?: Record<string, unknown>;
  last_refreshed_at: string;
  refresh_after?: string | null;
}

export interface SpeciesContentProvenanceOptions {
  sourceDetail?: string | null;
  confidence?: number | null;
  metadata?: Record<string, unknown>;
  refreshedAt?: Date;
  refreshAfter?: Date | null;
}

export interface SpeciesDictionaryProvenanceData {
  common_names?: Record<string, string | undefined> | null;
  alternative_common_names?: string[] | null;
  kingdom?: string | null;
  phylum?: string | null;
  class?: string | null;
  order?: string | null;
  family?: string | null;
  genus?: string | null;
  wikipedia_overview?: string | null;
  habitat_description?: string;
  wikipedia_url?: string | null;
  gbif_taxon_key?: number | null;
  reference_image_url?: string | null;
  iucn_red_list_status?: string;
  hazard_type?: string;
}

export function speciesContentProvenanceRow(
  speciesId: string,
  contentKey: SpeciesContentKey,
  source: SpeciesContentSource,
  options: SpeciesContentProvenanceOptions = {},
): SpeciesContentProvenanceRow {
  const refreshedAt = options.refreshedAt ?? new Date();
  const refreshAfter = options.refreshAfter === undefined
    ? defaultRefreshAfter(source, contentKey, refreshedAt)
    : options.refreshAfter;

  return {
    species_id: speciesId,
    content_key: contentKey,
    source,
    source_detail: options.sourceDetail ?? null,
    confidence: options.confidence ?? defaultConfidence(source),
    metadata: options.metadata ?? {},
    last_refreshed_at: refreshedAt.toISOString(),
    refresh_after: refreshAfter ? refreshAfter.toISOString() : null,
  };
}

export function buildSpeciesDictionaryProvenanceRows(
  speciesId: string,
  data: SpeciesDictionaryProvenanceData,
  refreshedAt = new Date(),
): SpeciesContentProvenanceRow[] {
  const rows: SpeciesContentProvenanceRow[] = [];

  if (hasCommonNames(data.common_names)) {
    rows.push(
      speciesContentProvenanceRow(
        speciesId,
        "common_names",
        "model_enrichment",
        {
          refreshedAt,
          sourceDetail: "identified common name",
          metadata: {
            locale_keys: Object.keys(data.common_names ?? {}).filter((key) =>
              stringValue(data.common_names?.[key])
            ),
          },
        },
      ),
    );
  }

  if (data.alternative_common_names !== undefined) {
    rows.push(
      speciesContentProvenanceRow(
        speciesId,
        "alternative_common_names",
        "gbif",
        {
          refreshedAt,
          sourceDetail: "GBIF vernacular names",
          metadata: { count: data.alternative_common_names?.length ?? 0 },
        },
      ),
    );
  }

  if (hasTaxonomy(data)) {
    rows.push(
      speciesContentProvenanceRow(speciesId, "taxonomy", "model_enrichment", {
        refreshedAt,
        sourceDetail: "taxonomy enrichment",
        metadata: {
          populated_ranks: [
            "kingdom",
            "phylum",
            "class",
            "order",
            "family",
            "genus",
          ].filter((key) =>
            stringValue(data[key as keyof SpeciesDictionaryProvenanceData])
          ),
        },
      }),
    );
  }

  if (stringValue(data.wikipedia_url)) {
    rows.push(
      speciesContentProvenanceRow(speciesId, "wikipedia_url", "wikipedia", {
        refreshedAt,
        sourceDetail: "Wikipedia REST summary",
      }),
    );
  }

  if (stringValue(data.wikipedia_overview)) {
    rows.push(
      speciesContentProvenanceRow(
        speciesId,
        "wikipedia_overview",
        "wikipedia",
        {
          refreshedAt,
          sourceDetail: "Wikipedia REST summary extract",
        },
      ),
    );
  }

  if (stringValue(data.habitat_description)) {
    rows.push(
      speciesContentProvenanceRow(
        speciesId,
        "habitat_description",
        "model_enrichment",
        {
          refreshedAt,
          sourceDetail: "static encyclopedic enrichment",
        },
      ),
    );
  }

  if (data.gbif_taxon_key != null) {
    rows.push(
      speciesContentProvenanceRow(speciesId, "gbif_taxon_key", "gbif", {
        refreshedAt,
        sourceDetail: "GBIF species match",
      }),
    );
  }

  if (stringValue(data.reference_image_url)) {
    rows.push(
      speciesContentProvenanceRow(speciesId, "reference_images", "mixed", {
        refreshedAt,
        sourceDetail: "Wikipedia image plus GBIF occurrence media",
        metadata: {
          url_count: legacyReferenceImageUrls(data.reference_image_url).length,
        },
      }),
    );
  }

  if (stringValue(data.iucn_red_list_status)) {
    rows.push(
      speciesContentProvenanceRow(
        speciesId,
        "iucn_red_list_status",
        "model_enrichment",
        {
          refreshedAt,
          sourceDetail: "species-level enrichment default or model output",
          confidence: 0.65,
        },
      ),
    );
  }

  if (stringValue(data.hazard_type)) {
    rows.push(
      speciesContentProvenanceRow(
        speciesId,
        "hazard_type",
        "model_enrichment",
        {
          refreshedAt,
          sourceDetail: "species-level hazard classification",
          confidence: 0.65,
        },
      ),
    );
  }

  return rows;
}

export function buildGroupTagsProvenanceRows(
  speciesId: string,
  groupTags: string[],
  refreshedAt = new Date(),
): SpeciesContentProvenanceRow[] {
  if (groupTags.length === 0) return [];
  return [
    speciesContentProvenanceRow(speciesId, "group_tags", "model_enrichment", {
      refreshedAt,
      sourceDetail: "group tag generation",
      metadata: { count: groupTags.length },
    }),
  ];
}

export function buildLookalikesProvenanceRows(
  speciesId: string,
  lookalikeCount: number,
  source: SpeciesContentSource = "model_enrichment",
  refreshedAt = new Date(),
): SpeciesContentProvenanceRow[] {
  if (lookalikeCount <= 0) return [];
  return [
    speciesContentProvenanceRow(speciesId, "lookalikes", source, {
      refreshedAt,
      sourceDetail: source === "model_enrichment"
        ? "validated similar-species generation"
        : "lookalike relationship update",
      metadata: { count: lookalikeCount },
    }),
  ];
}

export async function recordSpeciesContentProvenance(
  supabaseAdmin: SupabaseClient,
  rows: SpeciesContentProvenanceRow[],
  context: string,
): Promise<void> {
  if (rows.length === 0) return;

  const { error } = await supabaseAdmin
    .from("species_content_provenance")
    .upsert(rows, {
      onConflict: "species_id,content_key",
      ignoreDuplicates: false,
    });

  if (error) {
    console.error(
      `[${context}] Failed to record species content provenance:`,
      error.message,
    );
  }
}

export function defaultRefreshAfter(
  source: SpeciesContentSource,
  _contentKey: SpeciesContentKey,
  refreshedAt = new Date(),
): Date | null {
  if (source === "manual_curation") return null;

  const days = source === "system_backfill" || source === "unknown"
    ? 30
    : source === "model_enrichment"
    ? 90
    : source === "user_review" || source === "taxonomy_trigger"
    ? 365
    : 180;

  return addDays(refreshedAt, days);
}

export function defaultConfidence(source: SpeciesContentSource): number {
  switch (source) {
    case "manual_curation":
      return 1;
    case "gbif":
    case "wikipedia":
      return 0.95;
    case "mixed":
      return 0.9;
    case "user_review":
      return 0.85;
    case "model_enrichment":
      return 0.8;
    case "taxonomy_trigger":
      return 0.7;
    case "system_backfill":
      return 0.5;
    case "unknown":
      return 0.4;
  }
}

function hasCommonNames(
  commonNames: Record<string, string | undefined> | null | undefined,
): boolean {
  return Object.values(commonNames ?? {}).some((value) => stringValue(value));
}

function hasTaxonomy(data: SpeciesDictionaryProvenanceData): boolean {
  return [
    data.kingdom,
    data.phylum,
    data.class,
    data.order,
    data.family,
    data.genus,
  ].some((value) => stringValue(value));
}

function addDays(date: Date, days: number): Date {
  const next = new Date(date.getTime());
  next.setUTCDate(next.getUTCDate() + days);
  return next;
}
