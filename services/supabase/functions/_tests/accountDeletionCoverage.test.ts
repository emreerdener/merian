import { assert, assertStringIncludes } from "@std/assert";

const handlerUrl = new URL("../safe-delete/handler.ts", import.meta.url);
const workerUrl = new URL("../safe-delete/worker.ts", import.meta.url);
const dbUrl = new URL("../safe-delete/db.ts", import.meta.url);
const appleClientUrl = new URL("../_shared/appleSignIn.ts", import.meta.url);
const appleRegistrationUrl = new URL(
  "../register-apple-revocation-token/handler.ts",
  import.meta.url,
);
const swiftAuthUrl = new URL(
  "../../../../apps/ios/Merian/Core/Network/SupabaseManager.swift",
  import.meta.url,
);
const storageWorkerUrl = new URL(
  "../safe-delete/storageWorker.ts",
  import.meta.url,
);
const reaperUrl = new URL(
  "../reconcile-account-deletions/index.ts",
  import.meta.url,
);
const configUrl = new URL("../../config.toml", import.meta.url);
const workflowUrl = new URL(
  "../../../../.github/workflows/deploy.yml",
  import.meta.url,
);
const monitorWorkflowUrl = new URL(
  "../../../../.github/workflows/account-deletion-health-monitor.yml",
  import.meta.url,
);
const monitorScriptUrl = new URL(
  "../../scripts/monitor_account_deletion_health.ts",
  import.meta.url,
);
const catalogTestUrl = new URL(
  "../../tests/account_deletion_security.sql",
  import.meta.url,
);

Deno.test("account deletion source preserves durable cleanup-provider-Auth ordering", async () => {
  const [handler, worker, db, storageWorker, appleClient] = await Promise.all([
    Deno.readTextFile(handlerUrl),
    Deno.readTextFile(workerUrl),
    Deno.readTextFile(dbUrl),
    Deno.readTextFile(storageWorkerUrl),
    Deno.readTextFile(appleClientUrl),
  ]);

  assert(
    handler.indexOf("await request(userId, supabaseAdmin)") <
      handler.indexOf("await process(supabaseAdmin"),
    "The request receipt must be durable before the fast-path worker runs.",
  );
  assertStringIncludes(worker, 'if (cleanupPhase === "storage_pending")');
  assert(
    worker.indexOf('if (cleanupPhase === "storage_pending")') <
      worker.indexOf("await deleteAuth(claim.userId, supabaseAdmin)"),
    "Auth deletion must be unreachable while storage cleanup is pending.",
  );
  assert(
    worker.indexOf("await cleanup(supabaseAdmin, claim)") <
      worker.indexOf("await deleteAuth(claim.userId, supabaseAdmin)"),
    "Relational cleanup must complete before Auth deletion.",
  );
  assertStringIncludes(
    worker,
    'if (cleanupPhase === "provider_revocation_pending")',
  );
  assert(
    worker.indexOf("await revokeProvider(credential.refreshToken)") <
        worker.indexOf("await completeProvider(supabaseAdmin, claim)") &&
      worker.indexOf("await completeProvider(supabaseAdmin, claim)") <
        worker.indexOf("await deleteAuth(claim.userId, supabaseAdmin)"),
    "Apple must return success and the provider outcome must commit before Auth deletion.",
  );
  assert(
    !worker.includes('if (claim.status === "pending")'),
    "Every retry must revalidate cleanup immediately before Auth deletion.",
  );
  assertStringIncludes(worker, '"completion_write_failed"');
  assertStringIncludes(db, "auth.admin.deleteUser(userId)");
  assertStringIncludes(db, 'error.code === "user_not_found"');
  assertStringIncludes(db, "status === 404");
  assertStringIncludes(db, '"get_account_deletion_provider_token"');
  assertStringIncludes(
    db,
    '"complete_account_deletion_provider_revocation"',
  );
  assertStringIncludes(appleClient, "`${APPLE_ISSUER}/auth/revoke`");
  assertStringIncludes(appleClient, 'token_type_hint: "refresh_token"');
  for (
    const fragment of [
      "claimStorageDeletionJobs",
      "listR2ObjectKeys",
      "deleteR2Object",
      "advanceStorageDeletionJob",
      "failStorageDeletionJob",
      "MAX_LIMIT = 4",
    ]
  ) {
    assertStringIncludes(storageWorker, fragment);
  }
});

