/**
 * Guarded cleanup for old, empty Merian anonymous accounts.
 *
 * Dry-run is offline and is the default. Execute mode requires an exact plan
 * digest/count, fresh complete Supabase evidence, a reviewed protected cohort,
 * and live read-only RevenueCat verification. It never calls Auth Admin delete
 * or deletes public.users directly: each accepted account enters Merian's
 * durable relational -> storage -> provider -> Auth deletion state machine.
 */

import {
  type AuditSnapshotRow,
  GHOST_AUDIT_CONTRACT_VERSION,
  type GhostUserAuditReport,
} from "./audit_ghost_users.ts";
import {
  buildRevenueCatCustomerAudit,
  canonicalUUID,
  type RevenueCatCustomerAuditRow,
} from "./audit_revenuecat_customers.ts";
import {
  revalidateRevenueCatShell,
  type RevenueCatShellCleanupCandidate,
  sha256Hex,
} from "./cleanup_revenuecat_customer_shells.ts";
import {
  parseDelimitedText,
  readPossiblyGzippedTextArtifact,
} from "./revenuecat_csv.ts";
import { createServiceRoleClientFromEnvironment } from "../functions/_shared/serviceRoleClient.ts";
import type { SupabaseClient } from "@supabase/supabase-js";

const EXECUTE_CONFIRMATION = "--confirm-delete-likely-empty-ghosts";
const DEFAULT_LIMIT = 10;
const DEFAULT_THRESHOLD_DAYS = 30;
const DEFAULT_MAX_SNAPSHOT_AGE_HOURS = 24;
const MAX_BATCH_SIZE = 50;
const REVENUECAT_ABSENT_EXPORT_SENTINEL = "1970-01-01T00:00:00.000Z";

export interface CleanupArgs {
  snapshotJsonPath: string | null;
  revenueCatCustomersCsvPath: string | null;
  protectedCohortCsvPath: string | null;
  limit: number;
  thresholdDays: number;
  maxSnapshotAgeHours: number;
  execute: boolean;
  confirmed: boolean;
  approvedPlanSHA256: string | null;
  confirmedCount: number | null;
  projectID: string | null;
  outputJsonPath: string | null;
}

export interface CleanupCandidate {
  user_id: string;
  age_days: number | null;
  auth_created_at: string | null;
  auth_last_sign_in_at: string | null;
  public_user_exists: boolean;
  revenuecat_customer_id: string;
  revenuecat_export_state: "absent" | "empty_inactive";
  revenuecat_export_last_seen_at: string;
}

interface CleanupExcludedRow {
  user_id: string;
  reason: string;
}

interface CleanupExecutionRow {
  user_id: string;
  status:
    | "database_blocked"
    | "provider_blocked"
    | "deletion_started"
    | "failed";
  revenuecat_status: string;
  job_id: string;
  error_code: string;
}

export interface CleanupResult {
  mode: "dry_run" | "execute";
  generated_at: string;
  snapshot_generated_at: string | null;
  snapshot_age_hours: number | null;
  warnings: string[];
  threshold_days: number;
  max_snapshot_age_hours: number;
  protected_cohort_count: number;
  revenuecat_customer_count: number;
  audit_eligible_count: number;
  provider_eligible_count: number;
  selected_count: number;
  candidate_sha256: string;
  revenuecat_export_sha256: string;
  protected_cohort_sha256: string;
  candidates: CleanupCandidate[];
  exclusions: CleanupExcludedRow[];
  execution: CleanupExecutionRow[];
  direct_auth_deletions: 0;
  direct_public_user_deletions: 0;
}

interface CleanupPlan {
  candidates: CleanupCandidate[];
  exclusions: CleanupExcludedRow[];
  protectedCohort: Set<string>;
  revenueCatCustomerCount: number;
  auditEligibleCount: number;
  providerEligibleCount: number;
}

interface InspectCandidateRow {
  eligible?: boolean;
  blockers?: unknown;
}

interface DeletionRequestRow {
  job_id?: unknown;
  job_status?: unknown;
  manual_provider_revocation_required?: unknown;
}

if (import.meta.main) {
  try {
    Deno.exit(await runCleanup(Deno.args));
  } catch (error) {
    console.error(
      `Ghost cleanup failed: ${
        error instanceof Error ? error.message : String(error)
      }`,
    );
    Deno.exit(2);
  }
}

