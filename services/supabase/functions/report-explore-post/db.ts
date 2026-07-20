import { SupabaseClient } from "@supabase/supabase-js";

function makeHttpError(
  status: number,
  message: string,
): Error & { status: number } {
  const error = new Error(message) as Error & { status: number };
  error.status = status;
  return error;
}

export async function fetchReportablePost(
  postId: string,
  reporterUserId: string,
  supabaseAdmin: SupabaseClient,
): Promise<{ postAuthorUserId: string }> {
  const { data, error } = await supabaseAdmin
    .from("explore_posts")
    .select("id,user_id,unshared_at,moderated_at")
    .eq("id", postId)
    .single();
  if (
    error || !data || data.unshared_at != null || data.moderated_at != null
  ) {
    throw makeHttpError(404, "Explore post not found.");
  }
  if (data.user_id === reporterUserId) {
    throw makeHttpError(400, "You cannot report your own post.");
  }
  return { postAuthorUserId: data.user_id };
}

export async function upsertExplorePostReport(
  input: {
    postId: string;
    reporterUserId: string;
    postAuthorUserId: string;
    reason: string;
    details: string | null;
  },
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error } = await supabaseAdmin
    .from("explore_post_reports")
    .upsert({
      post_id: input.postId,
      reporter_user_id: input.reporterUserId,
      post_author_user_id: input.postAuthorUserId,
      reason: input.reason,
      details: input.details,
      updated_at: new Date().toISOString(),
    }, {
      onConflict: "post_id,reporter_user_id",
      ignoreDuplicates: false,
    });
  if (error) {
    throw new Error(`Failed to save Explore post report: ${error.message}`);
  }
}
