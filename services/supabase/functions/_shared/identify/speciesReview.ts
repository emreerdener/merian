/** Strict server review envelope shared by acknowledgement and saved-row consumers. */
export interface ConfirmedSpeciesIdentity {
  version: 1;
  species_id: string;
  scientific_name: string;
  common_name: null;
  gbif_taxon_key: number;
}
export interface SpeciesReview {
  version: 1;
  revision: number;
  identity: ConfirmedSpeciesIdentity | null;
  user_identification_override: string | null;
  user_confirmed_identification: boolean;
  confirmed_species_id: string | null;
  user_review_state: "unreviewed" | "ai_confirmed" | "user_overridden";
}
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
function object(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}
function exact(value: Record<string, unknown>, keys: string[]): boolean {
  return Object.keys(value).length === keys.length &&
    keys.every((key) => Object.hasOwn(value, key));
}
function revision(value: unknown, max = 2147483647): value is number {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 &&
    value <= max;
}
function hasControl(value: string): boolean {
  return Array.from(value).some((character) => {
    const code = character.charCodeAt(0);
    return code < 32 || code === 127;
  });
}
export function isScientificName(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 && value.length <= 160 &&
    value === value.trim() && !hasControl(value);
}
export function parseSpeciesReview(value: unknown): SpeciesReview {
  const invalid = () => new Error("Species review receipt is invalid.");
  const review = object(value);
  if (
    !review ||
    !exact(review, [
      "version",
      "revision",
      "identity",
      "user_identification_override",
      "user_confirmed_identification",
      "confirmed_species_id",
      "user_review_state",
    ]) ||
    review.version !== 1 || !revision(review.revision) ||
    new TextEncoder().encode(JSON.stringify(review)).byteLength > 8192
  ) throw invalid();
  const state = review.user_review_state,
    override = review.user_identification_override;
  if (
    (state !== "unreviewed" && state !== "ai_confirmed" &&
      state !== "user_overridden") ||
    review.user_confirmed_identification !== (state === "ai_confirmed") ||
    (state === "user_overridden"
      ? typeof override !== "string" ||
        override.replace(/^ +| +$/g, "").length < 1 ||
        new TextEncoder().encode(override).byteLength > 1024 ||
        hasControl(override)
      : override !== null)
  ) throw invalid();
  let identity: ConfirmedSpeciesIdentity | null = null;
  if (review.identity !== null) {
    const entry = object(review.identity);
    if (
      !entry ||
      !exact(entry, [
        "version",
        "species_id",
        "scientific_name",
        "common_name",
        "gbif_taxon_key",
      ]) ||
      entry.version !== 1 || typeof entry.species_id !== "string" ||
      !uuid.test(entry.species_id) ||
      !isScientificName(entry.scientific_name) ||
      entry.common_name !== null || !revision(entry.gbif_taxon_key) ||
      entry.gbif_taxon_key < 1 || state === "unreviewed" ||
      review.revision === 0
    ) throw invalid();
    identity = {
      version: 1,
      species_id: entry.species_id,
      scientific_name: entry.scientific_name,
      common_name: null,
      gbif_taxon_key: entry.gbif_taxon_key,
    };
  }
  if (review.confirmed_species_id !== (identity?.species_id ?? null)) {
    throw invalid();
  }
  return {
    version: 1,
    revision: review.revision,
    identity,
    user_identification_override: typeof override === "string"
      ? override
      : null,
    user_confirmed_identification: state === "ai_confirmed",
    confirmed_species_id: identity?.species_id ?? null,
    user_review_state: state,
  };
}
