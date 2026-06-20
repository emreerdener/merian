import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  type ExternalEnrichmentData,
  fetchExternalEnrichment,
} from "../_shared/external.ts";
import type { SimilarSpeciesEntry } from "../_shared/biology.ts";
import {
  buildPublicSpeciesDictionaryPayload,
  firstReferenceImageUrl,
  firstReferenceImageUrlsBySpeciesId,
  isPublicBiologicalSpeciesRow,
  type PublicReferenceImageSource,
  type PublicSimilarSpecies,
  publicSimilarSpeciesMetadata,
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
  reason?: string | null;
  visual_traits?: string[] | null;
  confidence?: number | null;
  source?: string | null;
  review_status?: string | null;
  is_bidirectional?: boolean | null;
  sort_order?: number | null;
  lookalike?: LookalikeSpeciesRow | LookalikeSpeciesRow[] | null;
}

interface LookalikeSpeciesRow {
  id?: string | null;
  scientific_name?: string | null;
  common_names?: Record<string, unknown> | null;
  reference_image_url?: string | null;
  iucn_red_list_status?: string | null;
}

export interface SpeciesDictionaryCatalogCursor {
  scientificName: string;
  speciesId: string;
  createdAt?: string;
}

export type SpeciesDictionaryCatalogCategory =
  | "all"
  | "region"
  | "group"
  | "recently_added";

export type SpeciesDictionaryOverviewCategoryId =
  | "all"
  | "your_region"
  | "taxonomy"
  | "recently_added";

export interface SpeciesDictionaryCatalogRequest {
  mode: "catalog";
  category?: SpeciesDictionaryCatalogCategory;
  query?: string;
  region?: string;
  group?: string;
  limit: number;
  cursor?: SpeciesDictionaryCatalogCursor;
}

export interface SpeciesDictionaryTreeRequest {
  mode: "tree";
}

export interface SpeciesDictionaryOverviewRequest {
  mode: "overview";
  userRegion?: string;
}

export interface SpeciesDictionaryCatalogItem {
  id: string;
  scientific_name: string;
  common_name: string;
  content_quality: string;
  taxonomy: SpeciesDictionaryTaxonomy | null;
  iucn_red_list_status: string | null;
  hazard_type: string | null;
  group_tags: string[];
  reference_image_url: string | null;
}

export interface SpeciesDictionaryCategorySummary {
  id: SpeciesDictionaryOverviewCategoryId;
  title: string;
  subtitle: string | null;
  count: number;
  reference_image_url: string | null;
  region: string | null;
}

export interface SpeciesDictionaryGroupSummary {
  id: string;
  title: string;
  count: number;
  reference_image_url: string | null;
}

export interface SpeciesDictionaryRegionSummary {
  id: string;
  title: string;
  count: number;
  reference_image_url: string | null;
}

export interface SpeciesDictionaryFeaturedSpecies {
  id: string;
  scientific_name: string;
  common_name: string;
  overview: string | null;
  reference_image_url: string | null;
}

export interface SpeciesDictionaryOverviewResult {
  featured_species: SpeciesDictionaryFeaturedSpecies | null;
  categories: SpeciesDictionaryCategorySummary[];
  groups: SpeciesDictionaryGroupSummary[];
  regions: SpeciesDictionaryRegionSummary[];
}

export interface SpeciesDictionaryCatalogResult {
  data: SpeciesDictionaryCatalogItem[];
  nextCursor: SpeciesDictionaryCatalogCursor | null;
}

export type TaxonomyTreeRank =
  | "kingdom"
  | "phylum"
  | "class"
  | "order"
  | "family"
  | "genus"
  | "species";

export interface SpeciesDictionaryTreeSpecies {
  id: string;
  scientific_name: string;
  common_name: string;
  content_quality: string;
  taxonomy: SpeciesDictionaryTaxonomy | null;
  iucn_red_list_status: string | null;
  hazard_type: string | null;
  group_tags: string[];
  reference_image_url: string | null;
}

export interface SpeciesDictionaryTreeNode {
  id: string;
  rank: TaxonomyTreeRank;
  title: string;
  subtitle: string | null;
  parent_id: string | null;
  species_count: number;
  child_count: number;
  lineage: SpeciesDictionaryTaxonomy | null;
  representative_species: SpeciesDictionaryTreeSpecies | null;
  species: SpeciesDictionaryTreeSpecies | null;
}

export interface SpeciesDictionaryTreeEdge {
  from: string;
  to: string;
}

export interface SpeciesDictionaryTreeResult {
  nodes: SpeciesDictionaryTreeNode[];
  edges: SpeciesDictionaryTreeEdge[];
}

export const USER_SCANNED_SPECIES_TREE_PAGE_SIZE = 500;
export const SPECIES_REFERENCE_IMAGE_LOOKUP_BATCH_SIZE = 100;
export const SPECIES_DICTIONARY_OVERVIEW_REGION_LIMIT = 24;
const SPECIES_DICTIONARY_CATALOG_SELECT =
  "id, scientific_name, common_names, alternative_common_names, kingdom, phylum, class, order, family, genus, wikipedia_url, reference_image_url, wikipedia_overview, hazard_type, iucn_red_list_status, habitat_description, gbif_taxon_key, group_tags, native_region, created_at";
