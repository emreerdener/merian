/**
 * Reads service-only RevenueCat reconciliation backlog health and writes
 * operator summaries.
 *
 * Required env:
 *   SUPABASE_URL
 *   SUPABASE_SERVER_API_KEY, deploy-synchronized
 *   MERIAN_SUPABASE_SERVER_API_KEY, platform SUPABASE_SECRET_KEYS,
 *   local/manual SUPABASE_SECRET_KEY, or the migration-only
 *   SUPABASE_SERVICE_ROLE_KEY fallback
 */

import { createServiceRoleClientFromEnvironmentWithOptions } from "../functions/_shared/serviceRoleClient.ts";
import type { SupabaseClient } from "@supabase/supabase-js";

const MONITOR_REQUEST_TIMEOUT_MS = 15_000;
const MONITOR_MAXIMUM_RESPONSE_BYTES = 64 * 1_024;
const DEFAULT_WARNING_PREPARED_ROTATIONS = 100;
const DEFAULT_CRITICAL_PREPARED_ROTATIONS = 500;

export type RevenueCatMonitorFailurePolicy = "critical" | "warning" | "never";
export type RevenueCatBacklogStatus = "ok" | "warning" | "critical";
export type PurchasePrincipalSignoutRotationHealthMode =
  | "expand-compatible"
  | "required";
export type PurchasePrincipalHealthAvailability = "available" | "not_deployed";

export interface RevenueCatMonitorArgs {
  warningAfterMinutes: number;
  criticalAfterMinutes: number;
  warningPreparedRotations: number;
  criticalPreparedRotations: number;
  failOn: RevenueCatMonitorFailurePolicy;
  purchasePrincipalSignoutRotationHealthMode:
    PurchasePrincipalSignoutRotationHealthMode;
  summaryJsonPath: string | null;
  summaryMarkdownPath: string | null;
}

export interface RevenueCatReconciliationHealth {
  generated_at: string;
  due_count: number;
  expired_claim_count: number;
  oldest_due_at: string | null;
  oldest_due_age_seconds: number | null;
  signout_prepared_count: number;
  signout_bound_count: number;
  oldest_signout_pending_at: string | null;
  oldest_signout_pending_age_seconds: number | null;
}

export interface PurchasePrincipalHealth {
  generated_at: string;
  active_principal_count: number;
  pending_principal_count: number;
  unbound_active_principal_count: number;
  due_reconciliation_count: number;
  expired_claim_count: number;
  oldest_due_at: string | null;
  oldest_due_age_seconds: number | null;
  oldest_pending_at: string | null;
  oldest_pending_age_seconds: number | null;
}

export interface PurchasePrincipalSignoutRotationHealth {
  generated_at: string;
  prepared_count: number;
  expired_prepared_count: number;
  oldest_prepared_at: string | null;
  oldest_prepared_age_seconds: number | null;
  completed_last_24h: number;
  cancelled_last_24h: number;
}

export interface RevenueCatMonitorSummary {
  generated_at: string;
  status: RevenueCatBacklogStatus;
  thresholds: {
    warning_after_minutes: number;
    critical_after_minutes: number;
    warning_prepared_rotations: number;
    critical_prepared_rotations: number;
  };
  failure_policy: {
    fail_on: RevenueCatMonitorFailurePolicy;
    should_fail: boolean;
  };
  health: RevenueCatReconciliationHealth;
  purchase_principal_health_availability: "available";
  purchase_principal_health: PurchasePrincipalHealth;
  purchase_principal_signout_rotation_health_availability:
    PurchasePrincipalHealthAvailability;
  purchase_principal_signout_rotation_health:
    | PurchasePrincipalSignoutRotationHealth
    | null;
}

interface HealthRpcError {
  code: string;
  message: string;
}

if (import.meta.main) {
  const exitCode = await runRevenueCatMonitor(Deno.args);
  Deno.exit(exitCode);
}

