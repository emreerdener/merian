/**
 * Offline, read-only comparison of a Supabase public.users CSV export and a
 * RevenueCat "Export all" customer list (.csv or .csv.gz).
 *
 * The default output is aggregate-only. App User IDs are written only when an
 * operator explicitly supplies --review-csv.
 */

import {
  parseDelimitedText,
  readPossiblyGzippedText,
  serializeDelimitedRows,
} from "./revenuecat_csv.ts";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const PURCHASE_HISTORY_FIELDS = [
  "latest_entitlement",
  "latest_product",
  "active_entitlements",
  "all_purchased_product_ids",
  "first_purchase_at",
  "last_purchase_at",
  "latest_purchase_at",
  "latest_expiration_at",
  "product_identifier",
];

export type RevenueCatCustomerClassification =
  | "canonical_supabase_uuid"
  | "case_variant_supabase_uuid"
  | "unknown_uuid"
  | "revenuecat_anonymous"
  | "linked_alias"
  | "unlinked_alias";

export type RevenueCatReviewRecommendation =
  | "keep_canonical"
  | "keep_purchase_history"
  | "keep_linked_alias"
  | "keep_recent"
  | "keep_unknown_recency"
  | "review_case_variant"
  | "review_inactive_anonymous"
  | "review_inactive_unknown_uuid"
  | "review_inactive_unlinked_alias";

export interface RevenueCatCustomerAuditRow {
  app_user_id: string;
  classification: RevenueCatCustomerClassification;
  linked_supabase_user_id: string | null;
  identity_group_size: number;
  has_purchase_evidence: boolean;
  last_seen_at: string | null;
  inactive_days: number | null;
  recommendation: RevenueCatReviewRecommendation;
}

export interface RevenueCatCustomerAuditSummary {
  generated_at: string;
  inactive_review_threshold_days: number;
  supabase_user_count: number;
  revenuecat_customer_count: number;
  classification_counts: Record<RevenueCatCustomerClassification, number>;
  purchase_evidence_count: number;
  custom_attribute_link_count: number;
  supabase_users_with_canonical_customer_count: number;
  supabase_users_missing_canonical_customer_count: number;
  duplicate_identity_group_count: number;
  review_candidate_count: number;
  deletion_performed: false;
}

export interface RevenueCatCustomerAuditReport {
  summary: RevenueCatCustomerAuditSummary;
  rows: RevenueCatCustomerAuditRow[];
}

export interface RevenueCatCustomerAuditArgs {
  supabaseUsersCsvPath: string | null;
  revenueCatCustomersCsvPath: string | null;
  inactiveDays: number;
  summaryJsonPath: string | null;
  reviewCsvPath: string | null;
}

if (import.meta.main) {
  try {
    const exitCode = await runRevenueCatCustomerAudit(Deno.args);
    Deno.exit(exitCode);
  } catch (error) {
    console.error(
      `RevenueCat customer audit failed: ${
        error instanceof Error ? error.message : String(error)
      }`,
    );
    Deno.exit(2);
  }
}

export async function runRevenueCatCustomerAudit(
  rawArgs: string[],
): Promise<number> {
  const args = parseRevenueCatCustomerAuditArgs(rawArgs);
  if (!args.supabaseUsersCsvPath || !args.revenueCatCustomersCsvPath) {
    throw new Error(
      "--supabase-users-csv and --revenuecat-customers-csv are required.",
    );
  }

  const [supabaseSource, revenueCatSource] = await Promise.all([
    readPossiblyGzippedText(args.supabaseUsersCsvPath),
    readPossiblyGzippedText(args.revenueCatCustomersCsvPath),
  ]);
  const report = buildRevenueCatCustomerAudit({
    supabaseSource,
    revenueCatSource,
    inactiveDays: args.inactiveDays,
    now: new Date(),
  });

  printRevenueCatCustomerAuditSummary(report.summary);
  if (args.summaryJsonPath) {
    await Deno.writeTextFile(
      args.summaryJsonPath,
      `${JSON.stringify(report.summary, null, 2)}\n`,
    );
    console.log(`summary_json: ${args.summaryJsonPath}`);
  }
  if (args.reviewCsvPath) {
    const reviewRows = report.rows.filter((row) =>
      row.recommendation.startsWith("review_")
    );
    await Deno.writeTextFile(
      args.reviewCsvPath,
      serializeDelimitedRows(
        [
          "app_user_id",
          "classification",
          "linked_supabase_user_id",
          "identity_group_size",
          "has_purchase_evidence",
          "last_seen_at",
          "inactive_days",
          "recommendation",
        ],
        reviewRows,
      ),
    );
    console.log(`review_csv: ${args.reviewCsvPath}`);
  }
  return 0;
}

