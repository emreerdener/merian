import { assertEquals, assertStringIncludes, assertThrows } from "@std/assert";
import {
  assertPurchasePrincipalHealth,
  assertPurchasePrincipalSignoutRotationHealth,
  assertRevenueCatReconciliationHealth,
  buildRevenueCatMonitorSummary,
  parseRevenueCatMonitorArgs,
  type PurchasePrincipalHealth,
  type PurchasePrincipalSignoutRotationHealth,
  renderRevenueCatMonitorMarkdown,
  resolvePurchasePrincipalHealthRpcResult,
  resolvePurchasePrincipalSignoutRotationHealthRpcResult,
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

const ROTATION_HEALTHY: PurchasePrincipalSignoutRotationHealth = {
  generated_at: "2026-07-26T03:30:00.000Z",
  prepared_count: 0,
  expired_prepared_count: 0,
  oldest_prepared_at: null,
  oldest_prepared_age_seconds: null,
  completed_last_24h: 3,
  cancelled_last_24h: 1,
};

Deno.test("parseRevenueCatMonitorArgs applies alerting defaults", () => {
  assertEquals(parseRevenueCatMonitorArgs([]), {
    warningAfterMinutes: 30,
    criticalAfterMinutes: 60,
    warningPreparedRotations: 100,
    criticalPreparedRotations: 500,
    failOn: "warning",
    purchasePrincipalSignoutRotationHealthMode: "required",
    summaryJsonPath: null,
    summaryMarkdownPath: null,
  });
  assertEquals(
    parseRevenueCatMonitorArgs([
      "--warning-after-minutes=45",
      "--critical-after-minutes",
      "90",
      "--warning-prepared-rotations",
      "250",
      "--critical-prepared-rotations=1000",
      "--fail-on",
      "critical",
      "--purchase-principal-signout-rotation-health-mode",
      "expand-compatible",
      "--summary-json=/tmp/revenuecat.json",
      "--summary-md",
      "/tmp/revenuecat.md",
    ]),
    {
      warningAfterMinutes: 45,
      criticalAfterMinutes: 90,
      warningPreparedRotations: 250,
      criticalPreparedRotations: 1_000,
      failOn: "critical",
      purchasePrincipalSignoutRotationHealthMode: "expand-compatible",
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
  assertThrows(() =>
    parseRevenueCatMonitorArgs([
      "--warning-prepared-rotations",
      "500",
      "--critical-prepared-rotations",
      "500",
    ])
  );
  assertThrows(() => parseRevenueCatMonitorArgs(["--fail-on", "always"]));
  assertThrows(() =>
    parseRevenueCatMonitorArgs([
      "--purchase-principal-health-mode",
      "required",
    ])
  );
  assertThrows(() =>
    parseRevenueCatMonitorArgs([
      "--purchase-principal-signout-rotation-health-mode",
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

Deno.test("assertPurchasePrincipalSignoutRotationHealth validates exact aggregate health", () => {
  assertEquals(
    assertPurchasePrincipalSignoutRotationHealth([ROTATION_HEALTHY]),
    ROTATION_HEALTHY,
  );
  assertThrows(() => assertPurchasePrincipalSignoutRotationHealth([]));
  assertThrows(() =>
    assertPurchasePrincipalSignoutRotationHealth([{
      ...ROTATION_HEALTHY,
      prepared_count: 1,
    }])
  );
  assertThrows(() =>
    assertPurchasePrincipalSignoutRotationHealth([{
      ...ROTATION_HEALTHY,
      expired_prepared_count: -1,
    }])
  );
});

Deno.test("purchase-principal health is unconditionally required", () => {
  assertEquals(
    resolvePurchasePrincipalHealthRpcResult(
      [PRINCIPAL_HEALTHY],
      null,
    ),
    PRINCIPAL_HEALTHY,
  );
  const missingRpc = {
    code: "PGRST202",
    message:
      "Could not find the function public.get_purchase_principal_health without parameters in the schema cache",
  };
  assertThrows(() => resolvePurchasePrincipalHealthRpcResult(null, missingRpc));
  assertThrows(() =>
    resolvePurchasePrincipalHealthRpcResult(
      null,
      {
        code: "PGRST202",
        message:
          "Could not find the function public.get_another_health_rpc without parameters in the schema cache",
      },
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
    )
  );
  assertThrows(() =>
    resolvePurchasePrincipalHealthRpcResult(
      null,
      { code: "42501", message: "permission denied" },
    )
  );
});

Deno.test("rotation health compatibility accepts only its exact missing RPC", () => {
  assertEquals(
    resolvePurchasePrincipalSignoutRotationHealthRpcResult(
      [ROTATION_HEALTHY],
      null,
      "required",
    ),
    ROTATION_HEALTHY,
  );
  const missingRpc = {
    code: "PGRST202",
    message:
      "Could not find the function public.get_purchase_principal_signout_rotation_health without parameters in the schema cache",
  };
  assertEquals(
    resolvePurchasePrincipalSignoutRotationHealthRpcResult(
      null,
      missingRpc,
      "expand-compatible",
    ),
    null,
  );
  assertThrows(() =>
    resolvePurchasePrincipalSignoutRotationHealthRpcResult(
      null,
      missingRpc,
      "required",
    )
  );
  assertThrows(() =>
    resolvePurchasePrincipalSignoutRotationHealthRpcResult(
      null,
      {
        code: "PGRST202",
        message:
          "Could not find the function public.get_purchase_principal_signout_rotation_health_extra without parameters in the schema cache",
      },
      "expand-compatible",
    )
  );
});

Deno.test("revenueCatBacklogStatus alerts on age and expired leases", () => {
  assertEquals(
    revenueCatBacklogStatus(HEALTHY, 30, 60, PRINCIPAL_HEALTHY),
    "ok",
  );
  assertEquals(
    revenueCatBacklogStatus(
      { ...HEALTHY, expired_claim_count: 1 },
      30,
      60,
      PRINCIPAL_HEALTHY,
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
      PRINCIPAL_HEALTHY,
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
      PRINCIPAL_HEALTHY,
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
      PRINCIPAL_HEALTHY,
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
  assertEquals(
    revenueCatBacklogStatus(
      HEALTHY,
      30,
      60,
      PRINCIPAL_HEALTHY,
      { ...ROTATION_HEALTHY, expired_prepared_count: 1 },
    ),
    "warning",
  );
  assertEquals(
    revenueCatBacklogStatus(
      HEALTHY,
      30,
      60,
      PRINCIPAL_HEALTHY,
      {
        ...ROTATION_HEALTHY,
        prepared_count: 1,
        oldest_prepared_at: "2026-07-26T02:30:00.000Z",
        oldest_prepared_age_seconds: 60 * 60,
      },
    ),
    "critical",
  );
  assertEquals(
    revenueCatBacklogStatus(
      HEALTHY,
      30,
      60,
      PRINCIPAL_HEALTHY,
      { ...ROTATION_HEALTHY, prepared_count: 100 },
      100,
      500,
    ),
    "warning",
  );
  assertEquals(
    revenueCatBacklogStatus(
      HEALTHY,
      30,
      60,
      PRINCIPAL_HEALTHY,
      { ...ROTATION_HEALTHY, prepared_count: 500 },
      100,
      500,
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
    ROTATION_HEALTHY,
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
  assertStringIncludes(markdown, "## Stable Sign-Out Rotations");
  assertStringIncludes(markdown, "- Prepared rotations: `0`");
  assertStringIncludes(markdown, "- Completed in 24h: `3`");
  assertStringIncludes(markdown, "Prepared-rotation warning count: `100`");
  assertStringIncludes(markdown, "Do not edit subscription tiers");
  assertStringIncludes(markdown, "discard bound proofs");
});

Deno.test("monitor summary exposes only an undeployed rotation RPC without fake zeroes", () => {
  const summary = buildRevenueCatMonitorSummary(
    HEALTHY,
    parseRevenueCatMonitorArgs([
      "--purchase-principal-signout-rotation-health-mode",
      "expand-compatible",
    ]),
    new Date("2026-07-26T03:30:00.000Z"),
    PRINCIPAL_HEALTHY,
    null,
  );
  const markdown = renderRevenueCatMonitorMarkdown(summary);

  assertEquals(summary.status, "ok");
  assertEquals(summary.failure_policy.should_fail, false);
  assertEquals(summary.purchase_principal_health_availability, "available");
  assertEquals(summary.purchase_principal_health, PRINCIPAL_HEALTHY);
  assertEquals(
    summary.purchase_principal_signout_rotation_health_availability,
    "not_deployed",
  );
  assertEquals(summary.purchase_principal_signout_rotation_health, null);
  assertStringIncludes(markdown, "- Availability: `not_deployed`");
  assertStringIncludes(
    markdown,
    "unavailable rotation aggregate",
  );
});