export async function runRevenueCatMonitor(
  rawArgs: string[],
): Promise<number> {
  const args = parseRevenueCatMonitorArgs(rawArgs);
  const supabase = createServiceRoleClientFromEnvironmentWithOptions({
    requestTimeoutMs: MONITOR_REQUEST_TIMEOUT_MS,
    maximumResponseBytes: MONITOR_MAXIMUM_RESPONSE_BYTES,
  });

  const [
    health,
    purchasePrincipalHealth,
    purchasePrincipalSignoutRotationHealth,
  ] = await Promise.all([
    fetchRevenueCatReconciliationHealth(supabase),
    fetchPurchasePrincipalHealth(supabase),
    fetchPurchasePrincipalSignoutRotationHealth(
      supabase,
      args.purchasePrincipalSignoutRotationHealthMode,
    ),
  ]);
  const summary = buildRevenueCatMonitorSummary(
    health,
    args,
    new Date(),
    purchasePrincipalHealth,
    purchasePrincipalSignoutRotationHealth,
  );

  printSummary(summary);
  await writeSummaryFiles(summary, args);

  if (summary.failure_policy.should_fail) {
    console.error(
      `RevenueCat reconciliation status=${summary.status} matched fail policy ${args.failOn}.`,
    );
    return 1;
  }
  return 0;
}

async function fetchRevenueCatReconciliationHealth(
  supabase: SupabaseClient,
): Promise<RevenueCatReconciliationHealth> {
  const { data, error } = await supabase.rpc(
    "get_revenuecat_reconciliation_health",
  );

  if (error) {
    throw new Error(
      `RevenueCat reconciliation health returned an error: ${error.message} (Code: ${error.code})`,
    );
  }

  return assertRevenueCatReconciliationHealth(data);
}

async function fetchPurchasePrincipalHealth(
  supabase: SupabaseClient,
): Promise<PurchasePrincipalHealth> {
  const { data, error } = await supabase.rpc("get_purchase_principal_health");
  return resolvePurchasePrincipalHealthRpcResult(data, error);
}

async function fetchPurchasePrincipalSignoutRotationHealth(
  supabase: SupabaseClient,
  mode: PurchasePrincipalSignoutRotationHealthMode,
): Promise<PurchasePrincipalSignoutRotationHealth | null> {
  const { data, error } = await supabase.rpc(
    "get_purchase_principal_signout_rotation_health",
  );
  return resolvePurchasePrincipalSignoutRotationHealthRpcResult(
    data,
    error,
    mode,
  );
}

export function resolvePurchasePrincipalHealthRpcResult(
  data: unknown,
  error: HealthRpcError | null,
): PurchasePrincipalHealth {
  if (error === null) {
    return assertPurchasePrincipalHealth(data);
  }
  throw new Error(
    `Purchase principal health returned an error: ${error.message} (Code: ${error.code})`,
  );
}

export function resolvePurchasePrincipalSignoutRotationHealthRpcResult(
  data: unknown,
  error: HealthRpcError | null,
  mode: PurchasePrincipalSignoutRotationHealthMode,
): PurchasePrincipalSignoutRotationHealth | null {
  if (error === null) {
    return assertPurchasePrincipalSignoutRotationHealth(data);
  }
  if (
    mode === "expand-compatible" &&
    error.code === "PGRST202" &&
    error.message.includes(
      "function public.get_purchase_principal_signout_rotation_health without parameters",
    )
  ) {
    console.warn(
      "Purchase principal sign-out rotation health is not deployed; continuing in explicit expand-compatible mode.",
    );
    return null;
  }
  throw new Error(
    `Purchase principal sign-out rotation health returned an error: ${error.message} (Code: ${error.code})`,
  );
}