export async function runCleanup(
  rawArgs: string[],
  dependencies: {
    fetcher?: typeof fetch;
    now?: Date;
    apiKey?: string | null;
    sleep?: (milliseconds: number) => Promise<void>;
    supabase?: SupabaseClient;
  } = {},
): Promise<number> {
  const args = parseCleanupArgs(rawArgs);
  requireInputs(args);

  const [report, revenueCatArtifact, protectedCohortArtifact] = await Promise
    .all([
      loadAuditReport(args.snapshotJsonPath!),
      readPossiblyGzippedTextArtifact(args.revenueCatCustomersCsvPath!),
      readPossiblyGzippedTextArtifact(args.protectedCohortCsvPath!),
    ]);
  const now = dependencies.now ?? new Date();
  const result = await buildDryRunResult(
    report,
    args,
    now,
    revenueCatArtifact.text,
    protectedCohortArtifact.text,
    await sha256Hex(revenueCatArtifact.sourceBytes),
    await sha256Hex(protectedCohortArtifact.sourceBytes),
  );

  if (args.execute) {
    validateExecuteAuthorization(args, result);
    const apiKey = dependencies.apiKey ??
      Deno.env.get("REVENUECAT_CLEANUP_V2_API_KEY") ?? null;
    const projectID = args.projectID ??
      Deno.env.get("REVENUECAT_PROJECT_ID") ?? null;
    if (!apiKey?.trim().startsWith("sk_")) {
      throw new Error(
        "REVENUECAT_CLEANUP_V2_API_KEY must be a RevenueCat V2 server-side secret key.",
      );
    }
    if (!projectID || !/^proj[a-zA-Z0-9_-]{4,251}$/.test(projectID)) {
      throw new Error(
        "A valid --project-id or REVENUECAT_PROJECT_ID is required.",
      );
    }

    await executeCleanup({
      result,
      report,
      protectedCohort: parseProtectedCohort(
        protectedCohortArtifact.text,
        report,
      ),
      supabase: dependencies.supabase ??
        createServiceRoleClientFromEnvironment(),
      projectID,
      apiKey: apiKey.trim(),
      fetcher: dependencies.fetcher ?? fetch,
      sleep: dependencies.sleep ?? boundedSleep,
      now,
    });
  }

  printCleanupResult(result);
  await writeOutput(result, args.outputJsonPath);
  return result.execution.some((row) => row.status !== "deletion_started")
    ? 1
    : 0;
}

export function parseCleanupArgs(rawArgs: string[]): CleanupArgs {
  const args: CleanupArgs = {
    snapshotJsonPath: null,
    revenueCatCustomersCsvPath: null,
    protectedCohortCsvPath: null,
    limit: DEFAULT_LIMIT,
    thresholdDays: DEFAULT_THRESHOLD_DAYS,
    maxSnapshotAgeHours: DEFAULT_MAX_SNAPSHOT_AGE_HOURS,
    execute: false,
    confirmed: false,
    approvedPlanSHA256: null,
    confirmedCount: null,
    projectID: null,
    outputJsonPath: null,
  };

  for (let index = 0; index < rawArgs.length; index += 1) {
    const argument = rawArgs[index];
    switch (argument) {
      case "--snapshot-json":
        args.snapshotJsonPath = nextArgument(rawArgs, ++index, argument);
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
      case "--limit":
        args.limit = boundedInteger(
          nextArgument(rawArgs, ++index, argument),
          argument,
          1,
          MAX_BATCH_SIZE,
        );
        break;
      case "--threshold-days":
        args.thresholdDays = boundedInteger(
          nextArgument(rawArgs, ++index, argument),
          argument,
          30,
          365,
        );
        break;
      case "--max-snapshot-age-hours":
        args.maxSnapshotAgeHours = boundedInteger(
          nextArgument(rawArgs, ++index, argument),
          argument,
          1,
          168,
        );
        break;
      case "--approved-plan-sha256":
        args.approvedPlanSHA256 = nextArgument(rawArgs, ++index, argument)
          .toLowerCase();
        break;
      case "--confirm-count":
        args.confirmedCount = boundedInteger(
          nextArgument(rawArgs, ++index, argument),
          argument,
          1,
          MAX_BATCH_SIZE,
        );
        break;
      case "--project-id":
        args.projectID = nextArgument(rawArgs, ++index, argument);
        break;
      case "--output-json":
        args.outputJsonPath = nextArgument(rawArgs, ++index, argument);
        break;
      case "--execute":
        args.execute = true;
        break;
      case EXECUTE_CONFIRMATION:
        args.confirmed = true;
        break;
      case "--help":
        printHelpAndExit();
        break;
      default:
        throw new Error(`Unknown argument: ${argument}`);
    }
  }
  return args;
}

