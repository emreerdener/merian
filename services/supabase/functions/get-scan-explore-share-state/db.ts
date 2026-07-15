import { SupabaseClient } from "@supabase/supabase-js";

export interface ExploreScanShareStateRow {
  scan_id: string;
  post_id?: string | null;
  shared_at?: string | null;
  community_request_id?: string | null;
  community_request_status?: "needs_id" | "resolved" | "withdrawn" | null;
  is_explore_feed_visible: boolean;
  location_sharing: "open" | "obscured" | "private";
}

export async function fetchExploreScanShareState(
  userId: string,
  scanId: string,
  supabaseAdmin: SupabaseClient,
): Promise<ExploreScanShareStateRow | null> {
  const { data, error } = await supabaseAdmin.rpc(
    "get_scan_explore_share_state",
    {
      self_id: userId,
      target_scan_id: scanId,
    },
  );

  if (error) {
    throw new Error(`Failed to fetch Explore share state: ${error.message}`);
  }

  const rows = (data ?? []) as ExploreScanShareStateRow[];
  return rows[0] ?? null;
}