Deno.test("Apple sign-in captures the one-use code through the authenticated durable endpoint", async () => {
  const [registration, swiftAuth, config, workflow] = await Promise.all([
    Deno.readTextFile(appleRegistrationUrl),
    Deno.readTextFile(swiftAuthUrl),
    Deno.readTextFile(configUrl),
    Deno.readTextFile(workflowUrl),
  ]);

  for (
    const fragment of [
      "appleRevocationRegistrationExists",
      "exchangeAppleAuthorizationCode",
      "storeAppleRevocationCredential",
      "revokeAppleRefreshToken",
      '"apple_credential_compensation_failed"',
    ]
  ) {
    assertStringIncludes(registration, fragment);
  }
  assert(
    registration.indexOf("await registrationExists(") <
        registration.indexOf(
          "await exchange(authorizationCode, identityToken)",
        ) &&
      registration.indexOf("await exchange(authorizationCode, identityToken)") <
        registration.indexOf("await store(supabaseAdmin"),
    "A retry receipt must be checked before code exchange, and exchange must precede the atomic Vault store.",
  );

  for (
    const fragment of [
      "appleIDCredential.authorizationCode",
      "ASAuthorizationAppleIDProvider.credentialRevokedNotification",
      "getCredentialState(",
      "self.currentUser?.identities?.contains(where:",
      '$0.provider == "apple" && $0.id == appleUserId',
      "shouldClearLocalSessionAfterAppleCredentialState",
      '"register-apple-revocation-token"',
      "performAppleCredentialRegistrationWithRetry",
      "didInstallAppleSession",
      "clearLocalSessionAfterAuthFailure",
    ]
  ) {
    assertStringIncludes(swiftAuth, fragment);
  }

  const registrationConfigStart = config.indexOf(
    "[functions.register-apple-revocation-token]",
  );
  const registrationConfigEnd = config.indexOf(
    "\n[functions.",
    registrationConfigStart + 1,
  );
  assertStringIncludes(
    config.slice(registrationConfigStart, registrationConfigEnd),
    "verify_jwt = true",
  );
  for (
    const secret of [
      "APPLE_SIGN_IN_TEAM_ID",
      "APPLE_SIGN_IN_KEY_ID",
      "APPLE_SIGN_IN_PRIVATE_KEY",
    ]
  ) {
    assertStringIncludes(workflow, secret);
  }
  const secretGateStart = workflow.indexOf(
    "- name: Validate deployment secrets",
  );
  const migrationPush = workflow.indexOf("- name: Push Database Migrations");
  const secretGate = workflow.slice(secretGateStart, migrationPush);
  for (
    const secret of [
      "APPLE_SIGN_IN_TEAM_ID",
      "APPLE_SIGN_IN_KEY_ID",
      "APPLE_SIGN_IN_PRIVATE_KEY",
    ]
  ) {
    assertStringIncludes(secretGate, secret);
  }
  assertStringIncludes(secretGate, "BEGIN PRIVATE KEY");
});