export async function buildDryRunResult(
  report: GhostUserAuditReport,
  args: CleanupArgs,
  now: Date,
  revenueCatSource: string,
  protectedCohortSource: string,
  revenueCatExportSHA256 = "",
  protectedCohortSHA256 = "",
): Promise<CleanupResult> {
  const plan = buildCleanupPlan({
    report,
    thresholdDays: args.thresholdDays,
    limit: args.limit,
    revenueCatSource,
    protectedCohortSource,
    now,
  });
  const snapshotAge = snapshotAgeHours(report.summary.generated_at, now);
  const warnings = snapshotWarnings(
    snapshotAge,
    args.maxSnapshotAgeHours,
    report.summary.generated_at,
    report.summary.missing_optional_sources,
    report.summary.audit_contract_version,
  );

  return {
    mode: args.execute ? "execute" : "dry_run",
    generated_at: now.toISOString(),
    snapshot_generated_at: report.summary.generated_at ?? null,
    snapshot_age_hours: snapshotAge,
    warnings,
    threshold_days: args.thresholdDays,
    max_snapshot_age_hours: args.maxSnapshotAgeHours,
    protected_cohort_count: plan.protectedCohort.size,
    revenuecat_customer_count: plan.revenueCatCustomerCount,
    audit_eligible_count: plan.auditEligibleCount,
    provider_eligible_count: plan.providerEligibleCount,
    selected_count: plan.candidates.length,
    candidate_sha256: await cleanupCandidateSHA256(plan.candidates),
    revenuecat_export_sha256: revenueCatExportSHA256,
    protected_cohort_sha256: protectedCohortSHA256,
    candidates: plan.candidates,
    exclusions: plan.exclusions,
    execution: [],
    direct_auth_deletions: 0,
    direct_public_user_deletions: 0,
  };
}

export function buildCleanupPlan(input: {
  report: GhostUserAuditReport;
  thresholdDays: number;
  limit: number;
  revenueCatSource: string;
  protectedCohortSource: string;
  now: Date;
}): CleanupPlan {
  if (input.thresholdDays < 30 || input.thresholdDays > 365) {
    throw new Error("Cleanup threshold must be between 30 and 365 days.");
  }
  const protectedCohort = parseProtectedCohort(
    input.protectedCohortSource,
    input.report,
  );
  const supabaseSource = `id,_audit_scope\n${
    input.report.rows.map((row) => `${row.user_id},snapshot`).join("\n")
  }\n`;
  const revenueCatAudit = buildRevenueCatCustomerAudit({
    supabaseSource,
    revenueCatSource: input.revenueCatSource,
    inactiveDays: input.thresholdDays,
    now: input.now,
  });
  const auditEligibleRows = selectCleanupRows(
    input.report.rows,
    input.thresholdDays,
    input.now,
  );
  const providerEligible: CleanupCandidate[] = [];
  const exclusions: CleanupExcludedRow[] = [];

  for (const row of auditEligibleRows) {
    const canonicalID = requiredCanonicalUUID(row.user_id, "audit user id");
    if (protectedCohort.has(canonicalID)) {
      exclusions.push({ user_id: row.user_id, reason: "protected_cohort" });
      continue;
    }
    const related = revenueCatAudit.rows.filter((customer) =>
      customer.linked_supabase_user_id === canonicalID ||
      canonicalUUID(customer.app_user_id) === canonicalID
    );
    const evidenceIssue = revenueCatEvidenceIssue(
      related,
      canonicalID,
      input.thresholdDays,
    );
    if (evidenceIssue) {
      exclusions.push({ user_id: row.user_id, reason: evidenceIssue });
      continue;
    }
    const canonicalCustomer = related[0] ?? null;
    providerEligible.push({
      ...toCleanupCandidate(row),
      revenuecat_customer_id: canonicalID,
      revenuecat_export_state: canonicalCustomer ? "empty_inactive" : "absent",
      revenuecat_export_last_seen_at: canonicalCustomer?.last_seen_at ??
        REVENUECAT_ABSENT_EXPORT_SENTINEL,
    });
  }

  providerEligible.sort((lhs, rhs) =>
    (rhs.age_days ?? -1) - (lhs.age_days ?? -1) ||
    lhs.user_id.localeCompare(rhs.user_id)
  );
  return {
    candidates: providerEligible.slice(0, input.limit),
    exclusions,
    protectedCohort,
    revenueCatCustomerCount: revenueCatAudit.summary.revenuecat_customer_count,
    auditEligibleCount: auditEligibleRows.length,
    providerEligibleCount: providerEligible.length,
  };
}

