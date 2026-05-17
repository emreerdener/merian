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

const stateCodeToName: Record<string, string> = {
  AL: "Alabama",
  AK: "Alaska",
  AZ: "Arizona",
  AR: "Arkansas",
  CA: "California",
  CO: "Colorado",
  CT: "Connecticut",
  DE: "Delaware",
  DC: "District of Columbia",
  FL: "Florida",
  GA: "Georgia",
  HI: "Hawaii",
  ID: "Idaho",
  IL: "Illinois",
  IN: "Indiana",
  IA: "Iowa",
  KS: "Kansas",
  KY: "Kentucky",
  LA: "Louisiana",
  ME: "Maine",
  MD: "Maryland",
  MA: "Massachusetts",
  MI: "Michigan",
  MN: "Minnesota",
  MS: "Mississippi",
  MO: "Missouri",
  MT: "Montana",
  NE: "Nebraska",
  NV: "Nevada",
  NH: "New Hampshire",
  NJ: "New Jersey",
  NM: "New Mexico",
  NY: "New York",
  NC: "North Carolina",
  ND: "North Dakota",
  OH: "Ohio",
  OK: "Oklahoma",
  OR: "Oregon",
  PA: "Pennsylvania",
  RI: "Rhode Island",
  SC: "South Carolina",
  SD: "South Dakota",
  TN: "Tennessee",
  TX: "Texas",
  UT: "Utah",
  VT: "Vermont",
  VA: "Virginia",
  WA: "Washington",
  WV: "West Virginia",
  WI: "Wisconsin",
  WY: "Wyoming",
};

const stateNameToCode = new Map(
  Object.entries(stateCodeToName).map((
    [code, name],
  ) => [name.toLowerCase(), code]),
);

const countryNames = new Set([
  "united states",
  "united states of america",
  "usa",
  "us",
  "canada",
]);

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
    if (
      Number.isFinite(latitude) && Number.isFinite(longitude) &&
      Math.abs(latitude) <= 90 && Math.abs(longitude) <= 180
    ) {
      return true;
    }
  }

  const numbers = Array.from(
    value.matchAll(/[-+]?\d{1,3}\.\d{3,}/g),
    (match) => Number(match[0]),
  );
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

function removingTrailingCountry(value: string) {
  const trimmed = value.trim();
  const lowercased = trimmed.toLowerCase();

  for (
    const country of Array.from(countryNames).sort((a, b) =>
      b.length - a.length
    )
  ) {
    if (lowercased === country) {
      return "";
    }

    const suffix = ` ${country}`;
    if (lowercased.endsWith(suffix)) {
      return trimmed.slice(0, -suffix.length).trim();
    }
  }

  return trimmed;
}

function normalizedState(value: string) {
  const trimmed = removingTrailingCountry(value);
  const uppercased = trimmed.toUpperCase();
  const zipMatch = trimmed.match(/^(.+?)\s+\d{5}(?:-\d{4})?$/);
  if (zipMatch) {
    const stateCandidate = zipMatch[1].trim();
    const stateCodeCandidate = stateCandidate.toUpperCase();
    const stateName = stateCodeToName[stateCodeCandidate];
    if (stateName) {
      return { code: stateCodeCandidate, name: stateName };
    }

    const stateCode = stateNameToCode.get(stateCandidate.toLowerCase());
    const stateNameForCode = stateCode ? stateCodeToName[stateCode] : null;
    if (stateCode && stateNameForCode) {
      return { code: stateCode, name: stateNameForCode };
    }
  }

  const stateName = stateCodeToName[uppercased];
  if (stateName) {
    return { code: uppercased, name: stateName };
  }

  const stateCode = stateNameToCode.get(trimmed.toLowerCase());
  const stateNameForCode = stateCode ? stateCodeToName[stateCode] : null;
  return stateCode && stateNameForCode
    ? { code: stateCode, name: stateNameForCode }
    : null;
}

function isStateLike(value: string) {
  return normalizedState(value) !== null;
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
    /\b(park|trail|preserve|garden|campus|building|museum|hotel|restaurant|cafe|creek|beach|woods|forest|campground|bay|harbor|harbour|marina|island|lake|pond|river|canal|inlet|lagoon|wetland|swamp|sound|cove|estuary)\.?$/,
  ].some((pattern) => pattern.test(trimmed));
}

function isSafeCityPart(value: string) {
  if (isPrivateLocationPart(value)) {
    return false;
  }

  const trimmed = value.trim().toLowerCase();
  return ![
    /\b(county|parish|borough|district|municipality|prefecture)\b/,
    /\b(province|region)\b$/,
  ].some((pattern) => pattern.test(trimmed));
}

function lastIndexWhere(
  values: string[],
  predicate: (value: string) => boolean,
) {
  for (let index = values.length - 1; index >= 0; index -= 1) {
    if (predicate(values[index])) {
      return index;
    }
  }

  return -1;
}

function publicDisplayLocationLabel(location?: string | null) {
  const cleaned = location?.trim().replace(/\s+/g, " ");
  if (!cleaned || containsCoordinatePair(cleaned)) {
    return null;
  }

  let parts = cleaned.split(",").map((part) => part.trim()).filter(Boolean);
  if (parts.length === 0) {
    return null;
  }

  parts = parts.filter((part) => !isCountry(part));

  const stateIndex = lastIndexWhere(parts, isStateLike);
  if (stateIndex >= 0) {
    const state = normalizedState(parts[stateIndex]);
    if (!state) {
      return null;
    }

    const city = parts.slice(0, stateIndex).reverse().find(isSafeCityPart);
    return city ? `${city}, ${state.code}` : state.name;
  }

  const state = parts[parts.length - 1];
  if (!state || isPrivateLocationPart(state)) {
    return null;
  }

  if (parts.length >= 2) {
    const city = parts.slice(0, -1).reverse().find(isSafeCityPart);
    return city ? `${city}, ${state}` : null;
  }

  return isSafeCityPart(state) ? state : null;
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
    isOwnedByViewer: row.is_owned_by_viewer,
  };
}

export async function fetchExplorePost(
  postId: string,
): Promise<ExplorePost | null> {
  const supabase = createServerSupabaseClient();

  if (!supabase) {
    return null;
  }

  const publicViewerId = process.env.SUPABASE_PUBLIC_VIEWER_ID ?? null;
  const { data, error } = await supabase.rpc("get_explore_post", {
    self_id: publicViewerId,
    target_post_id: postId,
  });

  if (error) {
    throw new Error(`Failed to fetch Explore post: ${error.message}`);
  }

  const rows = (data ?? []) as ExplorePostRow[];
  const post = rows[0];

  return post ? mapExplorePost(post) : null;
}
