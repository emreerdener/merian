import {
  assertEquals,
  assertRejects,
  assertStringIncludes,
  assertThrows,
} from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";

import {
  assertSuccessfulHealthResponse,
  buildMonitorSummary,
  fetchDeployedScanMediaHealth,
  isRetryableScanMediaHealthInvocationFailure,
  issueActionFor,
  parseMonitorArgs,
  renderMonitorMarkdown,
  type ScanMediaHealthInvocationOptions,
  type ScanMediaHealthResponse,
  shouldFailForPolicy,
} from "./monitor_scan_media_health.ts";
import { ServiceRoleFunctionInvocationError } from "../functions/_shared/serviceRoleClient.ts";

Deno.test("parseMonitorArgs applies production monitor defaults and aliases", () => {
  assertEquals(parseMonitorArgs([]), {
    limit: 25,
    recentScanLimit: 250,
    stuckAfterMinutes: 20,
    staleAssetAfterMinutes: 15,
    failOn: "critical",
    summaryJsonPath: null,
    summaryMarkdownPath: null,
  });

  assertEquals(
    parseMonitorArgs([
      "--limit",
      "50",
      "--recent_scan_limit=500",
      "--stuck-after-minutes",
      "30",
      "--stale_asset_after_minutes=45",
      "--fail-on",
      "warning",
      "--summary-json",
      "/tmp/health.json",
      "--summary-md=/tmp/health.md",
    ]),
    {
      limit: 50,
      recentScanLimit: 500,
      stuckAfterMinutes: 30,
      staleAssetAfterMinutes: 45,
      failOn: "warning",
      summaryJsonPath: "/tmp/health.json",
      summaryMarkdownPath: "/tmp/health.md",
    },
  );
});

Deno.test("parseMonitorArgs rejects unsafe values", () => {
  assertThrows(() => parseMonitorArgs(["--limit", "0"]));
  assertThrows(() => parseMonitorArgs(["--recent-scan-limit", "5000"]));
  assertThrows(() => parseMonitorArgs(["--fail-on", "all"]));
});

Deno.test("shouldFailForPolicy fails only at the configured severity", () => {
  assertEquals(shouldFailForPolicy("ok", "critical"), false);
  assertEquals(shouldFailForPolicy("warning", "critical"), false);
  assertEquals(shouldFailForPolicy("critical", "critical"), true);
  assertEquals(shouldFailForPolicy("warning", "warning"), true);
  assertEquals(shouldFailForPolicy("critical", "warning"), true);
  assertEquals(shouldFailForPolicy("critical", "never"), false);
});

Deno.test("scan media health retries only safe transient invocation failures", () => {
  for (const status of [401, 404, 408, 425, 429, 500, 502, 503, 504]) {
    assertEquals(
      isRetryableScanMediaHealthInvocationFailure(
        new ServiceRoleFunctionInvocationError(
          "scan-media-health",
          status,
          status === 500,
          "FunctionsHttpError",
        ),
      ),
      true,
    );
  }
  assertEquals(
    isRetryableScanMediaHealthInvocationFailure(
      new ServiceRoleFunctionInvocationError(
        "scan-media-health",
        null,
        false,
        "FunctionsFetchError",
      ),
    ),
    true,
  );
  assertEquals(
    isRetryableScanMediaHealthInvocationFailure(
      new ServiceRoleFunctionInvocationError(
        "scan-media-health",
        403,
        true,
        "FunctionsHttpError",
      ),
    ),
    false,
  );
});

Deno.test("scan media health monitor retries transient reads with bounded backoff", async () => {
  const expected = healthResponse();
  let attempts = 0;
  const waits: number[] = [];
  const invoke: NonNullable<ScanMediaHealthInvocationOptions["invoke"]> = <T>(
    _supabase: SupabaseClient,
    _functionName: string,
    _body: Record<string, unknown>,
  ): Promise<T> => {
    attempts += 1;
    if (attempts < 3) {
      return Promise.reject(
        new ServiceRoleFunctionInvocationError(
          "scan-media-health",
          401,
          false,
          "FunctionsHttpError",
        ),
      );
    }
    return Promise.resolve(expected as T);
  };

  assertEquals(
    await fetchDeployedScanMediaHealth(
      null as unknown as SupabaseClient,
      {},
      {
        maximumAttempts: 3,
        invoke,
        wait: (milliseconds) => {
          waits.push(milliseconds);
          return Promise.resolve();
        },
      },
    ),
    expected,
  );
  assertEquals(attempts, 3);
  assertEquals(waits, [2_000, 4_000]);

  await assertRejects(
    () =>
      fetchDeployedScanMediaHealth(
        null as unknown as SupabaseClient,
        {},
        { maximumAttempts: 0, invoke },
      ),
    TypeError,
    "maximumAttempts must be between 1 and 6",
  );
});