export function selectCleanupRows(
  rows: AuditSnapshotRow[],
  thresholdDays: number,
  now = new Date(),
): AuditSnapshotRow[] {
  return rows
    .filter((row) =>
      cleanupEligibilityIssues(row, thresholdDays, now).length === 0
    )
    .sort((lhs, rhs) => {
      const lhsAge = lhs.age_days ?? -1;
      const rhsAge = rhs.age_days ?? -1;
      return rhsAge - lhsAge || lhs.user_id.localeCompare(rhs.user_id);
    });
}

export function cleanupEligibilityIssues(
  row: AuditSnapshotRow,
  thresholdDays: number,
  now = new Date(),
): string[] {
  const issues: string[] = [];
  if (row.cleanup_recommendation !== "likely_empty_ghost_candidate_30d") {
    issues.push("cleanup recommendation is not candidate_30d");
  }
  if (row.classification !== "likely_empty_ghost") {
    issues.push("classification is not likely_empty_ghost");
  }
  if (row.allowlisted) issues.push("row is allowlisted");
  if (!row.auth.exists) issues.push("auth user is missing");
  if (row.auth.is_anonymous !== true) {
    issues.push("auth user is not anonymous");
  }
  if (normalizedText(row.auth.email)) issues.push("auth user has email");
  if (row.auth.providers.some((provider) => provider !== "anonymous")) {
    issues.push("auth user has non-anonymous provider");
  }
  if (row.age_days == null || row.age_days < thresholdDays) {
    issues.push(`age is below ${thresholdDays} days`);
  }
  const lastSignInAt = normalizedText(row.auth.last_sign_in_at);
  const lastSignInMs = lastSignInAt ? Date.parse(lastSignInAt) : Number.NaN;
  if (
    !Number.isFinite(lastSignInMs) ||
    lastSignInMs > now.getTime() - thresholdDays * 86_400_000
  ) {
    issues.push(`last sign-in is unknown or within ${thresholdDays} days`);
  }
  if (row.activity.total !== 0) issues.push("row has activity");
  if ((row.activity.bySource.ghost_profile_merge_handoff ?? 0) > 0) {
    issues.push("row has protected ghost merge handoff");
  }
  if (row.identity_flags.hasCustomPublicIdentity) {
    issues.push("row has custom public identity");
  }
  if (row.public_user.exists) {
    if (normalizedText(row.public_user.email)) {
      issues.push("public user has email");
    }
    if (row.public_user.subscription_tier !== "free") {
      issues.push("public user projection is not free");
    }
    if (normalizedText(row.public_user.subscription_expires_at)) {
      issues.push("public user has subscription/pass expiry evidence");
    }
  }
  return issues;
}

export async function cleanupCandidateSHA256(
  candidates: CleanupCandidate[],
): Promise<string> {
  const canonical = [...candidates]
    .sort((lhs, rhs) => lhs.user_id.localeCompare(rhs.user_id))
    .map((candidate) => ({
      user_id: candidate.user_id,
      age_days: candidate.age_days,
      auth_created_at: candidate.auth_created_at,
      auth_last_sign_in_at: candidate.auth_last_sign_in_at,
      revenuecat_customer_id: candidate.revenuecat_customer_id,
      revenuecat_export_state: candidate.revenuecat_export_state,
      revenuecat_export_last_seen_at: candidate.revenuecat_export_last_seen_at,
    }));
  return await sha256Hex(`${JSON.stringify(canonical)}\n`);
}

