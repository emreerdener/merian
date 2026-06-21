export type ExploreCoordinateVisibility = "exact" | "obscured";
export type ExploreMapSpeciesCategory =
  | "plants"
  | "fungi"
  | "birds"
  | "mammals"
  | "reptiles"
  | "amphibians"
  | "fish"
  | "insects"
  | "arachnids"
  | "other";

export interface ExploreMapPostRow {
  post_id: string;
  scan_id: string;
  latitude: number;
  longitude: number;
  coordinate_visibility: ExploreCoordinateVisibility;
  hero_image_url: string;
  shared_at: string;
  author_user_id: string;
  author_name: string;
  author_username?: string | null;
  author_avatar_url?: string | null;
  author_is_pro?: boolean;
  species_common_name: string;
  species_scientific_name: string;
  taxonomy_kingdom?: string | null;
  taxonomy_class?: string | null;
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

export interface ExploreMapCategoryCount {
  category: ExploreMapSpeciesCategory;
  count: number;
}

export interface ExploreMapCluster {
  id: string;
  latitude: number;
  longitude: number;
  post_count: number;
}

export interface ExploreMapPointsPayload {
  mode: "clusters" | "posts";
  visible_count: number;
  category_counts: ExploreMapCategoryCount[];
  clusters: ExploreMapCluster[];
  posts: ExploreMapPostRow[];
}