export function assertRevenueCatReconciliationHealth(
  value: unknown,
): RevenueCatReconciliationHealth {
  if (!Array.isArray(value) || value.length !== 1) {
    throw new Error(
      "RevenueCat reconciliation health response must contain one row.",
    );
  }
  const row = value[0] as Record<string, unknown>;
  const generatedAt = timestamp(row.generated_at, "generated_at");
  const dueCount = nonnegativeInteger(row.due_count, "due_count");
  const expiredClaimCount = nonnegativeInteger(
    row.expired_claim_count,
    "expired_claim_count",
  );
  const oldestDueAt = row.oldest_due_at === null
    ? null
    : timestamp(row.oldest_due_at, "oldest_due_at");
  const oldestDueAgeSeconds = row.oldest_due_age_seconds === null
    ? null
    : nonnegativeInteger(
      row.oldest_due_age_seconds,
      "oldest_due_age_seconds",
    );
  const hasSignoutHealth = [
    "signout_prepared_count",
    "signout_bound_count",
    "oldest_signout_pending_at",
    "oldest_signout_pending_age_seconds",
  ].some((field) => row[field] !== undefined);
  const signoutPreparedCount = hasSignoutHealth
    ? nonnegativeInteger(
      row.signout_prepared_count,
      "signout_prepared_count",
    )
    : 0;
  const signoutBoundCount = hasSignoutHealth
    ? nonnegativeInteger(row.signout_bound_count, "signout_bound_count")
    : 0;
  const oldestSignoutPendingAt = !hasSignoutHealth ||
      row.oldest_signout_pending_at === null
    ? null
    : timestamp(
      row.oldest_signout_pending_at,
      "oldest_signout_pending_at",
    );
  const oldestSignoutPendingAgeSeconds = !hasSignoutHealth ||
      row.oldest_signout_pending_age_seconds === null
    ? null
    : nonnegativeInteger(
      row.oldest_signout_pending_age_seconds,
      "oldest_signout_pending_age_seconds",
    );
  const signoutPendingCount = signoutPreparedCount + signoutBoundCount;

  if (
    (oldestDueAt === null) !== (oldestDueAgeSeconds === null) ||
    (dueCount === 0 && oldestDueAt !== null) ||
    (dueCount > 0 && oldestDueAt === null) ||
    (oldestSignoutPendingAt === null) !==
      (oldestSignoutPendingAgeSeconds === null) ||
    (signoutPendingCount === 0 && oldestSignoutPendingAt !== null) ||
    (signoutPendingCount > 0 && oldestSignoutPendingAt === null)
  ) {
    throw new Error(
      "RevenueCat reconciliation health response is inconsistent.",
    );
  }

  return {
    generated_at: generatedAt,
    due_count: dueCount,
    expired_claim_count: expiredClaimCount,
    oldest_due_at: oldestDueAt,
    oldest_due_age_seconds: oldestDueAgeSeconds,
    signout_prepared_count: signoutPreparedCount,
    signout_bound_count: signoutBoundCount,
    oldest_signout_pending_at: oldestSignoutPendingAt,
    oldest_signout_pending_age_seconds: oldestSignoutPendingAgeSeconds,
  };
}