async function executeCleanup(input: {
  result: CleanupResult;
  report: GhostUserAuditReport;
  protectedCohort: Set<string>;
  supabase: SupabaseClient;
  projectID: string;
  apiKey: string;
  fetcher: typeof fetch;
  sleep: (milliseconds: number) => Promise<void>;
  now: Date;
}): Promise<void> {
  const activeAuthIDs = new Set(
    input.report.rows.filter((row) => row.auth.exists).map((row) =>
      requiredCanonicalUUID(row.user_id, "audit user id")
    ),
  );
  const inactiveBeforeMs = input.now.getTime() -
    input.result.threshold_days * 86_400_000;

  for (const candidate of input.result.candidates) {
    let reservationToken: string | null = null;
    let intakeCompleted = false;
    try {
      const inspection = await inspectDatabaseCandidate(
        input.supabase,
        candidate.user_id,
        input.result.threshold_days,
      );
      if (!inspection.eligible) {
        input.result.execution.push({
          user_id: candidate.user_id,
          status: "database_blocked",
          revenuecat_status: "not_checked",
          job_id: "",
          error_code: inspection.blockers.join(","),
        });
        continue;
      }

      reservationToken = await reserveGhostUserBulkCleanup(
        input.supabase,
        candidate.user_id,
      );
      const candidateAuthIDs = new Set(activeAuthIDs);
      candidateAuthIDs.delete(candidate.revenuecat_customer_id);
      const verification = await revalidateRevenueCatShell({
        candidate: toRevenueCatVerificationCandidate(candidate),
        protectedCohort: input.protectedCohort,
        activeAuthUserIDs: candidateAuthIDs,
        inactiveBeforeMs,
        projectID: input.projectID,
        apiKey: input.apiKey,
        fetcher: input.fetcher,
        sleep: input.sleep,
      });
      if (
        verification.status !== "verified_empty" &&
        verification.status !== "already_absent"
      ) {
        await finishGhostUserBulkCleanup(
          input.supabase,
          candidate.user_id,
          reservationToken,
          false,
          `revenuecat_${verification.status}`,
        );
        reservationToken = null;
        input.result.execution.push({
          user_id: candidate.user_id,
          status: verification.status === "failed"
            ? "failed"
            : "provider_blocked",
          revenuecat_status: verification.status,
          job_id: "",
          error_code: verification.error_code,
        });
        continue;
      }

      const deletion = await requestGuardedDeletion(
        input.supabase,
        candidate.user_id,
        reservationToken,
        input.result.threshold_days,
        input.result.candidate_sha256,
        input.projectID,
        new Date().toISOString(),
      );
      intakeCompleted = true;
      reservationToken = null;
      input.result.execution.push({
        user_id: candidate.user_id,
        status: "deletion_started",
        revenuecat_status: verification.status,
        job_id: deletion.jobID,
        error_code: "",
      });
    } catch (error) {
      let errorMessage = error instanceof Error ? error.message : String(error);
      if (reservationToken && !intakeCompleted) {
        try {
          await finishGhostUserBulkCleanup(
            input.supabase,
            candidate.user_id,
            reservationToken,
            false,
            "guarded_cleanup_failed",
          );
        } catch (releaseError) {
          errorMessage += `; reservation release failed: ${
            releaseError instanceof Error
              ? releaseError.message
              : String(releaseError)
          }`;
        }
      }
      input.result.execution.push({
        user_id: candidate.user_id,
        status: "failed",
        revenuecat_status: "uncertain",
        job_id: "",
        error_code: boundedError(errorMessage),
      });
    }
  }
}

async function inspectDatabaseCandidate(
  supabase: SupabaseClient,
  userID: string,
  thresholdDays: number,
): Promise<{ eligible: boolean; blockers: string[] }> {
  const { data, error } = await supabase.rpc(
    "inspect_empty_ghost_cleanup_candidate",
    { p_user_id: userID, p_threshold_days: thresholdDays },
  );
  if (error) {
    throw new Error(
      `candidate inspection returned ${error.code}: ${error.message}`,
    );
  }
  const row = firstRPCRow<InspectCandidateRow>(data);
  if (typeof row.eligible !== "boolean" || !Array.isArray(row.blockers)) {
    throw new Error("candidate inspection returned an invalid result");
  }
  return {
    eligible: row.eligible,
    blockers: row.blockers.filter((value): value is string =>
      typeof value === "string"
    ),
  };
}

async function reserveGhostUserBulkCleanup(
  supabase: SupabaseClient,
  userID: string,
): Promise<string> {
  const { data, error } = await supabase.rpc(
    "reserve_ghost_user_bulk_cleanup",
    {
      p_ghost_user_id: userID,
      p_lease_minutes: 15,
    },
  );
  if (error) {
    throw new Error(
      `cleanup reservation returned ${error.code}: ${error.message}`,
    );
  }
  if (typeof data !== "string" || data.trim() === "") {
    throw new Error("cleanup reservation returned no token");
  }
  return data;
}

