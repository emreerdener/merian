/**
 * Guarded cleanup for Merian anonymous "ghost" users.
 *
 * This script is dry-run by default. Execute mode requires:
 *   - a fresh audit snapshot JSON
 *   - SUPABASE_URL
 *   - SUPABASE_SECRET_KEY or SUPABASE_SERVICE_ROLE_KEY
 *   - --execute
 *   - --confirm-delete-likely-empty-ghosts
 */

import {
  adminApiHeaders,
  type AuditSnapshotRow,
  type GhostUserAuditReport,
  requiredAdminApiKey,
} from "./audit_ghost_users.ts";

export interface CleanupArgs {
  snapshotJsonPath: string | null;
  limit: number;
  thresholdDays: number;
  maxSnapshotAgeHours: number;
  execute: boolean;
  confirmed: boolean;
  outputJsonPath: string | null;
}

export interface CleanupCandidate {
  user_id: string;
  age_days: number | null;
  auth_created_at: string | null;
  auth_last_sign_in_at: string | null;
  public_user_exists: boolean;
}

interface CleanupSkippedRow {
  user_id: string;
  reasons: string[];
}

interface CleanupFailure {
  user_id: string;
  error: string;
}

export interface CleanupResult {
  mode: "dry_run" | "execute";
  generated_at: string;
  snapshot_generated_at: string | null;
  snapshot_age_hours: number | null;
  warnings: string[];
  threshold_days: number;
  max_snapshot_age_hours: number;
  total_eligible: number;
  selected_count: number;
  candidates: CleanupCandidate[];
  deleted_auth_users: string[];
  deleted_public_users: string[];
  skipped: CleanupSkippedRow[];
  failures: CleanupFailure[];
}

const DEFAULT_LIMIT = 10;
const DEFAULT_THRESHOLD_DAYS = 30;
const DEFAULT_MAX_SNAPSHOT_AGE_HOURS = 24;

if (import.meta.main) {
  const exitCode = await runCleanup(Deno.args);
  Deno.exit(exitCode);
}

export async function runCleanup(rawArgs: string[]): Promise<number> {
  const args = parseCleanupArgs(rawArgs);
  if (!args.snapshotJsonPath) {
    throw new Error("--snapshot-json is required.");
  }

  const now = new Date();
  const report = await loadAuditReport(args.snapshotJsonPath);
  const result = buildDryRunResult(report, args, now);

  if (args.execute) {
    if (!args.confirmed) {
      throw new Error(
        "--execute also requires --confirm-delete-likely-empty-ghosts.",
      );
    }
    if (result.warnings.length > 0) {
      throw new Error(
        `Refusing execute mode because snapshot is not fresh: ${
          result.warnings.join("; ")
        }`,
      );
    }

    const supabaseUrl = requiredEnv("SUPABASE_URL").replace(/\/$/, "");
    const adminApiKey = requiredAdminApiKey(Deno.env.toObject());
    await executeCleanup(result, supabaseUrl, adminApiKey);
  }

  printCleanupResult(result);
  await writeOutput(result, args.outputJsonPath);

  return result.failures.length > 0 || result.skipped.length > 0 ? 1 : 0;
}

