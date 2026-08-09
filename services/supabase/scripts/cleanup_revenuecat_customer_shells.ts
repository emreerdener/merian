/**
 * Deletes only RevenueCat customer shells that a fresh offline export and live
 * provider revalidation both prove have no purchase, entitlement, receipt, or
 * alias history. Supabase users and app data are never mutated.
 *
 * Dry-run is the default and performs no network requests. Apply requires the
 * exact plan digest and count printed by dry-run plus an identity-bearing
 * results ledger in operator-controlled storage.
 */

import {
  buildRevenueCatCustomerAudit,
  canonicalUUID,
  type RevenueCatCustomerAuditRow,
  type RevenueCatCustomerClassification,
} from "./audit_revenuecat_customers.ts";
import {
  parseDelimitedText,
  readPossiblyGzippedTextArtifact,
  serializeDelimitedRows,
} from "./revenuecat_csv.ts";

const REVENUECAT_V1_BASE_URL = "https://api.revenuecat.com/v1";
const REVENUECAT_V2_BASE_URL = "https://api.revenuecat.com/v2";
const MAX_RESPONSE_BYTES = 512 * 1024;
const REQUEST_TIMEOUT_MS = 15_000;
const MAX_ATTEMPTS = 3;
const APPLY_CONFIRMATION = "--confirm-delete-empty-revenuecat-shells";

export interface RevenueCatShellCleanupArgs {
  supabaseUsersCsvPath: string | null;
  authAuditCsvPath: string | null;
  revenueCatCustomersCsvPath: string | null;
  protectedCohortCsvPath: string | null;
  inactiveDays: number;
  includeCurrentSupabaseShells: boolean;
  summaryJsonPath: string | null;
  reviewCsvPath: string | null;
  resultsCsvPath: string | null;
  projectID: string | null;
  apply: boolean;
  confirmed: boolean;
  approvedPlanSHA256: string | null;
  confirmedCount: number | null;
  concurrency: number;
}

export type RevenueCatShellCleanupReason =
  | "case_variant_with_canonical_replacement"
  | "inactive_revenuecat_anonymous"
  | "inactive_unknown_uuid"
  | "inactive_unlinked_alias"
  | "inactive_current_supabase_shell";

export interface RevenueCatShellCleanupCandidate {
  app_user_id: string;
  classification: RevenueCatCustomerClassification;
  linked_supabase_user_id: string;
  last_seen_at: string;
  inactive_days: number;
  reason: RevenueCatShellCleanupReason;
}

export interface RevenueCatShellCleanupSummary {
  generated_at: string;
  mode: "dry-run" | "apply";
  selection: "empty_inactive_shells_outside_protected_cohort";
  inactive_days: number;
  include_current_supabase_shells: boolean;
  supabase_export_sha256: string;
  auth_audit_sha256: string;
  revenuecat_export_sha256: string;
  protected_cohort_sha256: string;
  protected_cohort_count: number;
  active_auth_user_count: number;
  revenuecat_customer_count: number;
  candidate_count: number;
  candidate_sha256: string;
  deleted_count: number;
  queued_count: number;
  already_absent_count: number;
  protected_by_live_evidence_count: number;
  failed_count: number;
  supabase_mutations: false;
}

export type RevenueCatShellCleanupResultStatus =
  | "planned"
  | "deleted"
  | "queued"
  | "already_absent"
  | "protected_live_evidence"
  | "failed";

export interface RevenueCatShellCleanupResult {
  app_user_id: string;
  status: RevenueCatShellCleanupResultStatus;
  error_code: string;
}

interface RevenueCatListResponse {
  items?: unknown[];
  next_page?: string | null;
}

interface RevenueCatV2Customer {
  object?: string;
  id?: string;
  project_id?: string;
  last_seen_at?: number;
  active_entitlements?: RevenueCatListResponse;
  attributes?: RevenueCatListResponse;
}

interface RevenueCatV1CustomerInfo {
  subscriber?: {
    entitlements?: Record<string, unknown>;
    subscriptions?: Record<string, unknown>;
    non_subscriptions?: Record<string, unknown>;
    other_purchases?: Record<string, unknown>;
    original_app_user_id?: string | null;
    original_application_version?: string | null;
    original_purchase_date?: string | null;
    management_url?: string | null;
  };
}

interface CleanupPlan {
  candidates: RevenueCatShellCleanupCandidate[];
  protectedCohort: Set<string>;
  activeAuthUserIDs: Set<string>;
  activeAuthUserCount: number;
  revenueCatCustomerCount: number;
}

interface AuthAuditEvidence {
  allUserIDs: Set<string>;
  activeAuthUserIDs: Set<string>;
}