const HIGH_LEVEL_SPECIES_GROUPS = [
  {
    id: "plants",
    title: "Plants",
    filters: ["kingdom.ilike.Plantae", "group_tags.cs.{plant}"],
  },
  {
    id: "birds",
    title: "Birds",
    filters: ["class.ilike.Aves", "group_tags.cs.{bird}"],
  },
  {
    id: "insects",
    title: "Insects",
    filters: [
      "class.ilike.Insecta",
      "class.ilike.Entognatha",
      "class.ilike.Arachnida",
      "group_tags.cs.{insect}",
      "group_tags.cs.{arachnid}",
    ],
  },
  {
    id: "fungi",
    title: "Fungi",
    filters: [
      "kingdom.ilike.Fungi",
      "group_tags.cs.{fungus}",
      "group_tags.cs.{fungi}",
    ],
  },
  {
    id: "mammals",
    title: "Mammals",
    filters: ["class.ilike.Mammalia", "group_tags.cs.{mammal}"],
  },
  {
    id: "reptiles_amphibians",
    title: "Reptiles & Amphibians",
    filters: [
      "class.ilike.Reptilia",
      "class.ilike.Amphibia",
      "order.ilike.Squamata",
      "group_tags.cs.{reptile}",
      "group_tags.cs.{amphibian}",
    ],
  },
] as const;

export interface UserScanSpeciesRow {
  species_id?: string | null;
  confirmed_species_id?: string | null;
}

export interface SpeciesDictionaryRequestResult {
  mode?: "catalog" | "tree" | "overview";
  category?: SpeciesDictionaryCatalogCategory;
  speciesId?: string;
  scientificName?: string;
  query?: string;
  region?: string;
  group?: string;
  userRegion?: string;
  limit?: number;
  cursor?: SpeciesDictionaryCatalogCursor;
  error?: string;
  status?: number;
}

