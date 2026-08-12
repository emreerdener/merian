import { assertEquals, assertStringIncludes, assertThrows } from "@std/assert";
import {
  assertPurchasePrincipalHealth,
  assertRevenueCatReconciliationHealth,
  buildRevenueCatMonitorSummary,
  parseRevenueCatMonitorArgs,
  type PurchasePrincipalHealth,
  renderRevenueCatMonitorMarkdown,
  resolvePurchasePrincipalHealthRpcResult,
  revenueCatBacklogStatus,
  type RevenueCatReconciliationHealth,
  shouldFailRevenueCatMonitor,
} from "./monitor_revenuecat_reconciliation.ts";

const HEALTHY: RevenueCatReconciliationHealth = {
  generated_at: "2026-07-26T03:30:00.000Z",
  due_count: 0,
  expired_claim_count: 0,
  oldest_due_at: null,
  oldest_due_age_seconds: null,
  signout_prepared_count: 0,
  signout_bound_count: 0,
  oldest_signout_pending_at: null,
  oldest_signout_pending_age_seconds: null,
};

const PRINCIPAL_HEALTHY: PurchasePrincipalHealth = {
  generated_at: "2026-07-26T03:30:00.000Z",
  active_principal_count: 4,
  pending_principal_count: 0,
  unbound_active_principal_count: 0,
  due_reconciliation_count: 0,
  expired_claim_count: 0,
  oldest_due_at: null,
  oldest_due_age_seconds: null,
  oldest_pending_at: null,
  oldest_pending_age_seconds: null,
};

Deno.test("parseRevenueCatMonitorArgs applies alerting defaults", () => {
  assertEquals(parseRevenueCatMonitorArgs([]), {
    warningAfterMinutes: 30,
    criticalAfterMinutes: 60,
    failOn: "warning",
    purchasePrincipalHealthMode: "required",
    summaryJsonPath: null,
    summaryMarkdownPath: null,
  });
  assertEquals(
    parseRevenueCatMonitorArgs([
      "--warning-after-minutes=45",
      "--critical-after-minutes",
      "90",
      "--fail-on",
      "critical",
      "--purchase-principal-health-mode",
      "expand-compatible",
      "--summary-json=/tmp/revenuecat.json",
      "--summary-md",
      "/tmp/revenuecat.md",
    ]),
    {
      warningAfterMinutes: 45,
      criticalAfterMinutes: 90,
      failOn: "critical",
      purchasePrincipalHealthMode: "expand-compatible",
      summaryJsonPath: "/tmp/revenuecat.json",
      summaryMarkdownPath: "/tmp/revenuecat.md",
    },
  );
});

Deno.test("parseRevenueCatMonitorArgs rejects unsafe thresholds and arguments", () => {
  assertThrows(() =>
    parseRevenueCatMonitorArgs([
      "--warning-after-minutes",
      "60",
      "--critical-after-minutes",
      "60",
    ])
  );
  assertThrows(() =>
    parseRevenueCatMonitorArgs(["--critical-after-minutes", "0"])
  );
  assertThrows(() => parseRevenueCatMonitorArgs(["--fail-on", "always"]));
  assertThrows(() =>
    parseRevenueCatMonitorArgs([
      "--purchase-principal-health-mode",
      "optional",
    ])
  );
  assertThrows(() => parseRevenueCatMonitorArgs(["--unknown", "value"]));
});