async function finishGhostUserBulkCleanup(
  supabase: SupabaseClient,
  userID: string,
  reservationToken: string,
  succeeded: boolean,
  errorCode: string,
): Promise<void> {
  const { error } = await supabase.rpc("finish_ghost_user_bulk_cleanup", {
    p_ghost_user_id: userID,
    p_reservation_token: reservationToken,
    p_succeeded: succeeded,
    p_error_code: errorCode,
  });
  if (error) {
    throw new Error(
      `cleanup reservation finish returned ${error.code}: ${error.message}`,
    );
  }
}

async function requestGuardedDeletion(
  supabase: SupabaseClient,
  userID: string,
  reservationToken: string,
  thresholdDays: number,
  candidatePlanSHA256: string,
  projectID: string,
  verifiedAt: string,
): Promise<{ jobID: string }> {
  const { data, error } = await supabase.rpc(
    "request_empty_ghost_account_deletion",
    {
      p_user_id: userID,
      p_reservation_token: reservationToken,
      p_threshold_days: thresholdDays,
      p_candidate_plan_sha256: candidatePlanSHA256,
      p_revenuecat_project_id: projectID,
      p_revenuecat_verified_at: verifiedAt,
      p_revenuecat_checked_customer_count: 1,
    },
  );
  if (error) {
    throw new Error(
      `guarded deletion intake returned ${error.code}: ${error.message}`,
    );
  }
  const row = firstRPCRow<DeletionRequestRow>(data);
  if (
    typeof row.job_id !== "string" || row.job_id.trim() === "" ||
    row.job_status !== "storage_pending" ||
    row.manual_provider_revocation_required !== false
  ) {
    throw new Error(
      "guarded deletion intake returned an invalid durable state",
    );
  }
  return { jobID: row.job_id };
}

function revenueCatEvidenceIssue(
  related: RevenueCatCustomerAuditRow[],
  canonicalID: string,
  thresholdDays: number,
): string | null {
  if (related.length === 0) return null;
  if (related.some((row) => row.has_purchase_evidence)) {
    return "revenuecat_purchase_or_promotion_evidence";
  }
  if (related.some((row) => row.has_customer_attributes)) {
    return "revenuecat_customer_attribute_evidence";
  }
  if (related.length !== 1) return "revenuecat_multiple_linked_customers";
  const row = related[0];
  if (
    row.app_user_id !== canonicalID ||
    row.classification !== "canonical_supabase_uuid"
  ) {
    return "revenuecat_alias_or_case_variant_evidence";
  }
  if (
    row.last_seen_at === null || row.inactive_days === null ||
    row.inactive_days < thresholdDays
  ) {
    return "revenuecat_recent_or_unknown_activity";
  }
  return null;
}

function parseProtectedCohort(
  source: string,
  report: GhostUserAuditReport,
): Set<string> {
  const normalizedSource = source.startsWith("\uFEFF")
    ? source.slice(1)
    : source;
  const firstLine = normalizedSource.split(/\r?\n/, 1)[0]?.trim() ?? "";
  const parsed =
    !/[;,\t]/.test(firstLine) && ["id", "user_id"].includes(firstLine)
      ? {
        headers: [firstLine],
        rows: normalizedSource.split(/\r?\n/).slice(1)
          .map((value) => value.trim()).filter(Boolean)
          .map((value) => ({ [firstLine]: value })),
      }
      : parseDelimitedText(normalizedSource);
  if (
    parsed.headers.length !== 1 ||
    !["id", "user_id"].includes(parsed.headers[0])
  ) {
    throw new Error(
      "Protected cohort must be a one-column CSV headed id or user_id.",
    );
  }
  const snapshotAuthIDs = new Set(
    report.rows.filter((row) => row.auth.exists).map((row) =>
      requiredCanonicalUUID(row.user_id, "audit user id")
    ),
  );
  const cohort = new Set<string>();
  for (const row of parsed.rows) {
    const id = requiredCanonicalUUID(
      row[parsed.headers[0]],
      "protected cohort id",
    );
    if (!snapshotAuthIDs.has(id)) {
      throw new Error(
        "Protected cohort contains an ID without Supabase Auth snapshot evidence.",
      );
    }
    if (cohort.has(id)) {
      throw new Error("Protected cohort contains a duplicate id.");
    }
    cohort.add(id);
  }
  if (cohort.size === 0) {
    throw new Error("Protected cohort must contain at least one reviewed id.");
  }
  return cohort;
}

