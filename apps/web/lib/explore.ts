import { createServerSupabaseClient } from "./supabase";

type SupabaseRpcError = {
  code?: string;
  details?: string;
  hint?: string;
  message?: string;
};

type ExplorePostRow = {
  post_id: string;
  scan_id: string;
  hero_image_url: string;
  shared_at: string;
  author_user_id: string;
  author_name: string;
  author_username?: string | null;
  author_avatar_url?: string | null;
  author_is_pro?: boolean | null;
  hashtags?: string[] | null;
  species_common_name: string;
  species_scientific_name: string;
  pet_identification?: unknown;
  public_location_label?: string | null;
  location_sharing?: "open" | "obscured" | "private" | null;
  time_of_day?: string | null;
  current_month?: number | null;
  weather_condition?: string | null;
  weather_temperature_f?: number | null;
  like_count: number;
  comment_count: number;
  viewer_has_liked: boolean;
  is_owned_by_viewer: boolean;
};

type ExplorePostDetailRow = {
  post_id: string;
  field_notes?: string | null;
  location_sharing?: "open" | "obscured" | "private" | null;
  hashtags?: string[] | null;
  species_dictionary_id?: string | null;
  alternative_common_names?: string[] | null;
  taxonomy_kingdom?: string | null;
  taxonomy_phylum?: string | null;
  taxonomy_class?: string | null;
  taxonomy_order?: string | null;
  taxonomy_family?: string | null;
  taxonomy_genus?: string | null;
  ai_reasoning?: string | null;
  habitat_description?: string | null;
  gbif_taxon_key?: number | null;
  iucn_red_list_status?: string | null;
  hazard_type?: string | null;
  wikipedia_url?: string | null;
  reference_image_url?: string | null;
  wikipedia_overview?: string | null;
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
  authorUsername?: string | null;
  authorAvatarUrl?: string | null;
  authorIsPro: boolean;
  hashtags: string[];
  speciesCommonName: string;
  speciesScientificName: string;
  publicLocationLabel?: string | null;
  locationSharing?: "open" | "obscured" | "private" | null;
  timeOfDay?: string | null;
  currentMonth?: number | null;
  weatherCondition?: string | null;
  weatherTemperatureF?: number | null;
  likeCount: number;
  commentCount: number;
  viewerHasLiked: boolean;
  isOwnedByViewer: boolean;
};

export type ExploreReferenceImage = {
  url: string;
  source: "Merian" | "Wikipedia" | "GBIF";
};

export type ExplorePostDetail = {
  postId: string;
  fieldNotes?: string | null;
  locationSharing?: "open" | "obscured" | "private" | null;
  hashtags: string[];
  speciesDictionaryId?: string | null;
  alternativeCommonNames: string[];
  taxonomy: Array<{ label: string; value: string }>;
  aiReasoning?: string | null;
  habitatDescription?: string | null;
  gbifTaxonKey?: number | null;
  iucnRedListStatus?: string | null;
  hazardType?: string | null;
  wikipediaUrl?: string | null;
  referenceImages: ExploreReferenceImage[];
  wikipediaOverview?: string | null;
};

export type ExplorePostPageData = {
  post: ExplorePost;
  detail: ExplorePostDetail | null;
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

function trimmedString(value?: string | null) {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}

function normalizedStringList(values?: string[] | null) {
  const seen = new Set<string>();
  const normalized: string[] = [];

  for (const value of values ?? []) {
    const trimmed = trimmedString(value);
    if (!trimmed || seen.has(trimmed.toLowerCase())) {
      continue;
    }

    seen.add(trimmed.toLowerCase());
    normalized.push(trimmed);
  }

  return normalized;
}

function referenceImageSource(urlString: string, index: number, wikipediaUrl?: string | null): ExploreReferenceImage["source"] {
  let host = "";
  try {
    host = new URL(urlString).host.toLowerCase();
  } catch {
    return "GBIF";
  }

  if (host === "media.merian.app" || host.endsWith(".merian.app")) {
    return "Merian";
  }

  if (host.includes("wikipedia") || host.includes("wikimedia")) {
    return "Wikipedia";
  }

  if (index === 0 && trimmedString(wikipediaUrl)) {
    return "Wikipedia";
  }

  return "GBIF";
}

function referenceImagesFrom(value?: string | null, wikipediaUrl?: string | null) {
  const seen = new Set<string>();
  const urls = (value ?? "")
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean);

  return urls.flatMap((url, index) => {
    if (seen.has(url)) {
      return [];
    }

    seen.add(url);
    return [{
      url,
      source: referenceImageSource(url, index, wikipediaUrl),
    }];
  });
}