export function parseRevenueCatCustomerAuditArgs(
  rawArgs: string[],
): RevenueCatCustomerAuditArgs {
  const args: RevenueCatCustomerAuditArgs = {
    supabaseUsersCsvPath: null,
    revenueCatCustomersCsvPath: null,
    inactiveDays: 30,
    summaryJsonPath: null,
    reviewCsvPath: null,
  };

  for (let index = 0; index < rawArgs.length; index += 1) {
    const argument = rawArgs[index];
    switch (argument) {
      case "--supabase-users-csv":
        args.supabaseUsersCsvPath = nextArgument(rawArgs, ++index, argument);
        break;
      case "--revenuecat-customers-csv":
        args.revenueCatCustomersCsvPath = nextArgument(
          rawArgs,
          ++index,
          argument,
        );
        break;
      case "--inactive-days":
        args.inactiveDays = positiveInteger(
          nextArgument(rawArgs, ++index, argument),
          argument,
        );
        break;
      case "--summary-json":
        args.summaryJsonPath = nextArgument(rawArgs, ++index, argument);
        break;
      case "--review-csv":
        args.reviewCsvPath = nextArgument(rawArgs, ++index, argument);
        break;
      default:
        throw new Error(`Unknown argument: ${argument}`);
    }
  }
  return args;
}

