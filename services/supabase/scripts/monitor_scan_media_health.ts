/**
 * Calls the deployed scan-media-health endpoint and writes operator summaries.
 *
 * Required env:
 *   SUPABASE_URL
 *   SUPABASE_SERVICE_ROLE_KEY
 *
 * Example:
 *   deno run --allow-net --allow-env --allow-write \
 *     services/supabase/scripts/monitor_scan_media_health.ts \
 *     --summary-json /tmp/scan-media-health.json \
 *     --summary-md /tmp/scan-media-health.md
 */

export type MonitorFailurePolicy = "critical" | "warning" | "never";
export type ScanMediaHealthStatus = "ok" | "warning" | "critical";

export interface MonitorArgs {
  limit: number;
  recentScanLimit: number;
  stuckAfterMinutes: number;
  staleAssetAfterMinutes: number;
  failOn: MonitorFailurePolicy;
  summaryJsonPath: string | null;
  summaryMarkdownPath: string | null;
}

export interface ScanMediaAssetBreakdown {
  kind: string;
  role: string;
  count: number;
}

export interface ScanMediaHealthIssue {
  code: string;
  severity: "warning" | "critical";
  message: string;
  count: number;
  sample: Array<Record<string, unknown>>;
}

export interface ScanMediaHealthResponse {
  success: true;
  generated_at: string;
  status: ScanMediaHealthStatus;
  thresholds: {
    stuck_after_minutes: number;
    stale_asset_after_minutes: number;
  };
  asset_breakdown?: {
    stale_capture_upload_assets?: ScanMediaAssetBreakdown[];
    failed_assets?: ScanMediaAssetBreakdown[];
  };
  counts: Record<string, number>;
  issues: ScanMediaHealthIssue[];
}

export interface ScanMediaHealthMonitorSummary {
  generated_at: string;
  requested: {
    limit: number;
    recent_scan_limit: number;
    stuck_after_minutes: number;
    stale_asset_after_minutes: number;
  };
  failure_policy: {
    fail_on: MonitorFailurePolicy;
    should_fail: boolean;
  };
  health: ScanMediaHealthResponse;
}

if (import.meta.main) {
  const exitCode = await runMonitor(Deno.args);
  Deno.exit(exitCode);
}

export async function runMonitor(rawArgs: string[]): Promise<number> {
  const args = parseMonitorArgs(rawArgs);
  const supabaseUrl = requiredEnv("SUPABASE_URL").replace(/\/$/, "");
  const serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
  const health = await postJson(
    `${supabaseUrl}/functions/v1/scan-media-health`,
    {
      limit: args.limit,
      recent_scan_limit: args.recentScanLimit,
      stuck_after_minutes: args.stuckAfterMinutes,
      stale_asset_after_minutes: args.staleAssetAfterMinutes,
    },
    serviceRoleKey,
  );
  const summary = buildMonitorSummary(health, args, new Date());

  printMonitorSummary(summary);
  await writeSummaryFiles(summary, args);

  if (summary.failure_policy.should_fail) {
    console.error(
      `scan-media-health status=${summary.health.status} matched fail policy ${args.failOn}.`,
    );
    return 1;
  }

  return 0;
}