Deno.test("assertRevenueCatReconciliationHealth validates one consistent row", () => {
  const backlog = {
    ...HEALTHY,
    due_count: 7,
    expired_claim_count: 1,
    oldest_due_at: "2026-07-26T02:45:00.000Z",
    oldest_due_age_seconds: 2_700,
  };
  assertEquals(assertRevenueCatReconciliationHealth([backlog]), backlog);
  const {
    signout_prepared_count: _prepared,
    signout_bound_count: _bound,
    oldest_signout_pending_at: _pendingAt,
    oldest_signout_pending_age_seconds: _pendingAge,
    ...legacyHealth
  } = HEALTHY;
  assertEquals(
    assertRevenueCatReconciliationHealth([legacyHealth]),
    HEALTHY,
  );
  assertThrows(() => assertRevenueCatReconciliationHealth([]));
  assertThrows(() =>
    assertRevenueCatReconciliationHealth([{
      ...HEALTHY,
      due_count: 1,
    }])
  );
  assertThrows(() =>
    assertRevenueCatReconciliationHealth([{
      ...HEALTHY,
      due_count: -1,
    }])
  );
  assertThrows(() =>
    assertRevenueCatReconciliationHealth([{
      ...legacyHealth,
      signout_bound_count: 1,
    }])
  );
});

Deno.test("assertPurchasePrincipalHealth validates bounded aggregate health", () => {
  assertEquals(
    assertPurchasePrincipalHealth([PRINCIPAL_HEALTHY]),
    PRINCIPAL_HEALTHY,
  );
  assertThrows(() => assertPurchasePrincipalHealth([]));
  assertThrows(() =>
    assertPurchasePrincipalHealth([{
      ...PRINCIPAL_HEALTHY,
      unbound_active_principal_count: 5,
    }])
  );
  assertThrows(() =>
    assertPurchasePrincipalHealth([{
      ...PRINCIPAL_HEALTHY,
      pending_principal_count: 1,
    }])
  );
});

Deno.test("purchase-principal health compatibility accepts only its exact missing RPC", () => {
  assertEquals(
    resolvePurchasePrincipalHealthRpcResult(
      [PRINCIPAL_HEALTHY],
      null,
      "required",
    ),
    PRINCIPAL_HEALTHY,
  );
  const missingRpc = {
    code: "PGRST202",
    message:
      "Could not find the function public.get_purchase_principal_health without parameters in the schema cache",
  };
  assertEquals(
    resolvePurchasePrincipalHealthRpcResult(
      null,
      missingRpc,
      "expand-compatible",
    ),
    null,
  );
  assertThrows(() =>
    resolvePurchasePrincipalHealthRpcResult(null, missingRpc, "required")
  );
  assertThrows(() =>
    resolvePurchasePrincipalHealthRpcResult(
      null,
      {
        code: "PGRST202",
        message:
          "Could not find the function public.get_another_health_rpc without parameters in the schema cache",
      },
      "expand-compatible",
    )
  );
  assertThrows(() =>
    resolvePurchasePrincipalHealthRpcResult(
      null,
      {
        code: "PGRST202",
        message:
          "Could not find the function public.get_purchase_principal_health_extra without parameters in the schema cache",
      },
      "expand-compatible",
    )
  );
  assertThrows(() =>
    resolvePurchasePrincipalHealthRpcResult(
      null,
      { code: "42501", message: "permission denied" },
      "expand-compatible",
    )
  );
});

Deno.test("revenueCatBacklogStatus alerts on age and expired leases", () => {
  assertEquals(revenueCatBacklogStatus(HEALTHY, 30, 60), "ok");
  assertEquals(
    revenueCatBacklogStatus(
      { ...HEALTHY, expired_claim_count: 1 },
      30,
      60,
    ),
    "warning",
  );
  assertEquals(
    revenueCatBacklogStatus(
      {
        ...HEALTHY,
        due_count: 1,
        oldest_due_at: "2026-07-26T03:00:00.000Z",
        oldest_due_age_seconds: 30 * 60,
      },
      30,
      60,
    ),
    "warning",
  );
  assertEquals(
    revenueCatBacklogStatus(
      {
        ...HEALTHY,
        due_count: 1,
        oldest_due_at: "2026-07-26T02:30:00.000Z",
        oldest_due_age_seconds: 60 * 60,
      },
      30,
      60,
    ),
    "critical",
  );
  assertEquals(
    revenueCatBacklogStatus(
      {
        ...HEALTHY,
        signout_bound_count: 1,
        oldest_signout_pending_at: "2026-07-26T03:00:00.000Z",
        oldest_signout_pending_age_seconds: 30 * 60,
      },
      30,
      60,
    ),
    "warning",
  );
  assertEquals(
    revenueCatBacklogStatus(
      HEALTHY,
      30,
      60,
      { ...PRINCIPAL_HEALTHY, unbound_active_principal_count: 1 },
    ),
    "warning",
  );
  assertEquals(
    revenueCatBacklogStatus(
      HEALTHY,
      30,
      60,
      {
        ...PRINCIPAL_HEALTHY,
        pending_principal_count: 1,
        oldest_pending_at: "2026-07-26T02:30:00.000Z",
        oldest_pending_age_seconds: 60 * 60,
      },
    ),
    "critical",
  );
});

