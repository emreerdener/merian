import { SupabaseClient } from "@supabase/supabase-js";

export type ExploreMentionSuggestionSource =
  | "post_author"
  | "thread"
  | "following";

export interface ExploreMentionSuggestionRow {
  user_id: string;
  username: string;
  display_name: string;
  avatar_url?: string | null;
  source: ExploreMentionSuggestionSource;
}

export async function fetchExploreMentionSuggestions(
  userId: string,
  postId: string,
  parentCommentId: string | null,
  query: string,
  limit: number,
  supabaseAdmin: SupabaseClient,
): Promise<ExploreMentionSuggestionRow[]> {
  const { data, error } = await supabaseAdmin.rpc(
    "get_explore_mention_suggestions",
    {
      self_id: userId,
      target_post_id: postId,
      target_parent_comment_id: parentCommentId,
      raw_query: query,
      max_limit: limit,
    },
  );

  if (error) {
    throw new Error(
      `Failed to fetch Explore mention suggestions: ${error.message}`,
    );
  }

  return (data ?? []) as ExploreMentionSuggestionRow[];
}
