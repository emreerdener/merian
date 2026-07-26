import {
  assertEquals,
  assertStringIncludes,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  assertDwcaExportQueueHealth,
  buildDwcaMonitorSummary,
  type DwcaExportQueueHealth,
  dwcaQueueStatus,
  parseDwcaMonitorArgs,
  renderDwcaMonitorMarkdown,
  shouldFailDwcaMonitor,
} from "./monitor_dwca_export_queue.ts";

const HEALTHY: DwcaExportQueueHealth = {
  generated_at: "2026-07-26T22:00:00.000Z",
  backlog_count: 0,
  due_count: 0,
  active_claim_count: 0,
  expired_claim_count: 0,
  oldest_due_at: null,
  oldest_due_age_seconds: null,
};

Deno.test("parseDwcaMonitorArgs applies queue alerting defaults", () => {
  assertEquals(parseDwcaMonitorArgs([]), {
    warningAfterMinutes: 5,
    criticalAfterMinutes: 15,
    warningBacklog: 25,
    criticalBacklog: 100,
    failOn: "warning",
    summaryJsonPath: null,
    summaryMarkdownPath: null,
  });
  assertEquals(
    parseDwcaMonitorArgs([
      "--warning-after-minutes=10",
      "--critical-after-minutes",
      "30",
      "--warning-backlog",
      "50",
      "--critical-backlog=200",
      "--fail-on",
      "critical",
      "--summary-json=/tmp/dwca.json",
      "--summary-md",
      "/tmp/dwca.md",
    ]),
    {
      warningAfterMinutes: 10,
      criticalAfterMinutes: 30,
      warningBacklog: 50,
      criticalBacklog: 200,
      failOn: "critical",
      summaryJsonPath: "/tmp/dwca.json",
      summaryMarkdownPath: "/tmp/dwca.md",
    },
  );
});

Deno.test("parseDwcaMonitorArgs rejects inverted thresholds", () => {
  assertThrows(() =>
    parseDwcaMonitorArgs([
      "--warning-after-minutes",
      "15",
      "--critical-after-minutes",
      "15",
    ])
  );
  assertThrows(() =>
    parseDwcaMonitorArgs([
      "--warning-backlog",
      "100",
      "--critical-backlog",
      "100",
    ])
  );
  assertThrows(() => parseDwcaMonitorArgs(["--fail-on", "always"]));
  assertThrows(() => parseDwcaMonitorArgs(["--unknown", "value"]));
});

Deno.test("assertDwcaExportQueueHealth validates one consistent row", () => {
  const backlog = {
    ...HEALTHY,
    backlog_count: 7,
    due_count: 5,
    active_claim_count: 2,
    expired_claim_count: 1,
    oldest_due_at: "2026-07-26T21:50:00.000Z",
    oldest_due_age_seconds: 600,
  };
  assertEquals(assertDwcaExportQueueHealth([backlog]), backlog);
  assertThrows(() => assertDwcaExportQueueHealth([]));
  assertThrows(() =>
    assertDwcaExportQueueHealth([{
      ...HEALTHY,
      due_count: 1,
    }])
  );
  assertThrows(() =>
    assertDwcaExportQueueHealth([{
      ...HEALTHY,
      backlog_count: 1,
      active_claim_count: 2,
    }])
  );
});

Deno.test("dwcaQueueStatus alerts on age, depth, and expired claims", () => {
  const args = parseDwcaMonitorArgs([]);
  assertEquals(dwcaQueueStatus(HEALTHY, args), "ok");
  assertEquals(
    dwcaQueueStatus({ ...HEALTHY, backlog_count: 25 }, args),
    "warning",
  );
  assertEquals(
    dwcaQueueStatus({ ...HEALTHY, backlog_count: 100 }, args),
    "critical",
  );
  assertEquals(
    dwcaQueueStatus(
      {
        ...HEALTHY,
        backlog_count: 1,
        due_count: 1,
        oldest_due_at: "2026-07-26T21:55:00.000Z",
        oldest_due_age_seconds: 5 * 60,
      },
      args,
    ),
    "warning",
  );
  assertEquals(
    dwcaQueueStatus(
      { ...HEALTHY, backlog_count: 1, expired_claim_count: 1 },
      args,
    ),
    "warning",
  );
});

Deno.test("shouldFailDwcaMonitor honors the configured severity", () => {
  assertEquals(shouldFailDwcaMonitor("ok", "warning"), false);
  assertEquals(shouldFailDwcaMonitor("warning", "warning"), true);
  assertEquals(shouldFailDwcaMonitor("warning", "critical"), false);
  assertEquals(shouldFailDwcaMonitor("critical", "critical"), true);
  assertEquals(shouldFailDwcaMonitor("critical", "never"), false);
});

Deno.test("renderDwcaMonitorMarkdown includes queue state and recovery guidance", () => {
  const health: DwcaExportQueueHealth = {
    ...HEALTHY,
    backlog_count: 7,
    due_count: 5,
    active_claim_count: 2,
    expired_claim_count: 1,
    oldest_due_at: "2026-07-26T21:50:00.000Z",
    oldest_due_age_seconds: 600,
  };
  const summary = buildDwcaMonitorSummary(
    health,
    parseDwcaMonitorArgs([]),
    new Date("2026-07-26T22:00:00.000Z"),
  );
  const markdown = renderDwcaMonitorMarkdown(summary);

  assertEquals(summary.status, "warning");
  assertEquals(summary.failure_policy.should_fail, true);
  assertStringIncludes(markdown, "# DwC-A Export Queue Health");
  assertStringIncludes(markdown, "- Outstanding jobs: `7`");
  assertStringIncludes(markdown, "- Due jobs: `5`");
  assertStringIncludes(markdown, "- Expired claims: `1`");
  assertStringIncludes(markdown, "Do not edit private queue");
});
