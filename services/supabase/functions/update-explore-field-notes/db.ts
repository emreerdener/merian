import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

function makeHttpError(
  status: number,
  message: string,
): Error & { status: number } {
  const error = new Error(message) as Error & { status: number };
  error.status = status;
  return error;
}

export async function updateExploreFieldNotes(
  postId: string,
  userId: string,
  fieldNotes: string | null,
  hashtags: string[] | undefined,
  speciesCommonName: string | null | undefined,
  supabaseAdmin: SupabaseClient,
): Promise<{
  id: string;
  field_notes: string | null;
  species_common_name: string | null;
  hashtags?: string[];
}> {
  const updates: {
    field_notes: string | null;
    species_common_name?: string | null;
  } = {
    field_notes: fieldNotes,
  };
  if (speciesCommonName !== undefined) {
    updates.species_common_name = speciesCommonName;
  }

  const { data, error } = await supabaseAdmin
    .from("explore_posts")
    .update(updates)
    .eq("id", postId)
    .eq("user_id", userId)
    .is("unshared_at", null)
    .select("id,field_notes,species_common_name")
    .single();

  if (error || !data) {
    throw makeHttpError(404, "Explore post not found.");
  }

  if (hashtags !== undefined) {
    const { error: deleteError } = await supabaseAdmin
      .from("explore_post_hashtags")
      .delete()
      .eq("post_id", postId);

    if (deleteError) {
      throw new Error(
        `Failed to clear Explore post hashtags: ${deleteError.message}`,
      );
    }

    if (hashtags.length > 0) {
      const { error: insertError } = await supabaseAdmin
        .from("explore_post_hashtags")
        .insert(hashtags.map((tag) => ({ post_id: postId, tag })));

      if (insertError) {
        throw new Error(
          `Failed to save Explore post hashtags: ${insertError.message}`,
        );
      }
    }
  }

  return {
    ...(data as {
      id: string;
      field_notes: string | null;
      species_common_name: string | null;
    }),
    hashtags,
  };
}
