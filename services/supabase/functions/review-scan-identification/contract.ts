import { publicHttpError } from "../_shared/http.ts";
import {
  parseAIIdentificationReview,
  reviewUUID,
} from "../_shared/identify/aiIdentificationReview.ts";
import { parseSpeciesReview } from "../_shared/identify/speciesReview.ts";
import { isScientificName } from "../confirm-scan-species/contract.ts";
export interface ReviewRequest {
  scan_id: string;
  source_scan_id: string | null;
  source_revision: number | null;
  expected_revision: number;
  operation_id: string;
  action: "carry" | "reject" | "undo" | "confirm_primary" | "confirm_name";
  scientific_name: string | null;
  expected_species_review_revision: number | null;
}
export function parseRequest(value: unknown): ReviewRequest {
  const row = value as Record<string, unknown> | null;
  const keys = [
    "scan_id",
    "expected_revision",
    "operation_id",
    "action",
    "expected_species_review_revision",
  ];
  if (row?.action === "carry") keys.push("source_scan_id", "source_revision");
  if (row?.action === "confirm_name") keys.push("scientific_name");
  if (
    !row || typeof row !== "object" || Array.isArray(row) ||
    Object.keys(row).length !== keys.length ||
    keys.some((key) => !Object.hasOwn(row, key)) ||
    typeof row.scan_id !== "string" || !reviewUUID.test(row.scan_id) ||
    typeof row.operation_id !== "string" ||
    !reviewUUID.test(row.operation_id) ||
    !Number.isInteger(row.expected_revision) ||
    (row.expected_revision as number) < 0 ||
    (row.expected_revision as number) > 999999998 ||
    (row.expected_species_review_revision !== null &&
      (!Number.isInteger(row.expected_species_review_revision) ||
        (row.expected_species_review_revision as number) < 0 ||
        (row.expected_species_review_revision as number) > 2147483646)) ||
    !["carry", "reject", "undo", "confirm_primary", "confirm_name"].includes(
      row.action as string,
    ) ||
    (row.action === "confirm_name" && !isScientificName(row.scientific_name)) ||
    (row.action === "carry" &&
      (typeof row.source_scan_id !== "string" ||
        !reviewUUID.test(row.source_scan_id) ||
        row.source_scan_id === row.scan_id ||
        !Number.isInteger(row.source_revision) ||
        (row.source_revision as number) < 1 ||
        (row.source_revision as number) > 999999999))
  ) {
    throw publicHttpError(
      400,
      "Provide a valid identification review.",
      "invalid_identification_review",
    );
  }
  return {
    ...row,
    source_scan_id: row.action === "carry" ? row.source_scan_id : null,
    source_revision: row.action === "carry" ? row.source_revision : null,
    scientific_name: row.action === "confirm_name" ? row.scientific_name : null,
  } as unknown as ReviewRequest;
}
export function parseReceipt(value: unknown, scanID: string) {
  const row = value as Record<string, unknown> | null;
  if (
    !row || row.schema_version !== 1 || row.scan_id !== scanID ||
    Object.keys(row).length !== 5 ||
    (row.confirmed_species_id !== null &&
      (typeof row.confirmed_species_id !== "string" ||
        !reviewUUID.test(row.confirmed_species_id)))
  ) throw new Error("Invalid review receipt.");
  return {
    schema_version: 1 as const,
    scan_id: scanID,
    confirmed_species_id: row.confirmed_species_id as string | null,
    review: parseAIIdentificationReview(row.review),
    species_review: row.species_review === null
      ? null
      : parseSpeciesReview(row.species_review),
  };
}