if (import.meta.main) {
  try {
    Deno.exit(await runRevenueCatShellCleanup(Deno.args));
  } catch (error) {
    console.error(
      `RevenueCat shell cleanup failed: ${safeErrorMessage(error)}`,
    );
    Deno.exit(2);
  }
}

export async function runRevenueCatShellCleanup(
  rawArgs: string[],
  dependencies: {
    fetcher?: typeof fetch;
    now?: Date;
    apiKey?: string | null;
    sleep?: (milliseconds: number) => Promise<void>;
  } = {},
): Promise<number> {
  const args = parseRevenueCatShellCleanupArgs(rawArgs);
  requireInputs(args);

  const [
    supabaseArtifact,
    authAuditArtifact,
    revenueCatArtifact,
    cohortArtifact,
  ] = await Promise.all([
    readPossiblyGzippedTextArtifact(args.supabaseUsersCsvPath!),
    readPossiblyGzippedTextArtifact(args.authAuditCsvPath!),
    readPossiblyGzippedTextArtifact(args.revenueCatCustomersCsvPath!),
    readPossiblyGzippedTextArtifact(args.protectedCohortCsvPath!),
  ]);
  const now = dependencies.now ?? new Date();
  const plan = buildRevenueCatShellCleanupPlan({
    supabaseSource: supabaseArtifact.text,
    authAuditSource: authAuditArtifact.text,
    revenueCatSource: revenueCatArtifact.text,
    protectedCohortSource: cohortArtifact.text,
    inactiveDays: args.inactiveDays,
    includeCurrentSupabaseShells: args.includeCurrentSupabaseShells,
    now,
  });
  const [
    supabaseSHA,
    authAuditSHA,
    revenueCatSHA,
    cohortSHA,
    candidateSHA,
  ] = await Promise.all([
    sha256Hex(supabaseArtifact.sourceBytes),
    sha256Hex(authAuditArtifact.sourceBytes),
    sha256Hex(revenueCatArtifact.sourceBytes),
    sha256Hex(cohortArtifact.sourceBytes),
    revenueCatShellCandidateSHA256(plan.candidates),
  ]);

  if (args.reviewCsvPath) {
    await Deno.writeTextFile(
      args.reviewCsvPath,
      serializeDelimitedRows(
        [
          "app_user_id",
          "classification",
          "linked_supabase_user_id",
          "last_seen_at",
          "inactive_days",
          "reason",
        ],
        plan.candidates,
      ),
    );
  }

  let results: RevenueCatShellCleanupResult[] = plan.candidates.map(
    (candidate) => ({
      app_user_id: candidate.app_user_id,
      status: "planned",
      error_code: "",
    }),
  );

  if (args.apply) {
    validateApplyAuthorization(args, candidateSHA, plan.candidates.length);
    const apiKey = dependencies.apiKey ??
      Deno.env.get("REVENUECAT_SECRET_API_KEY") ?? null;
    const projectID = args.projectID ??
      Deno.env.get("REVENUECAT_PROJECT_ID") ?? null;
    if (!apiKey?.trim()) {
      throw new Error("REVENUECAT_SECRET_API_KEY is required for apply mode.");
    }
    if (!apiKey.trim().startsWith("sk_")) {
      throw new Error(
        "REVENUECAT_SECRET_API_KEY must be a server-side secret key.",
      );
    }
    if (!projectID || !/^proj[a-zA-Z0-9_-]{4,251}$/.test(projectID)) {
      throw new Error(
        "A valid --project-id or REVENUECAT_PROJECT_ID is required for apply mode.",
      );
    }

    results = await applyRevenueCatShellCleanup({
      candidates: plan.candidates,
      protectedCohort: plan.protectedCohort,
      activeAuthUserIDs: plan.activeAuthUserIDs,
      inactiveBeforeMs: now.getTime() - args.inactiveDays * 86_400_000,
      projectID,
      apiKey: apiKey.trim(),
      concurrency: args.concurrency,
      fetcher: dependencies.fetcher ?? fetch,
      sleep: dependencies.sleep ?? boundedSleep,
    });
    await Deno.writeTextFile(
      args.resultsCsvPath!,
      serializeDelimitedRows(
        ["app_user_id", "status", "error_code"],
        results,
      ),
    );
  }

  const summary = buildSummary({
    args,
    now,
    plan,
    results,
    supabaseSHA,
    authAuditSHA,
    revenueCatSHA,
    cohortSHA,
    candidateSHA,
  });
  printSummary(summary);
  if (args.summaryJsonPath) {
    await Deno.writeTextFile(
      args.summaryJsonPath,
      `${JSON.stringify(summary, null, 2)}\n`,
    );
  }
  if (args.reviewCsvPath) console.log(`review_csv: ${args.reviewCsvPath}`);
  if (args.resultsCsvPath && args.apply) {
    console.log(`results_csv: ${args.resultsCsvPath}`);
  }
  if (args.summaryJsonPath) {
    console.log(`summary_json: ${args.summaryJsonPath}`);
  }
  return results.some((result) => result.status === "failed") ? 1 : 0;
}

