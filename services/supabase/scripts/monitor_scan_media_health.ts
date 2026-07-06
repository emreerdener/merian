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
  incident_actions: ScanMediaHealthIncidentAction[];
}

export interface ScanMediaHealthIncidentAction {
  code: string;
  severity: "warning" | "critical";
  owner: string;
  next_step: string;
  runbook: string;
  sample_hint: string;
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
    incident_actions: health.issues.map(issueActionFor),
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

    lines.push(
      "",
      "## Incident Actions",
      "",
      "| Severity | Code | Owner | Next Step | Runbook |",
      "| --- | --- | --- | --- | --- |",
      ...summary.incident_actions.map((action) =>
        `| \`${action.severity}\` | \`${escapeMarkdownCell(action.code)}\` | ${
          escapeMarkdownCell(action.owner)
        } | ${escapeMarkdownCell(action.next_step)} | ${
          escapeMarkdownCell(action.runbook)
        } |`
      ),
    );

    for (const issue of health.issues) {
      if (issue.sample.length === 0) continue;
      const action = summary.incident_actions.find((entry) =>
        entry.code === issue.code
      );
      lines.push(
        "",
        `<details><summary>${escapeMarkdownCell(issue.code)} sample</summary>`,
        "",
        action ? `Sample hint: ${action.sample_hint}` : "",
        action ? "" : "",
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

export function issueActionFor(
  issue: ScanMediaHealthIssue,
): ScanMediaHealthIncidentAction {
  const defaults = {
    code: issue.code,
    severity: issue.severity,
  };
  switch (issue.code) {
    case "stuck_ingestion_jobs":
      return {
        ...defaults,
        owner: "scan ingestion",
        next_step:
          "Inspect job stage, lease, and Edge logs; run replay only if the lease is stale.",
        runbook:
          "docs/backend-and-data/06-supabase-deployment-runbook.md#scan-media-health",
        sample_hint:
          "Use scan_id, user_id, stage, attempt_count, manifest_checksum, and upload_session_ids to match the stuck request.",
      };
    case "retryable_ingestion_jobs_past_due":
      return {
        ...defaults,
        owner: "server replay",
        next_step:
          "Confirm pg_cron replay is scheduled, then inspect replay-scan-ingestion logs for dispatch failures.",
        runbook: "services/supabase/functions/replay-scan-ingestion/README.md",
        sample_hint:
          "Use scan_id and retry_after to verify the row is due and still retryable.",
      };
    case "ingestion_jobs_missing_intent":
      return {
        ...defaults,
        owner: "ingestion ledger",
        next_step:
          "Treat as client-owned unless staged media still exists; verify the writer recorded scan_ingestion_intents.",
        runbook:
          "docs/backend-and-data/04-database-schema.md#scan_ingestion_intents",
        sample_hint:
          "Use scan_id, endpoint, and created_at to find the endpoint path that accepted the scan without an intent.",
      };
    case "ingestion_intents_not_resumable":
      return {
        ...defaults,
        owner: "iOS offline queue",
        next_step:
          "Expect client retry for redacted inline media; only escalate if matching queued media is gone.",
        runbook: "docs/backend-and-data/01-offline-sync-pipeline.md",
        sample_hint:
          "Use inline_media_redacted and redacted_media_counts to confirm why server replay is unavailable.",
      };
    case "terminal_ingestion_failures":
      return {
        ...defaults,
        owner: "support review",
        next_step:
          "Review last_error and user impact; terminal local/media/auth failures may need user attention.",
        runbook: "docs/development-guides/06-error-handling.md",
        sample_hint:
          "Use last_error, stage, and attempt_count to distinguish validation/user-attention failures from defects.",
      };
    case "stale_capture_upload_assets":
      return {
        ...defaults,
        owner: "media reconciliation",
        next_step:
          "Check active leases and retry windows; otherwise run reconcile-scan-media-assets with dry_run first.",
        runbook:
          "services/supabase/functions/reconcile-scan-media-assets/README.md",
        sample_hint:
          "Use media_session_id, storage_key, client_scan_id, kind, role, and created_at to inspect staged objects.",
      };
    case "failed_scan_media_assets":
      return {
        ...defaults,
        owner: "media lifecycle",
        next_step:
          "Inspect failed asset reasons and confirm the matching scan/job ended terminally or was repaired.",
        runbook:
          "docs/backend-and-data/04-database-schema.md#scan_media_assets",
        sample_hint:
          "Use status, failure reason fields, kind, role, and scan_id to decide whether this is expected cleanup.",
      };
    case "video_scan_missing_captured_media_video":
      return {
        ...defaults,
        owner: "video manifest repair",
        next_step:
          "Run reconciliation or local video restore; do not publish sampled frames as video media.",
        runbook:
          "services/supabase/functions/reconcile-scan-media-assets/README.md",
        sample_hint:
          "Use scan_id, video_storage_urls, captured_media count, and image frame count to rebuild one video item.",
      };
    case "video_scan_missing_ready_playback_asset":
      return {
        ...defaults,
        owner: "scan media assets",
        next_step:
          "Refresh ready scan_media_assets from captured_media after confirming video_storage_urls are durable.",
        runbook: "services/supabase/functions/scan-media-health/README.md",
        sample_hint:
          "Use scan_id, video URL count, and ready_video_asset_count to verify the normalized asset table.",
      };
    case "frame_only_video_smells":
      return {
        ...defaults,
        owner: "video durability",
        next_step:
          "Repair only if the original local/staged mp4 exists; otherwise treat as image-only historical data.",
        runbook:
          "docs/backend-and-data/05-api-contracts.md#share-scan-to-explore-and-unshare-explore-post",
        sample_hint:
          "Use scan_id and image count to identify likely sampled video frames without playback media.",
      };
    case "explore_video_missing_thumbnail":
      return {
        ...defaults,
        owner: "Explore media",
        next_step:
          "Block or repair the post media row; video posts require a poster thumbnail before feed exposure.",
        runbook: "services/supabase/functions/share-scan-to-explore/README.md",
        sample_hint:
          "Use post_id, scan_id, media row id, url, and thumbnail_url to find the affected Explore media row.",
      };
    case "latest_reconciliation_run_not_clean":
      return {
        ...defaults,
        owner: "reconciliation cron",
        next_step:
          "Inspect the latest reconciliation summary and worker logs before changing retry/abandon thresholds.",
        runbook:
          "services/supabase/functions/reconcile-scan-media-assets/README.md",
        sample_hint:
          "Use run id, started_at, completed_at, repaired count, failed count, and errors from the latest run.",
      };
    default:
      return {
        ...defaults,
        owner: "scan media on-call",
        next_step:
          "Inspect the sample payload, preserve user media, and update monitor guidance when the code is understood.",
        runbook: "services/supabase/functions/scan-media-health/README.md",
        sample_hint:
          "Use the sample fields to identify affected scan, user, media asset, or Explore post rows.",
      };
  }
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