export function assertPurchasePrincipalHealth(
  value: unknown,
): PurchasePrincipalHealth {
  if (!Array.isArray(value) || value.length !== 1) {
    throw new Error("Purchase principal health response must contain one row.");
  }
  const row = value[0] as Record<string, unknown>;
  const health: PurchasePrincipalHealth = {
    generated_at: timestamp(row.generated_at, "generated_at"),
    active_principal_count: nonnegativeInteger(
      row.active_principal_count,
      "active_principal_count",
    ),
    pending_principal_count: nonnegativeInteger(
      row.pending_principal_count,
      "pending_principal_count",
    ),
    unbound_active_principal_count: nonnegativeInteger(
      row.unbound_active_principal_count,
      "unbound_active_principal_count",
    ),
    due_reconciliation_count: nonnegativeInteger(
      row.due_reconciliation_count,
      "due_reconciliation_count",
    ),
    expired_claim_count: nonnegativeInteger(
      row.expired_claim_count,
      "expired_claim_count",
    ),
    oldest_due_at: row.oldest_due_at === null
      ? null
      : timestamp(row.oldest_due_at, "oldest_due_at"),
    oldest_due_age_seconds: row.oldest_due_age_seconds === null
      ? null
      : nonnegativeInteger(
        row.oldest_due_age_seconds,
        "oldest_due_age_seconds",
      ),
    oldest_pending_at: row.oldest_pending_at === null
      ? null
      : timestamp(row.oldest_pending_at, "oldest_pending_at"),
    oldest_pending_age_seconds: row.oldest_pending_age_seconds === null
      ? null
      : nonnegativeInteger(
        row.oldest_pending_age_seconds,
        "oldest_pending_age_seconds",
      ),
  };
  if (
    health.unbound_active_principal_count > health.active_principal_count ||
    (health.oldest_due_at === null) !==
      (health.oldest_due_age_seconds === null) ||
    (health.due_reconciliation_count === 0 &&
      health.oldest_due_at !== null) ||
    (health.due_reconciliation_count > 0 &&
      health.oldest_due_at === null) ||
    (health.oldest_pending_at === null) !==
      (health.oldest_pending_age_seconds === null) ||
    (health.pending_principal_count === 0 &&
      health.oldest_pending_at !== null) ||
    (health.pending_principal_count > 0 &&
      health.oldest_pending_at === null)
  ) {
    throw new Error("Purchase principal health response is inconsistent.");
  }
  return health;
}

export function assertPurchasePrincipalSignoutRotationHealth(
  value: unknown,
): PurchasePrincipalSignoutRotationHealth {
  if (!Array.isArray(value) || value.length !== 1) {
    throw new Error(
      "Purchase principal sign-out rotation health response must contain one row.",
    );
  }
  const row = value[0] as Record<string, unknown>;
  const health: PurchasePrincipalSignoutRotationHealth = {
    generated_at: timestamp(row.generated_at, "generated_at"),
    prepared_count: nonnegativeInteger(
      row.prepared_count,
      "prepared_count",
    ),
    expired_prepared_count: nonnegativeInteger(
      row.expired_prepared_count,
      "expired_prepared_count",
    ),
    oldest_prepared_at: row.oldest_prepared_at === null
      ? null
      : timestamp(row.oldest_prepared_at, "oldest_prepared_at"),
    oldest_prepared_age_seconds: row.oldest_prepared_age_seconds === null
      ? null
      : nonnegativeInteger(
        row.oldest_prepared_age_seconds,
        "oldest_prepared_age_seconds",
      ),
    completed_last_24h: nonnegativeInteger(
      row.completed_last_24h,
      "completed_last_24h",
    ),
    cancelled_last_24h: nonnegativeInteger(
      row.cancelled_last_24h,
      "cancelled_last_24h",
    ),
  };
  if (
    (health.oldest_prepared_at === null) !==
      (health.oldest_prepared_age_seconds === null) ||
    (health.prepared_count === 0 && health.oldest_prepared_at !== null) ||
    (health.prepared_count > 0 && health.oldest_prepared_at === null)
  ) {
    throw new Error(
      "Purchase principal sign-out rotation health response is inconsistent.",
    );
  }
  return health;
}

