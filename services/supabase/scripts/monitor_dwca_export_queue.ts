/**
 * Reads service-only DwC-A continuation backlog health and writes operator
 * summaries.
 *
 * Required env:
 *   SUPABASE_URL
 *   SUPABASE_SERVER_API_KEY, platform SUPABASE_SECRET_KEYS, or the migration-only
 *   SUPABASE_SERVICE_ROLE_KEY fallback
 */

import {
  requireServerApiKeyFromEnvironment,
  serviceRoleRequestHeaders,
} from "../functions/_shared/serviceRoleAuth.ts";
import {
  EXPORT_BACKLOG_CRITICAL_AGE_SECONDS,
  EXPORT_BACKLOG_CRITICAL_COUNT,
  EXPORT_BACKLOG_WARNING_AGE_SECONDS,
  EXPORT_BACKLOG_WARNING_COUNT,
} from "../functions/export-dwca/limits.ts";

export type DwcaMonitorFailurePolicy = "critical" | "warning" | "never";
export type DwcaQueueStatus = "ok" | "warning" | "critical";

export interface DwcaMonitorArgs {
  warningAfterMinutes: number;
  criticalAfterMinutes: number;
  warningBacklog: number;
  criticalBacklog: number;
  failOn: DwcaMonitorFailurePolicy;
  summaryJsonPath: string | null;
  summaryMarkdownPath: string | null;
}

export interface DwcaExportQueueHealth {
  generated_at: string;
  backlog_count: number;
  due_count: number;
  active_claim_count: number;
  expired_claim_count: number;
  oldest_due_at: string | null;
  oldest_due_age_seconds: number | null;
}

export interface DwcaMonitorSummary {
  generated_at: string;
  status: DwcaQueueStatus;
  thresholds: {
    warning_after_minutes: number;
    critical_after_minutes: number;
    warning_backlog: number;
    critical_backlog: number;
  };
  failure_policy: {
    fail_on: DwcaMonitorFailurePolicy;
    should_fail: boolean;
  };
  health: DwcaExportQueueHealth;
}

const RESPONSE_DEADLINE_MS = 15_000;
const MAXIMUM_RESPONSE_BYTES = 64 * 1_024;

if (import.meta.main) {
  const exitCode = await runDwcaExportQueueMonitor(Deno.args);
  Deno.exit(exitCode);
}

export async function runDwcaExportQueueMonitor(
  rawArgs: string[],
): Promise<number> {
  const args = parseDwcaMonitorArgs(rawArgs);
  const supabaseUrl = requiredEnv("SUPABASE_URL").replace(/\/$/, "");
  const serverApiKey = requireServerApiKeyFromEnvironment();

  const health = await fetchDwcaExportQueueHealth(
    `${supabaseUrl}/rest/v1/rpc/get_dwca_export_queue_health`,
    serverApiKey,
  );
  const summary = buildDwcaMonitorSummary(health, args, new Date());
  printSummary(summary);
  await writeSummaryFiles(summary, args);

  if (summary.failure_policy.should_fail) {
    console.error(
      `DwC-A export queue status=${summary.status} matched fail policy ${args.failOn}.`,
    );
    return 1;
  }
  return 0;
}

async function fetchDwcaExportQueueHealth(
  url: string,
  serverApiKey: string,
): Promise<DwcaExportQueueHealth> {
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
        `DwC-A queue health returned invalid JSON (HTTP ${response.status}).`,
      );
    }
    if (!response.ok) {
      throw new Error(
        `DwC-A queue health returned HTTP ${response.status}.`,
      );
    }
    return assertDwcaExportQueueHealth(json);
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
    throw new Error("DwC-A queue health response is too large.");
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
        throw new Error("DwC-A queue health response is too large.");
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

export function assertDwcaExportQueueHealth(
  value: unknown,
): DwcaExportQueueHealth {
  if (!Array.isArray(value) || value.length !== 1) {
    throw new Error("DwC-A queue health response must contain one row.");
  }
  const row = value[0] as Record<string, unknown>;
  const generatedAt = timestamp(row.generated_at, "generated_at");
  const backlogCount = nonnegativeInteger(
    row.backlog_count,
    "backlog_count",
  );
  const dueCount = nonnegativeInteger(row.due_count, "due_count");
  const activeClaimCount = nonnegativeInteger(
    row.active_claim_count,
    "active_claim_count",
  );
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
    (dueCount > 0 && oldestDueAt === null) ||
    activeClaimCount > backlogCount ||
    expiredClaimCount > backlogCount
  ) {
    throw new Error("DwC-A queue health response is inconsistent.");
  }

  return {
    generated_at: generatedAt,
    backlog_count: backlogCount,
    due_count: dueCount,
    active_claim_count: activeClaimCount,
    expired_claim_count: expiredClaimCount,
    oldest_due_at: oldestDueAt,
    oldest_due_age_seconds: oldestDueAgeSeconds,
  };
}

export function dwcaQueueStatus(
  health: DwcaExportQueueHealth,
  args: Pick<
    DwcaMonitorArgs,
    | "warningAfterMinutes"
    | "criticalAfterMinutes"
    | "warningBacklog"
    | "criticalBacklog"
  >,
): DwcaQueueStatus {
  const oldestDueAgeSeconds = health.oldest_due_age_seconds ?? 0;
  if (
    oldestDueAgeSeconds >= args.criticalAfterMinutes * 60 ||
    health.backlog_count >= args.criticalBacklog
  ) {
    return "critical";
  }
  if (
    health.expired_claim_count > 0 ||
    oldestDueAgeSeconds >= args.warningAfterMinutes * 60 ||
    health.backlog_count >= args.warningBacklog
  ) {
    return "warning";
  }
  return "ok";
}

