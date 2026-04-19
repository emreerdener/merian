import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export async function fetchScanOwnership(
  scanId: string,
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<boolean> {
  const { data, error } = await supabaseAdmin
    .from("scans")
    .select("id")
    .eq("id", scanId)
    .eq("user_id", userId)
    .maybeSingle();

  if (error) {
    throw new Error(`fetchScanOwnership: ${error.message}`);
  }

  return data?.id != null;
}