export function revenueCatBacklogStatus(
  health: RevenueCatReconciliationHealth,
  warningAfterMinutes: number,
  criticalAfterMinutes: number,
  purchasePrincipalHealth: PurchasePrincipalHealth,
  purchasePrincipalSignoutRotationHealth:
    | PurchasePrincipalSignoutRotationHealth
    | null = null,
  warningPreparedRotations = DEFAULT_WARNING_PREPARED_ROTATIONS,
  criticalPreparedRotations = DEFAULT_CRITICAL_PREPARED_ROTATIONS,
): RevenueCatBacklogStatus {
  const oldestDueAgeSeconds = Math.max(
    health.oldest_due_age_seconds ?? 0,
    health.oldest_signout_pending_age_seconds ?? 0,
    purchasePrincipalHealth.oldest_due_age_seconds ?? 0,
    purchasePrincipalHealth.oldest_pending_age_seconds ?? 0,
    purchasePrincipalSignoutRotationHealth
      ?.oldest_prepared_age_seconds ?? 0,
  );
  if (oldestDueAgeSeconds >= criticalAfterMinutes * 60) {
    return "critical";
  }
  if (
    (purchasePrincipalSignoutRotationHealth?.prepared_count ?? 0) >=
      criticalPreparedRotations
  ) {
    return "critical";
  }
  if (
    health.expired_claim_count > 0 ||
    purchasePrincipalHealth.expired_claim_count > 0 ||
    purchasePrincipalHealth.unbound_active_principal_count > 0 ||
    (purchasePrincipalSignoutRotationHealth?.expired_prepared_count ?? 0) > 0 ||
    (purchasePrincipalSignoutRotationHealth?.prepared_count ?? 0) >=
      warningPreparedRotations ||
    oldestDueAgeSeconds >= warningAfterMinutes * 60
  ) {
    return "warning";
  }
  return "ok";
}

export function buildRevenueCatMonitorSummary(
  health: RevenueCatReconciliationHealth,
  args: RevenueCatMonitorArgs,
  now: Date,
  purchasePrincipalHealth: PurchasePrincipalHealth,
  purchasePrincipalSignoutRotationHealth:
    | PurchasePrincipalSignoutRotationHealth
    | null = null,
): RevenueCatMonitorSummary {
  const status = revenueCatBacklogStatus(
    health,
    args.warningAfterMinutes,
    args.criticalAfterMinutes,
    purchasePrincipalHealth,
    purchasePrincipalSignoutRotationHealth,
    args.warningPreparedRotations,
    args.criticalPreparedRotations,
  );
  return {
    generated_at: now.toISOString(),
    status,
    thresholds: {
      warning_after_minutes: args.warningAfterMinutes,
      critical_after_minutes: args.criticalAfterMinutes,
      warning_prepared_rotations: args.warningPreparedRotations,
      critical_prepared_rotations: args.criticalPreparedRotations,
    },
    failure_policy: {
      fail_on: args.failOn,
      should_fail: shouldFailRevenueCatMonitor(status, args.failOn),
    },
    health,
    purchase_principal_health_availability: "available",
    purchase_principal_health: purchasePrincipalHealth,
    purchase_principal_signout_rotation_health_availability:
      purchasePrincipalSignoutRotationHealth === null
        ? "not_deployed"
        : "available",
    purchase_principal_signout_rotation_health:
      purchasePrincipalSignoutRotationHealth,
  };
}

export function shouldFailRevenueCatMonitor(
  status: RevenueCatBacklogStatus,
  policy: RevenueCatMonitorFailurePolicy,
): boolean {
  if (policy === "never") return false;
  if (policy === "warning") return status !== "ok";
  return status === "critical";
}

