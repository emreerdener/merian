import { SupabaseClient } from "@supabase/supabase-js";
import { PublicHttpError, publicHttpError } from "../_shared/http.ts";

function makeHttpError(status: number, message: string): PublicHttpError {
  return publicHttpError(status, message);
}

export async function ensureOwnedExplorePost(
  postId: string,
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { data, error } = await supabaseAdmin
    .from("explore_posts")
    .select("id")
    .eq("id", postId)
    .eq("user_id", userId)
    .single();

  if (error || !data) {
    throw makeHttpError(404, "Explore post not found.");
  }
}

export async function unshareExplorePost(
  postId: string,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error } = await supabaseAdmin
    .from("explore_posts")
    .update({ unshared_at: new Date().toISOString() })
    .eq("id", postId)
    .is("unshared_at", null);

  if (error) {
    throw new Error(`Failed to unshare Explore post: ${error.message}`);
  }
}
