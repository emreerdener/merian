import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export interface ExploreAuthorProfileRow {
  author_user_id: string;
  author_name: string;
  author_username?: string | null;
  author_avatar_url?: string | null;
  author_is_pro?: boolean;
  species_count: number;
  current_streak: number;
  heatmap: unknown;
  awards: unknown[];
  published_post_count: number;
  follower_count: number;
  following_count: number;
  viewer_is_following: boolean;
  preview_posts: unknown[];
  field_trips?: unknown;
}

export async function fetchExploreAuthorProfile(
  userId: string,
  authorUserId: string,
  previewLimit: number,
  supabaseAdmin: SupabaseClient,
): Promise<ExploreAuthorProfileRow | null> {
  const { data, error } = await supabaseAdmin.rpc(
    "get_explore_author_profile",
    {
      self_id: userId,
      target_author_user_id: authorUserId,
      preview_limit: previewLimit,
    },
  );

  if (error) {
    throw new Error(`Failed to fetch Explore author profile: ${error.message}`);
  }

  const rows = (data ?? []) as ExploreAuthorProfileRow[];
  return rows[0] ?? null;
}
