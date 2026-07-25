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
const configUrl = new URL("../../config.toml", import.meta.url);
const workflowUrl = new URL(
  "../../../../.github/workflows/deploy.yml",
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

Deno.test("RevenueCat has a bounded leased periodic CustomerInfo sweep", async () => {
  const [index, worker, config] = await Promise.all([
    Deno.readTextFile(reconcilerUrl),
    Deno.readTextFile(reconcilerWorkerUrl),
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
      "MAX_CLAIMS_PER_INVOCATION = 10",
      "FETCH_CONCURRENCY = 3",
      "claimRevenueCatReconciliations",
      "fetchRevenueCatCustomerInfo",
      "deriveRevenueCatEntitlementState(",
      "allowNonSubscriptionPassGrant",
      "applyRevenueCatReconciliation",
      "failRevenueCatReconciliation",
    ]
  ) {
    assertStringIncludes(worker, fragment);
  }

  const sectionStart = config.indexOf(
    "[functions.reconcile-revenuecat-subscribers]",
  );
  const sectionEnd = config.indexOf("\n[functions.", sectionStart + 1);
  assertStringIncludes(
    config.slice(sectionStart, sectionEnd),
    "verify_jwt = false",
  );
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
