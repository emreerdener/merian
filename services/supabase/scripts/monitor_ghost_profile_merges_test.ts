import {
  assert,
  assertEquals,
  assertStringIncludes,
  assertThrows,
} from "@std/assert";
import {
  assertGhostMergeHealth,
  buildGhostMergeMonitorSummary,
  type GhostMergeHealth,
  ghostMergeHealthStatus,
  parseGhostMergeMonitorArgs,
  renderGhostMergeMonitorMarkdown,
  shouldFailGhostMergeMonitor,
} from "./monitor_ghost_profile_merges.ts";

const monitorSourceUrl = new URL(
  "./monitor_ghost_profile_merges.ts",
  import.meta.url,
);

function health(
  overrides: Partial<GhostMergeHealth> = {},
): GhostMergeHealth {
  return {
    generated_at: "2026-08-02 02:00:00+00",
    recent_prepared_count: 0,
    recent_merged_count: 1,
    recent_expired_count: 0,
    oldest_recent_prepared_age_seconds: null,
    cleanup_pending_count: 0,
    cleanup_overdue_count: 0,
    cleanup_error_count: 0,
    oldest_cleanup_age_seconds: null,
    missing_destination_queue_count: 0,
    misdirected_destination_queue_count: 0,
    unrefreshed_destination_queue_count: 0,
    ...overrides,
  };
}

Deno.test("Ghost merge health parser accepts one consistent aggregate row", () => {
  assertEquals(assertGhostMergeHealth([health()]), health());
});