function toRevenueCatVerificationCandidate(
  candidate: CleanupCandidate,
): RevenueCatShellCleanupCandidate {
  return {
    app_user_id: candidate.revenuecat_customer_id,
    classification: "canonical_supabase_uuid",
    linked_supabase_user_id: candidate.revenuecat_customer_id,
    last_seen_at: candidate.revenuecat_export_last_seen_at,
    inactive_days: candidate.age_days ?? 0,
    reason: "inactive_current_supabase_shell",
  };
}

function toCleanupCandidate(row: AuditSnapshotRow): Omit<
  CleanupCandidate,
  | "revenuecat_customer_id"
  | "revenuecat_export_state"
  | "revenuecat_export_last_seen_at"
> {
  return {
    user_id: row.user_id,
    age_days: row.age_days,
    auth_created_at: row.auth.created_at,
    auth_last_sign_in_at: row.auth.last_sign_in_at,
    public_user_exists: row.public_user.exists,
  };
}

function validateExecuteAuthorization(
  args: CleanupArgs,
  result: CleanupResult,
): void {
  if (!args.confirmed) {
    throw new Error(`--execute also requires ${EXECUTE_CONFIRMATION}.`);
  }
  if (!args.outputJsonPath) {
    throw new Error(
      "--output-json is required in execute mode for the results ledger.",
    );
  }
  if (result.warnings.length > 0) {
    throw new Error(`Execute refused: ${result.warnings.join("; ")}`);
  }
  if (result.selected_count === 0) {
    throw new Error(
      "Execute refused because the reviewed plan has no candidates.",
    );
  }
  if (!/^[0-9a-f]{64}$/.test(args.approvedPlanSHA256 ?? "")) {
    throw new Error("--approved-plan-sha256 must be the dry-run digest.");
  }
  if (args.approvedPlanSHA256 !== result.candidate_sha256) {
    throw new Error(
      "Approved plan digest does not match the current candidate plan.",
    );
  }
  if (args.confirmedCount !== result.selected_count) {
    throw new Error(
      "--confirm-count does not match the current candidate count.",
    );
  }
}

function requireInputs(args: CleanupArgs): void {
  if (
    !args.snapshotJsonPath || !args.revenueCatCustomersCsvPath ||
    !args.protectedCohortCsvPath
  ) {
    throw new Error(
      "--snapshot-json, --revenuecat-customers-csv, and --protected-cohort-csv are required.",
    );
  }
}

async function loadAuditReport(path: string): Promise<GhostUserAuditReport> {
  const parsed = JSON.parse(await Deno.readTextFile(path)) as unknown;
  if (
    typeof parsed !== "object" || parsed === null ||
    !Array.isArray((parsed as GhostUserAuditReport).rows) ||
    typeof (parsed as GhostUserAuditReport).summary !== "object" ||
    (parsed as GhostUserAuditReport).summary === null
  ) {
    throw new Error("Audit snapshot JSON has an invalid shape.");
  }
  return parsed as GhostUserAuditReport;
}

function firstRPCRow<T extends object>(data: unknown): T {
  const row = Array.isArray(data) ? data[0] : data;
  if (typeof row !== "object" || row === null || Array.isArray(row)) {
    throw new Error("RPC returned no result row");
  }
  return row as T;
}

function snapshotAgeHours(
  generatedAt: string | null | undefined,
  now: Date,
): number | null {
  if (!generatedAt) return null;
  const timestamp = Date.parse(generatedAt);
  if (Number.isNaN(timestamp)) return null;
  return Math.max(0, (now.getTime() - timestamp) / 3_600_000);
}

