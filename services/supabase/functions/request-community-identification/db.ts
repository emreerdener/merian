import { SupabaseClient } from "@supabase/supabase-js";
import { makeHttpError } from "../_shared/communityIdentification.ts";
import { buildExplorePostMediaRows } from "../_shared/explorePostMedia.ts";
import {
  fetchShareEligibleScan,
  prepareExplorePostMediaForPublication,
  upsertExplorePost,
} from "../share-scan-to-explore/db.ts";
import type { ShareEligibleScanRow } from "../share-scan-to-explore/db.ts";
import type { AudioModerationQuota } from "../_shared/audioModeration.ts";

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

async function fetchInitialTaxonNodeId(
  speciesId: string | null,
  supabaseAdmin: SupabaseClient,
): Promise<{ id: string; taxonomyVersionId: string } | null> {
  if (!speciesId) return null;

  await supabaseAdmin.rpc("sync_taxon_nodes_from_species_dictionary");

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

async function upsertCommunityExplorePost(
  scan: ShareEligibleScanRow,
  userId: string,
  speciesCommonName: string | null,
  locationSharing: string,
  supabaseAdmin: SupabaseClient,
  moderationQuota: AudioModerationQuota,
): Promise<{ id: string; shared_at: string }> {
  const { data: existing, error: existingError } = await supabaseAdmin
    .from("explore_posts")
    .select("id,shared_at,unshared_at")
    .eq("scan_id", scan.id)
    .eq("user_id", userId)
    .maybeSingle();

  if (existingError) {
    throw new Error(`Failed to inspect Explore post: ${existingError.message}`);
  }

  if (!existing) {
    return await upsertExplorePost(
      scan,
      userId,
      speciesCommonName,
      null,
      locationSharing,
      undefined,
      supabaseAdmin,
      moderationQuota,
    );
  }

  const updates: Record<string, string | null> = {
    location_sharing: locationSharing,
    unshared_at: null,
  };
  if (speciesCommonName) {
    updates.species_common_name = speciesCommonName;
  }
  if ((existing as { unshared_at?: string | null }).unshared_at != null) {
    updates.shared_at = new Date().toISOString();
  }

  const { data, error } = await supabaseAdmin
    .from("explore_posts")
    .update(updates)
    .eq("id", (existing as { id: string }).id)
    .select("id,shared_at")
    .single();

  if (error || !data) {
    throw new Error(
      `Failed to update Explore post for community request: ${
        error?.message ?? "Unknown error"
      }`,
    );
  }

  const post = data as { id: string; shared_at: string };
  let mediaRows = buildExplorePostMediaRows(scan, undefined);
  mediaRows = await prepareExplorePostMediaForPublication(
    scan.id,
    userId,
    mediaRows,
    supabaseAdmin,
    moderationQuota,
  );
  await replaceCommunityExplorePostMediaRows(post.id, mediaRows, supabaseAdmin);

  return post;
}

async function replaceCommunityExplorePostMediaRows(
  postId: string,
  rows: ReturnType<typeof buildExplorePostMediaRows>,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error: deleteError } = await supabaseAdmin
    .from("explore_post_media")
    .delete()
    .eq("post_id", postId);

  if (deleteError) {
    throw new Error(
      `Failed to clear Explore post media: ${deleteError.message}`,
    );
  }

  const { error: insertError } = await supabaseAdmin
    .from("explore_post_media")
    .insert(rows.map((row) => ({ ...row, post_id: postId })));

  if (insertError) {
    throw new Error(
      `Failed to save Explore post media: ${insertError.message}`,
    );
  }
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

  const { error: repairError } = await supabaseAdmin
    .from("explore_community_requests")
    .update({
      requested_by: userId,
      updated_at: new Date().toISOString(),
    })
    .eq("scan_id", scanId)
    .neq("requested_by", userId);

  if (repairError) {
    throw new Error(
      `Failed to repair community request ownership: ${repairError.message}`,
    );
  }

  const post = await upsertCommunityExplorePost(
    scan,
    userId,
    speciesCommonName,
    locationSharing ?? scan.geoprivacy,
    supabaseAdmin,
    moderationQuota,
  );

  const { data: existing, error: existingError } = await supabaseAdmin
    .from("explore_community_requests")
    .select(
      "id,post_id,scan_id,requested_by,requested_at,status,note,initial_taxon_node_id,taxonomy_version_id,current_community_taxon_node_id,resolved_taxon_node_id,consensus_score,consensus_identification_count,consensus_rank",
    )
    .eq("post_id", post.id)
    .maybeSingle();

  if (existingError) {
    throw new Error(
      `Failed to inspect community request: ${existingError.message}`,
    );
  }

  if (existing && (existing as CommunityRequestRow).status !== "withdrawn") {
    return existing as CommunityRequestRow;
  }

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

  const payload = {
    post_id: post.id,
    scan_id: scanId,
    requested_by: userId,
    note,
    status: "needs_id",
    initial_taxon_node_id: initialTaxonNode.id,
    taxonomy_version_id: initialTaxonNode.taxonomyVersionId,
    current_community_taxon_node_id: null,
    resolved_taxon_node_id: null,
    resolved_observation_taxon_node_id: null,
    consensus_score: null,
    consensus_identification_count: 0,
    consensus_rank: null,
    resolved_at: null,
    withdrawn_at: null,
    updated_at: new Date().toISOString(),
  };

  const selection =
    "id,post_id,scan_id,requested_by,requested_at,status,note,initial_taxon_node_id,taxonomy_version_id,current_community_taxon_node_id,resolved_taxon_node_id,consensus_score,consensus_identification_count,consensus_rank";
  const { data, error } = existing
    ? await supabaseAdmin
      .from("explore_community_requests")
      .update(payload)
      .eq("post_id", post.id)
      .select(selection)
      .single()
    : await supabaseAdmin
      .from("explore_community_requests")
      .insert(payload)
      .select(selection)
      .single();

  if (error || !data) {
    throw new Error(
      `Failed to create community request: ${
        error?.message ?? "Unknown error"
      }`,
    );
  }

  return data as CommunityRequestRow;
}
