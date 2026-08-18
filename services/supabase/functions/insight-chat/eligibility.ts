import type { ChatScanContext, SpeciesDictionaryContext } from "./types.ts";

const HUMAN_IDENTITIES = new Set([
  "human",
  "humans",
  "human being",
  "person",
  "homo sapiens",
  "homo sapien",
]);

const UNRESOLVED_SCIENTIFIC_NAMES = new Set([
  "",
  "unknown",
  "unknown subject",
  "taxonomy unavailable",
  "unidentified wildlife",
  "no wildlife detected",
  "not applicable",
  "n/a",
  "inanimate object",
]);

function relationValue<T>(value: T | T[] | null | undefined): T | null {
  if (Array.isArray(value)) return value[0] ?? null;
  return value ?? null;
}

function normalizedIdentity(value: unknown): string {
  return typeof value === "string"
    ? value.toLowerCase().replace(/\s+/g, " ").trim()
    : "";
}

function selectedSpecies(
  scan: ChatScanContext,
): SpeciesDictionaryContext | null {
  if (scan.confirmed_species_id) {
    return relationValue(scan.confirmed_species);
  }
  return relationValue(scan.species_dictionary);
}

/**
 * Server-side Field Chat admission. The client also hides the action, but the
 * authenticated endpoint independently requires resolved, non-Human taxonomy.
 */
export function isFieldChatEligibleScan(scan: ChatScanContext): boolean {
  if (scan.is_biological_subject === false) return false;

  const overrideName = normalizedIdentity(scan.user_identification_override);
  if (HUMAN_IDENTITIES.has(overrideName)) return false;

  const scientificName = normalizedIdentity(
    selectedSpecies(scan)?.scientific_name,
  );
  return !UNRESOLVED_SCIENTIFIC_NAMES.has(scientificName) &&
    !HUMAN_IDENTITIES.has(scientificName);
}