export function parseRevenueCatShellCleanupArgs(
  rawArgs: string[],
): RevenueCatShellCleanupArgs {
  const args: RevenueCatShellCleanupArgs = {
    supabaseUsersCsvPath: null,
    authAuditCsvPath: null,
    revenueCatCustomersCsvPath: null,
    protectedCohortCsvPath: null,
    inactiveDays: 7,
    includeCurrentSupabaseShells: false,
    summaryJsonPath: null,
    reviewCsvPath: null,
    resultsCsvPath: null,
    projectID: null,
    apply: false,
    confirmed: false,
    approvedPlanSHA256: null,
    confirmedCount: null,
    concurrency: 2,
  };

  for (let index = 0; index < rawArgs.length; index += 1) {
    const argument = rawArgs[index];
    switch (argument) {
      case "--supabase-users-csv":
        args.supabaseUsersCsvPath = nextArgument(rawArgs, ++index, argument);
        break;
      case "--auth-audit-csv":
        args.authAuditCsvPath = nextArgument(rawArgs, ++index, argument);
        break;
      case "--revenuecat-customers-csv":
        args.revenueCatCustomersCsvPath = nextArgument(
          rawArgs,
          ++index,
          argument,
        );
        break;
      case "--protected-cohort-csv":
        args.protectedCohortCsvPath = nextArgument(rawArgs, ++index, argument);
        break;
      case "--inactive-days":
        args.inactiveDays = positiveInteger(
          nextArgument(rawArgs, ++index, argument),
          argument,
        );
        break;
      case "--include-current-supabase-shells":
        args.includeCurrentSupabaseShells = true;
        break;
      case "--summary-json":
        args.summaryJsonPath = nextArgument(rawArgs, ++index, argument);
        break;
      case "--review-csv":
        args.reviewCsvPath = nextArgument(rawArgs, ++index, argument);
        break;
      case "--results-csv":
        args.resultsCsvPath = nextArgument(rawArgs, ++index, argument);
        break;
      case "--project-id":
        args.projectID = nextArgument(rawArgs, ++index, argument);
        break;
      case "--approved-plan-sha256":
        args.approvedPlanSHA256 = nextArgument(rawArgs, ++index, argument)
          .toLowerCase();
        break;
      case "--confirm-count":
        args.confirmedCount = nonnegativeInteger(
          nextArgument(rawArgs, ++index, argument),
          argument,
        );
        break;
      case "--concurrency":
        args.concurrency = boundedInteger(
          nextArgument(rawArgs, ++index, argument),
          argument,
          1,
          3,
        );
        break;
      case "--apply":
        args.apply = true;
        break;
      case APPLY_CONFIRMATION:
        args.confirmed = true;
        break;
      default:
        throw new Error(`Unknown argument: ${argument}`);
    }
  }
  return args;
}

export function buildRevenueCatShellCleanupPlan(input: {
  supabaseSource: string;
  authAuditSource: string;
  revenueCatSource: string;
  protectedCohortSource: string;
  inactiveDays: number;
  includeCurrentSupabaseShells: boolean;
  now: Date;
}): CleanupPlan {
  const audit = buildRevenueCatCustomerAudit({
    supabaseSource: input.supabaseSource,
    revenueCatSource: input.revenueCatSource,
    inactiveDays: input.inactiveDays,
    now: input.now,
  });
  const supabaseIDs = parseCanonicalIDColumn(
    input.supabaseSource,
    "Supabase users",
  );
  const protectedCohort = parseCanonicalIDColumn(
    input.protectedCohortSource,
    "Protected cohort",
    true,
  );
  if (protectedCohort.size === 0) {
    throw new Error("Protected cohort must contain at least one reviewed id.");
  }
  const authAudit = parseAuthAuditEvidence(input.authAuditSource);
  for (const protectedID of protectedCohort) {
    if (!supabaseIDs.has(protectedID)) {
      throw new Error(
        "Protected cohort contains an ID absent from the Supabase users export.",
      );
    }
    if (!authAudit.activeAuthUserIDs.has(protectedID)) {
      throw new Error(
        "Protected cohort contains an ID without active Supabase Auth evidence.",
      );
    }
  }
  for (const supabaseID of supabaseIDs) {
    if (!authAudit.allUserIDs.has(supabaseID)) {
      throw new Error("Auth audit is missing a Supabase users export ID.");
    }
  }

  const exactRevenueCatIDs = new Set(
    audit.rows.map((row) => row.app_user_id),
  );
  const candidates = audit.rows.flatMap((row) => {
    const candidate = candidateFromAuditRow({
      row,
      protectedCohort,
      activeAuthUserIDs: authAudit.activeAuthUserIDs,
      exactRevenueCatIDs,
      inactiveDays: input.inactiveDays,
      includeCurrentSupabaseShells: input.includeCurrentSupabaseShells,
    });
    return candidate ? [candidate] : [];
  }).sort((lhs, rhs) => lhs.app_user_id.localeCompare(rhs.app_user_id));

  return {
    candidates,
    protectedCohort,
    activeAuthUserIDs: authAudit.activeAuthUserIDs,
    activeAuthUserCount: authAudit.activeAuthUserIDs.size,
    revenueCatCustomerCount: audit.summary.revenuecat_customer_count,
  };
}