export function parseSpeciesDictionaryRequest(
  body: Record<string, unknown>,
): SpeciesDictionaryRequestResult {
  if (body.mode === "catalog") {
    return parseSpeciesDictionaryCatalogRequest(body);
  }

  if (body.mode === "tree") {
    return { mode: "tree" };
  }

  if (body.mode === "overview") {
    const userRegion = normalizeOptionalRegion(body.user_region);
    if (userRegion?.error) return userRegion;
    return userRegion?.region
      ? { mode: "overview", userRegion: userRegion.region }
      : { mode: "overview" };
  }

  if (body.mode !== undefined && body.mode !== null) {
    return {
      error: "mode must be catalog, overview, or tree when provided.",
      status: 400,
    };
  }

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

export function parseSpeciesDictionaryCatalogRequest(
  body: Record<string, unknown>,
): SpeciesDictionaryRequestResult {
  const category = normalizeOptionalCatalogCategory(body.category);
  if (category?.error) return category;

  const limit = normalizeCatalogLimit(body.limit);
  if (limit?.error) return limit;

  const query = normalizeOptionalCatalogQuery(body.query);
  if (query?.error) return query;

  const region = normalizeOptionalRegion(body.region);
  if (region?.error) return region;

  const group = normalizeOptionalGroup(body.group);
  if (group?.error) return group;

  const cursor = normalizeOptionalCatalogCursor(body.cursor);
  if (cursor?.error) return cursor;

  if (category?.category === "region" && !region?.region) {
    return {
      error: "region is required when category is region.",
      status: 400,
    };
  }

  if (
    category?.category === "recently_added" && cursor?.cursor &&
    !cursor.cursor.createdAt
  ) {
    return {
      error: "cursor.created_at is required when category is recently_added.",
      status: 400,
    };
  }

  if (category?.category === "group" && !group?.group) {
    return {
      error: "group is required when category is group.",
      status: 400,
    };
  }

  const result: SpeciesDictionaryRequestResult = {
    mode: "catalog",
    category: category?.category ?? "all",
    limit: limit?.limit ?? 40,
  };
  if (query?.query) result.query = query.query;
  if (region?.region) result.region = region.region;
  if (group?.group) result.group = group.group;
  if (cursor?.cursor) result.cursor = cursor.cursor;
  return result;
}

export async function fetchSpeciesDictionaryCatalog(
  request: SpeciesDictionaryCatalogRequest,
  supabaseAdmin: SupabaseClient,
): Promise<SpeciesDictionaryCatalogResult> {
  const requestedLimit = Math.max(1, Math.min(100, Math.floor(request.limit)));
  const fetchLimit = requestedLimit + 1;
  const queryText = request.query?.trim().replace(/\s+/g, " ");
  const category = request.category ?? "all";

  let catalogQuery = supabaseAdmin
    .from("species_dictionary")
    .select(SPECIES_DICTIONARY_CATALOG_SELECT)
    .or("gbif_taxon_key.not.is.null,kingdom.not.is.null")
    .limit(fetchLimit);

  if (queryText) {
    catalogQuery = catalogQuery.ilike("scientific_name", `%${queryText}%`);
  }

  if (category === "region" && request.region) {
    const regionFilter = normalizedRegionTitle(request.region) ??
      request.region;
    catalogQuery = catalogQuery.ilike(
      "native_region",
      `%${regionFilter.trim().replace(/\s+/g, " ")}%`,
    );
  }

  if (category === "group" && request.group) {
    const groupDefinition = highLevelSpeciesGroup(request.group);
    if (groupDefinition) {
      catalogQuery = catalogQuery.or(groupDefinition.filters.join(","));
    }
  }

  if (category === "recently_added") {
    catalogQuery = catalogQuery
      .order("created_at", { ascending: false })
      .order("id", { ascending: false });
  } else {
    catalogQuery = catalogQuery
      .order("scientific_name", { ascending: true })
      .order("id", { ascending: true });
  }

  if (
    request.cursor && category === "recently_added" && request.cursor.createdAt
  ) {
    catalogQuery = catalogQuery.or(
      `created_at.lt.${request.cursor.createdAt},and(created_at.eq.${request.cursor.createdAt},id.lt.${request.cursor.speciesId})`,
    );
  } else if (request.cursor && category !== "recently_added") {
    catalogQuery = catalogQuery.or(
      `scientific_name.gt.${request.cursor.scientificName},and(scientific_name.eq.${request.cursor.scientificName},id.gt.${request.cursor.speciesId})`,
    );
  }

  const { data, error } = await catalogQuery;
  if (error) {
    throw new Error(
      `Failed to fetch species dictionary catalog: ${error.message}`,
    );
  }

  const rows = ((data ?? []) as SpeciesDictionaryRow[])
    .filter(isPublicBiologicalSpeciesRow)
    .slice(0, fetchLimit);
  const visibleRows = rows.slice(0, requestedLimit);
  const firstImageBySpeciesId = await fetchFirstReferenceImagesForSpecies(
    visibleRows.map((row) => row.id),
    supabaseAdmin,
  );
  const items = visibleRows.map((row) =>
    buildSpeciesDictionaryCatalogItem(
      row,
      firstImageBySpeciesId.get(row.id) ??
        firstReferenceImageUrl(row.reference_image_url),
    )
  );
  const lastVisibleRow = visibleRows[visibleRows.length - 1];
  const nextCursor = rows.length > requestedLimit && lastVisibleRow
    ? {
      scientificName: lastVisibleRow.scientific_name,
      speciesId: lastVisibleRow.id,
      createdAt: stringValue(lastVisibleRow.created_at) ?? undefined,
    }
    : null;

  return { data: items, nextCursor };
}

export async function fetchSpeciesDictionaryOverview(
  request: SpeciesDictionaryOverviewRequest,
  supabaseAdmin: SupabaseClient,
): Promise<SpeciesDictionaryOverviewResult> {
  const { data, error } = await supabaseAdmin
    .from("species_dictionary")
    .select(SPECIES_DICTIONARY_CATALOG_SELECT)
    .or("gbif_taxon_key.not.is.null,kingdom.not.is.null")
    .order("scientific_name", { ascending: true })
    .order("id", { ascending: true });

  if (error) {
    throw new Error(
      `Failed to fetch species dictionary overview: ${error.message}`,
    );
  }

  const rows = ((data ?? []) as SpeciesDictionaryRow[])
    .filter(isPublicBiologicalSpeciesRow);
  const firstImageBySpeciesId = await fetchFirstReferenceImagesForSpecies(
    rows.map((row) => row.id),
    supabaseAdmin,
  );
  return buildSpeciesDictionaryOverview(
    rows,
    firstImageBySpeciesId,
    request.userRegion,
  );
}

export async function fetchUserScannedSpeciesDictionaryTree(
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<SpeciesDictionaryTreeResult> {
  const rows = await fetchUserScannedSpeciesDictionaryRows(
    userId,
    supabaseAdmin,
  );
  const firstImageBySpeciesId = await fetchFirstReferenceImagesForSpecies(
    rows.map((row) => row.id),
    supabaseAdmin,
  );

  return buildSpeciesDictionaryTree(rows, firstImageBySpeciesId);
}

async function fetchUserScannedSpeciesDictionaryRows(
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<SpeciesDictionaryRow[]> {
  const scanRows: UserScanSpeciesRow[] = [];
  let from = 0;

  while (true) {
    const to = from + USER_SCANNED_SPECIES_TREE_PAGE_SIZE - 1;
    const { data, error } = await supabaseAdmin
      .from("scans")
      .select("species_id, confirmed_species_id")
      .eq("user_id", userId)
      .eq("is_tombstoned", false)
      .eq("is_biological_subject", true)
      .order("timestamp", { ascending: false })
      .order("id", { ascending: false })
      .range(from, to);

    if (error) {
      throw new Error(
        `Failed to fetch user scanned species: ${error.message}`,
      );
    }

    const page = (data ?? []) as UserScanSpeciesRow[];
    scanRows.push(...page);
    if (page.length < USER_SCANNED_SPECIES_TREE_PAGE_SIZE) break;
    from += USER_SCANNED_SPECIES_TREE_PAGE_SIZE;
  }

  const speciesIds = speciesIdsFromUserScanRows(scanRows);
  return fetchSpeciesDictionaryRowsByIds(speciesIds, supabaseAdmin);
}

export function speciesIdsFromUserScanRows(
  rows: UserScanSpeciesRow[],
): string[] {
  const seen = new Set<string>();
  const speciesIds: string[] = [];

  for (const row of rows) {
    const speciesId = stringValue(row.confirmed_species_id) ??
      stringValue(row.species_id);
    if (!speciesId) continue;

    const key = speciesId.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    speciesIds.push(speciesId);
  }

  return speciesIds;
}

async function fetchSpeciesDictionaryRowsByIds(
  speciesIds: string[],
  supabaseAdmin: SupabaseClient,
): Promise<SpeciesDictionaryRow[]> {
  if (speciesIds.length === 0) return [];

  const rows: SpeciesDictionaryRow[] = [];
  for (
    const batch of speciesReferenceImageLookupBatches(
      speciesIds,
      SPECIES_REFERENCE_IMAGE_LOOKUP_BATCH_SIZE,
    )
  ) {
    const { data, error } = await supabaseAdmin
      .from("species_dictionary")
      .select(SPECIES_DICTIONARY_CATALOG_SELECT)
      .in("id", batch)
      .order("scientific_name", { ascending: true })
      .order("id", { ascending: true });

    if (error) {
      throw new Error(
        `Failed to fetch scanned species dictionary rows: ${error.message}`,
      );
    }

    rows.push(
      ...((data ?? []) as SpeciesDictionaryRow[]).filter(
        isPublicBiologicalSpeciesRow,
      ),
    );
  }

  return rows;
}

export function buildSpeciesDictionaryTree(
  rows: SpeciesDictionaryRow[],
  firstImageBySpeciesId: Map<string, string> = new Map(),
): SpeciesDictionaryTreeResult {
  const nodesById = new Map<string, SpeciesDictionaryTreeNode>();
  const edgesById = new Map<string, SpeciesDictionaryTreeEdge>();
  const sortedRows = rows.filter(isPublicBiologicalSpeciesRow).sort(
    (lhs, rhs) => {
      const lhsName = (stringValue(lhs.scientific_name) ?? "")
        .toLocaleLowerCase();
      const rhsName = (stringValue(rhs.scientific_name) ?? "")
        .toLocaleLowerCase();
      if (lhsName === rhsName) {
        return (stringValue(lhs.id) ?? "").localeCompare(
          stringValue(rhs.id) ?? "",
        );
      }
      return lhsName.localeCompare(rhsName);
    },
  );

  for (const row of sortedRows) {
    const referenceImageUrl = firstImageBySpeciesId.get(row.id) ??
      firstReferenceImageUrl(row.reference_image_url);
    const catalogItem = buildSpeciesDictionaryCatalogItem(
      row,
      referenceImageUrl,
    );
    const treeSpecies: SpeciesDictionaryTreeSpecies = {
      id: catalogItem.id,
      scientific_name: catalogItem.scientific_name,
      common_name: catalogItem.common_name,
      content_quality: catalogItem.content_quality,
      taxonomy: catalogItem.taxonomy,
      iucn_red_list_status: catalogItem.iucn_red_list_status,
      hazard_type: catalogItem.hazard_type,
      group_tags: catalogItem.group_tags,
      reference_image_url: catalogItem.reference_image_url,
    };
    const lineageValues: Array<[TaxonomyTreeRank, string]> = [
      ["kingdom", taxonomyDisplayValue(row.kingdom)],
      ["phylum", taxonomyDisplayValue(row.phylum)],
      ["class", taxonomyDisplayValue(row.class)],
      ["order", taxonomyDisplayValue(row.order)],
      ["family", taxonomyDisplayValue(row.family)],
      ["genus", taxonomyDisplayValue(row.genus)],
    ];

    let parentId: string | null = null;
    const pathParts: string[] = [];
    const lineage: Partial<SpeciesDictionaryTaxonomy> = {};

    for (const [rank, value] of lineageValues) {
      pathParts.push(taxonomyKey(value));
      const nodeId = `taxonomy:${rank}:${pathParts.join("/")}`;
      setLineageValue(lineage, rank, value);
      const node = nodesById.get(nodeId) ?? {
        id: nodeId,
        rank,
        title: value,
        subtitle: taxonomyRankTitle(rank),
        parent_id: parentId,
        species_count: 0,
        child_count: 0,
        lineage: completeLineage(lineage),
        representative_species: treeSpecies,
        species: null,
      };

      node.species_count += 1;
      if (
        !node.representative_species?.reference_image_url &&
        treeSpecies.reference_image_url
      ) {
        node.representative_species = treeSpecies;
      }
      nodesById.set(nodeId, node);

      if (parentId) {
        const edge = { from: parentId, to: nodeId };
        edgesById.set(`${edge.from}->${edge.to}`, edge);
      }
      parentId = nodeId;
    }

    const speciesNodeId = `species:${row.id}`;
    nodesById.set(speciesNodeId, {
      id: speciesNodeId,
      rank: "species",
      title: treeSpecies.common_name,
      subtitle: treeSpecies.scientific_name,
      parent_id: parentId,
      species_count: 1,
      child_count: 0,
      lineage: treeSpecies.taxonomy,
      representative_species: treeSpecies,
      species: treeSpecies,
    });

    if (parentId) {
      const edge = { from: parentId, to: speciesNodeId };
      edgesById.set(`${edge.from}->${edge.to}`, edge);
    }
  }

  const childCounts = new Map<string, number>();
  for (const edge of edgesById.values()) {
    childCounts.set(edge.from, (childCounts.get(edge.from) ?? 0) + 1);
  }

  const nodes = Array.from(nodesById.values())
    .map((node) => ({
      ...node,
      child_count: childCounts.get(node.id) ?? 0,
    }))
    .sort(taxonomyTreeNodeSort);
  const edges = Array.from(edgesById.values()).sort((lhs, rhs) =>
    `${lhs.from}->${lhs.to}`.localeCompare(`${rhs.from}->${rhs.to}`)
  );

  return { nodes, edges };
}

export function buildSpeciesDictionaryCatalogItem(
  row: SpeciesDictionaryRow,
  referenceImageUrl: string | null = firstReferenceImageUrl(
    row.reference_image_url,
  ),
): SpeciesDictionaryCatalogItem {
  const payload = buildSpeciesDictionaryPayload(
    row,
    [],
    referenceImageUrl ? [{ url: referenceImageUrl, source: "gbif" }] : [],
  );

  return {
    id: payload.id,
    scientific_name: payload.scientific_name,
    common_name: payload.common_name,
    content_quality: payload.content_quality,
    taxonomy: payload.taxonomy,
    iucn_red_list_status: payload.iucn_red_list_status,
    hazard_type: payload.hazard_type,
    group_tags: payload.group_tags,
    reference_image_url: referenceImageUrl,
  };
}

export function buildSpeciesDictionaryOverview(
  rows: SpeciesDictionaryRow[],
  firstImageBySpeciesId: Map<string, string> = new Map(),
  userRegion?: string,
): SpeciesDictionaryOverviewResult {
  const biologicalRows = rows.filter(isPublicBiologicalSpeciesRow);
  const sortedRows = biologicalRows.slice().sort(
    speciesDictionaryCreatedAtDescending,
  );
  const regions = buildSpeciesDictionaryRegionSummaries(
    biologicalRows,
    firstImageBySpeciesId,
  );
  const normalizedUserRegion = normalizedRegionKey(userRegion);
  const userRegionRows = normalizedUserRegion
    ? biologicalRows.filter((row) =>
      regionKeysMatch(
        normalizedRegionKey(row.native_region),
        normalizedUserRegion,
      )
    )
    : [];
  const userRegionTitle = userRegionRows.length > 0
    ? (regions.find((region) =>
      regionKeysMatch(normalizedRegionKey(region.title), normalizedUserRegion)
    )?.title ?? normalizedRegionTitle(userRegion))
    : null;
  const categoryReferenceImageUrls = randomRepresentativeImageUrlPair(
    biologicalRows,
    firstImageBySpeciesId,
  );

  return {
    featured_species: buildFeaturedSpeciesSummary(
      sortedRows,
      firstImageBySpeciesId,
    ),
    categories: [
      {
        id: "all",
        title: "All",
        subtitle: "Browse every species in the dictionary",
        count: biologicalRows.length,
        reference_image_url: categoryReferenceImageUrls[0],
        region: null,
      },
      {
        id: "your_region",
        title: "Your Region",
        subtitle: userRegionTitle
          ? `Species associated with ${userRegionTitle}`
          : "Browse regions to find local species",
        count: userRegionRows.length,
        reference_image_url: representativeImageUrl(
          userRegionRows,
          firstImageBySpeciesId,
        ),
        region: userRegionTitle,
      },
      {
        id: "taxonomy",
        title: "Taxonomy",
        subtitle: "Explore species by biological lineage",
        count: biologicalRows.length,
        reference_image_url: categoryReferenceImageUrls[1],
        region: null,
      },
      {
        id: "recently_added",
        title: "Recently Added",
        subtitle: "Newest entries added to the database",
        count: biologicalRows.length,
        reference_image_url: representativeImageUrl(
          sortedRows,
          firstImageBySpeciesId,
        ),
        region: null,
      },
    ],
    groups: buildSpeciesDictionaryGroupSummaries(
      biologicalRows,
      firstImageBySpeciesId,
    ),
    regions,
  };
}

function buildFeaturedSpeciesSummary(
  rows: SpeciesDictionaryRow[],
  firstImageBySpeciesId: Map<string, string>,
): SpeciesDictionaryFeaturedSpecies | null {
  const recentlyAddedRows = rows.slice().sort(
    speciesDictionaryCreatedAtDescending,
  );
  const candidatesWithOverviewAndImage = rows.filter((row) =>
    referenceImageUrlForRow(row, firstImageBySpeciesId) &&
    normalizedOverview(row.wikipedia_overview)
  );
  const candidatesWithImage = rows.filter((row) =>
    referenceImageUrlForRow(row, firstImageBySpeciesId)
  );
  const candidatesWithOverview = rows.filter((row) =>
    normalizedOverview(row.wikipedia_overview)
  );
  const candidates = candidatesWithOverviewAndImage.length > 0
    ? candidatesWithOverviewAndImage
    : candidatesWithImage.length > 0
    ? candidatesWithImage
    : candidatesWithOverview.length > 0
    ? candidatesWithOverview
    : rows;

  if (candidates.length === 0) return null;

  const row =
    recentlyAddedRows.find((recentRow) =>
      candidates.some((candidate) => candidate.id === recentRow.id)
    ) ?? candidates[0];
  const referenceImageUrl = referenceImageUrlForRow(row, firstImageBySpeciesId);
  const catalogItem = buildSpeciesDictionaryCatalogItem(row, referenceImageUrl);

  return {
    id: catalogItem.id,
    scientific_name: catalogItem.scientific_name,
    common_name: catalogItem.common_name,
    overview: normalizedOverview(row.wikipedia_overview),
    reference_image_url: catalogItem.reference_image_url,
  };
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
    .select(SPECIES_DICTIONARY_CATALOG_SELECT)
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
  if (!row) {
    return normalizedLookup.scientificName
      ? await fetchExternalSpeciesDictionary(normalizedLookup.scientificName)
      : null;
  }
  if (!isPublicBiologicalSpeciesRow(row)) return null;

  const similarSpecies = await fetchSimilarSpecies(row.id, supabaseAdmin);
  const referenceImages = await fetchReferenceImages(
    row.id,
    row.reference_image_url,
    row.wikipedia_url,
    supabaseAdmin,
  );
  return buildSpeciesDictionaryPayload(row, similarSpecies, referenceImages);
}

export async function fetchExternalSpeciesDictionary(
  scientificName: string,
): Promise<SpeciesDictionaryPayload> {
  const normalizedScientificName = scientificName.trim().replace(/\s+/g, " ");
  const externalData = await fetchExternalEnrichment(normalizedScientificName);
  const taxonomy = externalData.gbifTaxonomy;
  const { fetchSimilarSpecies: fetchModelSimilarSpecies } = await import(
    "../_shared/biology.ts"
  );
  const similarResult = await fetchModelSimilarSpecies(
    "species-dictionary-public",
    normalizedScientificName,
    taxonomy,
  );
  const similarSpecies = externalSimilarSpecies(
    similarResult?.similar_species ?? [],
  );

  return buildExternalSpeciesDictionaryPayload(
    normalizedScientificName,
    externalData,
    similarSpecies,
  );
}

export function buildExternalSpeciesDictionaryPayload(
  scientificName: string,
  externalData: ExternalEnrichmentData,
  similarSpecies: SpeciesDictionarySimilarSpecies[] = [],
): SpeciesDictionaryPayload {
  const normalizedScientificName = scientificName.trim().replace(/\s+/g, " ");
  return buildSpeciesDictionaryPayload(
    externalSpeciesRow(normalizedScientificName, externalData),
    similarSpecies,
  );
}

function externalSpeciesRow(
  scientificName: string,
  externalData: ExternalEnrichmentData,
): SpeciesDictionaryRow {
  const taxonomy = externalData.gbifTaxonomy;
  const commonName = externalCommonName(scientificName, externalData);

  return {
    id: externalSpeciesId(scientificName),
    scientific_name: scientificName,
    common_names: commonName ? { en: commonName } : null,
    alternative_common_names: externalData.alternativeCommonNames,
    kingdom: taxonomy?.kingdom ?? null,
    phylum: taxonomy?.phylum ?? null,
    class: taxonomy?.class ?? null,
    order: taxonomy?.order ?? null,
    family: taxonomy?.family ?? null,
    genus: taxonomy?.genus ?? null,
    wikipedia_url: externalData.wikipediaUrl,
    reference_image_url: externalData.referenceImageUrl,
    wikipedia_overview: externalData.wikiExtract,
    hazard_type: null,
    iucn_red_list_status: null,
    habitat_description: null,
    gbif_taxon_key: externalData.gbifKey,
    group_tags: [],
  };
}

function externalSimilarSpecies(
  entries: SimilarSpeciesEntry[],
): SpeciesDictionarySimilarSpecies[] {
  return entries.map((entry, index) => ({
    scientific_name: entry.scientific_name,
    common_name: entry.common_name,
    reference_image_url: null,
    iucn_red_list_status: null,
    reason: stringValue(entry.reason),
    visual_traits: Array.isArray(entry.visual_traits)
      ? entry.visual_traits
      : [],
    confidence:
      typeof entry.confidence === "number" && Number.isFinite(entry.confidence)
        ? Math.max(0, Math.min(1, entry.confidence))
        : null,
    source: "model_enrichment",
    review_status: "unreviewed",
    is_bidirectional: false,
    sort_order: index,
  }));
}

function externalCommonName(
  scientificName: string,
  externalData: ExternalEnrichmentData,
): string | null {
  const wikiTitle = stringValue(externalData.wikiTitle)
    ?.replace(/\s*\([^)]+\)$/, "")
    .trim();
  if (wikiTitle && wikiTitle.toLowerCase() !== scientificName.toLowerCase()) {
    return wikiTitle;
  }

  return externalData.alternativeCommonNames[0] ?? null;
}

function externalSpeciesId(scientificName: string): string {
  return `external:${encodeURIComponent(scientificName.toLowerCase())}`;
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
      "reason, visual_traits, confidence, source, review_status, is_bidirectional, sort_order, lookalike:species_dictionary!lookalike_id(id, scientific_name, common_names, reference_image_url, iucn_red_list_status)",
    )
    .eq("species_id", speciesId)
    .neq("review_status", "rejected")
    .order("sort_order", { ascending: true })
    .order("created_at", { ascending: true });

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
    relation: LookalikeRelationRow;
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
      relation: row,
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
    ...publicSimilarSpeciesMetadata(row.relation),
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

  const rows: SpeciesReferenceImageRow[] = [];
  for (
    const batch of speciesReferenceImageLookupBatches(
      uniqueSpeciesIds,
      SPECIES_REFERENCE_IMAGE_LOOKUP_BATCH_SIZE,
    )
  ) {
    const { data, error } = await supabaseAdmin
      .from("species_reference_images")
      .select("id, species_id, url, sort_order, created_at")
      .in("species_id", batch)
      .order("species_id", { ascending: true })
      .order("sort_order", { ascending: true })
      .order("created_at", { ascending: true })
      .order("id", { ascending: true });

    if (error) {
      throw new Error(
        `Failed to fetch species reference image previews: ${error.message}`,
      );
    }

    rows.push(...((data ?? []) as SpeciesReferenceImageRow[]));
  }

  return firstReferenceImageUrlsBySpeciesId(rows);
}

export function speciesReferenceImageLookupBatches(
  speciesIds: string[],
  batchSize = SPECIES_REFERENCE_IMAGE_LOOKUP_BATCH_SIZE,
): string[][] {
  const normalizedBatchSize = Math.max(1, Math.floor(batchSize));
  const uniqueSpeciesIds = Array.from(
    new Set(
      speciesIds
        .map((id) => id.trim())
        .filter((id) => id.length > 0),
    ),
  );
  const batches: string[][] = [];

  for (
    let index = 0;
    index < uniqueSpeciesIds.length;
    index += normalizedBatchSize
  ) {
    batches.push(
      uniqueSpeciesIds.slice(index, index + normalizedBatchSize),
    );
  }

  return batches;
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

function taxonomyDisplayValue(value: string | null | undefined): string {
  const normalized = (stringValue(value) ?? "").trim().replace(/\s+/g, " ");
  return normalized || "Unclassified";
}

function taxonomyKey(value: string): string {
  const normalized = value.trim().toLocaleLowerCase().replace(/\s+/g, " ");
  return encodeURIComponent(normalized || "unclassified");
}

function taxonomyRankTitle(rank: TaxonomyTreeRank): string {
  switch (rank) {
    case "kingdom":
      return "Kingdom";
    case "phylum":
      return "Phylum";
    case "class":
      return "Class";
    case "order":
      return "Order";
    case "family":
      return "Family";
    case "genus":
      return "Genus";
    case "species":
      return "Species";
  }
}

function setLineageValue(
  lineage: Partial<SpeciesDictionaryTaxonomy>,
  rank: TaxonomyTreeRank,
  value: string,
): void {
  if (rank === "species") return;
  lineage[rank] = value;
}

function completeLineage(
  lineage: Partial<SpeciesDictionaryTaxonomy>,
): SpeciesDictionaryTaxonomy {
  return {
    kingdom: lineage.kingdom ?? null,
    phylum: lineage.phylum ?? null,
    class: lineage.class ?? null,
    order: lineage.order ?? null,
    family: lineage.family ?? null,
    genus: lineage.genus ?? null,
  };
}

function taxonomyTreeNodeSort(
  lhs: SpeciesDictionaryTreeNode,
  rhs: SpeciesDictionaryTreeNode,
): number {
  const rankDelta = taxonomyRankSortValue(lhs.rank) -
    taxonomyRankSortValue(rhs.rank);
  if (rankDelta !== 0) return rankDelta;
  const parentDelta = (stringValue(lhs.parent_id) ?? "").localeCompare(
    stringValue(rhs.parent_id) ?? "",
  );
  if (parentDelta !== 0) return parentDelta;
  const titleDelta = lhs.title.localeCompare(rhs.title);
  if (titleDelta !== 0) return titleDelta;
  return lhs.id.localeCompare(rhs.id);
}

function taxonomyRankSortValue(rank: TaxonomyTreeRank): number {
  return [
    "kingdom",
    "phylum",
    "class",
    "order",
    "family",
    "genus",
    "species",
  ].indexOf(rank);
}

function buildSpeciesDictionaryRegionSummaries(
  rows: SpeciesDictionaryRow[],
  firstImageBySpeciesId: Map<string, string>,
): SpeciesDictionaryRegionSummary[] {
  const summariesByKey = new Map<
    string,
    {
      title: string;
      count: number;
      referenceImageUrl: string | null;
    }
  >();

  for (const row of rows) {
    const title = normalizedRegionTitle(row.native_region);
    if (!title) continue;

    const key = normalizedRegionKey(title);
    if (!key) continue;

    const current = summariesByKey.get(key) ?? {
      title,
      count: 0,
      referenceImageUrl: null,
    };
    current.count += 1;
    current.referenceImageUrl ??= referenceImageUrlForRow(
      row,
      firstImageBySpeciesId,
    );
    summariesByKey.set(key, current);
  }

  return Array.from(summariesByKey.entries())
    .map(([key, summary]) => ({
      id: `region:${encodeURIComponent(key)}`,
      title: summary.title,
      count: summary.count,
      reference_image_url: summary.referenceImageUrl,
    }))
    .sort((lhs, rhs) => {
      const countDelta = rhs.count - lhs.count;
      return countDelta !== 0 ? countDelta : lhs.title.localeCompare(rhs.title);
    })
    .slice(0, SPECIES_DICTIONARY_OVERVIEW_REGION_LIMIT);
}

function buildSpeciesDictionaryGroupSummaries(
  rows: SpeciesDictionaryRow[],
  firstImageBySpeciesId: Map<string, string>,
): SpeciesDictionaryGroupSummary[] {
  return HIGH_LEVEL_SPECIES_GROUPS
    .map((group) => {
      const groupRows = rows.filter((row) =>
        rowMatchesHighLevelGroup(row, group.id)
      );
      return {
        id: group.id,
        title: group.title,
        count: groupRows.length,
        reference_image_url: representativeImageUrl(
          groupRows,
          firstImageBySpeciesId,
        ),
      };
    })
    .filter((group) => group.count > 0);
}

function rowMatchesHighLevelGroup(
  row: SpeciesDictionaryRow,
  groupId: string,
): boolean {
  const kingdom = normalizedTaxonomyValue(row.kingdom);
  const className = normalizedTaxonomyValue(row.class);
  const order = normalizedTaxonomyValue(row.order);
  const groupTags = new Set(
    (row.group_tags ?? []).map((tag) => normalizedTaxonomyValue(tag)),
  );

  switch (groupId) {
    case "plants":
      return kingdom === "plantae" || groupTags.has("plant");
    case "birds":
      return className === "aves" || groupTags.has("bird");
    case "insects":
      return className === "insecta" ||
        className === "entognatha" ||
        className === "arachnida" ||
        groupTags.has("insect") ||
        groupTags.has("arachnid");
    case "fungi":
      return kingdom === "fungi" ||
        groupTags.has("fungus") ||
        groupTags.has("fungi");
    case "mammals":
      return className === "mammalia" || groupTags.has("mammal");
    case "reptiles_amphibians":
      return className === "reptilia" ||
        className === "amphibia" ||
        order === "squamata" ||
        groupTags.has("reptile") ||
        groupTags.has("amphibian");
    default:
      return false;
  }
}

function normalizedTaxonomyValue(value: unknown): string {
  return stringValue(value)?.trim().toLocaleLowerCase() ?? "";
}

function representativeImageUrl(
  rows: SpeciesDictionaryRow[],
  firstImageBySpeciesId: Map<string, string>,
): string | null {
  for (const row of rows) {
    const url = referenceImageUrlForRow(row, firstImageBySpeciesId);
    if (url) return url;
  }
  return null;
}

function randomRepresentativeImageUrlPair(
  rows: SpeciesDictionaryRow[],
  firstImageBySpeciesId: Map<string, string>,
): [string | null, string | null] {
  const urls = uniqueRepresentativeImageUrls(rows, firstImageBySpeciesId);
  if (urls.length === 0) return [null, null];
  if (urls.length === 1) return [urls[0], urls[0]];

  const firstIndex = Math.floor(Math.random() * urls.length);
  const remainingUrls = urls.filter((_, index) => index !== firstIndex);
  const secondIndex = Math.floor(Math.random() * remainingUrls.length);
  return [urls[firstIndex], remainingUrls[secondIndex]];
}

function uniqueRepresentativeImageUrls(
  rows: SpeciesDictionaryRow[],
  firstImageBySpeciesId: Map<string, string>,
): string[] {
  const urls: string[] = [];
  const seenUrls = new Set<string>();

  for (const row of rows) {
    const url = referenceImageUrlForRow(row, firstImageBySpeciesId);
    if (!url || seenUrls.has(url)) continue;
    seenUrls.add(url);
    urls.push(url);
  }

  return urls;
}

function referenceImageUrlForRow(
  row: SpeciesDictionaryRow,
  firstImageBySpeciesId: Map<string, string>,
): string | null {
  return firstImageBySpeciesId.get(row.id) ??
    firstReferenceImageUrl(row.reference_image_url);
}

function normalizedOverview(value: unknown): string | null {
  const overview = stringValue(value)?.trim().replace(/\s+/g, " ");
  return overview || null;
}

function speciesDictionaryCreatedAtDescending(
  lhs: SpeciesDictionaryRow,
  rhs: SpeciesDictionaryRow,
): number {
  const lhsCreatedAt = stringValue(lhs.created_at) ?? "";
  const rhsCreatedAt = stringValue(rhs.created_at) ?? "";
  const createdAtDelta = rhsCreatedAt.localeCompare(lhsCreatedAt);
  return createdAtDelta !== 0
    ? createdAtDelta
    : (stringValue(rhs.id) ?? "").localeCompare(stringValue(lhs.id) ?? "");
}

function normalizeCatalogLimit(
  value: unknown,
): SpeciesDictionaryRequestResult | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return { error: "limit must be a number when provided.", status: 400 };
  }

  return { limit: Math.max(1, Math.min(100, Math.floor(value))) };
}

