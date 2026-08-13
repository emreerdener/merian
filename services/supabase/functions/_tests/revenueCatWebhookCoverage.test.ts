import { assert, assertStringIncludes } from "@std/assert";

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
const identityBoundaryUrls = [
  new URL("../resolve-purchase-principal/handler.ts", import.meta.url),
  new URL("../transfer-signout-purchases/handler.ts", import.meta.url),
  new URL("../merge-ghost-profile/index.ts", import.meta.url),
  new URL("../reconcile-ghost-profile-merges/index.ts", import.meta.url),
  reconcilerUrl,
];

Deno.test("RevenueCat webhook verifies ingress before authoritative state mutation", async () => {
  const handler = await Deno.readTextFile(handlerUrl);
  const signatureIndex = handler.indexOf("verifyRevenueCatSignature(");
  const parseIndex = handler.indexOf("parseRevenueCatWebhook(rawBody)");
  const duplicateLookupIndex = handler.indexOf(
    "getRevenueCatWebhookEventResult(",
  );
  const identityResolutionIndex = handler.lastIndexOf(
    "resolveRevenueCatIdentitySubjects(",
  );
  const customerInfoIndex = handler.indexOf("fetchRevenueCatCustomerInfo(");
  const transactionIndex = handler.indexOf("applyRevenueCatIdentityState(");
  const scheduleIndex = handler.lastIndexOf(
    "scheduleRevenueCatIdentityReconciliation(",
  );

  for (
    const index of [
      signatureIndex,
      parseIndex,
      duplicateLookupIndex,
      identityResolutionIndex,
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
      duplicateLookupIndex < identityResolutionIndex &&
      identityResolutionIndex < customerInfoIndex &&
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
  assertStringIncludes(handler, "Promise.all(");
  assertStringIncludes(handler, "resolvedSubjects.map(async (subject)");
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
      "authorizeServiceRoleRequestFromEnvironment(",
      "createServiceRoleClient(",
      "auth.serverApiKey",
      "processRevenueCatReconciliations(",
      "REVENUECAT_SECRET_API_KEY",
    ]
  ) {
    assertStringIncludes(index, fragment);
  }
  assert(
    !index.includes('Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")'),
    "The reconciler must not bypass the shared server-key resolver.",
  );
  for (
    const fragment of [
      "CLAIM_BATCH_SIZE_PER_IDENTITY = 3",
      "FETCH_CONCURRENCY = 3",
      "RUNTIME_BUDGET_MS = 90_000",
      "FINAL_WAVE_AND_HEALTH_RESERVE_MS = 30_000",
      "while (runtime.monotonicNow() < claimCutoffAt)",
      "claimRevenueCatReconciliations",
      "claimPurchasePrincipalReconciliations",
      "fetchRevenueCatCustomerInfo",
      "deriveRevenueCatEntitlementState(",
      "deriveRevenueCatStoreEntitlementState(",
      "allowNonSubscriptionPassGrant",
      "applyRevenueCatReconciliation",
      "applyPurchasePrincipalReconciliation",
      "failRevenueCatReconciliation",
      "failPurchasePrincipalReconciliation",
      "getRevenueCatReconciliationHealth",
      "getPurchasePrincipalHealth",
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
      '"get_revenuecat_reconciliation_health"',
      '"get_purchase_principal_health"',
      "createServiceRoleClientFromEnvironment",
      'values.get("warning-after-minutes") ?? "30"',
      'values.get("critical-after-minutes") ?? "60"',
      'values.get("fail-on") ?? "warning"',
      'values.get("purchase-principal-health-mode") ?? "required"',
      'error.code === "PGRST202"',
      '"function public.get_purchase_principal_health without parameters"',
      "expired_claim_count > 0",
      "oldestDueAgeSeconds >= criticalAfterMinutes * 60",
      "oldest_signout_pending_age_seconds",
      "purchasePrincipalHealth?.expired_claim_count",
      "purchasePrincipalHealth?.unbound_active_principal_count",
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
      "--purchase-principal-health-mode required",
      "SUPABASE_SERVER_API_KEY",
      "resolve_project_api_keys.ts",
    ]
  ) {
    assertStringIncludes(workflow, fragment);
  }
});

Deno.test("authentication and purchase identity failures use the zero-identity logger", async () => {
  for (const url of identityBoundaryUrls) {
    const source = await Deno.readTextFile(url);
    assertStringIncludes(source, "logIdentitySafeError");
    assert(
      !source.includes("logStructuredError"),
      `${url.pathname} can bypass the identity-safe detail allowlist.`,
    );
    assert(
      !source.includes("console.error"),
      `${url.pathname} can emit raw authentication or purchase errors.`,
    );
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