async function postJson(
  url: string,
  body: Record<string, unknown>,
  serviceRoleKey: string,
): Promise<ScanMediaHealthResponse> {
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${serviceRoleKey}`,
      "apikey": serviceRoleKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  const text = await response.text();
  const json = text ? JSON.parse(text) : {};
  if (!response.ok) {
    throw new Error(
      `${url} returned HTTP ${response.status}: ${JSON.stringify(json)}`,
    );
  }
  return assertSuccessfulHealthResponse(json);
}

export function buildMonitorSummary(
  health: ScanMediaHealthResponse,
  args: MonitorArgs,
  now: Date,
): ScanMediaHealthMonitorSummary {
  return {
    generated_at: now.toISOString(),
    requested: {
      limit: args.limit,
      recent_scan_limit: args.recentScanLimit,
      stuck_after_minutes: args.stuckAfterMinutes,
      stale_asset_after_minutes: args.staleAssetAfterMinutes,
    },
    failure_policy: {
      fail_on: args.failOn,
      should_fail: shouldFailForPolicy(health.status, args.failOn),
    },
    health,
  };
}

export function assertSuccessfulHealthResponse(
  value: unknown,
): ScanMediaHealthResponse {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("scan-media-health response must be an object.");
  }
  const response = value as Record<string, unknown>;
  if (response.success !== true) {
    throw new Error("scan-media-health response did not report success.");
  }
  if (!isHealthStatus(response.status)) {
    throw new Error("scan-media-health response returned an invalid status.");
  }
  if (!response.counts || typeof response.counts !== "object") {
    throw new Error("scan-media-health response is missing counts.");
  }
  if (!Array.isArray(response.issues)) {
    throw new Error("scan-media-health response is missing issues.");
  }
  return response as unknown as ScanMediaHealthResponse;
}

function isHealthStatus(value: unknown): value is ScanMediaHealthStatus {
  return value === "ok" || value === "warning" || value === "critical";
}

export function shouldFailForPolicy(
  status: ScanMediaHealthStatus,
  policy: MonitorFailurePolicy,
): boolean {
  if (policy === "never") return false;
  if (policy === "warning") {
    return status === "warning" || status === "critical";
  }
  return status === "critical";
}

async function writeSummaryFiles(
  summary: ScanMediaHealthMonitorSummary,
  args: MonitorArgs,
): Promise<void> {
  if (args.summaryJsonPath) {
    await Deno.writeTextFile(
      args.summaryJsonPath,
      `${JSON.stringify(summary, null, 2)}\n`,
    );
    console.log(`summary_json: ${args.summaryJsonPath}`);
  }

  if (args.summaryMarkdownPath) {
    await Deno.writeTextFile(
      args.summaryMarkdownPath,
      renderMonitorMarkdown(summary),
    );
    console.log(`summary_markdown: ${args.summaryMarkdownPath}`);
  }
}

function printMonitorSummary(summary: ScanMediaHealthMonitorSummary): void {
  console.log("Scan media health monitor complete");
  console.log(`status: ${summary.health.status}`);
  console.log(`issues: ${summary.health.counts.issues ?? 0}`);
  console.log(`critical_issues: ${summary.health.counts.critical_issues ?? 0}`);
  console.log(`warning_issues: ${summary.health.counts.warning_issues ?? 0}`);
  console.log(`fail_on: ${summary.failure_policy.fail_on}`);
  console.log(`should_fail: ${summary.failure_policy.should_fail}`);
}

export function renderMonitorMarkdown(
  summary: ScanMediaHealthMonitorSummary,
): string {
  const health = summary.health;
  const lines = [
    "# Scan Media Health Summary",
    "",
    `Generated: ${summary.generated_at}`,
    "",
    "## Status",
    "",
    `- Health: \`${health.status}\``,
    `- Endpoint generated: \`${health.generated_at}\``,
    `- Fail policy: \`${summary.failure_policy.fail_on}\``,
    `- Failing this run: \`${summary.failure_policy.should_fail}\``,
    "",
    "## Request",
    "",
    `- Limit: \`${summary.requested.limit}\``,
    `- Recent scan limit: \`${summary.requested.recent_scan_limit}\``,
    `- Stuck after minutes: \`${summary.requested.stuck_after_minutes}\``,
    `- Stale asset after minutes: \`${summary.requested.stale_asset_after_minutes}\``,
    "",
    "## Counts",
    "",
    "| Metric | Count |",
    "| --- | ---: |",
    ...Object.entries(health.counts)
      .sort(([lhs], [rhs]) => lhs.localeCompare(rhs))
      .map(([key, value]) =>
        `| \`${escapeMarkdownCell(key)}\` | \`${value}\` |`
      ),
  ];

  const staleBreakdown = health.asset_breakdown?.stale_capture_upload_assets ??
    [];
  const failedBreakdown = health.asset_breakdown?.failed_assets ?? [];
  if (staleBreakdown.length > 0 || failedBreakdown.length > 0) {
    lines.push(
      "",
      "## Asset Breakdown",
      "",
      "| Group | Kind | Role | Count |",
      "| --- | --- | --- | ---: |",
      ...breakdownRows("stale_capture_upload_assets", staleBreakdown),
      ...breakdownRows("failed_assets", failedBreakdown),
    );
  }

  if (health.issues.length > 0) {
    lines.push(
      "",
      "## Issues",
      "",
      "| Severity | Code | Count | Message |",
      "| --- | --- | ---: | --- |",
      ...health.issues.map((issue) =>
        `| \`${issue.severity}\` | \`${
          escapeMarkdownCell(issue.code)
        }\` | \`${issue.count}\` | ${escapeMarkdownCell(issue.message)} |`
      ),
    );

    for (const issue of health.issues) {
      if (issue.sample.length === 0) continue;
      lines.push(
        "",
        `<details><summary>${escapeMarkdownCell(issue.code)} sample</summary>`,
        "",
        "```json",
        JSON.stringify(issue.sample, null, 2),
        "```",
        "",
        "</details>",
      );
    }
  } else {
    lines.push("", "## Issues", "", "No scan media health issues reported.");
  }

  lines.push("");
  return `${lines.join("\n")}\n`;
}

