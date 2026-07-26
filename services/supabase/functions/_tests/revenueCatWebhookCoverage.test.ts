import {
  assert,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";

const handlerUrl = new URL("../revenuecat-webhook/handler.ts", import.meta.url);
const indexUrl = new URL("../revenuecat-webhook/index.ts", import.meta.url);
const reconcilerUrl = new URL(
  "../reconcile-revenuecat-subscribers/index.ts",
  import.meta.url,
);
const reconcilerWorkerUrl = new URL(
  "../reconcile-revenuecat-subscribers/worker.ts",
  import.meta.url,
);
const reconcilerDatabaseUrl = new URL(
  "../reconcile-revenuecat-subscribers/db.ts",
  import.meta.url,
);
const monitorScriptUrl = new URL(
  "../../scripts/monitor_revenuecat_reconciliation.ts",
  import.meta.url,
);
const configUrl = new URL("../../config.toml", import.meta.url);
const workflowUrl = new URL(
  "../../../../.github/workflows/deploy.yml",
  import.meta.url,
);
const monitorWorkflowUrl = new URL(
  "../../../../.github/workflows/revenuecat-reconciliation-health-monitor.yml",
  import.meta.url,
);

Deno.test("RevenueCat webhook verifies ingress before authoritative state mutation", async () => {
  const handler = await Deno.readTextFile(handlerUrl);
  const signatureIndex = handler.indexOf("verifyRevenueCatSignature(");
  const parseIndex = handler.indexOf("parseRevenueCatWebhook(rawBody)");
  const duplicateLookupIndex = handler.indexOf(
    "getRevenueCatWebhookEventResult(",
  );
  const customerInfoIndex = handler.indexOf("fetchRevenueCatCustomerInfo(");
  const transactionIndex = handler.indexOf("applyRevenueCatCustomerState(");
  const scheduleIndex = handler.lastIndexOf(
    "scheduleRevenueCatReconciliation(",
  );

  for (
    const index of [
      signatureIndex,
      parseIndex,
      duplicateLookupIndex,
      customerInfoIndex,
      transactionIndex,
      scheduleIndex,
    ]
  ) {
    assert(
      index >= 0,
      "RevenueCat webhook boundary is missing a required stage.",
    );
  }
  assert(
    signatureIndex < parseIndex &&
      parseIndex < duplicateLookupIndex &&
      duplicateLookupIndex < customerInfoIndex &&
      customerInfoIndex < transactionIndex,
    "RevenueCat webhook must verify, parse, deduplicate, reconcile, then transact in that order.",
  );
  assert(
    transactionIndex < scheduleIndex,
    "Periodic reconciliation must be durably scheduled before the delivery is acknowledged.",
  );
  assertStringIncludes(
    handler,
    "first delivery may have committed the entitlement transaction",
  );
  assertStringIncludes(handler, "Promise.all(subjects.map(");
  assertStringIncludes(
    handler,
    "TRANSFER reconciles both sides before",
  );
});

Deno.test("RevenueCat has a deadline-draining leased periodic CustomerInfo sweep", async () => {
  const [index, worker, database, config] = await Promise.all([
    Deno.readTextFile(reconcilerUrl),
    Deno.readTextFile(reconcilerWorkerUrl),
    Deno.readTextFile(reconcilerDatabaseUrl),
    Deno.readTextFile(configUrl),
  ]);

  for (
    const fragment of [
      "timingSafeCompare(",
      "`Bearer ${serviceRoleKey}`",
      "processRevenueCatReconciliations(",
      "REVENUECAT_SECRET_API_KEY",
    ]
  ) {
    assertStringIncludes(index, fragment);
  }
  for (
    const fragment of [
      "CLAIM_BATCH_SIZE = 6",
      "FETCH_CONCURRENCY = 3",
      "RUNTIME_BUDGET_MS = 90_000",
      "FINAL_WAVE_AND_HEALTH_RESERVE_MS = 30_000",
      "while (runtime.monotonicNow() < claimCutoffAt)",
      "claimRevenueCatReconciliations",
      "fetchRevenueCatCustomerInfo",
      "deriveRevenueCatEntitlementState(",
      "allowNonSubscriptionPassGrant",
      "applyRevenueCatReconciliation",
      "failRevenueCatReconciliation",
      "getRevenueCatReconciliationHealth",
      "revenueCatReconciliationHealthStatus",
      'event: "revenuecat_reconciliation_health"',
    ]
  ) {
    assertStringIncludes(worker, fragment);
  }
  assertStringIncludes(
    database,
    '"get_revenuecat_reconciliation_health"',
  );
  assertStringIncludes(database, "limit = 6");

  const sectionStart = config.indexOf(
    "[functions.reconcile-revenuecat-subscribers]",
  );
  const sectionEnd = config.indexOf("\n[functions.", sectionStart + 1);
  assertStringIncludes(
    config.slice(sectionStart, sectionEnd),
    "verify_jwt = false",
  );
});

Deno.test("RevenueCat reconciliation backlog has an independent age alert", async () => {
  const [script, workflow] = await Promise.all([
    Deno.readTextFile(monitorScriptUrl),
    Deno.readTextFile(monitorWorkflowUrl),
  ]);

  for (
    const fragment of [
      "/rest/v1/rpc/get_revenuecat_reconciliation_health",
      "RESPONSE_DEADLINE_MS = 15_000",
      "MAXIMUM_RESPONSE_BYTES = 64 * 1_024",
      'values.get("warning-after-minutes") ?? "30"',
      'values.get("critical-after-minutes") ?? "60"',
      'values.get("fail-on") ?? "warning"',
      "expired_claim_count > 0",
      "oldestDueAgeSeconds >= criticalAfterMinutes * 60",
    ]
  ) {
    assertStringIncludes(script, fragment);
  }
  for (
    const fragment of [
      'cron: "7,22,37,52 * * * *"',
      "default: warning",
      "monitor_revenuecat_reconciliation.ts",
      "--warning-after-minutes",
      "--critical-after-minutes",
      "SUPABASE_SERVICE_ROLE_KEY",
    ]
  ) {
    assertStringIncludes(workflow, fragment);
  }
});

Deno.test("RevenueCat production secrets are fail-closed and synchronized", async () => {
  const index = await Deno.readTextFile(indexUrl);
  const handler = await Deno.readTextFile(handlerUrl);
  const workflow = await Deno.readTextFile(workflowUrl);

  for (
    const secret of [
      "REVENUECAT_SECRET_API_KEY",
      "REVENUECAT_WEBHOOK_SECRET",
      "REVENUECAT_WEBHOOK_SIGNING_SECRET",
    ]
  ) {
    assertStringIncludes(index, secret);
    assertStringIncludes(
      workflow,
      `\${${secret}:?Missing ${secret} GitHub secret}`,
    );
    assertStringIncludes(
      workflow,
      `"${secret}=$${secret}"`,
    );
  }

  assertStringIncludes(handler, 'config.apiKey.startsWith("sk_")');
  assertStringIncludes(workflow, "sk_*)");
});
