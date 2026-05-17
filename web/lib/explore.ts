import { createServerSupabaseClient } from "./supabase";

type ExplorePostRow = {
  post_id: string;
  scan_id: string;
  hero_image_url: string;
  shared_at: string;
  author_user_id: string;
  author_name: string;
  author_avatar_url?: string | null;
  species_common_name: string;
  species_scientific_name: string;
  public_location_label?: string | null;
  time_of_day?: string | null;
  current_month?: number | null;
  weather_condition?: string | null;
  weather_temperature_f?: number | null;
  like_count: number;
  comment_count: number;
  viewer_has_liked: boolean;
  is_owned_by_viewer: boolean;
};

export type ExplorePost = {
  postId: string;
  scanId: string;
  heroImageUrl: string;
  sharedAt: string;
  authorUserId: string;
  authorName: string;
  authorAvatarUrl?: string | null;
  speciesCommonName: string;
  speciesScientificName: string;
  publicLocationLabel?: string | null;
  timeOfDay?: string | null;
  currentMonth?: number | null;
  weatherCondition?: string | null;
  weatherTemperatureF?: number | null;
  likeCount: number;
  commentCount: number;
  viewerHasLiked: boolean;
  isOwnedByViewer: boolean;
};

function mapExplorePost(row: ExplorePostRow): ExplorePost {
  return {
    postId: row.post_id,
    scanId: row.scan_id,
    heroImageUrl: row.hero_image_url,
    sharedAt: row.shared_at,
    authorUserId: row.author_user_id,
    authorName: row.author_name,
    authorAvatarUrl: row.author_avatar_url,
    speciesCommonName: row.species_common_name,
    speciesScientificName: row.species_scientific_name,
    publicLocationLabel: row.public_location_label,
    timeOfDay: row.time_of_day,
    currentMonth: row.current_month,
    weatherCondition: row.weather_condition,
    weatherTemperatureF: row.weather_temperature_f,
    likeCount: row.like_count,
    commentCount: row.comment_count,
    viewerHasLiked: row.viewer_has_liked,
    isOwnedByViewer: row.is_owned_by_viewer
  };
}

export async function fetchExplorePost(postId: string): Promise<ExplorePost | null> {
  const supabase = createServerSupabaseClient();

  if (!supabase) {
    return null;
  }

  const publicViewerId = process.env.SUPABASE_PUBLIC_VIEWER_ID ?? null;
  const { data, error } = await supabase.rpc("get_explore_post", {
    self_id: publicViewerId,
    target_post_id: postId
  });

  if (error) {
    throw new Error(`Failed to fetch Explore post: ${error.message}`);
  }

  const rows = (data ?? []) as ExplorePostRow[];
  const post = rows[0];

  return post ? mapExplorePost(post) : null;
}