function normalizeOptionalCatalogQuery(
  value: unknown,
): SpeciesDictionaryRequestResult | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "string") {
    return { error: "query must be a string when provided.", status: 400 };
  }

  const query = value.trim().replace(/\s+/g, " ");
  if (!query) return undefined;
  if (query.length > 80) {
    return { error: "query is too long.", status: 400 };
  }

  return { query };
}

function normalizeOptionalCatalogCategory(
  value: unknown,
): SpeciesDictionaryRequestResult | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "string") {
    return { error: "category must be a string when provided.", status: 400 };
  }

  const category = value.trim();
  if (!category) return undefined;
  if (
    category === "all" || category === "region" ||
    category === "group" || category === "recently_added"
  ) {
    return { category };
  }

  return {
    error: "category must be all, region, group, or recently_added.",
    status: 400,
  };
}

function normalizeOptionalGroup(
  value: unknown,
): SpeciesDictionaryRequestResult | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "string") {
    return { error: "group must be a string when provided.", status: 400 };
  }

  const group = value.trim().toLocaleLowerCase();
  if (!group) return undefined;
  if (!highLevelSpeciesGroup(group)) {
    return { error: "group is not supported.", status: 400 };
  }

  return { group };
}

function highLevelSpeciesGroup(groupId: string) {
  return HIGH_LEVEL_SPECIES_GROUPS.find((group) => group.id === groupId);
}