function candidateFromAuditRow(input: {
  row: RevenueCatCustomerAuditRow;
  protectedCohort: Set<string>;
  activeAuthUserIDs: Set<string>;
  exactRevenueCatIDs: Set<string>;
  inactiveDays: number;
  includeCurrentSupabaseShells: boolean;
}): RevenueCatShellCleanupCandidate | null {
  const { row } = input;
  if (row.has_purchase_evidence) return null;
  if (row.last_seen_at === null || row.inactive_days === null) return null;
  if (row.inactive_days < input.inactiveDays) return null;
  if (
    row.linked_supabase_user_id &&
    input.protectedCohort.has(row.linked_supabase_user_id)
  ) return null;
  const directCanonicalID = canonicalUUID(row.app_user_id);
  if (
    directCanonicalID && input.activeAuthUserIDs.has(directCanonicalID) &&
    row.classification !== "case_variant_supabase_uuid"
  ) return null;

  let reason: RevenueCatShellCleanupReason | null = null;
  switch (row.classification) {
    case "canonical_supabase_uuid":
      if (input.includeCurrentSupabaseShells) {
        reason = "inactive_current_supabase_shell";
      }
      break;
    case "case_variant_supabase_uuid":
      if (
        row.linked_supabase_user_id &&
        input.exactRevenueCatIDs.has(row.linked_supabase_user_id)
      ) {
        reason = "case_variant_with_canonical_replacement";
      }
      break;
    case "revenuecat_anonymous":
      reason = "inactive_revenuecat_anonymous";
      break;
    case "unknown_uuid":
      reason = "inactive_unknown_uuid";
      break;
    case "unlinked_alias":
      reason = "inactive_unlinked_alias";
      break;
    case "linked_alias":
      break;
  }
  if (!reason) return null;

  return {
    app_user_id: row.app_user_id,
    classification: row.classification,
    linked_supabase_user_id: row.linked_supabase_user_id ?? "",
    last_seen_at: row.last_seen_at,
    inactive_days: row.inactive_days,
    reason,
  };
}

export async function revenueCatShellCandidateSHA256(
  candidates: RevenueCatShellCleanupCandidate[],
): Promise<string> {
  const canonicalPlan = candidates.map((candidate) => ({
    app_user_id: candidate.app_user_id,
    classification: candidate.classification,
    linked_supabase_user_id: candidate.linked_supabase_user_id,
    last_seen_at: candidate.last_seen_at,
    inactive_days: candidate.inactive_days,
    reason: candidate.reason,
  }));
  return await sha256Hex(`${JSON.stringify(canonicalPlan)}\n`);
}

export async function applyRevenueCatShellCleanup(input: {
  candidates: RevenueCatShellCleanupCandidate[];
  protectedCohort: Set<string>;
  activeAuthUserIDs: Set<string>;
  inactiveBeforeMs: number;
  projectID: string;
  apiKey: string;
  concurrency: number;
  fetcher: typeof fetch;
  sleep: (milliseconds: number) => Promise<void>;
}): Promise<RevenueCatShellCleanupResult[]> {
  const results = new Array<RevenueCatShellCleanupResult>(
    input.candidates.length,
  );
  let nextIndex = 0;

  const worker = async () => {
    while (true) {
      const index = nextIndex;
      nextIndex += 1;
      if (index >= input.candidates.length) return;
      results[index] = await revalidateAndDeleteRevenueCatShell({
        candidate: input.candidates[index],
        protectedCohort: input.protectedCohort,
        activeAuthUserIDs: input.activeAuthUserIDs,
        inactiveBeforeMs: input.inactiveBeforeMs,
        projectID: input.projectID,
        apiKey: input.apiKey,
        fetcher: input.fetcher,
        sleep: input.sleep,
      });
    }
  };
  await Promise.all(
    Array.from(
      { length: Math.min(input.concurrency, input.candidates.length) },
      worker,
    ),
  );
  return results;
}

