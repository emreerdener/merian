import { PublicHttpError, publicHttpError } from "../_shared/http.ts";

export const VALID_CAMPAIGN_ID = "beta_feedback_2026_06";

const VALID_USED_FEATURES = new Set([
  "identify_found_subject",
  "learn_after_scan",
  "build_collection",
  "share_to_explore",
  "browse_explore",
  "audio_or_description",
  "other",
]);

const VALID_MOST_USEFUL_FEATURES = new Set([
  "camera_identification",
  "insight_sheet",
  "species_dictionary",
  "scan_library_collections",
  "explore",
  "profile_progress",
  "not_sure_yet",
]);

const VALID_BUG_STATUSES = new Set(["no", "workaround", "blocked"]);

const MAX_LONG_TEXT_LENGTH = 4000;
const MAX_CONTACT_LENGTH = 320;
const MAX_METADATA_LENGTH = 160;

export type FeedbackSurveyInsert = {
  survey_campaign_id: string;
  satisfaction_rating: number;
  recommendation_rating: number;
  used_features: string[];
  most_useful_features: string[];
  bug_status: string;
  confusing_or_disappointing: string;
  wished_next: string;
  bug_details: string;
  may_follow_up: boolean;
  contact: string;
  app_version: string | null;
  build_number: string | null;
  platform: string;
  device_model: string | null;
  os_version: string | null;
  locale: string | null;
  timezone: string | null;
  raw_response: Record<string, unknown>;
};

export function parseFeedbackSurveyPayload(
  body: unknown,
): FeedbackSurveyInsert {
  if (!isRecord(body)) {
    throw badRequest("JSON body must be an object.");
  }

  const surveyCampaignId = requiredString(body, "survey_campaign_id", 80);
  if (surveyCampaignId !== VALID_CAMPAIGN_ID) {
    throw badRequest("Unknown survey campaign.");
  }

  const satisfactionRating = requiredInteger(body, "satisfaction_rating", 1, 5);
  const recommendationRating = requiredInteger(
    body,
    "recommendation_rating",
    0,
    10,
  );
  const usedFeatures = optionalStringArray(
    body,
    "used_features",
    VALID_USED_FEATURES,
    12,
  );
  const mostUsefulFeatures = optionalStringArray(
    body,
    "most_useful_features",
    VALID_MOST_USEFUL_FEATURES,
    12,
  );
  const bugStatus = requiredEnum(body, "bug_status", VALID_BUG_STATUSES);

  const confusingOrDisappointing = optionalString(
    body,
    "confusing_or_disappointing",
    MAX_LONG_TEXT_LENGTH,
  );
  const wishedNext = optionalString(body, "wished_next", MAX_LONG_TEXT_LENGTH);
  const bugDetails = optionalString(body, "bug_details", MAX_LONG_TEXT_LENGTH);
  const mayFollowUp = optionalBoolean(body, "may_follow_up");
  const contact = mayFollowUp
    ? optionalString(body, "contact", MAX_CONTACT_LENGTH)
    : "";

  return {
    survey_campaign_id: surveyCampaignId,
    satisfaction_rating: satisfactionRating,
    recommendation_rating: recommendationRating,
    used_features: usedFeatures,
    most_useful_features: mostUsefulFeatures,
    bug_status: bugStatus,
    confusing_or_disappointing: confusingOrDisappointing,
    wished_next: wishedNext,
    bug_details: bugDetails,
    may_follow_up: mayFollowUp,
    contact,
    app_version: optionalNullableString(
      body,
      "app_version",
      MAX_METADATA_LENGTH,
    ),
    build_number: optionalNullableString(
      body,
      "build_number",
      MAX_METADATA_LENGTH,
    ),
    platform: optionalString(body, "platform", MAX_METADATA_LENGTH) || "ios",
    device_model: optionalNullableString(
      body,
      "device_model",
      MAX_METADATA_LENGTH,
    ),
    os_version: optionalNullableString(body, "os_version", MAX_METADATA_LENGTH),
    locale: optionalNullableString(body, "locale", MAX_METADATA_LENGTH),
    timezone: optionalNullableString(body, "timezone", MAX_METADATA_LENGTH),
    raw_response: sanitizedRawResponse(body),
  };
}

function sanitizedRawResponse(
  body: Record<string, unknown>,
): Record<string, unknown> {
  const raw = { ...body };
  delete raw.user_id;
  return raw;
}

function requiredInteger(
  body: Record<string, unknown>,
  key: string,
  min: number,
  max: number,
): number {
  const value = body[key];
  if (
    !Number.isInteger(value) || (value as number) < min ||
    (value as number) > max
  ) {
    throw badRequest(`${key} must be an integer from ${min} to ${max}.`);
  }
  return value as number;
}

function requiredString(
  body: Record<string, unknown>,
  key: string,
  maxLength: number,
): string {
  const value = body[key];
  if (typeof value !== "string") {
    throw badRequest(`${key} must be a string.`);
  }
  const trimmed = value.trim();
  if (!trimmed) {
    throw badRequest(`${key} cannot be blank.`);
  }
  if (trimmed.length > maxLength) {
    throw badRequest(`${key} is too long.`);
  }
  return trimmed;
}

function optionalString(
  body: Record<string, unknown>,
  key: string,
  maxLength: number,
): string {
  const value = body[key];
  if (value == null) return "";
  if (typeof value !== "string") {
    throw badRequest(`${key} must be a string.`);
  }
  const trimmed = value.trim();
  if (trimmed.length > maxLength) {
    throw badRequest(`${key} is too long.`);
  }
  return trimmed;
}

function optionalNullableString(
  body: Record<string, unknown>,
  key: string,
  maxLength: number,
): string | null {
  const value = optionalString(body, key, maxLength);
  return value === "" ? null : value;
}

function optionalBoolean(body: Record<string, unknown>, key: string): boolean {
  const value = body[key];
  if (value == null) return false;
  if (typeof value !== "boolean") {
    throw badRequest(`${key} must be a boolean.`);
  }
  return value;
}

function requiredEnum(
  body: Record<string, unknown>,
  key: string,
  allowed: Set<string>,
): string {
  const value = body[key];
  if (typeof value !== "string" || !allowed.has(value)) {
    throw badRequest(`${key} is invalid.`);
  }
  return value;
}

function optionalStringArray(
  body: Record<string, unknown>,
  key: string,
  allowed: Set<string>,
  maxItems: number,
): string[] {
  const value = body[key];
  if (value == null) return [];
  if (!Array.isArray(value) || value.length > maxItems) {
    throw badRequest(`${key} must be an array with at most ${maxItems} items.`);
  }

  const normalized: string[] = [];
  const seen = new Set<string>();
  for (const item of value) {
    if (typeof item !== "string" || !allowed.has(item)) {
      throw badRequest(`${key} contains an invalid value.`);
    }
    if (!seen.has(item)) {
      seen.add(item);
      normalized.push(item);
    }
  }
  return normalized;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function badRequest(message: string): PublicHttpError {
  return publicHttpError(400, message);
}
