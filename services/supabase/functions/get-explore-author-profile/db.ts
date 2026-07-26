import { SupabaseClient } from "@supabase/supabase-js";

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

export interface ExploreOwnerPublicationSummaryRow {
  publication_intent_count: number;
  visible_post_count: number;
  recovery_needed_post_count: number;
  degraded_post_count: number;
  quarantined_post_count: number;
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

export async function fetchOwnedExplorePublicationSummary(
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<ExploreOwnerPublicationSummaryRow> {
  const { data, error } = await supabaseAdmin.rpc(
    "get_owned_explore_publication_summary",
    { self_id: userId },
  );

  if (error) {
    throw new Error(
      `Failed to fetch owned Explore publication summary: ${error.message}`,
    );
  }

  const rows = (data ?? []) as ExploreOwnerPublicationSummaryRow[];
  return rows[0] ?? {
    publication_intent_count: 0,
    visible_post_count: 0,
    recovery_needed_post_count: 0,
    degraded_post_count: 0,
    quarantined_post_count: 0,
  };
}