function normalizeOptionalRegion(
  value: unknown,
): SpeciesDictionaryRequestResult | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "string") {
    return { error: "region must be a string when provided.", status: 400 };
  }

  const region = value.trim().replace(/\s+/g, " ");
  if (!region) return undefined;
  if (region.length > 80) {
    return { error: "region is too long.", status: 400 };
  }

  return { region };
}

function normalizedRegionTitle(
  value: string | null | undefined,
): string | null {
  const region = stringValue(value)?.trim().replace(/\s+/g, " ");
  if (region && isUnknownRegionTitle(region)) return null;
  if (region && /^[A-Za-z]{2}$/.test(region)) {
    return regionDisplayName(region.toUpperCase()) ?? region;
  }
  return region || null;
}

function isUnknownRegionTitle(region: string): boolean {
  const normalized = region
    .toLocaleLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
  return normalized === "unknown" ||
    normalized === "unspecified" ||
    normalized === "not available" ||
    normalized === "n a";
}

function regionDisplayName(regionCode: string): string | null {
  try {
    return new Intl.DisplayNames(["en"], { type: "region" }).of(regionCode) ??
      null;
  } catch {
    return null;
  }
}

function normalizedRegionKey(value: string | null | undefined): string {
  return normalizedRegionTitle(value)
    ?.toLocaleLowerCase()
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
    .replace(/\s+/g, " ") ?? "";
}