function snapshotWarnings(
  ageHours: number | null,
  maxSnapshotAgeHours: number,
  generatedAt: string | null | undefined,
  missingOptionalSources: string[] | undefined,
  auditContractVersion: number | undefined,
): string[] {
  const warnings: string[] = [];
  if (auditContractVersion !== GHOST_AUDIT_CONTRACT_VERSION) {
    warnings.push(
      `audit contract version is ${
        auditContractVersion ?? "missing"
      }; required ${GHOST_AUDIT_CONTRACT_VERSION}`,
    );
  }
  if (!generatedAt || ageHours == null) {
    warnings.push("snapshot generated_at is missing or invalid");
  } else if (ageHours > maxSnapshotAgeHours) {
    warnings.push(
      `snapshot is ${
        ageHours.toFixed(1)
      } hours old; max is ${maxSnapshotAgeHours}`,
    );
  }
  if (!Array.isArray(missingOptionalSources)) {
    warnings.push("audit missing optional-source coverage inventory");
  } else if (missingOptionalSources.length > 0) {
    warnings.push(
      `audit could not read activity sources: ${
        missingOptionalSources.join(",")
      }`,
    );
  }
  return warnings;
}

async function writeOutput(
  result: CleanupResult,
  outputJsonPath: string | null,
): Promise<void> {
  if (!outputJsonPath) return;
  await Deno.writeTextFile(
    outputJsonPath,
    `${JSON.stringify(result, null, 2)}\n`,
  );
  console.log(`cleanup_output_json: ${outputJsonPath}`);
}

function printCleanupResult(result: CleanupResult): void {
  console.log(`mode: ${result.mode}`);
  console.log(
    `snapshot_generated_at: ${result.snapshot_generated_at ?? "unknown"}`,
  );
  console.log(`protected_cohort_count: ${result.protected_cohort_count}`);
  console.log(`revenuecat_customers: ${result.revenuecat_customer_count}`);
  console.log(`audit_eligible_count: ${result.audit_eligible_count}`);
  console.log(`provider_eligible_count: ${result.provider_eligible_count}`);
  console.log(`selected_count: ${result.selected_count}`);
  console.log(`candidate_sha256: ${result.candidate_sha256}`);
  console.log(
    `deletion_started_count: ${
      result.execution.filter((row) => row.status === "deletion_started").length
    }`,
  );
  for (const warning of result.warnings) console.warn(`warning: ${warning}`);
  if (result.mode === "dry_run") {
    console.log("No Supabase or RevenueCat records were changed.");
  }
}

function nextArgument(rawArgs: string[], index: number, flag: string): string {
  const value = rawArgs[index];
  if (!value || value.startsWith("--")) {
    throw new Error(`${flag} requires a value.`);
  }
  return value;
}

function boundedInteger(
  value: string,
  flag: string,
  minimum: number,
  maximum: number,
): number {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < minimum || parsed > maximum) {
    throw new Error(`${flag} must be between ${minimum} and ${maximum}.`);
  }
  return parsed;
}

function normalizedText(value: unknown): string | null {
  return typeof value === "string" && value.trim() !== "" ? value.trim() : null;
}

function requiredCanonicalUUID(value: string, label: string): string {
  const canonical = canonicalUUID(value);
  if (!canonical) throw new Error(`${label} is not a UUID.`);
  return canonical;
}

function boundedError(value: string): string {
  return value.replaceAll(/[\r\n\t]+/g, " ").slice(0, 300);
}

async function boundedSleep(milliseconds: number): Promise<void> {
  await new Promise((resolve) =>
    setTimeout(resolve, Math.min(milliseconds, 2_000))
  );
}

function printHelpAndExit(): never {
  console.log(
    `Usage: deno run --allow-net --allow-env --allow-read --allow-write services/supabase/scripts/cleanup_ghost_users.ts [options]

Required for dry-run:
  --snapshot-json <path>                 Fresh audit_ghost_users JSON.
  --revenuecat-customers-csv <path>      Fresh RevenueCat Export all CSV/GZ.
  --protected-cohort-csv <path>          Reviewed one-column id/user_id CSV.

Dry-run options:
  --limit <1..50>                        Batch size. Default: 10.
  --threshold-days <30..365>             Inactivity floor. Default: 30.
  --output-json <path>                   Write the review/result ledger.

Execute-only requirements:
  --execute ${EXECUTE_CONFIRMATION}
  --approved-plan-sha256 <digest> --confirm-count <count>
  --project-id <RevenueCat project id>   Or REVENUECAT_PROJECT_ID.
  --output-json <path>                   Mandatory durable operator ledger.
  REVENUECAT_CLEANUP_V2_API_KEY          Dedicated V2 secret; used for GET only.

Execute rechecks the database, reads RevenueCat live without deleting it, and
starts Merian's storage-first/Auth-last account deletion workflow.
`,
  );
  Deno.exit(0);
}