export function buildRevenueCatCustomerAudit(input: {
  supabaseSource: string;
  revenueCatSource: string;
  inactiveDays: number;
  now: Date;
}): RevenueCatCustomerAuditReport {
  const supabase = parseDelimitedText(input.supabaseSource);
  const revenueCat = parseDelimitedText(input.revenueCatSource);
  requireHeader(supabase.headers, "id", "Supabase");
  requireHeader(revenueCat.headers, "app_user_id", "RevenueCat");

  const supabaseIDs = new Set<string>();
  for (const row of supabase.rows) {
    const canonicalID = canonicalUUID(row.id);
    if (!canonicalID) {
      throw new Error(`Supabase users CSV has invalid id: ${row.id}`);
    }
    if (supabaseIDs.has(canonicalID)) {
      throw new Error(`Supabase users CSV contains duplicate id: ${row.id}`);
    }
    supabaseIDs.add(canonicalID);
  }

  const exactRevenueCatIDs = new Set<string>();
  const stagedRows = revenueCat.rows.map((row) => {
    const appUserID = row.app_user_id.trim();
    if (!appUserID) {
      throw new Error("RevenueCat customer has an empty app_user_id.");
    }
    exactRevenueCatIDs.add(appUserID);

    const directUUID = canonicalUUID(appUserID);
    const attributeUUID = supabaseIDFromAttributes(row.custom_attributes);
    const directMatch = directUUID !== null && supabaseIDs.has(directUUID);
    const attributeMatch = attributeUUID !== null &&
      supabaseIDs.has(attributeUUID);
    const linkedSupabaseID = directMatch
      ? directUUID
      : attributeMatch
      ? attributeUUID
      : null;
    const classification = classifyRevenueCatCustomer(
      appUserID,
      directUUID,
      directMatch,
      attributeMatch,
    );
    const lastSeenAt = normalizedTimestamp(
      firstNonEmpty(row.last_seen_at, row.last_seen),
    );
    const inactiveDays = daysSince(lastSeenAt, input.now);
    const hasPurchaseEvidence = revenueCatPurchaseEvidence(row);

    return {
      app_user_id: appUserID,
      classification,
      linked_supabase_user_id: linkedSupabaseID,
      identity_group_size: 1,
      has_purchase_evidence: hasPurchaseEvidence,
      last_seen_at: lastSeenAt,
      inactive_days: inactiveDays,
      recommendation: recommendationForCustomer({
        classification,
        hasPurchaseEvidence,
        inactiveDays,
        inactiveThresholdDays: input.inactiveDays,
      }),
      linkedByAttribute: attributeMatch,
    };
  });

  const identityGroupSizes = new Map<string, number>();
  for (const row of stagedRows) {
    if (row.linked_supabase_user_id) {
      identityGroupSizes.set(
        row.linked_supabase_user_id,
        (identityGroupSizes.get(row.linked_supabase_user_id) ?? 0) + 1,
      );
    }
  }

  const rows: RevenueCatCustomerAuditRow[] = stagedRows.map((row) => ({
    app_user_id: row.app_user_id,
    classification: row.classification,
    linked_supabase_user_id: row.linked_supabase_user_id,
    identity_group_size: row.linked_supabase_user_id
      ? identityGroupSizes.get(row.linked_supabase_user_id) ?? 1
      : 1,
    has_purchase_evidence: row.has_purchase_evidence,
    last_seen_at: row.last_seen_at,
    inactive_days: row.inactive_days,
    recommendation: row.recommendation,
  }));

  const classificationCounts = emptyClassificationCounts();
  for (const row of rows) classificationCounts[row.classification] += 1;
  const canonicalCount =
    [...supabaseIDs].filter((id) => exactRevenueCatIDs.has(id)).length;

  return {
    summary: {
      generated_at: input.now.toISOString(),
      inactive_review_threshold_days: input.inactiveDays,
      supabase_user_count: supabaseIDs.size,
      revenuecat_customer_count: rows.length,
      classification_counts: classificationCounts,
      purchase_evidence_count: rows.filter((row) => row.has_purchase_evidence)
        .length,
      custom_attribute_link_count:
        stagedRows.filter((row) => row.linkedByAttribute).length,
      supabase_users_with_canonical_customer_count: canonicalCount,
      supabase_users_missing_canonical_customer_count: supabaseIDs.size -
        canonicalCount,
      duplicate_identity_group_count: [...identityGroupSizes.values()].filter(
        (count) => count > 1,
      ).length,
      review_candidate_count:
        rows.filter((row) => row.recommendation.startsWith("review_")).length,
      deletion_performed: false,
    },
    rows,
  };
}

export function canonicalUUID(value: string | undefined): string | null {
  const normalized = value?.trim() ?? "";
  return UUID_PATTERN.test(normalized) ? normalized.toUpperCase() : null;
}

export function revenueCatPurchaseEvidence(
  row: Record<string, string>,
): boolean {
  if (truthy(row.is_rc_promo)) return true;
  const totalSpent = Number(
    (row.total_spent ?? "").replaceAll(/[^0-9.-]/g, ""),
  );
  if (Number.isFinite(totalSpent) && totalSpent > 0) return true;
  return PURCHASE_HISTORY_FIELDS.some((field) => meaningfulValue(row[field]));
}

export function recommendationForCustomer(input: {
  classification: RevenueCatCustomerClassification;
  hasPurchaseEvidence: boolean;
  inactiveDays: number | null;
  inactiveThresholdDays: number;
}): RevenueCatReviewRecommendation {
  if (input.classification === "canonical_supabase_uuid") {
    return "keep_canonical";
  }
  if (input.hasPurchaseEvidence) return "keep_purchase_history";
  if (input.classification === "linked_alias") return "keep_linked_alias";
  if (input.classification === "case_variant_supabase_uuid") {
    return "review_case_variant";
  }
  if (input.inactiveDays === null) return "keep_unknown_recency";
  if (input.inactiveDays < input.inactiveThresholdDays) return "keep_recent";
  if (input.classification === "revenuecat_anonymous") {
    return "review_inactive_anonymous";
  }
  if (input.classification === "unknown_uuid") {
    return "review_inactive_unknown_uuid";
  }
  return "review_inactive_unlinked_alias";
}

