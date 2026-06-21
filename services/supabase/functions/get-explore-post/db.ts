import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import type { PetIdentification } from "../_shared/identify/types.ts";

export interface ExplorePostRow {
  post_id: string;
  scan_id: string;
  hero_image_url: string;
  shared_at: string;
  author_user_id: string;
  author_name: string;
  author_username?: string | null;
  author_avatar_url?: string | null;
  author_is_pro?: boolean;
  hashtags?: string[];
  species_common_name: string;
  species_scientific_name: string;
  pet_identification?: PetIdentification | null;
  public_location_label?: string | null;
  location_sharing: "open" | "obscured" | "private";
  time_of_day?: string | null;
  current_month?: number | null;
  weather_condition?: string | null;
  weather_temperature_f?: number | null;
  like_count: number;
  comment_count: number;
  viewer_has_liked: boolean;
  is_owned_by_viewer: boolean;
}

export async function fetchExplorePost(
  userId: string,
  postId: string,
  supabaseAdmin: SupabaseClient,
): Promise<ExplorePostRow | null> {
  const { data, error } = await supabaseAdmin.rpc("get_explore_post", {
    self_id: userId,
    target_post_id: postId,
  });

  if (error) {
    throw new Error(`Failed to fetch Explore post: ${error.message}`);
  }

  const rows = (data ?? []) as ExplorePostRow[];
  return rows[0] ?? null;
}