export function renderRevenueCatMonitorMarkdown(
  summary: RevenueCatMonitorSummary,
): string {
  const oldestDueAge = summary.health.oldest_due_age_seconds === null
    ? "none"
    : `${summary.health.oldest_due_age_seconds}s`;
  const oldestSignoutAge = summary.health
      .oldest_signout_pending_age_seconds === null
    ? "none"
    : `${summary.health.oldest_signout_pending_age_seconds}s`;
  const oldestPrincipalDueAge = summary.purchase_principal_health
      .oldest_due_age_seconds == null
    ? "none"
    : `${summary.purchase_principal_health.oldest_due_age_seconds}s`;
  const oldestPrincipalPendingAge = summary.purchase_principal_health
      .oldest_pending_age_seconds == null
    ? "none"
    : `${summary.purchase_principal_health.oldest_pending_age_seconds}s`;
  const oldestRotationAge = summary
      .purchase_principal_signout_rotation_health
      ?.oldest_prepared_age_seconds == null
    ? "none"
    : `${summary.purchase_principal_signout_rotation_health.oldest_prepared_age_seconds}s`;
  const purchasePrincipalLines = [
    `- Availability: \`${summary.purchase_principal_health_availability}\``,
    `- Active principals: \`${summary.purchase_principal_health.active_principal_count}\``,
    `- Pending principals: \`${summary.purchase_principal_health.pending_principal_count}\``,
    `- Unbound active principals with current StoreKit access: \`${summary.purchase_principal_health.unbound_active_principal_count}\``,
    `- Due reconciliations: \`${summary.purchase_principal_health.due_reconciliation_count}\``,
    `- Expired claims: \`${summary.purchase_principal_health.expired_claim_count}\``,
    `- Oldest due age: \`${oldestPrincipalDueAge}\``,
    `- Oldest pending age: \`${oldestPrincipalPendingAge}\``,
  ];
  const purchasePrincipalRotationLines = summary
      .purchase_principal_signout_rotation_health === null
    ? [
      `- Availability: \`${summary.purchase_principal_signout_rotation_health_availability}\``,
      "- The aggregate rotation health RPC is not deployed; server-authorized stable sign-out monitoring is unavailable.",
    ]
    : [
      `- Availability: \`${summary.purchase_principal_signout_rotation_health_availability}\``,
      `- Prepared rotations: \`${summary.purchase_principal_signout_rotation_health.prepared_count}\``,
      `- Expired prepared rotations: \`${summary.purchase_principal_signout_rotation_health.expired_prepared_count}\``,
      `- Oldest prepared age: \`${oldestRotationAge}\``,
      `- Completed in 24h: \`${summary.purchase_principal_signout_rotation_health.completed_last_24h}\``,
      `- Cancelled in 24h: \`${summary.purchase_principal_signout_rotation_health.cancelled_last_24h}\``,
    ];
  const operatorAction = summary.status !== "ok"
    ? "Inspect the reconciliation, stable purchase-principal, server-authorized rotation, and sign-out purchase-handoff Edge logs; inspect queue error codes, entitled unbound principals, expired rotations, and pending ages; repair provider/database configuration and let device-safe retries plus claim-fenced reconciliation complete. Do not edit subscription tiers, move bindings, or discard bound proofs directly."
    : summary.purchase_principal_signout_rotation_health === null
    ? "No deployed backlog action required. Keep only the unavailable rotation aggregate in expand-compatible mode until its migration and hosted health-RPC smoke pass, then switch that aggregate's scheduled flag to required mode."
    : "No action required.";
  return [
    "# RevenueCat Reconciliation Health",
    "",
    `Generated: ${summary.generated_at}`,
    "",
    "## Status",
    "",
    `- Health: \`${summary.status}\``,
    `- Failing this run: \`${summary.failure_policy.should_fail}\``,
    `- Fail policy: \`${summary.failure_policy.fail_on}\``,
    "",
    "## Backlog",
    "",
    `- Due rows: \`${summary.health.due_count}\``,
    `- Expired claims: \`${summary.health.expired_claim_count}\``,
    `- Oldest due at: \`${summary.health.oldest_due_at ?? "none"}\``,
    `- Oldest due age: \`${oldestDueAge}\``,
    `- Prepared sign-out handoffs: \`${summary.health.signout_prepared_count}\``,
    `- Bound sign-out handoffs: \`${summary.health.signout_bound_count}\``,
    `- Oldest pending sign-out at: \`${
      summary.health.oldest_signout_pending_at ?? "none"
    }\``,
    `- Oldest pending sign-out age: \`${oldestSignoutAge}\``,
    "",
    "## Stable Purchase Principals",
    "",
    ...purchasePrincipalLines,
    "",
    "## Stable Sign-Out Rotations",
    "",
    ...purchasePrincipalRotationLines,
    "",
    "## Thresholds",
    "",
    `- Warning after: \`${summary.thresholds.warning_after_minutes}m\``,
    `- Critical after: \`${summary.thresholds.critical_after_minutes}m\``,
    `- Prepared-rotation warning count: \`${summary.thresholds.warning_prepared_rotations}\``,
    `- Prepared-rotation critical count: \`${summary.thresholds.critical_prepared_rotations}\``,
    "",
    "## Operator Action",
    "",
    operatorAction,
    "",
  ].join("\n");
}