function classifyRevenueCatCustomer(
  appUserID: string,
  directUUID: string | null,
  directMatch: boolean,
  attributeMatch: boolean,
): RevenueCatCustomerClassification {
  if (appUserID.startsWith("$RCAnonymousID:")) return "revenuecat_anonymous";
  if (directUUID && directMatch) {
    return appUserID === directUUID
      ? "canonical_supabase_uuid"
      : "case_variant_supabase_uuid";
  }
  if (directUUID) return "unknown_uuid";
  return attributeMatch ? "linked_alias" : "unlinked_alias";
}

function supabaseIDFromAttributes(value: string | undefined): string | null {
  if (!value?.trim()) return null;
  try {
    const attributes = JSON.parse(value) as Record<string, unknown>;
    const candidate = attributes.supabase_user_id;
    if (typeof candidate === "string") return canonicalUUID(candidate);
    if (
      candidate && typeof candidate === "object" && !Array.isArray(candidate)
    ) {
      const attributeValue = (candidate as Record<string, unknown>).value;
      return typeof attributeValue === "string"
        ? canonicalUUID(attributeValue)
        : null;
    }
  } catch {
    return null;
  }
  return null;
}

function normalizedTimestamp(value: string | null): string | null {
  if (!value) return null;
  const numeric = Number(value);
  const milliseconds = /^\d{10,13}$/.test(value)
    ? numeric * (value.length === 10 ? 1_000 : 1)
    : Date.parse(value);
  return Number.isFinite(milliseconds)
    ? new Date(milliseconds).toISOString()
    : null;
}

function daysSince(timestamp: string | null, now: Date): number | null {
  if (!timestamp) return null;
  const difference = now.getTime() - Date.parse(timestamp);
  if (!Number.isFinite(difference) || difference < 0) return null;
  return Math.floor(difference / (24 * 60 * 60 * 1_000));
}

function meaningfulValue(value: string | undefined): boolean {
  const normalized = value?.trim().toLowerCase() ?? "";
  return !["", "[]", "{}", "null", "false", "0"].includes(normalized);
}

function truthy(value: string | undefined): boolean {
  return ["true", "t", "1", "yes"].includes(value?.trim().toLowerCase() ?? "");
}

function firstNonEmpty(...values: Array<string | undefined>): string | null {
  for (const value of values) {
    if (value?.trim()) return value.trim();
  }
  return null;
}

function emptyClassificationCounts(): Record<
  RevenueCatCustomerClassification,
  number
> {
  return {
    canonical_supabase_uuid: 0,
    case_variant_supabase_uuid: 0,
    unknown_uuid: 0,
    revenuecat_anonymous: 0,
    linked_alias: 0,
    unlinked_alias: 0,
  };
}

function printRevenueCatCustomerAuditSummary(
  summary: RevenueCatCustomerAuditSummary,
): void {
  console.log("mode: read-only");
  console.log(`supabase_users: ${summary.supabase_user_count}`);
  console.log(`revenuecat_customers: ${summary.revenuecat_customer_count}`);
  console.log(
    `canonical_customer_coverage: ${summary.supabase_users_with_canonical_customer_count}/${summary.supabase_user_count}`,
  );
  console.log(
    `duplicate_identity_groups: ${summary.duplicate_identity_group_count}`,
  );
  console.log(`review_candidates: ${summary.review_candidate_count}`);
  console.log("deletion_performed: false");
}

function requireHeader(headers: string[], header: string, label: string): void {
  if (!headers.includes(header)) {
    throw new Error(`${label} CSV is missing required header: ${header}`);
  }
}

function nextArgument(
  rawArgs: string[],
  index: number,
  argument: string,
): string {
  const value = rawArgs[index];
  if (!value || value.startsWith("--")) {
    throw new Error(`${argument} requires a value.`);
  }
  return value;
}

function positiveInteger(value: string, argument: string): number {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) {
    throw new Error(`${argument} must be a positive integer.`);
  }
  return parsed;
}
