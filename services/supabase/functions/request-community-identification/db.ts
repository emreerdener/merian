import { SupabaseClient } from "@supabase/supabase-js";
import { makeHttpError } from "../_shared/communityIdentification.ts";
import { buildExplorePostMediaRows } from "../_shared/explorePostMedia.ts";
import {
  fetchShareEligibleScan,
  prepareExplorePostMediaForPublication,
} from "../share-scan-to-explore/db.ts";
import type { AudioModerationQuota } from "../_shared/audioModeration.ts";

const COMMUNITY_IDENTIFICATION_PENDING_MESSAGE =
  "Wait for the community to identify this request before sharing it to Explore.";

export interface AtomicCommunityIdentificationPayload {
  p_scan_id: string;
  p_user_id: string;
  p_note: string | null;
  p_location_sharing: string | null;
  p_species_common_name: string | null;
  p_media_rows: ReturnType<typeof buildExplorePostMediaRows>;
  p_initial_taxon_node_id: string;
  p_taxonomy_version_id: string;
}

export interface CommunityRequestRow {
  id: string;
  post_id: string;
  scan_id: string;
  requested_by: string;
  requested_at: string;
  status: "needs_id" | "resolved" | "withdrawn";
  note?: string | null;
  initial_taxon_node_id?: string | null;
  taxonomy_version_id?: string | null;
  current_community_taxon_node_id?: string | null;
  resolved_taxon_node_id?: string | null;
  consensus_score?: number | null;
  consensus_identification_count: number;
  consensus_rank?: string | null;
}

export async function fetchInitialTaxonNodeId(
  speciesId: string | null,
  supabaseAdmin: SupabaseClient,
): Promise<{ id: string; taxonomyVersionId: string } | null> {
  if (!speciesId) return null;

  const { error: syncError } = await supabaseAdmin.rpc(
    "sync_taxon_nodes_from_species_dictionary",
  );
  if (syncError) {
    throw new Error(
      `Failed to synchronize taxonomy nodes: ${syncError.message}`,
    );
  }

  const { data: activeVersion, error: activeVersionError } = await supabaseAdmin
    .from("taxonomy_versions")
    .select("id")
    .eq("source", "merian_dictionary")
    .eq("status", "active")
    .order("activated_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (activeVersionError) {
    throw new Error(
      `Failed to resolve active taxonomy version: ${activeVersionError.message}`,
    );
  }

  const taxonomyVersionId = (activeVersion as { id?: string } | null)?.id;
  if (!taxonomyVersionId) return null;

  const { data, error } = await supabaseAdmin
    .from("taxon_nodes")
    .select("id,taxonomy_version_id")
    .eq("species_id", speciesId)
    .eq("taxonomy_version_id", taxonomyVersionId)
    .maybeSingle();

  if (error) {
    throw new Error(`Failed to resolve initial taxon node: ${error.message}`);
  }

  const row = data as { id?: string; taxonomy_version_id?: string } | null;
  if (!row?.id || !row.taxonomy_version_id) return null;
  return { id: row.id, taxonomyVersionId: row.taxonomy_version_id };
}

function isUuid(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value);
}

function isTimestamp(value: unknown): value is string {
  return typeof value === "string" &&
    value.length > 0 &&
    Number.isFinite(Date.parse(value));
}

function isCommunityRequestRow(value: unknown): value is CommunityRequestRow {
  if (value == null || typeof value !== "object" || Array.isArray(value)) {
    return false;
  }
  const row = value as Record<string, unknown>;
  return isUuid(row.id) &&
    isUuid(row.post_id) &&
    isUuid(row.scan_id) &&
    isUuid(row.requested_by) &&
    isTimestamp(row.requested_at) &&
    (
      row.status === "needs_id" ||
      row.status === "resolved" ||
      row.status === "withdrawn"
    ) &&
    isUuid(row.taxonomy_version_id) &&
    isUuid(row.initial_taxon_node_id) &&
    Number.isInteger(row.consensus_identification_count) &&
    (row.consensus_identification_count as number) >= 0;
}

export async function invokeAtomicCommunityIdentificationRequest(
  payload: AtomicCommunityIdentificationPayload,
  supabaseAdmin: SupabaseClient,
) {
  let result = await supabaseAdmin.rpc(
    "request_community_identification_atomically",
    payload,
  );
  if (
    result.error?.code === "P0001" &&
    result.error.message === COMMUNITY_IDENTIFICATION_PENDING_MESSAGE
  ) {
    // A same-scan request can commit while this transaction waits for the scan
    // lock. Retry the already-prepared relational call once; its active-request
    // branch returns the definitive row without repeating media moderation.
    result = await supabaseAdmin.rpc(
      "request_community_identification_atomically",
      payload,
    );
  }
  return result;
}

export async function requestCommunityIdentification(
  scanId: string,
  userId: string,
  note: string | null,
  locationSharing: string | null,
  speciesCommonName: string | null,
  restoredObjectKeys: string[],
  supabaseAdmin: SupabaseClient,
  moderationQuota: AudioModerationQuota,
): Promise<CommunityRequestRow> {
  const scan = await fetchShareEligibleScan(
    scanId,
    userId,
    restoredObjectKeys,
    [],
    [],
    supabaseAdmin,
  );

  const initialTaxonNode = await fetchInitialTaxonNodeId(
    scan.confirmed_species_id ?? scan.species_id,
    supabaseAdmin,
  );

  if (!initialTaxonNode) {
    throw makeHttpError(
      409,
      "This scan does not have enough taxonomy context to request community identification.",
    );
  }

  let mediaRows = buildExplorePostMediaRows(scan, undefined);
  mediaRows = await prepareExplorePostMediaForPublication(
    scan.id,
    userId,
    mediaRows,
    supabaseAdmin,
    moderationQuota,
  );

  const payload: AtomicCommunityIdentificationPayload = {
    p_scan_id: scanId,
    p_user_id: userId,
    p_note: note,
    p_location_sharing: locationSharing,
    p_species_common_name: speciesCommonName,
    p_media_rows: mediaRows,
    p_initial_taxon_node_id: initialTaxonNode.id,
    p_taxonomy_version_id: initialTaxonNode.taxonomyVersionId,
  };
  const result = await invokeAtomicCommunityIdentificationRequest(
    payload,
    supabaseAdmin,
  );
  const { data, error } = result;

  if (
    error ||
    !isCommunityRequestRow(data) ||
    data.scan_id !== scanId ||
    data.requested_by !== userId
  ) {
    throw new Error(
      `Failed to create community request atomically: ${
        error?.message ?? "Invalid database response"
      }`,
    );
  }

  return data;
}
