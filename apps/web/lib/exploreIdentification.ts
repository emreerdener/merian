export type IdentificationRank =
  | "species"
  | "genus"
  | "family"
  | "unresolved_biological";
export type ExploreIdentification = {
  version: 1;
  rank: IdentificationRank;
  labelSource: "ai_primary" | "verified_selection" | "community";
  originalRank: IdentificationRank | null;
  originalScientificName: string | null;
  originalCommonName: string | null;
};
const ranks = new Set(["species", "genus", "family", "unresolved_biological"]);
function name(value: unknown): value is string | null {
  return value === null ||
    (typeof value === "string" && value.length > 0 && value.length <= 255 &&
      value.trim() === value &&
      !Array.from(value).some((c) =>
        c.charCodeAt(0) < 32 || c.charCodeAt(0) === 127
      ));
}
export function parseExploreIdentification(
  value: unknown,
): ExploreIdentification | null {
  if (value == null) return null;
  if (typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Invalid identification labels");
  }
  const row = value as Record<string, unknown>;
  const keys = [
    "version",
    "rank",
    "label_source",
    "original_rank",
    "original_scientific_name",
    "original_common_name",
  ];
  if (
    Object.keys(row).length !== keys.length ||
    keys.some((k) => !Object.hasOwn(row, k)) || row.version !== 1 ||
    !ranks.has(row.rank as string) ||
    !["ai_primary", "verified_selection", "community"].includes(
      row.label_source as string,
    ) ||
    (row.original_rank !== null && !ranks.has(row.original_rank as string)) ||
    !name(row.original_scientific_name) || !name(row.original_common_name) ||
    (row.label_source === "verified_selection" && row.rank !== "species") ||
    (row.label_source !== "community" && row.original_rank === null) ||
    (row.label_source === "ai_primary" && row.rank !== row.original_rank) ||
    (row.original_rank === null &&
      (row.original_scientific_name !== null ||
        row.original_common_name !== null)) ||
    (row.original_rank === "unresolved_biological" &&
      row.original_scientific_name !== null) ||
    (row.original_rank !== null &&
      row.original_rank !== "unresolved_biological" &&
      row.original_scientific_name === null)
  ) {
    throw new Error("Invalid identification labels");
  }
  return {
    version: 1,
    rank: row.rank as IdentificationRank,
    labelSource: row.label_source as ExploreIdentification["labelSource"],
    originalRank: row.original_rank as IdentificationRank | null,
    originalScientificName: row.original_scientific_name as string | null,
    originalCommonName: row.original_common_name as string | null,
  };
}
export function identificationDescription(
  value: ExploreIdentification | null | undefined,
): string | null {
  if (!value) return null;
  if (value.labelSource === "verified_selection") {
    return "Species selected by observer";
  }
  const rank = value.rank === "unresolved_biological"
    ? "Unidentified organism"
    : value.rank;
  if (value.labelSource === "community") {
    return `Community identification · ${rank}`;
  }
  if (value.rank === "genus") return "Genus-level identification";
  if (value.rank === "family") return "Family-level identification";
  return value.rank === "unresolved_biological"
    ? "Unidentified organism"
    : null;
}
export function originalIdentificationDescription(
  value: ExploreIdentification | null | undefined,
): string | null {
  if (
    !value || value.labelSource === "ai_primary" || value.originalRank === null
  ) return null;
  return `Original AI identification: ${
    value.originalCommonName ?? value.originalScientificName ??
      "Unidentified organism"
  } (${value.originalRank.replaceAll("_", " ")})`;
}

export function permitsSpeciesPresentation(
  value: ExploreIdentification | null | undefined,
): boolean {
  return !value ||
    (value.rank === "species" && value.labelSource !== "community");
}
