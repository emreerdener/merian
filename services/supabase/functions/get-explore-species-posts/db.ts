import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import type { ExplorePostMediaItem } from "../_shared/explore.ts";
import type { PetIdentification } from "../_shared/identify/types.ts";

export interface ExploreSpeciesPostRow {
  post_id: string;
  scan_id: string;
  hero_image_url: string;
  reference_thumbnail_url?: string | null;
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
  ranking_value?: number | null;
  media_items?: ExplorePostMediaItem[];
  image_quality_score: number | null;
}

export async function fetchExploreSpeciesPosts(
  userId: string,
  speciesId: string,
  limit: number,
  beforeImageQualityScore: number | null,
  beforeSharedAt: string | null,
  beforePostId: string | null,
  supabaseAdmin: SupabaseClient,
): Promise<ExploreSpeciesPostRow[]> {
  const { data, error } = await supabaseAdmin.rpc(
    "get_explore_species_posts",
    {
      self_id: userId,
      target_species_id: speciesId,
      max_limit: limit,
      before_image_quality_score: beforeImageQualityScore,
      before_shared_at: beforeSharedAt,
      before_post_id: beforePostId,
    },
  );

  if (error) {
    throw new Error(
      `Failed to fetch Explore species posts: ${error.message}`,
    );
  }

  return (data ?? []) as ExploreSpeciesPostRow[];
}