export async function revalidateAndDeleteRevenueCatShell(input: {
  candidate: RevenueCatShellCleanupCandidate;
  protectedCohort: Set<string>;
  activeAuthUserIDs?: Set<string>;
  inactiveBeforeMs: number;
  projectID: string;
  apiKey: string;
  fetcher: typeof fetch;
  sleep: (milliseconds: number) => Promise<void>;
}): Promise<RevenueCatShellCleanupResult> {
  const customerID = input.candidate.app_user_id;
  try {
    if (
      candidateTouchesProtectedIdentity(
        input.candidate,
        input.protectedCohort,
        input.activeAuthUserIDs ?? new Set(),
      )
    ) {
      return result(
        customerID,
        "protected_live_evidence",
        "protected_identity",
      );
    }
    const encodedProjectID = encodeURIComponent(input.projectID);
    const encodedCustomerID = encodeURIComponent(customerID);
    const headers = {
      Authorization: `Bearer ${input.apiKey}`,
      "Content-Type": "application/json",
    };
    const customerResponse = await requestRevenueCat({
      url:
        `${REVENUECAT_V2_BASE_URL}/projects/${encodedProjectID}/customers/${encodedCustomerID}?expand=attributes`,
      method: "GET",
      headers,
      fetcher: input.fetcher,
      sleep: input.sleep,
    });
    if (customerResponse.status === 404) {
      return result(customerID, "already_absent", "");
    }
    if (customerResponse.status !== 200) {
      return result(
        customerID,
        "failed",
        `customer_http_${customerResponse.status}`,
      );
    }
    const customer = parseJSON<RevenueCatV2Customer>(customerResponse.body);
    if (
      customer.object !== "customer" || customer.id !== customerID ||
      customer.project_id !== input.projectID ||
      !liveCustomerRemainsInactive(
        customer,
        input.candidate,
        input.inactiveBeforeMs,
      ) ||
      !isEmptyCompleteList(customer.active_entitlements) ||
      !attributesAreSafeForCandidate(
        customer.attributes,
        input.candidate,
        input.protectedCohort,
        input.activeAuthUserIDs ?? new Set(),
      )
    ) {
      return result(customerID, "protected_live_evidence", "customer_state");
    }

    const aliasesResponse = await requestRevenueCat({
      url:
        `${REVENUECAT_V2_BASE_URL}/projects/${encodedProjectID}/customers/${encodedCustomerID}/aliases?limit=100`,
      method: "GET",
      headers,
      fetcher: input.fetcher,
      sleep: input.sleep,
    });
    if (aliasesResponse.status !== 200) {
      return result(
        customerID,
        "failed",
        `aliases_http_${aliasesResponse.status}`,
      );
    }
    const aliases = parseJSON<RevenueCatListResponse>(aliasesResponse.body);
    if (!aliasesAreSelfOnly(aliases, customerID)) {
      return result(customerID, "protected_live_evidence", "aliases");
    }

    const infoResponse = await requestRevenueCat({
      url: `${REVENUECAT_V1_BASE_URL}/subscribers/${encodedCustomerID}`,
      method: "GET",
      headers,
      fetcher: input.fetcher,
      sleep: input.sleep,
    });
    if (infoResponse.status !== 200) {
      return result(
        customerID,
        "failed",
        `customer_info_http_${infoResponse.status}`,
      );
    }
    const customerInfo = parseJSON<RevenueCatV1CustomerInfo>(infoResponse.body);
    if (
      hasCustomerInfoHistory(customerInfo, customerID) ||
      candidateTouchesProtectedIdentity(
        input.candidate,
        input.protectedCohort,
        input.activeAuthUserIDs ?? new Set(),
      )
    ) {
      return result(
        customerID,
        "protected_live_evidence",
        "customer_info_history",
      );
    }

    const deleteResponse = await requestRevenueCat({
      url:
        `${REVENUECAT_V2_BASE_URL}/projects/${encodedProjectID}/customers/${encodedCustomerID}`,
      method: "DELETE",
      headers,
      fetcher: input.fetcher,
      sleep: input.sleep,
    });
    if (deleteResponse.status === 200) {
      return result(customerID, "deleted", "");
    }
    if (deleteResponse.status === 202) {
      return result(customerID, "queued", "");
    }
    if (deleteResponse.status === 404) {
      return result(customerID, "already_absent", "");
    }
    return result(
      customerID,
      "failed",
      `delete_http_${deleteResponse.status}`,
    );
  } catch (error) {
    return result(customerID, "failed", stableErrorCode(error));
  }
}