export function parseCleanupArgs(rawArgs: string[]): CleanupArgs {
  const args: CleanupArgs = {
    snapshotJsonPath: null,
    limit: DEFAULT_LIMIT,
    thresholdDays: DEFAULT_THRESHOLD_DAYS,
    maxSnapshotAgeHours: DEFAULT_MAX_SNAPSHOT_AGE_HOURS,
    execute: false,
    confirmed: false,
    outputJsonPath: null,
  };

  for (let index = 0; index < rawArgs.length; index += 1) {
    const arg = rawArgs[index];
    switch (arg) {
      case "--snapshot-json":
        args.snapshotJsonPath = readNextArg(rawArgs, ++index, arg);
        break;
      case "--limit":
        args.limit = parsePositiveInteger(
          readNextArg(rawArgs, ++index, arg),
          arg,
        );
        break;
      case "--threshold-days":
        args.thresholdDays = parsePositiveInteger(
          readNextArg(rawArgs, ++index, arg),
          arg,
        );
        break;
      case "--max-snapshot-age-hours":
        args.maxSnapshotAgeHours = parsePositiveInteger(
          readNextArg(rawArgs, ++index, arg),
          arg,
        );
        break;
      case "--output-json":
        args.outputJsonPath = readNextArg(rawArgs, ++index, arg);
        break;
      case "--execute":
        args.execute = true;
        break;
      case "--confirm-delete-likely-empty-ghosts":
        args.confirmed = true;
        break;
      case "--help":
        printHelpAndExit();
        break;
      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }

  return args;
}

export function buildDryRunResult(
  report: GhostUserAuditReport,
  args: CleanupArgs,
  now: Date,
): CleanupResult {
  const eligibleRows = selectCleanupRows(report.rows, args.thresholdDays);
  const selectedRows = eligibleRows.slice(0, args.limit);
  const snapshotAge = snapshotAgeHours(report.summary.generated_at, now);
  const warnings = snapshotWarnings(
    snapshotAge,
    args.maxSnapshotAgeHours,
    report.summary.generated_at,
  );

  return {
    mode: args.execute ? "execute" : "dry_run",
    generated_at: now.toISOString(),
    snapshot_generated_at: report.summary.generated_at ?? null,
    snapshot_age_hours: snapshotAge,
    warnings,
    threshold_days: args.thresholdDays,
    max_snapshot_age_hours: args.maxSnapshotAgeHours,
    total_eligible: eligibleRows.length,
    selected_count: selectedRows.length,
    candidates: selectedRows.map(toCleanupCandidate),
    deleted_auth_users: [],
    deleted_public_users: [],
    skipped: [],
    failures: [],
  };
}

export function selectCleanupRows(
  rows: AuditSnapshotRow[],
  thresholdDays: number,
): AuditSnapshotRow[] {
  return rows
    .filter((row) => cleanupEligibilityIssues(row, thresholdDays).length === 0)
    .sort((lhs, rhs) => {
      const lhsAge = lhs.age_days ?? -1;
      const rhsAge = rhs.age_days ?? -1;
      return rhsAge - lhsAge || lhs.user_id.localeCompare(rhs.user_id);
    });
}

export function cleanupEligibilityIssues(
  row: AuditSnapshotRow,
  thresholdDays: number,
): string[] {
  const issues: string[] = [];

  if (row.cleanup_recommendation !== "likely_empty_ghost_candidate_30d") {
    issues.push("cleanup recommendation is not candidate_30d");
  }
  if (row.classification !== "likely_empty_ghost") {
    issues.push("classification is not likely_empty_ghost");
  }
  if (row.allowlisted) {
    issues.push("row is allowlisted");
  }
  if (!row.auth.exists) {
    issues.push("auth user is missing");
  }
  if (row.auth.is_anonymous !== true) {
    issues.push("auth user is not anonymous");
  }
  if (normalizedText(row.auth.email)) {
    issues.push("auth user has email");
  }
  if (row.auth.providers.some((provider) => provider !== "anonymous")) {
    issues.push("auth user has non-anonymous provider");
  }
  if (row.age_days == null || row.age_days < thresholdDays) {
    issues.push(`age is below ${thresholdDays} days`);
  }
  if (row.activity.total !== 0) {
    issues.push("row has activity");
  }
  if ((row.activity.bySource.ghost_profile_merge_handoff ?? 0) > 0) {
    issues.push("row has protected ghost merge handoff");
  }
  if (row.identity_flags.hasCustomPublicIdentity) {
    issues.push("row has custom public identity");
  }
  if (normalizedText(row.public_user.email)) {
    issues.push("public user has email");
  }
  if (row.public_user.subscription_tier === "pro") {
    issues.push("public user is pro");
  }
  const passExpiresAt = normalizedText(row.public_user.subscription_expires_at);
  if (passExpiresAt && Date.parse(passExpiresAt) > Date.now()) {
    issues.push("public user has active pass/subscription expiry");
  }

  return issues;
}

async function executeCleanup(
  result: CleanupResult,
  supabaseUrl: string,
  adminApiKey: string,
): Promise<void> {
  for (const candidate of result.candidates) {
    let reservationToken: string | null = null;
    try {
      reservationToken = await reserveGhostUserBulkCleanup(
        supabaseUrl,
        adminApiKey,
        candidate.user_id,
      );
      await deleteAuthUser(supabaseUrl, adminApiKey, candidate.user_id);
      result.deleted_auth_users.push(candidate.user_id);
      if (candidate.public_user_exists) {
        await deletePublicUser(supabaseUrl, adminApiKey, candidate.user_id);
        result.deleted_public_users.push(candidate.user_id);
      }
      await finishGhostUserBulkCleanup(
        supabaseUrl,
        adminApiKey,
        candidate.user_id,
        reservationToken,
        true,
        null,
      );
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      if (reservationToken) {
        try {
          await finishGhostUserBulkCleanup(
            supabaseUrl,
            adminApiKey,
            candidate.user_id,
            reservationToken,
            false,
            "bulk_cleanup_failed",
          );
        } catch (finishError) {
          result.failures.push({
            user_id: candidate.user_id,
            error: `${message}; reservation release failed: ${
              finishError instanceof Error
                ? finishError.message
                : String(finishError)
            }`,
          });
          continue;
        }
      }
      result.failures.push({
        user_id: candidate.user_id,
        error: message,
      });
    }
  }
}

async function reserveGhostUserBulkCleanup(
  supabaseUrl: string,
  adminApiKey: string,
  userId: string,
): Promise<string> {
  const response = await fetch(
    `${supabaseUrl}/rest/v1/rpc/reserve_ghost_user_bulk_cleanup`,
    {
      method: "POST",
      headers: adminApiHeaders(adminApiKey),
      body: JSON.stringify({
        p_ghost_user_id: userId,
        p_lease_minutes: 15,
      }),
    },
  );
  const text = await response.text();
  if (!response.ok) {
    throw new Error(
      `ghost cleanup reservation returned HTTP ${response.status}: ${text}`,
    );
  }

  const token: unknown = text ? JSON.parse(text) : null;
  if (typeof token !== "string" || token.trim() === "") {
    throw new Error("ghost cleanup reservation returned no token");
  }
  return token;
}

async function finishGhostUserBulkCleanup(
  supabaseUrl: string,
  adminApiKey: string,
  userId: string,
  reservationToken: string,
  succeeded: boolean,
  errorCode: string | null,
): Promise<void> {
  const response = await fetch(
    `${supabaseUrl}/rest/v1/rpc/finish_ghost_user_bulk_cleanup`,
    {
      method: "POST",
      headers: adminApiHeaders(adminApiKey),
      body: JSON.stringify({
        p_ghost_user_id: userId,
        p_reservation_token: reservationToken,
        p_succeeded: succeeded,
        p_error_code: errorCode,
      }),
    },
  );
  const text = await response.text();
  if (!response.ok) {
    throw new Error(
      `ghost cleanup reservation finish returned HTTP ${response.status}: ${text}`,
    );
  }
}

async function deleteAuthUser(
  supabaseUrl: string,
  adminApiKey: string,
  userId: string,
): Promise<void> {
  const response = await fetch(
    `${supabaseUrl}/auth/v1/admin/users/${encodeURIComponent(userId)}`,
    {
      method: "DELETE",
      headers: adminApiHeaders(adminApiKey),
    },
  );
  const text = await response.text();
  if (!response.ok) {
    throw new Error(`auth delete returned HTTP ${response.status}: ${text}`);
  }
}

async function deletePublicUser(
  supabaseUrl: string,
  adminApiKey: string,
  userId: string,
): Promise<void> {
  const headers = {
    ...(adminApiHeaders(adminApiKey) as Record<string, string>),
    "Prefer": "return=minimal",
  };
  const response = await fetch(
    `${supabaseUrl}/rest/v1/users?id=eq.${encodeURIComponent(userId)}`,
    {
      method: "DELETE",
      headers,
    },
  );
  const text = await response.text();
  if (!response.ok) {
    throw new Error(
      `public.users delete returned HTTP ${response.status}: ${text}`,
    );
  }
}

async function loadAuditReport(path: string): Promise<GhostUserAuditReport> {
  const text = await Deno.readTextFile(path);
  return JSON.parse(text) as GhostUserAuditReport;
}

function toCleanupCandidate(row: AuditSnapshotRow): CleanupCandidate {
  return {
    user_id: row.user_id,
    age_days: row.age_days,
    auth_created_at: row.auth.created_at,
    auth_last_sign_in_at: row.auth.last_sign_in_at,
    public_user_exists: row.public_user.exists,
  };
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
): string[] {
  if (!generatedAt || ageHours == null) {
    return ["snapshot generated_at is missing or invalid"];
  }
  if (ageHours > maxSnapshotAgeHours) {
    return [
      `snapshot is ${
        ageHours.toFixed(1)
      } hours old; max is ${maxSnapshotAgeHours}`,
    ];
  }
  return [];
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
  console.log(`Ghost user cleanup ${result.mode}`);
  console.log(
    `snapshot_generated_at: ${result.snapshot_generated_at ?? "unknown"}`,
  );
  console.log(
    `snapshot_age_hours: ${
      result.snapshot_age_hours == null
        ? "unknown"
        : result.snapshot_age_hours.toFixed(2)
    }`,
  );
  console.log(`threshold_days: ${result.threshold_days}`);
  console.log(`total_eligible: ${result.total_eligible}`);
  console.log(`selected_count: ${result.selected_count}`);
  console.log(`deleted_auth_users: ${result.deleted_auth_users.length}`);
  console.log(`deleted_public_users: ${result.deleted_public_users.length}`);
  console.log(`failures: ${result.failures.length}`);
  for (const warning of result.warnings) {
    console.warn(`warning: ${warning}`);
  }
  if (result.mode === "dry_run") {
    console.log(
      "No users were deleted. Pass --execute and --confirm-delete-likely-empty-ghosts to delete.",
    );
  }
  for (const candidate of result.candidates.slice(0, 20)) {
    console.log(
      `candidate: ${candidate.user_id} age=${
        candidate.age_days ?? "unknown"
      }d public_user=${
        candidate.public_user_exists ? "yes" : "no"
      } last_sign_in=${candidate.auth_last_sign_in_at ?? "unknown"}`,
    );
  }
  for (const failure of result.failures) {
    console.error(`failure: ${failure.user_id}: ${failure.error}`);
  }
}

function readNextArg(rawArgs: string[], index: number, flag: string): string {
  const value = rawArgs[index];
  if (!value || value.startsWith("--")) {
    throw new Error(`${flag} requires a value.`);
  }
  return value;
}

function parsePositiveInteger(value: string, flag: string): number {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new Error(`${flag} must be a positive integer.`);
  }
  return parsed;
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`${name} is required.`);
  return value;
}

function normalizedText(value: unknown): string | null {
  return typeof value === "string" && value.trim() !== "" ? value.trim() : null;
}

function printHelpAndExit(): never {
  console.log(
    `Usage: deno run --allow-net --allow-env --allow-read --allow-write services/supabase/scripts/cleanup_ghost_users.ts [options]

Required:
  --snapshot-json <path>   Audit JSON from audit_ghost_users.ts.

Dry-run options:
  --limit <number>         Number of eligible candidates to print. Default: 10.
  --threshold-days <n>     Minimum empty-ghost age. Default: 30.
  --output-json <path>     Write cleanup plan/result JSON.

Execute options:
  --execute
  --confirm-delete-likely-empty-ghosts
  --max-snapshot-age-hours <n>  Refuse execute mode when snapshot is older. Default: 24.
`,
  );
  Deno.exit(0);
}