function regionKeysMatch(lhs: string, rhs: string): boolean {
  return lhs.length > 0 && rhs.length > 0 &&
    (lhs.includes(rhs) || rhs.includes(lhs));
}

function normalizeOptionalCatalogCursor(
  value: unknown,
): SpeciesDictionaryRequestResult | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "object" || Array.isArray(value)) {
    return { error: "cursor must be an object when provided.", status: 400 };
  }

  const cursor = value as Record<string, unknown>;
  const scientificNameValue = cursor.scientific_name ?? cursor.scientificName;
  const speciesIdValue = cursor.species_id ?? cursor.speciesId;
  const createdAtValue = cursor.created_at ?? cursor.createdAt;

  if (typeof scientificNameValue !== "string") {
    return { error: "cursor.scientific_name must be a string.", status: 400 };
  }
  if (typeof speciesIdValue !== "string" || !isUuid(speciesIdValue.trim())) {
    return { error: "cursor.species_id must be a valid UUID.", status: 400 };
  }

  const scientificName = scientificNameValue.trim().replace(/\s+/g, " ");
  if (!scientificName) {
    return { error: "cursor.scientific_name must be a string.", status: 400 };
  }
  if (scientificName.length > 160) {
    return { error: "cursor.scientific_name is too long.", status: 400 };
  }

  const normalizedCursor: SpeciesDictionaryCatalogCursor = {
    scientificName,
    speciesId: speciesIdValue.trim(),
  };

  if (createdAtValue !== undefined && createdAtValue !== null) {
    if (typeof createdAtValue !== "string" || !createdAtValue.trim()) {
      return { error: "cursor.created_at must be a string.", status: 400 };
    }
    normalizedCursor.createdAt = createdAtValue.trim();
  }

  return { cursor: normalizedCursor };
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
    value,
  );
}
