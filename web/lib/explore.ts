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

const stateCodes = new Set([
  "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "DC", "FL",
  "GA", "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME",
  "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH",
  "NJ", "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI",
  "SC", "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI",
  "WY"
]);

const stateNames = new Set([
  "alabama", "alaska", "arizona", "arkansas", "california", "colorado",
  "connecticut", "delaware", "district of columbia", "florida", "georgia",
  "hawaii", "idaho", "illinois", "indiana", "iowa", "kansas", "kentucky",
  "louisiana", "maine", "maryland", "massachusetts", "michigan",
  "minnesota", "mississippi", "missouri", "montana", "nebraska", "nevada",
  "new hampshire", "new jersey", "new mexico", "new york",
  "north carolina", "north dakota", "ohio", "oklahoma", "oregon",
  "pennsylvania", "rhode island", "south carolina", "south dakota",
  "tennessee", "texas", "utah", "vermont", "virginia", "washington",
  "west virginia", "wisconsin", "wyoming"
]);

const countryNames = new Set(["united states", "united states of america", "usa", "us", "canada"]);

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

function containsCoordinatePair(value: string) {
  const commaParts = value.split(",").map((part) => part.trim());
  if (commaParts.length === 2) {
    const latitude = Number(commaParts[0]);
    const longitude = Number(commaParts[1]);
    if (Number.isFinite(latitude) && Number.isFinite(longitude) && Math.abs(latitude) <= 90 && Math.abs(longitude) <= 180) {
      return true;
    }
  }

  const numbers = Array.from(value.matchAll(/[-+]?\d{1,3}\.\d{3,}/g), (match) => Number(match[0]));
  for (let index = 0; index < numbers.length - 1; index += 1) {
    if (Math.abs(numbers[index]) <= 90 && Math.abs(numbers[index + 1]) <= 180) {
      return true;
    }
  }

  return false;
}

function isCountry(value: string) {
  return countryNames.has(value.trim().toLowerCase());
}

function isStateLike(value: string) {
  const trimmed = value.trim();
  return stateCodes.has(trimmed.toUpperCase()) || stateNames.has(trimmed.toLowerCase());
}

function isPrivateLocationPart(value: string) {
  const trimmed = value.trim().toLowerCase();
  if (!trimmed || isCountry(trimmed) || containsCoordinatePair(trimmed)) {
    return true;
  }

  return [
    /^\d+/,
    /(street|avenue|road|boulevard|drive|lane|court|terrace|highway|route|suite|unit|apartment)/,
    /\b(st|ave|rd|blvd|dr|ln|ct|pl)\.?$/,
    /(gps|latitude|longitude|coordinate)/,
    /\b(park|trail|preserve|garden|campus|building|museum|hotel|restaurant|cafe|creek|beach|woods|forest|campground)\.?$/
  ].some((pattern) => pattern.test(trimmed));
}

function publicDisplayLocationLabel(location?: string | null) {
  const cleaned = location?.trim().replace(/\s+/g, " ");
  if (!cleaned || containsCoordinatePair(cleaned)) {
    return null;
  }

  const parts = cleaned.split(",").map((part) => part.trim()).filter(Boolean);
  if (parts.length === 0) {
    return null;
  }

  if (parts.length >= 2 && isCountry(parts[parts.length - 1])) {
    parts.pop();
  }

  const state = parts[parts.length - 1];
  if (!state || isPrivateLocationPart(state)) {
    return null;
  }

  if (parts.length >= 2) {
    const city = parts[parts.length - 2];
    return isPrivateLocationPart(city) ? (isStateLike(state) ? state : null) : `${city}, ${state}`;
  }

  return isStateLike(state) ? state : null;
}

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
    publicLocationLabel: publicDisplayLocationLabel(row.public_location_label),
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