export function hasCustomerInfoHistory(
  customerInfo: RevenueCatV1CustomerInfo,
  expectedCustomerID: string,
): boolean {
  const subscriber = customerInfo.subscriber;
  if (!subscriber) return true;
  if (subscriber.original_app_user_id !== expectedCustomerID) return true;
  if (hasKeys(subscriber.entitlements)) return true;
  if (hasKeys(subscriber.subscriptions)) return true;
  if (hasKeys(subscriber.non_subscriptions)) return true;
  if (hasKeys(subscriber.other_purchases)) return true;
  if (meaningful(subscriber.management_url)) return true;
  return false;
}

function candidateTouchesProtectedIdentity(
  candidate: RevenueCatShellCleanupCandidate,
  protectedCohort: Set<string>,
  activeAuthUserIDs: Set<string>,
): boolean {
  const directID = canonicalUUID(candidate.app_user_id);
  const activeDirectIdentity = directID !== null &&
    activeAuthUserIDs.has(directID) &&
    candidate.classification !== "case_variant_supabase_uuid";
  return activeDirectIdentity ||
    (directID !== null && protectedCohort.has(directID)) ||
    (candidate.linked_supabase_user_id !== "" &&
      protectedCohort.has(candidate.linked_supabase_user_id));
}

function attributesAreSafeForCandidate(
  response: RevenueCatListResponse | undefined,
  candidate: RevenueCatShellCleanupCandidate,
  protectedCohort: Set<string>,
  activeAuthUserIDs: Set<string>,
): boolean {
  if (!response || !Array.isArray(response.items) || response.next_page) {
    return false;
  }
  for (const item of response.items) {
    if (
      typeof item !== "object" || item === null ||
      (item as Record<string, unknown>).object !== "customer.attribute"
    ) return false;
    const attribute = item as Record<string, unknown>;
    if (attribute.name !== "supabase_user_id") continue;
    if (typeof attribute.value !== "string") return false;
    const linkedID = canonicalUUID(attribute.value);
    if (!linkedID) return false;
    if (protectedCohort.has(linkedID)) return false;
    if (
      activeAuthUserIDs.has(linkedID) &&
      !(candidate.classification === "case_variant_supabase_uuid" &&
        candidate.linked_supabase_user_id === linkedID)
    ) return false;
  }
  return true;
}

function aliasesAreSelfOnly(
  response: RevenueCatListResponse,
  customerID: string,
): boolean {
  if (!Array.isArray(response.items) || response.next_page) return false;
  return response.items.every((item) =>
    typeof item === "object" && item !== null &&
    (item as Record<string, unknown>).object === "customer.alias" &&
    (item as Record<string, unknown>).id === customerID
  );
}

function isEmptyCompleteList(response: RevenueCatListResponse | undefined) {
  return response !== undefined && Array.isArray(response.items) &&
    response.items.length === 0 && !response.next_page;
}

function liveCustomerRemainsInactive(
  customer: RevenueCatV2Customer,
  candidate: RevenueCatShellCleanupCandidate,
  inactiveBeforeMs: number,
): boolean {
  const exportedLastSeenMs = Date.parse(candidate.last_seen_at);
  const liveLastSeenMs = customer.last_seen_at;
  return typeof liveLastSeenMs === "number" &&
    Number.isSafeInteger(liveLastSeenMs) && liveLastSeenMs > 0 &&
    Number.isFinite(exportedLastSeenMs) &&
    liveLastSeenMs <= exportedLastSeenMs &&
    liveLastSeenMs <= inactiveBeforeMs;
}

async function requestRevenueCat(input: {
  url: string;
  method: "GET" | "DELETE";
  headers: Record<string, string>;
  fetcher: typeof fetch;
  sleep: (milliseconds: number) => Promise<void>;
}): Promise<{ status: number; body: string }> {
  let lastStatus = 0;
  let lastError: unknown;
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt += 1) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
    try {
      const response = await input.fetcher(input.url, {
        method: input.method,
        headers: input.headers,
        signal: controller.signal,
      });
      lastStatus = response.status;
      const body = await readBoundedResponseText(response);
      if (!retryableStatus(response.status) || attempt === MAX_ATTEMPTS) {
        return { status: response.status, body };
      }
    } catch (error) {
      lastError = error;
      if (attempt === MAX_ATTEMPTS) throw error;
    } finally {
      clearTimeout(timer);
    }
    await input.sleep(Math.min(2_000, 250 * 2 ** (attempt - 1)));
  }
  if (lastStatus !== 0) return { status: lastStatus, body: "" };
  throw lastError ?? new Error("RevenueCat request failed.");
}

