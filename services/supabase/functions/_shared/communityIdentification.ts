import { PublicHttpError, publicHttpError } from "./http.ts";

export type CommunityIdentificationDisagreementMode =
  | "implicit_support"
  | "explicit_disagreement"
  | "maverick";

export type CommunityLocationSharing = "open" | "obscured" | "private";

export function makeHttpError(
  status: number,
  message: string,
): PublicHttpError {
  return publicHttpError(status, message);
}

export function normalizeCommunityNote(value: unknown): string | null {
  if (value == null) return null;
  if (typeof value !== "string") {
    throw makeHttpError(400, "note must be a string.");
  }

  const trimmed = value.trim();
  if (trimmed.length === 0) return null;
  if (trimmed.length > 1000) {
    throw makeHttpError(400, "note must be 1000 characters or fewer.");
  }

  return trimmed;
}

export function normalizeCommunityReasoning(value: unknown): string | null {
  if (value == null) return null;
  if (typeof value !== "string") {
    throw makeHttpError(400, "reasoning must be a string.");
  }

  const trimmed = value.trim();
  if (trimmed.length === 0) return null;
  if (trimmed.length > 1000) {
    throw makeHttpError(400, "reasoning must be 1000 characters or fewer.");
  }

  return trimmed;
}

export function normalizeCommunitySearchQuery(value: unknown): string {
  if (typeof value !== "string") {
    throw makeHttpError(400, "query must be a string.");
  }

  const trimmed = value.trim().replace(/\s+/g, " ");
  if (trimmed.length < 2) {
    throw makeHttpError(400, "query must be at least 2 characters.");
  }
  if (trimmed.length > 120) {
    throw makeHttpError(400, "query must be 120 characters or fewer.");
  }

  return trimmed;
}

export function normalizeCommunityLocationSharing(
  value: unknown,
): CommunityLocationSharing | null {
  if (value == null) return null;
  if (typeof value !== "string") {
    throw makeHttpError(400, "location_sharing must be a string.");
  }

  const normalized = value.trim().toLowerCase();
  if (
    normalized === "open" || normalized === "obscured" ||
    normalized === "private"
  ) {
    return normalized;
  }
  if (normalized === "hidden") return "private";

  throw makeHttpError(
    400,
    "location_sharing must be open, obscured, or private.",
  );
}

export function normalizeDisagreementMode(
  value: unknown,
): CommunityIdentificationDisagreementMode {
  if (value == null) return "implicit_support";
  if (typeof value !== "string") {
    throw makeHttpError(400, "disagreement_mode must be a string.");
  }

  const normalized = value.trim().toLowerCase();
  if (
    normalized === "implicit_support" ||
    normalized === "explicit_disagreement" ||
    normalized === "maverick"
  ) {
    return normalized;
  }

  throw makeHttpError(
    400,
    "disagreement_mode must be implicit_support, explicit_disagreement, or maverick.",
  );
}

export function normalizeCommunityBoolean(
  value: unknown,
  fieldName: string,
  fallback = false,
): boolean {
  if (value == null) return fallback;
  if (typeof value === "boolean") return value;
  throw makeHttpError(400, `${fieldName} must be a boolean.`);
}

/** SQL owns qualification. Do not synthesize it from a tier or raw score. */
export function assertCommunityConfidenceProjection(
  value: unknown,
): asserts value is Record<string, unknown> & {
  ai_confidence_qualified: boolean;
  author_user_id: string;
  post_id: string;
} {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("community_confidence_projection_invalid");
  }
  const row = value as Record<string, unknown>;
  if (
    typeof row.ai_confidence_qualified !== "boolean" ||
    typeof row.author_user_id !== "string" || typeof row.post_id !== "string" ||
    !Array.isArray(row.suggested_taxa) || row.suggested_taxa.length > 6 ||
    "identification_provenance" in row
  ) {
    throw new Error("community_confidence_projection_invalid");
  }
  if (
    !row.ai_confidence_qualified &&
    row.suggested_taxa.some((item: unknown) =>
      item === null || typeof item !== "object" || Array.isArray(item) ||
      (item as Record<string, unknown>).confidence_score !== null
    )
  ) throw new Error("community_confidence_projection_invalid");
}
