/**
 * Reads service-only RevenueCat reconciliation backlog health and writes
 * operator summaries.
 *
 * Required env:
 *   SUPABASE_URL
 *   SUPABASE_SERVER_API_KEY (or legacy SUPABASE_SERVICE_ROLE_KEY)
 */

import { serviceRoleRequestHeaders } from "../functions/_shared/serviceRoleAuth.ts";

export type RevenueCatMonitorFailurePolicy = "critical" | "warning" | "never";
export type RevenueCatBacklogStatus = "ok" | "warning" | "critical";

export interface RevenueCatMonitorArgs {
  warningAfterMinutes: number;
  criticalAfterMinutes: number;
  failOn: RevenueCatMonitorFailurePolicy;
  summaryJsonPath: string | null;
  summaryMarkdownPath: string | null;
}

export interface RevenueCatReconciliationHealth {
  generated_at: string;
  due_count: number;
  expired_claim_count: number;
  oldest_due_at: string | null;
  oldest_due_age_seconds: number | null;
}

export interface RevenueCatMonitorSummary {
  generated_at: string;
  status: RevenueCatBacklogStatus;
  thresholds: {
    warning_after_minutes: number;
    critical_after_minutes: number;
  };
  failure_policy: {
    fail_on: RevenueCatMonitorFailurePolicy;
    should_fail: boolean;
  };
  health: RevenueCatReconciliationHealth;
}

const RESPONSE_DEADLINE_MS = 15_000;
const MAXIMUM_RESPONSE_BYTES = 64 * 1_024;

if (import.meta.main) {
  const exitCode = await runRevenueCatMonitor(Deno.args);
  Deno.exit(exitCode);
}

export async function runRevenueCatMonitor(
  rawArgs: string[],
): Promise<number> {
  const args = parseRevenueCatMonitorArgs(rawArgs);
  const supabaseUrl = requiredEnv("SUPABASE_URL").replace(/\/$/, "");
  const serverApiKey = (
    Deno.env.get("SUPABASE_SERVER_API_KEY") ??
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
      ""
  ).trim();
  if (!serverApiKey) {
    throw new Error(
      "Missing required environment variable: SUPABASE_SERVER_API_KEY",
    );
  }
  const health = await fetchRevenueCatReconciliationHealth(
    `${supabaseUrl}/rest/v1/rpc/get_revenuecat_reconciliation_health`,
    serverApiKey,
  );
  const summary = buildRevenueCatMonitorSummary(health, args, new Date());

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
  url: string,
  serverApiKey: string,
): Promise<RevenueCatReconciliationHealth> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), RESPONSE_DEADLINE_MS);
  try {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        ...serviceRoleRequestHeaders(serverApiKey),
        "Content-Type": "application/json",
      },
      body: "{}",
      signal: controller.signal,
    });
    const text = await readBoundedResponse(response);
    let json: unknown;
    try {
      json = text.length === 0 ? null : JSON.parse(text);
    } catch {
      throw new Error(
        `RevenueCat reconciliation health returned invalid JSON (HTTP ${response.status}).`,
      );
    }
    if (!response.ok) {
      throw new Error(
        `RevenueCat reconciliation health returned HTTP ${response.status}.`,
      );
    }
    return assertRevenueCatReconciliationHealth(json);
  } finally {
    clearTimeout(timeout);
  }
}

async function readBoundedResponse(response: Response): Promise<string> {
  const declaredLength = response.headers.get("Content-Length");
  if (
    declaredLength !== null &&
    /^\d+$/.test(declaredLength) &&
    Number(declaredLength) > MAXIMUM_RESPONSE_BYTES
  ) {
    await response.body?.cancel();
    throw new Error("RevenueCat reconciliation health response is too large.");
  }
  if (!response.body) return "";

  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let totalBytes = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      totalBytes += value.byteLength;
      if (totalBytes > MAXIMUM_RESPONSE_BYTES) {
        await reader.cancel();
        throw new Error(
          "RevenueCat reconciliation health response is too large.",
        );
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }

  const combined = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    combined.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(combined);
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

  if (
    (oldestDueAt === null) !== (oldestDueAgeSeconds === null) ||
    (dueCount === 0 && oldestDueAt !== null) ||
    (dueCount > 0 && oldestDueAt === null)
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
  };
}

export function revenueCatBacklogStatus(
  health: RevenueCatReconciliationHealth,
  warningAfterMinutes: number,
  criticalAfterMinutes: number,
): RevenueCatBacklogStatus {
  const oldestDueAgeSeconds = health.oldest_due_age_seconds ?? 0;
  if (oldestDueAgeSeconds >= criticalAfterMinutes * 60) {
    return "critical";
  }
  if (
    health.expired_claim_count > 0 ||
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
): RevenueCatMonitorSummary {
  const status = revenueCatBacklogStatus(
    health,
    args.warningAfterMinutes,
    args.criticalAfterMinutes,
  );
  return {
    generated_at: now.toISOString(),
    status,
    thresholds: {
      warning_after_minutes: args.warningAfterMinutes,
      critical_after_minutes: args.criticalAfterMinutes,
    },
    failure_policy: {
      fail_on: args.failOn,
      should_fail: shouldFailRevenueCatMonitor(status, args.failOn),
    },
    health,
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
    "",
    "## Thresholds",
    "",
    `- Warning after: \`${summary.thresholds.warning_after_minutes}m\``,
    `- Critical after: \`${summary.thresholds.critical_after_minutes}m\``,
    "",
    "## Operator Action",
    "",
    summary.status === "ok"
      ? "No action required."
      : "Inspect the reconciliation Edge logs and queue error codes; repair provider/database configuration and let claim-fenced retries drain the queue. Do not edit subscription tiers directly.",
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

  return {
    warningAfterMinutes,
    criticalAfterMinutes,
    failOn: parseFailurePolicy(values.get("fail-on") ?? "warning"),
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
    "fail-on",
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
  console.log(`should_fail: ${summary.failure_policy.should_fail}`);
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing required env ${name}.`);
  return value;
}