Deno.test("account deletion reaper is service-only, bounded, and deployed", async () => {
  const [reaper, config, workflow] = await Promise.all([
    Deno.readTextFile(reaperUrl),
    Deno.readTextFile(configUrl),
    Deno.readTextFile(workflowUrl),
  ]);

  for (
    const fragment of [
      "authorizeServiceRoleRequestFromEnvironment(req)",
      "createServiceRoleClient(",
      "auth.serverApiKey",
      'limit: "small"',
      "allowEmpty: true",
      "processAccountDeletionJobs(supabaseAdmin",
      "processPendingStorageDeletions(",
    ]
  ) {
    assertStringIncludes(reaper, fragment);
  }
  assert(
    !reaper.includes("targetUserId"),
    "The service reaper must never accept a caller-selected target user.",
  );

  const configStart = config.indexOf(
    "[functions.reconcile-account-deletions]",
  );
  const configEnd = config.indexOf("\n[functions.", configStart + 1);
  const section = config.slice(configStart, configEnd);
  assertStringIncludes(section, "verify_jwt = false");
  assertStringIncludes(
    workflow,
    "supabase/functions/_tests/accountDeletionCoverage.test.ts",
  );
  assertStringIncludes(
    workflow,
    "supabase/tests/account_deletion_security.sql",
  );
});

Deno.test("account deletion catalog fixture follows the durable phase order", async () => {
  const catalogTest = await Deno.readTextFile(catalogTestUrl);
  const prematureFinish = catalogTest.indexOf(
    "PERFORM public.finish_account_deletion_attempt(",
  );
  const relationalCleanup = catalogTest.indexOf(
    "SELECT public.complete_account_deletion_cleanup(",
  );
  const verificationDeadlineOverride = catalogTest.indexOf(
    "SET verification_not_before = pg_catalog.NOW()",
  );
  const storageClaim = catalogTest.indexOf(
    "FROM public.claim_pending_storage_deletions(1)",
  );
  const providerToken = catalogTest.indexOf(
    "FROM public.get_account_deletion_provider_token(",
    storageClaim,
  );
  const providerCompletion = catalogTest.indexOf(
    "SELECT public.complete_account_deletion_provider_revocation(",
    providerToken,
  );
  const healthCheck = catalogTest.indexOf(
    "FROM public.get_account_deletion_health() AS health",
  );
  const authDeletion = catalogTest.indexOf(
    "DELETE FROM auth.users\nWHERE id =",
    providerCompletion,
  );

  assert(
    prematureFinish >= 0 &&
      relationalCleanup > prematureFinish &&
      verificationDeadlineOverride > relationalCleanup &&
      storageClaim > verificationDeadlineOverride &&
      providerToken > storageClaim &&
      providerCompletion > providerToken &&
      healthCheck > providerCompletion &&
      authDeletion > healthCheck,
    "The executable fixture must reject premature completion, finish durable storage, revoke and destroy the Apple credential, observe retry state, and only then delete Auth.",
  );
});

Deno.test("account deletion health alert is independent of the database reaper", async () => {
  const [workflow, monitor] = await Promise.all([
    Deno.readTextFile(monitorWorkflowUrl),
    Deno.readTextFile(monitorScriptUrl),
  ]);

  for (
    const fragment of [
      'cron: "2-57/5 * * * *"',
      "environment: Production",
      "timeout-minutes: 5",
      "permissions:\n  contents: read",
      "resolve_project_api_keys.ts",
      "SUPABASE_ACCESS_TOKEN",
      "monitor_account_deletion_health.ts",
      "--warning-due-after-minutes",
      "--critical-sla-hours",
      "if: ${{ always() }}",
    ]
  ) {
    assertStringIncludes(workflow, fragment);
  }
  assert(
    !workflow.includes("vault.decrypted_secrets") &&
      !workflow.includes("/functions/v1/reconcile-account-deletions"),
    "The independent alert must not depend on reaper Vault configuration or invoke deletion work.",
  );

  for (
    const fragment of [
      '"get_account_deletion_health"',
      "createServiceRoleClientFromEnvironment",
      "reaper_cron_active",
      "reaper_credentials_configured",
      "orphaned_storage_job_count",
      "oldest_pending_age_seconds",
      "oldest_storage_due_age_seconds",
    ]
  ) {
    assertStringIncludes(monitor, fragment);
  }
});