export function parseRevenueCatMonitorArgs(
  rawArgs: string[],
): RevenueCatMonitorArgs {
  const values = argumentValues(rawArgs);
  const warningAfterMinutes = parseInteger(
    values.get("warning-after-minutes") ?? "30",
    "--warning-after-minutes",
    1,
    24 * 60,
  );
  const criticalAfterMinutes = parseInteger(
    values.get("critical-after-minutes") ?? "60",
    "--critical-after-minutes",
    2,
    48 * 60,
  );
  if (criticalAfterMinutes <= warningAfterMinutes) {
    throw new Error(
      "--critical-after-minutes must exceed --warning-after-minutes.",
    );
  }
  const warningPreparedRotations = parseInteger(
    values.get("warning-prepared-rotations") ??
      String(DEFAULT_WARNING_PREPARED_ROTATIONS),
    "--warning-prepared-rotations",
    1,
    1_000_000,
  );
  const criticalPreparedRotations = parseInteger(
    values.get("critical-prepared-rotations") ??
      String(DEFAULT_CRITICAL_PREPARED_ROTATIONS),
    "--critical-prepared-rotations",
    2,
    10_000_000,
  );
  if (criticalPreparedRotations <= warningPreparedRotations) {
    throw new Error(
      "--critical-prepared-rotations must exceed --warning-prepared-rotations.",
    );
  }

  return {
    warningAfterMinutes,
    criticalAfterMinutes,
    warningPreparedRotations,
    criticalPreparedRotations,
    failOn: parseFailurePolicy(values.get("fail-on") ?? "warning"),
    purchasePrincipalSignoutRotationHealthMode:
      parsePurchasePrincipalSignoutRotationHealthMode(
        values.get("purchase-principal-signout-rotation-health-mode") ??
          "required",
        "--purchase-principal-signout-rotation-health-mode",
      ),
    summaryJsonPath: optionalPath(
      values.get("summary-json"),
      "--summary-json",
    ),
    summaryMarkdownPath: optionalPath(
      values.get("summary-md"),
      "--summary-md",
    ),
  };
}

function argumentValues(rawArgs: string[]): Map<string, string | boolean> {
  const supported = new Set([
    "warning-after-minutes",
    "critical-after-minutes",
    "warning-prepared-rotations",
    "critical-prepared-rotations",
    "fail-on",
    "purchase-principal-signout-rotation-health-mode",
    "summary-json",
    "summary-md",
  ]);
  const values = new Map<string, string | boolean>();
  for (let index = 0; index < rawArgs.length; index += 1) {
    const argument = rawArgs[index];
    if (!argument.startsWith("--")) {
      throw new Error(`Unexpected argument: ${argument}`);
    }
    const [key, inlineValue] = argument.slice(2).split("=", 2);
    if (!supported.has(key)) {
      throw new Error(`Unsupported argument: --${key}`);
    }
    if (inlineValue !== undefined) {
      values.set(key, inlineValue);
    } else if (
      rawArgs[index + 1] !== undefined &&
      !rawArgs[index + 1].startsWith("--")
    ) {
      values.set(key, rawArgs[index + 1]);
      index += 1;
    } else {
      values.set(key, true);
    }
  }
  return values;
}

