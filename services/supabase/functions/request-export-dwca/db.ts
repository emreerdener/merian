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

/// Returns false when a concurrent request already inserted a pending job
/// (race condition TOCTOU), true when the job was successfully queued.
/// A partial unique index on export_jobs(user_id) WHERE status NOT IN
/// ('completed','failed') hardens this at the DB level; the 23505 error
/// code is the reliable fallback for when two requests slip through the
/// application-level check simultaneously.
export async function queueExportJob(
  userId: string,
  exportScope: string,
  includePreciseCoordinates: boolean,
  supabaseAdmin: SupabaseClient,
): Promise<boolean> {
  const { error } = await supabaseAdmin.from("export_jobs").insert({
    user_id: userId,
    export_scope: exportScope,
    include_precise_coordinates: includePreciseCoordinates,
    status: "pending",
  });

  if (error) {
    // Unique constraint violation — a concurrent request already queued a job.
    // Treat this as "already queued" (idempotent) rather than an internal error.
    if (error.code === "23505") return false;
    throw new Error(`Failed to queue export job: ${error.message}`);
  }

  return true;
}