function breakdownRows(
  group: string,
  rows: ScanMediaAssetBreakdown[],
): string[] {
  return rows.map((row) =>
    `| \`${group}\` | \`${escapeMarkdownCell(row.kind)}\` | \`${
      escapeMarkdownCell(row.role)
    }\` | \`${row.count}\` |`
  );
}

function escapeMarkdownCell(value: string): string {
  return value.replaceAll("|", "\\|").replaceAll("\n", " ");
}

export function parseMonitorArgs(rawArgs: string[]): MonitorArgs {
  const values = new Map<string, string | boolean>();
  for (let index = 0; index < rawArgs.length; index += 1) {
    const arg = rawArgs[index];
    if (!arg.startsWith("--")) continue;
    const [key, inlineValue] = arg.slice(2).split("=", 2);
    if (inlineValue !== undefined) {
      values.set(key, inlineValue);
    } else if (rawArgs[index + 1] && !rawArgs[index + 1].startsWith("--")) {
      values.set(key, rawArgs[index + 1]);
      index += 1;
    } else {
      values.set(key, true);
    }
  }

  return {
    limit: parseInteger(values.get("limit") ?? "25", "--limit", 1, 100),
    recentScanLimit: parseInteger(
      values.get("recent-scan-limit") ??
        values.get("recent_scan_limit") ??
        "250",
      "--recent-scan-limit",
      1,
      1_000,
    ),
    stuckAfterMinutes: parseInteger(
      values.get("stuck-after-minutes") ??
        values.get("stuck_after_minutes") ??
        "20",
      "--stuck-after-minutes",
      1,
      24 * 60,
    ),
    staleAssetAfterMinutes: parseInteger(
      values.get("stale-asset-after-minutes") ??
        values.get("stale_asset_after_minutes") ??
        "15",
      "--stale-asset-after-minutes",
      1,
      24 * 60,
    ),
    failOn: parseFailurePolicy(values.get("fail-on") ?? "critical"),
    summaryJsonPath: parseOptionalString(
      values.get("summary-json") ?? values.get("summary_json"),
      "--summary-json",
    ),
    summaryMarkdownPath: parseOptionalString(
      values.get("summary-md") ?? values.get("summary_md"),
      "--summary-md",
    ),
  };
}

function parseFailurePolicy(
  value: string | boolean,
): MonitorFailurePolicy {
  if (typeof value !== "string") {
    throw new Error("--fail-on must be critical, warning, or never.");
  }
  const normalized = value.toLowerCase();
  if (
    normalized === "critical" || normalized === "warning" ||
    normalized === "never"
  ) {
    return normalized;
  }
  throw new Error("--fail-on must be critical, warning, or never.");
}

function parseOptionalString(
  value: string | boolean | undefined,
  label: string,
): string | null {
  if (value === undefined || value === false) return null;
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`${label} must be a non-empty path.`);
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

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing required env ${name}.`);
  return value;
}