export function buildDwcaMonitorSummary(
  health: DwcaExportQueueHealth,
  args: DwcaMonitorArgs,
  now: Date,
): DwcaMonitorSummary {
  const status = dwcaQueueStatus(health, args);
  return {
    generated_at: now.toISOString(),
    status,
    thresholds: {
      warning_after_minutes: args.warningAfterMinutes,
      critical_after_minutes: args.criticalAfterMinutes,
      warning_backlog: args.warningBacklog,
      critical_backlog: args.criticalBacklog,
    },
    failure_policy: {
      fail_on: args.failOn,
      should_fail: shouldFailDwcaMonitor(status, args.failOn),
    },
    health,
  };
}

export function shouldFailDwcaMonitor(
  status: DwcaQueueStatus,
  policy: DwcaMonitorFailurePolicy,
): boolean {
  if (policy === "never") return false;
  if (policy === "warning") return status !== "ok";
  return status === "critical";
}

export function renderDwcaMonitorMarkdown(
  summary: DwcaMonitorSummary,
): string {
  const oldestDueAge = summary.health.oldest_due_age_seconds === null
    ? "none"
    : `${summary.health.oldest_due_age_seconds}s`;
  return [
    "# DwC-A Export Queue Health",
    "",
    `Generated: ${summary.generated_at}`,
    "",
    "## Status",
    "",
    `- Health: \`${summary.status}\``,
    `- Failing this run: \`${summary.failure_policy.should_fail}\``,
    `- Fail policy: \`${summary.failure_policy.fail_on}\``,
    "",
    "## Queue",
    "",
    `- Outstanding jobs: \`${summary.health.backlog_count}\``,
    `- Due jobs: \`${summary.health.due_count}\``,
    `- Active claims: \`${summary.health.active_claim_count}\``,
    `- Expired claims: \`${summary.health.expired_claim_count}\``,
    `- Oldest due at: \`${summary.health.oldest_due_at ?? "none"}\``,
    `- Oldest due age: \`${oldestDueAge}\``,
    "",
    "## Thresholds",
    "",
    `- Warning age: \`${summary.thresholds.warning_after_minutes}m\``,
    `- Critical age: \`${summary.thresholds.critical_after_minutes}m\``,
    `- Warning backlog: \`${summary.thresholds.warning_backlog}\``,
    `- Critical backlog: \`${summary.thresholds.critical_backlog}\``,
    "",
    "## Operator Action",
    "",
    summary.status === "ok"
      ? "No action required."
      : "Inspect export-dwca queue-health and step logs, verify R2/database/provider health, and let claim-fenced retries resume. Do not edit private queue or claim rows directly.",
    "",
  ].join("\n");
}

export function parseDwcaMonitorArgs(rawArgs: string[]): DwcaMonitorArgs {
  const values = argumentValues(rawArgs);
  const warningAfterMinutes = parseInteger(
    values.get("warning-after-minutes") ??
      String(EXPORT_BACKLOG_WARNING_AGE_SECONDS / 60),
    "--warning-after-minutes",
    1,
    24 * 60,
  );
  const criticalAfterMinutes = parseInteger(
    values.get("critical-after-minutes") ??
      String(EXPORT_BACKLOG_CRITICAL_AGE_SECONDS / 60),
    "--critical-after-minutes",
    2,
    48 * 60,
  );
  const warningBacklog = parseInteger(
    values.get("warning-backlog") ??
      String(EXPORT_BACKLOG_WARNING_COUNT),
    "--warning-backlog",
    1,
    100_000,
  );
  const criticalBacklog = parseInteger(
    values.get("critical-backlog") ??
      String(EXPORT_BACKLOG_CRITICAL_COUNT),
    "--critical-backlog",
    2,
    1_000_000,
  );
  if (criticalAfterMinutes <= warningAfterMinutes) {
    throw new Error(
      "--critical-after-minutes must exceed --warning-after-minutes.",
    );
  }
  if (criticalBacklog <= warningBacklog) {
    throw new Error("--critical-backlog must exceed --warning-backlog.");
  }

  return {
    warningAfterMinutes,
    criticalAfterMinutes,
    warningBacklog,
    criticalBacklog,
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
    "warning-backlog",
    "critical-backlog",
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
    throw new Error(`DwC-A queue health has invalid ${field}.`);
  }
  return value;
}

function nonnegativeInteger(value: unknown, field: string): number {
  if (
    typeof value !== "number" ||
    !Number.isSafeInteger(value) ||
    value < 0
  ) {
    throw new Error(`DwC-A queue health has invalid ${field}.`);
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
): DwcaMonitorFailurePolicy {
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
  summary: DwcaMonitorSummary,
  args: DwcaMonitorArgs,
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
      `${renderDwcaMonitorMarkdown(summary)}\n`,
    );
  }
}

function printSummary(summary: DwcaMonitorSummary): void {
  console.log("DwC-A export queue health monitor complete");
  console.log(`status: ${summary.status}`);
  console.log(`backlog_count: ${summary.health.backlog_count}`);
  console.log(`due_count: ${summary.health.due_count}`);
  console.log(`active_claim_count: ${summary.health.active_claim_count}`);
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
