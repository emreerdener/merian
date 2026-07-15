import { normalizeCursorTimestamp, requireUuid } from "../_shared/explore.ts";

export interface ExploreSpeciesPostsRequest {
  speciesId: string;
  limit: number;
  beforeImageQualityScore: number | null;
  beforeSharedAt: string | null;
  beforePostId: string | null;
}

function makeHttpError(
  status: number,
  message: string,
): Error & { status: number } {
  const error = new Error(message) as Error & { status: number };
  error.status = status;
  return error;
}

export function normalizeImageQualityCursor(
  rawValue: unknown,
): number | null {
  if (rawValue == null) return null;
  if (
    typeof rawValue !== "number" || !Number.isInteger(rawValue) ||
    rawValue < 0 || rawValue > 100
  ) {
    throw makeHttpError(
      400,
      "before_image_quality_score must be an integer from 0 to 100.",
    );
  }
  return rawValue;
}

export function normalizeSpeciesPostsLimit(rawValue: unknown): number {
  if (rawValue == null) return 30;
  if (
    typeof rawValue !== "number" || !Number.isInteger(rawValue) ||
    rawValue < 1 || rawValue > 100
  ) {
    throw makeHttpError(400, "limit must be an integer from 1 to 100.");
  }
  return rawValue;
}

export function parseExploreSpeciesPostsRequest(
  body: Record<string, unknown>,
): ExploreSpeciesPostsRequest {
  const speciesId = requireUuid(body.species_id, "species_id");
  const limit = normalizeSpeciesPostsLimit(body.limit);
  const beforeImageQualityScore = normalizeImageQualityCursor(
    body.before_image_quality_score,
  );
  const beforeSharedAt = normalizeCursorTimestamp(
    body.before_shared_at,
    "before_shared_at",
  );
  const beforePostId = body.before_post_id == null
    ? null
    : requireUuid(body.before_post_id, "before_post_id");

  if ((beforeSharedAt == null) !== (beforePostId == null)) {
    throw makeHttpError(
      400,
      "before_shared_at and before_post_id must be provided together.",
    );
  }
  if (beforeSharedAt == null && beforeImageQualityScore != null) {
    throw makeHttpError(
      400,
      "before_image_quality_score requires before_shared_at and before_post_id.",
    );
  }

  return {
    speciesId,
    limit,
    beforeImageQualityScore,
    beforeSharedAt,
    beforePostId,
  };
}
