/** Independent of verified species identity; applies to legacy and explicit results. */
export interface AIIdentificationReview {
  community: {
    request_id: string;
    rank: "species" | "genus";
    scientific_name: string;
    common_name: string | null;
    species_id: string | null;
  } | null;
  version: 1;
  revision: number;
  state: "clear" | "ai_rejected" | "awaiting_acceptance";
  origin_scan_id: string | null;
  origin_identification: Record<string, unknown> | null;
  operation_id: string | null;
  operation_digest: string | null;
}
export const reviewUUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
export function parseAIIdentificationReview(
  value: unknown,
): AIIdentificationReview {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Invalid identification review.");
  }
  const row = value as Record<string, unknown>;
  const keys = [
    "community",
    "version",
    "revision",
    "state",
    "origin_scan_id",
    "origin_identification",
    "operation_id",
    "operation_digest",
  ];
  const origin = row.origin_identification as Record<string, unknown> | null;
  const validOrigin = origin === null ||
    (typeof origin === "object" && !Array.isArray(origin) &&
      Object.keys(origin).length === 2 &&
      ["scientific_name", "common_name"].every((key) =>
        Object.hasOwn(origin, key) &&
        (origin[key] === null ||
          typeof origin[key] === "string" &&
            (origin[key] as string).length <= 160)
      ));
  const community = row.community as Record<string, unknown> | null;
  const validCommunity = community === null ||
    (community && typeof community === "object" && !Array.isArray(community) &&
      row.state === "clear" && Object.keys(community).length === 5 &&
      ["request_id", "rank", "scientific_name", "common_name", "species_id"]
        .every((key) => Object.hasOwn(community, key)) &&
      typeof community.request_id === "string" &&
      reviewUUID.test(community.request_id) &&
      ["genus", "species"].includes(community.rank as string) &&
      typeof community.scientific_name === "string" &&
      community.scientific_name.length > 0 &&
      community.scientific_name.length <= 160 &&
      (community.common_name === null ||
        typeof community.common_name === "string" &&
          community.common_name.length <= 160) &&
      (community.rank === "genus"
        ? community.species_id === null
        : typeof community.species_id === "string" &&
          reviewUUID.test(community.species_id)));
  if (
    !validCommunity || !validOrigin ||
    Object.keys(row).length !== keys.length ||
    keys.some((key) => !Object.hasOwn(row, key)) ||
    (row.operation_digest !== null &&
      (typeof row.operation_digest !== "string" ||
        !/^[0-9a-f]{32}$/.test(row.operation_digest))) ||
    row.version !== 1 || !Number.isInteger(row.revision) ||
    (row.revision as number) < 0 || (row.revision as number) > 999999999 ||
    !["clear", "ai_rejected", "awaiting_acceptance"].includes(
      row.state as string,
    ) ||
    [row.origin_scan_id, row.operation_id].some((id) =>
      id !== null && (typeof id !== "string" || !reviewUUID.test(id))
    ) ||
    (row.state !== "clear" && row.origin_scan_id === null) ||
    (row.origin_identification !== null &&
      (typeof row.origin_identification !== "object" ||
        Array.isArray(row.origin_identification))) ||
    new TextEncoder().encode(JSON.stringify(value)).length > 8192
  ) throw new Error("Invalid identification review.");
  return row as unknown as AIIdentificationReview;
}
export function hasUnresolvedAIReview(value: unknown): boolean {
  return value != null && parseAIIdentificationReview(value).state !== "clear";
}
