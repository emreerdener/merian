import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export interface ExploreScanShareStateRow {
  scan_id: string;
  post_id?: string | null;
  shared_at?: string | null;
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