async function readBoundedResponseText(response: Response): Promise<string> {
  const declaredLength = Number(response.headers.get("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > MAX_RESPONSE_BYTES) {
    throw new Error("response_too_large");
  }
  if (!response.body) return "";
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > MAX_RESPONSE_BYTES) {
      await reader.cancel();
      throw new Error("response_too_large");
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
}

function retryableStatus(status: number): boolean {
  return [408, 409, 423, 425, 429, 500, 502, 503, 504].includes(status);
}

function parseCanonicalIDColumn(
  source: string,
  label: string,
  exactHeaderOnly = false,
): Set<string> {
  const normalizedSource = source.startsWith("\uFEFF")
    ? source.slice(1)
    : source;
  const firstLine = normalizedSource.split(/\r?\n/, 1)[0]?.trim() ?? "";
  if (firstLine === "id" && !/[;,\t]/.test(firstLine)) {
    const ids = new Set<string>();
    const values = normalizedSource.split(/\r?\n/).slice(1)
      .map((value) => value.trim()).filter(Boolean);
    for (const value of values) {
      const id = canonicalUUID(value);
      if (!id) throw new Error(`${label} CSV contains a malformed UUID.`);
      if (ids.has(id)) {
        throw new Error(`${label} CSV contains a duplicate UUID.`);
      }
      ids.add(id);
    }
    return ids;
  }

  const parsed = parseDelimitedText(normalizedSource);
  if (
    exactHeaderOnly &&
    (parsed.headers.length !== 1 || parsed.headers[0] !== "id")
  ) {
    throw new Error(`${label} CSV must contain exactly one header named id.`);
  }
  if (!parsed.headers.includes("id")) {
    throw new Error(`${label} CSV is missing required header: id`);
  }
  const ids = new Set<string>();
  for (const row of parsed.rows) {
    const id = canonicalUUID(row.id);
    if (!id) throw new Error(`${label} CSV contains a malformed UUID.`);
    if (ids.has(id)) throw new Error(`${label} CSV contains a duplicate UUID.`);
    ids.add(id);
  }
  return ids;
}

function parseAuthAuditEvidence(source: string): AuthAuditEvidence {
  const parsed = parseDelimitedText(source);
  for (const header of ["user_id", "auth_exists", "public_user_exists"]) {
    if (!parsed.headers.includes(header)) {
      throw new Error(`Auth audit CSV is missing required header: ${header}`);
    }
  }

  const allUserIDs = new Set<string>();
  const activeAuthUserIDs = new Set<string>();
  for (const row of parsed.rows) {
    const userID = canonicalUUID(row.user_id);
    if (!userID) throw new Error("Auth audit CSV contains a malformed UUID.");
    if (allUserIDs.has(userID)) {
      throw new Error("Auth audit CSV contains a duplicate UUID.");
    }
    allUserIDs.add(userID);

    const authExists = strictBoolean(row.auth_exists, "auth_exists");
    strictBoolean(row.public_user_exists, "public_user_exists");
    if (authExists) activeAuthUserIDs.add(userID);
  }
  return { allUserIDs, activeAuthUserIDs };
}

function strictBoolean(value: string, field: string): boolean {
  switch (value.trim().toLowerCase()) {
    case "true":
      return true;
    case "false":
      return false;
    default:
      throw new Error(`Auth audit CSV contains an invalid ${field} value.`);
  }
}

function requireInputs(args: RevenueCatShellCleanupArgs): void {
  if (
    !args.supabaseUsersCsvPath || !args.authAuditCsvPath ||
    !args.revenueCatCustomersCsvPath ||
    !args.protectedCohortCsvPath
  ) {
    throw new Error(
      "--supabase-users-csv, --auth-audit-csv, --revenuecat-customers-csv, and --protected-cohort-csv are required.",
    );
  }
}

function validateApplyAuthorization(
  args: RevenueCatShellCleanupArgs,
  candidateSHA: string,
  candidateCount: number,
): void {
  if (!args.confirmed) {
    throw new Error(`Apply mode requires ${APPLY_CONFIRMATION}.`);
  }
  if (!args.resultsCsvPath) {
    throw new Error("Apply mode requires --results-csv.");
  }
  if (!/^[0-9a-f]{64}$/.test(args.approvedPlanSHA256 ?? "")) {
    throw new Error("Apply mode requires --approved-plan-sha256.");
  }
  if (args.approvedPlanSHA256 !== candidateSHA) {
    throw new Error("Approved plan digest does not match the current inputs.");
  }
  if (args.confirmedCount !== candidateCount) {
    throw new Error(
      "Confirmed count does not match the current candidate set.",
    );
  }
}

function buildSummary(input: {
  args: RevenueCatShellCleanupArgs;
  now: Date;
  plan: CleanupPlan;
  results: RevenueCatShellCleanupResult[];
  supabaseSHA: string;
  authAuditSHA: string;
  revenueCatSHA: string;
  cohortSHA: string;
  candidateSHA: string;
}): RevenueCatShellCleanupSummary {
  const count = (status: RevenueCatShellCleanupResultStatus) =>
    input.results.filter((result) => result.status === status).length;
  return {
    generated_at: input.now.toISOString(),
    mode: input.args.apply ? "apply" : "dry-run",
    selection: "empty_inactive_shells_outside_protected_cohort",
    inactive_days: input.args.inactiveDays,
    include_current_supabase_shells: input.args.includeCurrentSupabaseShells,
    supabase_export_sha256: input.supabaseSHA,
    auth_audit_sha256: input.authAuditSHA,
    revenuecat_export_sha256: input.revenueCatSHA,
    protected_cohort_sha256: input.cohortSHA,
    protected_cohort_count: input.plan.protectedCohort.size,
    active_auth_user_count: input.plan.activeAuthUserCount,
    revenuecat_customer_count: input.plan.revenueCatCustomerCount,
    candidate_count: input.plan.candidates.length,
    candidate_sha256: input.candidateSHA,
    deleted_count: count("deleted"),
    queued_count: count("queued"),
    already_absent_count: count("already_absent"),
    protected_by_live_evidence_count: count("protected_live_evidence"),
    failed_count: count("failed"),
    supabase_mutations: false,
  };
}

function printSummary(summary: RevenueCatShellCleanupSummary): void {
  console.log(`mode: ${summary.mode}`);
  console.log(`selection: ${summary.selection}`);
  console.log(`protected_cohort_count: ${summary.protected_cohort_count}`);
  console.log(`active_auth_user_count: ${summary.active_auth_user_count}`);
  console.log(`revenuecat_customers: ${summary.revenuecat_customer_count}`);
  console.log(`candidate_count: ${summary.candidate_count}`);
  console.log(`candidate_sha256: ${summary.candidate_sha256}`);
  console.log(`deleted_count: ${summary.deleted_count}`);
  console.log(`queued_count: ${summary.queued_count}`);
  console.log(`already_absent_count: ${summary.already_absent_count}`);
  console.log(
    `protected_by_live_evidence_count: ${summary.protected_by_live_evidence_count}`,
  );
  console.log(`failed_count: ${summary.failed_count}`);
  console.log("supabase_mutations: false");
}

function result(
  appUserID: string,
  status: RevenueCatShellCleanupResultStatus,
  errorCode: string,
): RevenueCatShellCleanupResult {
  return { app_user_id: appUserID, status, error_code: errorCode };
}

function hasKeys(value: Record<string, unknown> | undefined): boolean {
  return value === undefined || Object.keys(value).length > 0;
}

function meaningful(value: string | null | undefined): boolean {
  return typeof value === "string" && value.trim().length > 0;
}

function parseJSON<T>(source: string): T {
  try {
    return JSON.parse(source) as T;
  } catch {
    throw new Error("invalid_json");
  }
}

export async function sha256Hex(
  value: string | Uint8Array,
): Promise<string> {
  const bytes = typeof value === "string"
    ? new TextEncoder().encode(value)
    : new Uint8Array(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function stableErrorCode(error: unknown): string {
  if (error instanceof DOMException && error.name === "AbortError") {
    return "request_timeout";
  }
  if (error instanceof Error) {
    if (error.message === "response_too_large") return "response_too_large";
    if (error.message === "invalid_json") return "invalid_json";
  }
  return "request_failed";
}

function safeErrorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  return String(error);
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
  return boundedInteger(value, argument, 1, Number.MAX_SAFE_INTEGER);
}

function nonnegativeInteger(value: string, argument: string): number {
  return boundedInteger(value, argument, 0, Number.MAX_SAFE_INTEGER);
}

function boundedInteger(
  value: string,
  argument: string,
  minimum: number,
  maximum: number,
): number {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < minimum || parsed > maximum) {
    throw new Error(
      `${argument} must be an integer from ${minimum} through ${maximum}.`,
    );
  }
  return parsed;
}

function boundedSleep(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}
