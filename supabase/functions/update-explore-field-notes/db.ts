import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

function makeHttpError(status: number, message: string): Error & { status: number } {
  const error = new Error(message) as Error & { status: number };
  error.status = status;
  return error;
}

export async function updateExploreFieldNotes(
  postId: string,
  userId: string,
  fieldNotes: string | null,
  supabaseAdmin: SupabaseClient,
): Promise<{ id: string; field_notes: string | null }> {
  const { data, error } = await supabaseAdmin
    .from("explore_posts")
    .update({ field_notes: fieldNotes })
    .eq("id", postId)
    .eq("user_id", userId)
    .is("unshared_at", null)
    .select("id,field_notes")
    .single();

  if (error || !data) {
    throw makeHttpError(404, "Explore post not found.");
  }

  return data as { id: string; field_notes: string | null };
}
