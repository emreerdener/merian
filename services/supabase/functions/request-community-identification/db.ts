import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { makeHttpError } from "../_shared/communityIdentification.ts";
import {
  fetchShareEligibleScan,
  upsertExplorePost,
} from "../share-scan-to-explore/db.ts";

export interface CommunityRequestRow {
  id: string;
  post_id: string;
  scan_id: string;
  requested_by: string;
  requested_at: string;
  status: "needs_id" | "resolved" | "withdrawn";
  note?: string | null;
  initial_taxon_node_id?: string | null;
  current_community_taxon_node_id?: string | null;
  resolved_taxon_node_id?: string | null;
  consensus_score?: number | null;
  consensus_identification_count: number;
  consensus_rank?: string | null;
}

async function fetchInitialTaxonNodeId(
  speciesId: string | null,
  supabaseAdmin: SupabaseClient,
): Promise<string | null> {
  if (!speciesId) return null;

  await supabaseAdmin.rpc("sync_taxon_nodes_from_species_dictionary");

  const { data, error } = await supabaseAdmin
    .from("taxon_nodes")
    .select("id")
    .eq("species_id", speciesId)
    .maybeSingle();

  if (error) {
    throw new Error(`Failed to resolve initial taxon node: ${error.message}`);
  }

  return (data as { id?: string } | null)?.id ?? null;
}

async function upsertCommunityExplorePost(
  scanId: string,
  userId: string,
  speciesCommonName: string | null,
  locationSharing: string,
  supabaseAdmin: SupabaseClient,
): Promise<{ id: string; shared_at: string }> {
  const { data: existing, error: existingError } = await supabaseAdmin
    .from("explore_posts")
    .select("id,shared_at,unshared_at")
    .eq("scan_id", scanId)
    .eq("user_id", userId)
    .maybeSingle();

  if (existingError) {
    throw new Error(`Failed to inspect Explore post: ${existingError.message}`);
  }

  if (!existing) {
    return await upsertExplorePost(
      scanId,
      userId,
      speciesCommonName,
      null,
      locationSharing,
      supabaseAdmin,
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

  return data as { id: string; shared_at: string };
}

export async function requestCommunityIdentification(
  scanId: string,
  userId: string,
  note: string | null,
  locationSharing: string | null,
  speciesCommonName: string | null,
  restoredObjectKeys: string[],
  supabaseAdmin: SupabaseClient,
): Promise<CommunityRequestRow> {
  const scan = await fetchShareEligibleScan(
    scanId,
    userId,
    restoredObjectKeys,
    supabaseAdmin,
  );

  const post = await upsertCommunityExplorePost(
    scanId,
    userId,
    speciesCommonName,
    locationSharing ?? scan.geoprivacy,
    supabaseAdmin,
  );

  const { data: existing, error: existingError } = await supabaseAdmin
    .from("explore_community_requests")
    .select(
      "id,post_id,scan_id,requested_by,requested_at,status,note,initial_taxon_node_id,current_community_taxon_node_id,resolved_taxon_node_id,consensus_score,consensus_identification_count,consensus_rank",
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

  const initialTaxonNodeId = await fetchInitialTaxonNodeId(
    scan.confirmed_species_id ?? scan.species_id,
    supabaseAdmin,
  );

  if (!initialTaxonNodeId) {
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
    initial_taxon_node_id: initialTaxonNodeId,
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
    "id,post_id,scan_id,requested_by,requested_at,status,note,initial_taxon_node_id,current_community_taxon_node_id,resolved_taxon_node_id,consensus_score,consensus_identification_count,consensus_rank";
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
      `Failed to create community request: ${error?.message ?? "Unknown error"}`,
    );
  }

  return data as CommunityRequestRow;
}