Deno.test("Ghost merge database audit is bounded and read-only", async () => {
  const source = await Deno.readTextFile(monitorSourceUrl);

  assertStringIncludes(source, 'sql.unsafe("BEGIN TRANSACTION READ ONLY")');
  assertStringIncludes(source, "SET LOCAL statement_timeout = '10s'");
  assertStringIncludes(
    source,
    "SET LOCAL idle_in_transaction_session_timeout = '15s'",
  );
  assertStringIncludes(source, "INTERVAL '12 hours'");
  assertStringIncludes(source, "INTERVAL '24 hours'");
  assertEquals(source.match(/GROUP BY clock\.observed_at/g)?.length, 2);
  assertEquals(source.match(/pg_catalog\.DATE_PART\(/g)?.length, 2);
  assert(!source.includes("pg_catalog.EXTRACT("));
  assertEquals(
    source.match(
      /LEFT JOIN internal\.ghost_profile_merge_handoffs AS handoff/g,
    )?.length,
    3,
  );
  assertStringIncludes(source, "COUNT(handoff.id)::INTEGER");
  assertStringIncludes(source, "max: 1");
  assertStringIncludes(source, "prepare: false");
  assertStringIncludes(source, "queue.updated_at < handoff.merged_at");
  assertStringIncludes(
    source,
    "pg_catalog.UPPER(handoff.target_user_id::TEXT)",
  );
  assert(
    !source.includes("internal.canonical_revenuecat_app_user_id("),
    "the scheduled monitor must remain executable before the helper migration deploys",
  );
});

Deno.test("Ghost merge health parser rejects malformed or inconsistent rows", () => {
  assertThrows(() => assertGhostMergeHealth([]));
  assertThrows(() =>
    assertGhostMergeHealth([
      health({
        recent_prepared_count: 1,
        oldest_recent_prepared_age_seconds: null,
      }),
    ])
  );
  assertThrows(() =>
    assertGhostMergeHealth([
      health({
        cleanup_pending_count: 1,
        cleanup_overdue_count: 2,
        oldest_cleanup_age_seconds: 1_300,
      }),
    ])
  );
  assertThrows(() =>
    assertGhostMergeHealth([
      { ...health(), missing_destination_queue_count: -1 },
    ])
  );
});

Deno.test("Ghost merge health severity follows cleanup and queue invariants", () => {
  assertEquals(ghostMergeHealthStatus(health(), 20, 60), "ok");
  assertEquals(
    ghostMergeHealthStatus(
      health({
        cleanup_pending_count: 1,
        cleanup_overdue_count: 1,
        oldest_cleanup_age_seconds: 1_300,
      }),
      20,
      60,
    ),
    "warning",
  );
  assertEquals(
    ghostMergeHealthStatus(
      health({
        cleanup_pending_count: 1,
        oldest_cleanup_age_seconds: 3_600,
      }),
      20,
      60,
    ),
    "critical",
  );
  assertEquals(
    ghostMergeHealthStatus(
      health({ missing_destination_queue_count: 1 }),
      20,
      60,
    ),
    "critical",
  );
  assertEquals(
    ghostMergeHealthStatus(
      health({ misdirected_destination_queue_count: 1 }),
      20,
      60,
    ),
    "critical",
  );
  assertEquals(
    ghostMergeHealthStatus(
      health({ unrefreshed_destination_queue_count: 1 }),
      20,
      60,
    ),
    "critical",
  );
});

Deno.test("Ghost merge monitor failure policy is fail-closed", () => {
  assert(!shouldFailGhostMergeMonitor("ok", "warning"));
  assert(shouldFailGhostMergeMonitor("warning", "warning"));
  assert(!shouldFailGhostMergeMonitor("warning", "critical"));
  assert(shouldFailGhostMergeMonitor("critical", "critical"));
  assert(!shouldFailGhostMergeMonitor("critical", "never"));
});

Deno.test("Ghost merge monitor arguments validate thresholds and paths", () => {
  assertEquals(parseGhostMergeMonitorArgs([]), {
    cleanupWarningAfterMinutes: 20,
    cleanupCriticalAfterMinutes: 60,
    failOn: "warning",
    summaryJsonPath: null,
    summaryMarkdownPath: null,
  });
  assertEquals(
    parseGhostMergeMonitorArgs([
      "--cleanup-warning-after-minutes",
      "30",
      "--cleanup-critical-after-minutes=90",
      "--fail-on",
      "critical",
      "--summary-json",
      "/tmp/ghost.json",
      "--summary-md=/tmp/ghost.md",
    ]),
    {
      cleanupWarningAfterMinutes: 30,
      cleanupCriticalAfterMinutes: 90,
      failOn: "critical",
      summaryJsonPath: "/tmp/ghost.json",
      summaryMarkdownPath: "/tmp/ghost.md",
    },
  );
  assertThrows(() =>
    parseGhostMergeMonitorArgs([
      "--cleanup-warning-after-minutes",
      "60",
      "--cleanup-critical-after-minutes",
      "60",
    ])
  );
  assertThrows(() => parseGhostMergeMonitorArgs(["--fail-on", "sometimes"]));
  assertThrows(() => parseGhostMergeMonitorArgs(["--unknown", "1"]));
});

Deno.test("Ghost merge summary remains aggregate-only and gives safe recovery", () => {
  const summary = buildGhostMergeMonitorSummary(
    health({
      recent_prepared_count: 2,
      oldest_recent_prepared_age_seconds: 2_000,
      missing_destination_queue_count: 1,
    }),
    parseGhostMergeMonitorArgs([]),
  );
  const markdown = renderGhostMergeMonitorMarkdown(summary);

  assertEquals(summary.status, "critical");
  assert(summary.failure_policy.should_fail);
  assertStringIncludes(markdown, "Prepared receipts: `2`");
  assertStringIncludes(markdown, "Missing destination RevenueCat queues: `1`");
  assertStringIncludes(markdown, "Unrefreshed destination RevenueCat queues");
  assertStringIncludes(markdown, "proof-capable clients");
  assertStringIncludes(markdown, "Do not edit receipt state");
  assertStringIncludes(markdown, "manually reparent user data");
  assertStringIncludes(markdown, "aggregate counts only");

  const artifact = JSON.stringify(summary);
  assert(!/handoff_id|user_id|proof_hash|provider_subject/.test(artifact));
});