Deno.test("shouldFailRevenueCatMonitor honors the configured severity", () => {
  assertEquals(shouldFailRevenueCatMonitor("ok", "warning"), false);
  assertEquals(shouldFailRevenueCatMonitor("warning", "warning"), true);
  assertEquals(shouldFailRevenueCatMonitor("warning", "critical"), false);
  assertEquals(shouldFailRevenueCatMonitor("critical", "critical"), true);
  assertEquals(shouldFailRevenueCatMonitor("critical", "never"), false);
});

Deno.test("renderRevenueCatMonitorMarkdown includes backlog and operator action", () => {
  const health: RevenueCatReconciliationHealth = {
    ...HEALTHY,
    due_count: 7,
    expired_claim_count: 1,
    oldest_due_at: "2026-07-26T02:45:00.000Z",
    oldest_due_age_seconds: 2_700,
  };
  const summary = buildRevenueCatMonitorSummary(
    health,
    parseRevenueCatMonitorArgs([]),
    new Date("2026-07-26T03:30:00.000Z"),
    PRINCIPAL_HEALTHY,
  );
  const markdown = renderRevenueCatMonitorMarkdown(summary);

  assertEquals(summary.status, "warning");
  assertEquals(summary.purchase_principal_health_availability, "available");
  assertEquals(summary.failure_policy.should_fail, true);
  assertStringIncludes(markdown, "# RevenueCat Reconciliation Health");
  assertStringIncludes(markdown, "- Due rows: `7`");
  assertStringIncludes(markdown, "- Expired claims: `1`");
  assertStringIncludes(markdown, "- Oldest due age: `2700s`");
  assertStringIncludes(markdown, "- Bound sign-out handoffs: `0`");
  assertStringIncludes(markdown, "## Stable Purchase Principals");
  assertStringIncludes(markdown, "- Active principals: `4`");
  assertStringIncludes(
    markdown,
    "- Unbound active principals with current StoreKit access: `0`",
  );
  assertStringIncludes(markdown, "Do not edit subscription tiers");
  assertStringIncludes(markdown, "discard bound proofs");
});

Deno.test("monitor summary exposes an undeployed principal RPC without fake zeroes", () => {
  const summary = buildRevenueCatMonitorSummary(
    HEALTHY,
    parseRevenueCatMonitorArgs([
      "--purchase-principal-health-mode",
      "expand-compatible",
    ]),
    new Date("2026-07-26T03:30:00.000Z"),
    null,
  );
  const markdown = renderRevenueCatMonitorMarkdown(summary);

  assertEquals(summary.status, "ok");
  assertEquals(summary.failure_policy.should_fail, false);
  assertEquals(summary.purchase_principal_health_availability, "not_deployed");
  assertEquals(summary.purchase_principal_health, null);
  assertStringIncludes(markdown, "- Availability: `not_deployed`");
  assertStringIncludes(markdown, "legacy reconciliation");
  assertStringIncludes(markdown, "switch the scheduled monitor to required");
});
