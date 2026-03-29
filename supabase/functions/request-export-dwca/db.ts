// deno-lint-ignore no-import-prefix
import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export async function hasRecentExportJob(
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<boolean> {
  const { data: recentJobs, error: selectError } = await supabaseAdmin
    .from("export_jobs")
    .select("created_at")
    .eq("user_id", userId)
    .gte("created_at", new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString())
    .limit(1);

  if (selectError) {
    throw new Error(`Failed to verify rate limit: ${selectError.message}`);
  }

  return recentJobs !== null && recentJobs.length > 0;
}

export async function queueExportJob(
  userId: string,
  exportScope: string,
  includePreciseCoordinates: boolean,
  supabaseAdmin: SupabaseClient,
) {
  const { error } = await supabaseAdmin.from("export_jobs").insert({
    user_id: userId,
    export_scope: exportScope,
    include_precise_coordinates: includePreciseCoordinates,
    status: "pending",
  });

  if (error) {
    throw new Error(`Failed to queue export job: ${error.message}`);
  }
}
