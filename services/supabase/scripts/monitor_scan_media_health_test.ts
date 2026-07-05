import {
  assertEquals,
  assertStringIncludes,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

import {
  assertSuccessfulHealthResponse,
  buildMonitorSummary,
  parseMonitorArgs,
  renderMonitorMarkdown,
  type ScanMediaHealthResponse,
  shouldFailForPolicy,
} from "./monitor_scan_media_health.ts";

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
  assertStringIncludes(markdown, '"scan_id": "scan-1"');
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