Deno.test("assertSuccessfulHealthResponse validates endpoint shape", () => {
  const response = healthResponse({
    status: "warning",
    counts: { issues: 1, critical_issues: 0, warning_issues: 1 },
  });

  assertEquals(assertSuccessfulHealthResponse(response), response);
  assertThrows(() => assertSuccessfulHealthResponse({ success: false }));
  assertThrows(() =>
    assertSuccessfulHealthResponse({
      ...response,
      status: "unknown",
    })
  );
  assertThrows(() =>
    assertSuccessfulHealthResponse({
      ...response,
      issues: null,
    })
  );
});

Deno.test("renderMonitorMarkdown includes counts, breakdowns, and samples", () => {
  const health = healthResponse({
    status: "critical",
    counts: {
      issues: 1,
      critical_issues: 1,
      warning_issues: 0,
      failed_assets: 1,
    },
    asset_breakdown: {
      stale_capture_upload_assets: [
        { kind: "audio", role: "audio", count: 1 },
      ],
      failed_assets: [
        { kind: "video", role: "playback", count: 1 },
      ],
    },
    issues: [{
      code: "video_scan_missing_ready_playback_asset",
      severity: "critical",
      message: "Missing ready video asset.",
      count: 1,
      sample: [{ scan_id: "scan-1", ready_video_asset_count: 0 }],
    }],
  });
  const summary = buildMonitorSummary(
    health,
    parseMonitorArgs(["--fail-on", "critical"]),
    new Date("2026-07-05T15:00:00.000Z"),
  );

  const markdown = renderMonitorMarkdown(summary);
  assertStringIncludes(markdown, "# Scan Media Health Summary");
  assertStringIncludes(markdown, "- Health: `critical`");
  assertStringIncludes(markdown, "| `failed_assets` | `1` |");
  assertStringIncludes(
    markdown,
    "| `failed_assets` | `video` | `playback` | `1` |",
  );
  assertStringIncludes(
    markdown,
    "`video_scan_missing_ready_playback_asset`",
  );
  assertStringIncludes(markdown, "## Incident Actions");
  assertStringIncludes(markdown, "scan media assets");
  assertStringIncludes(
    markdown,
    "Refresh ready scan_media_assets from captured_media",
  );
  assertStringIncludes(markdown, "## Sample Preview");
  assertStringIncludes(
    markdown,
    '{"scan_id":"scan-1","ready_video_asset_count":0}',
  );
  assertStringIncludes(markdown, "Sample hint:");
  assertStringIncludes(markdown, '"scan_id": "scan-1"');
});

Deno.test("issueActionFor maps known and future issue codes to operator guidance", () => {
  assertEquals(
    issueActionFor({
      code: "frame_only_video_smells",
      severity: "critical",
      message: "Likely video scan without video.",
      count: 1,
      sample: [],
    }),
    {
      code: "frame_only_video_smells",
      severity: "critical",
      owner: "video durability",
      next_step:
        "Repair only if the original local/staged mp4 exists; otherwise treat as image-only historical data.",
      runbook:
        "docs/backend-and-data/05-api-contracts.md#share-scan-to-explore-and-unshare-explore-post",
      sample_hint:
        "Use scan_id and image count to identify likely sampled video frames without playback media.",
    },
  );

  assertEquals(
    issueActionFor({
      code: "scan_deletion_cleanup_backlog",
      severity: "critical",
      message: "Erasure outside SLA.",
      count: 1,
      sample: [],
    }).owner,
    "privacy erasure",
  );

  assertEquals(
    issueActionFor({
      code: "future_media_issue",
      severity: "warning",
      message: "A future issue.",
      count: 1,
      sample: [],
    }).owner,
    "scan media on-call",
  );
});

function healthResponse(
  overrides: Partial<ScanMediaHealthResponse> = {},
): ScanMediaHealthResponse {
  return {
    success: true,
    generated_at: "2026-07-05T15:00:00.000Z",
    status: "ok",
    thresholds: {
      stuck_after_minutes: 20,
      stale_asset_after_minutes: 15,
    },
    asset_breakdown: {
      stale_capture_upload_assets: [],
      failed_assets: [],
    },
    counts: {
      ingestion_jobs_checked: 0,
      stale_capture_upload_assets: 0,
      failed_assets: 0,
      recent_scans_checked: 0,
      ready_video_assets_checked: 0,
      explore_video_rows_checked: 0,
      reconciliation_runs_checked: 0,
      issues: 0,
      critical_issues: 0,
      warning_issues: 0,
    },
    issues: [],
    ...overrides,
  };
}