function timestamp(value: unknown, field: string): string {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    !Number.isFinite(Date.parse(value))
  ) {
    throw new Error(
      `RevenueCat reconciliation health has invalid ${field}.`,
    );
  }
  return value;
}

function nonnegativeInteger(value: unknown, field: string): number {
  if (
    typeof value !== "number" ||
    !Number.isSafeInteger(value) ||
    value < 0
  ) {
    throw new Error(
      `RevenueCat reconciliation health has invalid ${field}.`,
    );
  }
  return value;
}

function parseInteger(
  value: string | boolean,
  label: string,
  min: number,
  max: number,
): number {
  if (typeof value !== "string" || !/^\d+$/.test(value)) {
    throw new Error(`${label} must be an integer.`);
  }
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < min || parsed > max) {
    throw new Error(`${label} must be from ${min} to ${max}.`);
  }
  return parsed;
}

function parseFailurePolicy(
  value: string | boolean,
): RevenueCatMonitorFailurePolicy {
  if (typeof value !== "string") {
    throw new Error("--fail-on must be critical, warning, or never.");
  }
  const normalized = value.toLowerCase();
  if (
    normalized === "critical" ||
    normalized === "warning" ||
    normalized === "never"
  ) {
    return normalized;
  }
  throw new Error("--fail-on must be critical, warning, or never.");
}

function parsePurchasePrincipalSignoutRotationHealthMode(
  value: string | boolean,
  label: string,
): PurchasePrincipalSignoutRotationHealthMode {
  if (value === "expand-compatible" || value === "required") {
    return value;
  }
  throw new Error(
    `${label} must be expand-compatible or required.`,
  );
}

function optionalPath(
  value: string | boolean | undefined,
  label: string,
): string | null {
  if (value === undefined) return null;
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`${label} must be a non-empty path.`);
  }
  return value;
}

async function writeSummaryFiles(
  summary: RevenueCatMonitorSummary,
  args: RevenueCatMonitorArgs,
): Promise<void> {
  if (args.summaryJsonPath) {
    await Deno.writeTextFile(
      args.summaryJsonPath,
      `${JSON.stringify(summary, null, 2)}\n`,
    );
  }
  if (args.summaryMarkdownPath) {
    await Deno.writeTextFile(
      args.summaryMarkdownPath,
      `${renderRevenueCatMonitorMarkdown(summary)}\n`,
    );
  }
}

function printSummary(summary: RevenueCatMonitorSummary): void {
  console.log("RevenueCat reconciliation health monitor complete");
  console.log(`status: ${summary.status}`);
  console.log(`due_count: ${summary.health.due_count}`);
  console.log(`expired_claim_count: ${summary.health.expired_claim_count}`);
  console.log(
    `oldest_due_age_seconds: ${
      summary.health.oldest_due_age_seconds ?? "none"
    }`,
  );
  console.log(
    `purchase_principal_health_availability: ${summary.purchase_principal_health_availability}`,
  );
  console.log(
    `purchase_principal_due_count: ${summary.purchase_principal_health.due_reconciliation_count}`,
  );
  console.log(
    `purchase_principal_unbound_active_count: ${summary.purchase_principal_health.unbound_active_principal_count}`,
  );
  console.log(
    `purchase_principal_signout_rotation_health_availability: ${summary.purchase_principal_signout_rotation_health_availability}`,
  );
  console.log(
    `purchase_principal_signout_prepared_count: ${
      summary.purchase_principal_signout_rotation_health?.prepared_count ??
        "unavailable"
    }`,
  );
  console.log(
    `purchase_principal_signout_newly_expired_count: ${
      summary.purchase_principal_signout_rotation_health
        ?.expired_prepared_count ?? "unavailable"
    }`,
  );
  console.log(`should_fail: ${summary.failure_policy.should_fail}`);
}