function taxonomyRows(row: ExplorePostDetailRow) {
  const values: Array<[string, string | null | undefined]> = [
    ["Kingdom", row.taxonomy_kingdom],
    ["Phylum", row.taxonomy_phylum],
    ["Class", row.taxonomy_class],
    ["Order", row.taxonomy_order],
    ["Family", row.taxonomy_family],
    ["Genus", row.taxonomy_genus],
  ];

  return values.flatMap(([label, value]) => {
    const trimmed = trimmedString(value);
    return trimmed ? [{ label, value: trimmed }] : [];
  });
}

function mapExplorePost(row: ExplorePostRow): ExplorePost {
  return {
    postId: row.post_id,
    scanId: row.scan_id,
    heroImageUrl: row.hero_image_url,
    sharedAt: row.shared_at,
    authorUserId: row.author_user_id,
    authorName: row.author_name,
    authorUsername: row.author_username,
    authorAvatarUrl: row.author_avatar_url,
    authorIsPro: row.author_is_pro === true,
    hashtags: normalizedStringList(row.hashtags),
    speciesCommonName: row.species_common_name,
    speciesScientificName: row.species_scientific_name,
    publicLocationLabel: publicDisplayLocationLabel(row.public_location_label),
    locationSharing: row.location_sharing,
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

function mapExplorePostDetail(row: ExplorePostDetailRow): ExplorePostDetail {
  return {
    postId: row.post_id,
    fieldNotes: trimmedString(row.field_notes),
    locationSharing: row.location_sharing,
    hashtags: normalizedStringList(row.hashtags),
    speciesDictionaryId: row.species_dictionary_id,
    alternativeCommonNames: normalizedStringList(row.alternative_common_names),
    taxonomy: taxonomyRows(row),
    aiReasoning: trimmedString(row.ai_reasoning),
    habitatDescription: trimmedString(row.habitat_description),
    gbifTaxonKey: row.gbif_taxon_key,
    iucnRedListStatus: trimmedString(row.iucn_red_list_status),
    hazardType: trimmedString(row.hazard_type),
    wikipediaUrl: trimmedString(row.wikipedia_url),
    referenceImages: referenceImagesFrom(
      row.reference_image_url,
      row.wikipedia_url,
    ),
    wikipediaOverview: trimmedString(row.wikipedia_overview),
  };
}

function logExplorePostRpcError(
  event: string,
  postId: string,
  error: SupabaseRpcError,
) {
  console.error(event, {
    post_id: postId,
    code: error.code,
    message: error.message,
    details: error.details,
    hint: error.hint,
  });
}

function supabaseUrlHost() {
  const url = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
  if (!url) {
    return null;
  }

  try {
    return new URL(url).host;
  } catch {
    return "invalid";
  }
}

async function fetchExplorePostDetail(
  postId: string,
): Promise<ExplorePostDetail | null> {
  const supabase = createServerSupabaseClient();

  if (!supabase) {
    return null;
  }

  const publicViewerId = process.env.SUPABASE_PUBLIC_VIEWER_ID ?? null;
  const { data, error } = await supabase.rpc("get_explore_post_detail", {
    self_id: publicViewerId,
    target_post_id: postId,
  });

  if (error) {
    logExplorePostRpcError("explore_post_detail_rpc_failed", postId, error);
    throw new Error(`Failed to fetch Explore post detail: ${error.message}`);
  }

  const rows = (data ?? []) as ExplorePostDetailRow[];
  const detail = rows[0];

  return detail ? mapExplorePostDetail(detail) : null;
}

export async function fetchExplorePost(
  postId: string,
): Promise<ExplorePost | null> {
  const supabase = createServerSupabaseClient();

  if (!supabase) {
    console.error("explore_post_supabase_config_missing", {
      post_id: postId,
    });
    return null;
  }

  const publicViewerId = process.env.SUPABASE_PUBLIC_VIEWER_ID ?? null;
  const { data, error } = await supabase.rpc("get_explore_post", {
    self_id: publicViewerId,
    target_post_id: postId,
  });

  if (error) {
    logExplorePostRpcError("explore_post_rpc_failed", postId, error);
    throw new Error(`Failed to fetch Explore post: ${error.message}`);
  }

  const rows = (data ?? []) as ExplorePostRow[];
  const post = rows[0];

  if (!post) {
    console.warn("explore_post_rpc_empty", {
      post_id: postId,
      supabase_host: supabaseUrlHost(),
    });
    return null;
  }

  try {
    return mapExplorePost(post);
  } catch (error) {
    console.error("explore_post_map_failed", {
      post_id: postId,
      error: error instanceof Error ? error.message : String(error),
    });
    throw error;
  }
}

export async function fetchExplorePostPage(
  postId: string,
): Promise<ExplorePostPageData | null> {
  const post = await fetchExplorePost(postId);

  if (!post) {
    return null;
  }

  let detail: ExplorePostDetail | null = null;
  try {
    detail = await fetchExplorePostDetail(postId);
  } catch (error) {
    console.warn("explore_post_detail_fetch_failed", {
      post_id: postId,
      error: error instanceof Error ? error.message : String(error),
    });
  }

  return { post, detail };
}
