import { assert, assertStringIncludes } from "@std/assert";

const handlerUrl = new URL("../safe-delete/handler.ts", import.meta.url);
const safeDeleteIndexUrl = new URL("../safe-delete/index.ts", import.meta.url);
const recoveryHandlerUrl = new URL(
  "../recover-account-deletion/handler.ts",
  import.meta.url,
);
const recoveryProtocolUrl = new URL(
  "../safe-delete/protocol.ts",
  import.meta.url,
);
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
const swiftOAuthCoordinatorUrl = new URL(
  "../../../../apps/ios/Merian/Core/Network/Auth/Coordinators/OAuthSignInCoordinator.swift",
  import.meta.url,
);
const swiftOAuthProviderCoordinatorUrl = new URL(
  "../../../../apps/ios/Merian/Core/Network/Auth/Coordinators/OAuthProviderSignInCoordinator.swift",
  import.meta.url,
);
const swiftOAuthModelsUrl = new URL(
  "../../../../apps/ios/Merian/Core/Network/Auth/Models/OAuthSignInModels.swift",
  import.meta.url,
);
const swiftAppleOAuthProviderUrl = new URL(
  "../../../../apps/ios/Merian/Core/Network/Auth/Services/AppleOAuthAuthorizationLiveProvider.swift",
  import.meta.url,
);
const swiftAppleCredentialRegistrationServiceUrl = new URL(
  "../../../../apps/ios/Merian/Core/Network/Auth/Services/AppleOAuthCredentialRegistrationService+Live.swift",
  import.meta.url,
);
const swiftAppleCredentialRegistrationCoreUrl = new URL(
  "../../../../apps/ios/Merian/Core/Network/Auth/Services/AppleOAuthCredentialRegistrationService.swift",
  import.meta.url,
);
const swiftOAuthWorkflowUrl = new URL(
  "../../../../apps/ios/Merian/Core/Network/Auth/Coordinators/OAuthSignInWorkflow.swift",
  import.meta.url,
);
const swiftAppleRevocationCoordinatorUrl = new URL(
  "../../../../apps/ios/Merian/Core/Network/Auth/Coordinators/AppleCredentialRevocationCoordinator.swift",
  import.meta.url,
);
const swiftAppleRevocationProviderUrl = new URL(
  "../../../../apps/ios/Merian/Core/Network/AppleCredentialRevocationLiveProvider.swift",
  import.meta.url,
);
const swiftDeletionWorkflowUrl = new URL(
  "../../../../apps/ios/Merian/Core/Network/Auth/Coordinators/AccountDeletionWorkflow.swift",
  import.meta.url,
);
const swiftDeletionCoordinatorUrl = new URL(
  "../../../../apps/ios/Merian/Core/Network/Auth/Coordinators/AccountDeletionCoordinator.swift",
  import.meta.url,
);
const swiftDeletionRecoveryCoordinatorUrl = new URL(
  "../../../../apps/ios/Merian/Core/Network/Auth/Coordinators/AccountDeletionRecoveryCoordinator.swift",
  import.meta.url,
);
const storageWorkerUrl = new URL(
  "../safe-delete/storageWorker.ts",
  import.meta.url,
);
const reaperUrl = new URL(
  "../reconcile-account-deletions/handler.ts",
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
const recoveryMigrationUrl = new URL(
  "../../migrations/20260813053000_add_account_deletion_recovery_capabilities.sql",
  import.meta.url,
);
const preparedRecoveryV2MigrationUrl = new URL(
  "../../migrations/20260813142638_prepare_account_deletion_recovery_v2.sql",
  import.meta.url,
);
const swiftRecoveryCapabilityUrl = new URL(
  "../../../../apps/ios/Merian/Core/Security/AccountDeletion/Stores/AccountDeletionRecoveryCapabilityStore.swift",
  import.meta.url,
);
const swiftDeletionStateModelUrl = new URL(
  "../../../../apps/ios/Merian/Core/Security/AccountDeletion/Models/AccountDeletionLocalRecoveryState.swift",
  import.meta.url,
);
const swiftDeletionStateStoreUrl = new URL(
  "../../../../apps/ios/Merian/Core/Security/AccountDeletion/Stores/AccountDeletionLocalCleanupStore.swift",
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
  assertStringIncludes(handler, "logIdentitySafeError");
  assert(
    !handler.includes("job_id:"),
    "Account-deletion logs must not expose the private job identity.",
  );
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
  const [
    registration,
    swiftAuth,
    swiftOAuthCoordinator,
    swiftOAuthProviderCoordinator,
    swiftOAuthModels,
    swiftAppleOAuthProvider,
    swiftAppleCredentialRegistrationService,
    swiftAppleCredentialRegistrationCore,
    swiftOAuthWorkflow,
    swiftAppleRevocationCoordinator,
    swiftAppleRevocationProvider,
    config,
    workflow,
  ] = await Promise.all([
    Deno.readTextFile(appleRegistrationUrl),
    Deno.readTextFile(swiftAuthUrl),
    Deno.readTextFile(swiftOAuthCoordinatorUrl),
    Deno.readTextFile(swiftOAuthProviderCoordinatorUrl),
    Deno.readTextFile(swiftOAuthModelsUrl),
    Deno.readTextFile(swiftAppleOAuthProviderUrl),
    Deno.readTextFile(swiftAppleCredentialRegistrationServiceUrl),
    Deno.readTextFile(swiftAppleCredentialRegistrationCoreUrl),
    Deno.readTextFile(swiftOAuthWorkflowUrl),
    Deno.readTextFile(swiftAppleRevocationCoordinatorUrl),
    Deno.readTextFile(swiftAppleRevocationProviderUrl),
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
      '$0.provider == "apple" && !$0.id.isEmpty',
      "appleCredentialRevocationCoordinator",
      "appleCredentialRevocationDependencies()",
      "appleOAuthCredentialRegistrationService = .live(client: client)",
      "oauthProviderSignInCoordinator.signInWithGoogle(",
      "oauthProviderSignInCoordinator.startAppleSignIn(",
      "appleCredentialRegistration",
      "registerAppleRevocationCredential(",
      "recoverOAuthSignInFailureIfNeeded",
    ]
  ) {
    assertStringIncludes(swiftAuth, fragment);
  }
  for (
    const fragment of [
      '"register-apple-revocation-token"',
      "private struct AppleOAuthCredentialRegistrationPayload",
      "private struct AppleOAuthCredentialRegistrationResponse",
      "registration_id: registrationID",
      ".uuidString.lowercased()",
      "authorization_code: authorizationCode",
      "identity_token: identityToken",
    ]
  ) {
    assertStringIncludes(swiftAppleCredentialRegistrationService, fragment);
  }
  assert(
    swiftAppleCredentialRegistrationService.split(
      "client.functions.invoke(",
    ).length === 2,
    "The Apple credential registration adapter must retain one live Function invocation.",
  );
  for (
    const forbiddenOwner of [
      "SupabaseManager",
      "Task {",
      "Task.detached",
      "URLSession",
    ]
  ) {
    assert(
      !swiftAppleCredentialRegistrationService.includes(forbiddenOwner),
      `Apple registration transport acquired forbidden ownership: ${forbiddenOwner}`,
    );
  }
  for (
    const retiredManagerTransport of [
      "AppleRevocationCredentialPayload",
      "AppleRevocationCredentialResponse",
      '"register-apple-revocation-token"',
    ]
  ) {
    assert(
      !swiftAuth.includes(retiredManagerTransport),
      `SupabaseManager reacquired Apple registration transport: ${retiredManagerTransport}`,
    );
  }
  assertStringIncludes(swiftAppleCredentialRegistrationCore, "receipt.success");
  assertStringIncludes(
    swiftAppleCredentialRegistrationCore,
    'receipt.status == "registered"',
  );
  for (
    const fragment of [
      "credential.authorizationCode",
      "AppleOAuthCredentialRegistration(",
      "registrationID: dependencies.registrationID()",
      "authorizationCode: authorizationCodeString",
    ]
  ) {
    assertStringIncludes(swiftAppleOAuthProvider, fragment);
  }
  const appleRegistrationModelStart = swiftOAuthModels.indexOf(
    "struct AppleOAuthCredentialRegistration",
  );
  const appleRegistrationModelEnd = swiftOAuthModels.indexOf(
    "struct OAuthProviderAuthorization",
    appleRegistrationModelStart,
  );
  const appleRegistrationModel = swiftOAuthModels.slice(
    appleRegistrationModelStart,
    appleRegistrationModelEnd,
  );
  assert(
    appleRegistrationModelStart >= 0 &&
      appleRegistrationModelEnd > appleRegistrationModelStart &&
      !appleRegistrationModel.includes("identityToken"),
    "The durable Apple registration value must not duplicate the identity token owned by OAuth credentials.",
  );
  assert(
    swiftAppleOAuthProvider.indexOf("guard let authorizationCode else") <
      swiftAppleOAuthProvider.indexOf(
        "AppleOAuthCredentialRegistration(",
      ),
    "The Apple provider must validate the one-use authorization code before creating the durable registration value.",
  );
  for (
    const fragment of [
      "verifyExpectedSessionIfPresent",
      "didMutateSession = true",
      "recoverAfterFailure(",
    ]
  ) {
    assertStringIncludes(swiftOAuthProviderCoordinator, fragment);
  }
  for (
    const fragment of [
      "ASAuthorizationAppleIDProvider.credentialRevokedNotification",
      "getCredentialState(",
      "lookupFailed: error != nil",
    ]
  ) {
    assertStringIncludes(swiftAppleRevocationProvider, fragment);
  }
  for (
    const fragment of [
      "contextGeneration == attempt.contextGeneration",
      "currentIdentity() == attempt.identity",
      ".clearLocalSessionIfCurrent(",
      "case .contextChanged:",
      "case .deferred:",
    ]
  ) {
    assertStringIncludes(swiftAppleRevocationCoordinator, fragment);
  }
  assert(
    !swiftAppleRevocationCoordinator.includes(
      "dependencies.operations.clearLocalSession()",
    ),
    "Apple credential revocation must not clear a session without fencing the expected identity.",
  );
  const providerAssemblyStart = swiftAuth.indexOf(
    "private func oauthProviderSignInDependencies()",
  );
  const providerAssemblyEnd = swiftAuth.indexOf(
    "private func oauthSignInDependencies()",
    providerAssemblyStart,
  );
  const providerAssembly = swiftAuth.slice(
    providerAssemblyStart,
    providerAssemblyEnd,
  );
  assertStringIncludes(
    providerAssembly,
    "registerProviderCredential: registration",
  );
  assertStringIncludes(
    providerAssembly,
    "let identityToken = authorization.credentials.idToken",
  );
  assertStringIncludes(providerAssembly, "identityToken: identityToken");
  assert(
    !providerAssembly.includes("credential.identityToken"),
    "Apple registration must use the exact identity token that installed the OAuth session.",
  );
  assert(
    providerAssembly.indexOf(
      "let registration: OAuthProviderCredentialRegistration?",
    ) <
      providerAssembly.indexOf(
        "OAuthSignInCoordinator(",
      ),
    "The live Auth assembly must adapt the Apple registration value before provider-neutral session completion.",
  );
  const liveRegistrationStart = swiftAuth.indexOf(
    "private func registerAppleRevocationCredential(",
  );
  const liveRegistrationEnd = swiftAuth.indexOf(
    "private func installOAuthSessionReplacingCurrentAccount(",
    liveRegistrationStart,
  );
  const liveRegistration = swiftAuth.slice(
    liveRegistrationStart,
    liveRegistrationEnd,
  );
  const preflightFence = liveRegistration.indexOf(
    "currentSessionMatchesAuthTransition(transition)",
  );
  const serviceInvocation = liveRegistration.indexOf(
    "appleOAuthCredentialRegistrationService.register(",
  );
  const postflightFence = liveRegistration.indexOf(
    "currentSessionMatchesAuthTransition(transition)",
    preflightFence + 1,
  );
  assert(
    preflightFence >= 0 &&
      serviceInvocation > preflightFence &&
      postflightFence > serviceInvocation,
    "Exact-session fences must surround the extracted Apple registration service.",
  );
  assert(
    !liveRegistration.includes("client.functions.invoke("),
    "The Auth facade must not reacquire the Apple registration transport.",
  );
  for (
    const fragment of [
      "static func registerAppleCredential(",
      "maximumAttempts: Int = 2",
      "try await waitBeforeRetry()",
    ]
  ) {
    assertStringIncludes(swiftOAuthWorkflow, fragment);
  }
  const registrationValidation = swiftOAuthCoordinator.indexOf(
    "let providerRegistrationIsValid = switch credentials.provider",
  );
  const transitionValidation = swiftOAuthCoordinator.indexOf(
    "guard transition.kind == .oauth(credentials.provider) else",
  );
  const sessionInstallation = swiftOAuthCoordinator.indexOf(
    "let installed = try await installSession(",
  );
  assert(
    transitionValidation >= 0 &&
      registrationValidation > transitionValidation &&
      sessionInstallation > registrationValidation,
    "Provider and credential-registration configuration must fail closed before session mutation",
  );
  const registrationStart = swiftOAuthCoordinator.indexOf(
    "if let registerProviderCredential",
  );
  const registrationDispatch = swiftOAuthCoordinator.indexOf(
    "try await registerProviderCredential(",
    registrationStart,
  );
  const metadataPersistence = swiftOAuthCoordinator.indexOf(
    "persistProfileMetadata(",
    registrationDispatch,
  );
  assert(
    registrationStart >= 0 &&
      registrationDispatch > registrationStart &&
      metadataPersistence > registrationDispatch,
    "Apple credential registration must finish before optional profile metadata and purchase binding",
  );

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
  const [reaper, config, workflow, candidateWorkflow] = await Promise.all([
    Deno.readTextFile(reaperUrl),
    Deno.readTextFile(configUrl),
    Deno.readTextFile(workflowUrl),
    Deno.readTextFile(
      new URL("supabase-candidate-validation.yml", workflowUrl),
    ),
  ]);

  for (
    const fragment of [
      "authorizeServiceRoleRequestFromEnvironment(request)",
      "createServiceRoleClient",
      "auth.serverApiKey",
      'limit: "small"',
      "allowEmpty: true",
      "processAccountDeletionJobs",
      "processPendingStorageDeletions",
      'parsed.kind === "dry_run"',
      "{ success: true, dry_run: true }",
      '"Cache-Control": "private, no-store"',
    ]
  ) {
    assertStringIncludes(reaper, fragment);
  }
  assert(
    !reaper.includes("targetUserId"),
    "The service reaper must never accept a caller-selected target user.",
  );
  assertStringIncludes(reaper, "logIdentitySafeError");
  assert(
    !reaper.includes("job_id:") && !reaper.includes("deletion_id:"),
    "Account-deletion reconciliation logs must be aggregate and identity-free.",
  );

  const configStart = config.indexOf(
    "[functions.reconcile-account-deletions]",
  );
  const configEnd = config.indexOf("\n[functions.", configStart + 1);
  const section = config.slice(configStart, configEnd);
  assertStringIncludes(section, "verify_jwt = false");
  assertStringIncludes(
    candidateWorkflow,
    "supabase/functions/_tests/accountDeletionCoverage.test.ts",
  );
  assertStringIncludes(
    candidateWorkflow,
    "supabase/tests/account_deletion_security.sql",
  );
  for (
    const fragment of [
      '"/functions/v1/reconcile-account-deletions"',
      "'{\"dry_run\":true}'",
      '(keys | sort) == ["dry_run", "success"]',
      ".success == true",
      ".dry_run == true",
    ]
  ) {
    assertStringIncludes(workflow, fragment);
  }
});

Deno.test("lost deletion responses recover through a hash-only public capability", async () => {
  const [
    handler,
    safeDeleteIndex,
    protocol,
    migration,
    preparedRecoveryV2Migration,
    swiftCapability,
    swiftDeletionCoordinator,
    swiftDeletionRecoveryCoordinator,
    swiftDeletionWorkflow,
    swiftDeletionStateModel,
    swiftDeletionStateStore,
    config,
    workflow,
  ] = await Promise.all([
    Deno.readTextFile(recoveryHandlerUrl),
    Deno.readTextFile(safeDeleteIndexUrl),
    Deno.readTextFile(recoveryProtocolUrl),
    Deno.readTextFile(recoveryMigrationUrl),
    Deno.readTextFile(preparedRecoveryV2MigrationUrl),
    Deno.readTextFile(swiftRecoveryCapabilityUrl),
    Deno.readTextFile(swiftDeletionCoordinatorUrl),
    Deno.readTextFile(swiftDeletionRecoveryCoordinatorUrl),
    Deno.readTextFile(swiftDeletionWorkflowUrl),
    Deno.readTextFile(swiftDeletionStateModelUrl),
    Deno.readTextFile(swiftDeletionStateStoreUrl),
    Deno.readTextFile(configUrl),
    Deno.readTextFile(workflowUrl),
  ]);
  const swiftDeletionState =
    `${swiftDeletionStateModel}\n${swiftDeletionStateStore}`;
  const swiftDeletionOrchestration =
    `${swiftDeletionCoordinator}\n${swiftDeletionRecoveryCoordinator}`;

  for (
    const fragment of [
      "parseAccountDeletionRecoveryRequest",
      "hashAccountDeletionCapability(",
      '"v2_recovery"',
      '"v2_acknowledgement"',
      "parsed.protocolVersion === 2",
      '"Cache-Control": "private, no-store"',
    ]
  ) {
    assertStringIncludes(handler, fragment);
  }
  for (
    const fragment of [
      "hashAccountDeletionCapability(",
      '"v2_recovery"',
      '"v2_acknowledgement"',
    ]
  ) {
    assertStringIncludes(safeDeleteIndex, fragment);
  }
  assertStringIncludes(protocol, "merian.account-deletion.v2.recovery");
  assertStringIncludes(
    protocol,
    "merian.account-deletion.v2.acknowledgement",
  );
  assert(
    !handler.includes("userId") && !handler.includes("user_id"),
    "The public recovery route must not accept or return an account identity.",
  );
  for (
    const forbidden of [
      "target_user_id",
      "auth_user_id",
      "job_id",
      "email",
    ]
  ) {
    assert(
      !protocol.includes(forbidden),
      `The recovery protocol unexpectedly exposes ${forbidden}.`,
    );
  }
  for (
    const fragment of [
      "internal.account_deletion_recovery_capabilities",
      "secret_hash TEXT NOT NULL UNIQUE",
      "PERFORM internal.require_service_role()",
      "request_account_deletion_with_recovery",
      "recover_account_deletion",
      "account_deletion_recovery_expired",
      "acknowledged_at IS NOT NULL",
    ]
  ) {
    assertStringIncludes(migration, fragment);
  }
  for (
    const fragment of [
      ".whenUnlockedThisDeviceOnly",
      "dataOrThrow(forKey: key) == data",
      "recoveryCapability != acknowledgementCapability",
      "func prepareLegacyIntake()",
      "removeObjectVerified",
    ]
  ) {
    assertStringIncludes(swiftCapability, fragment);
  }
  assertStringIncludes(
    swiftDeletionRecoveryCoordinator,
    "recoveryCapabilityStore.prepareLegacyIntake()",
  );
  for (
    const fragment of [
      "recoveryState == .capabilityIntakePending",
      "recoveryState == .capabilityCleanupPending",
      "recoverDeletion: recoverDeletionV1",
      "allowAuthenticatedIntakeReplay: false",
    ]
  ) {
    assertStringIncludes(swiftDeletionRecoveryCoordinator, fragment);
  }
  assert(
    !swiftDeletionRecoveryCoordinator.includes(
      "recoveryCapabilityStore.prepare()",
    ),
    "Installed legacy intake recovery must persist a v1 proof instead of creating a v2 envelope for the v1 endpoint.",
  );
  assert(
    swiftDeletionCoordinator.indexOf(
          "recordCapabilityPreparationPending()",
        ) <
        swiftDeletionCoordinator.indexOf("recoveryCapabilityStore.prepare()") &&
      swiftDeletionCoordinator.indexOf("recoveryCapabilityStore.prepare()") <
        swiftDeletionCoordinator.indexOf("prepareDeletionV2(") &&
      swiftDeletionCoordinator.indexOf("prepareDeletionV2(") <
        swiftDeletionCoordinator.indexOf("recordCapabilityPreparedPending()") &&
      swiftDeletionCoordinator.indexOf("recordCapabilityPreparedPending()") <
        swiftDeletionCoordinator.indexOf("commitDeletionV2("),
    "The local barrier and verified two-proof Keychain envelope must precede non-destructive server preparation, and the prepared marker must precede destructive commit.",
  );
  assertStringIncludes(
    swiftCapability,
    "restoreBarrierBeforeAuthBootstrap",
  );
  for (
    const fragment of [
      "case capabilityRejectionRetirementPending =",
      '"capability_rejection_retirement_pending"',
      "recordCapabilityRejectionRetirementPending",
    ]
  ) {
    assertStringIncludes(swiftDeletionState, fragment);
  }
  const interactiveRetirement = swiftDeletionCoordinator.slice(
    swiftDeletionCoordinator.indexOf(
      ".performDefinitiveIntakeRejectionRetirement(",
    ),
  );
  const rejectionMarker = interactiveRetirement.indexOf(
    ".recordCapabilityRejectionRetirementPending()",
  );
  const rejectionProofRemoval = interactiveRetirement.indexOf(
    "clearCapability(",
    rejectionMarker,
  );
  const rejectionMarkerRemoval = interactiveRetirement.indexOf(
    ".localState.resolve()",
    rejectionProofRemoval,
  );
  assert(
    rejectionMarker >= 0 &&
      rejectionProofRemoval > rejectionMarker &&
      rejectionMarkerRemoval > rejectionProofRemoval,
    "Definitive rejection must persist its phase before verified proof removal and clear the marker last.",
  );
  assertStringIncludes(
    swiftDeletionRecoveryCoordinator,
    "recoveryState == .capabilityRejectionRetirementPending",
  );
  assertStringIncludes(
    swiftDeletionRecoveryCoordinator,
    ".retireRejectedRecoveryProof(",
  );
  assertStringIncludes(
    swiftDeletionWorkflow,
    "static func retireRejectedRecoveryProof",
  );
  assertStringIncludes(
    swiftDeletionWorkflow,
    "static func performDefinitiveIntakeRejectionRetirement",
  );
  const compactDeletionWorkflow = swiftDeletionWorkflow.replaceAll(
    /\s+/g,
    " ",
  );
  const preparedIntakeStart = compactDeletionWorkflow.indexOf(
    "static func performPreparedIntake(",
  );
  const preparedIntakeEnd = compactDeletionWorkflow.indexOf(
    "static func performAcceptedCleanup(",
    preparedIntakeStart,
  );
  const preparedIntake = compactDeletionWorkflow.slice(
    preparedIntakeStart,
    preparedIntakeEnd,
  );
  assert(
    preparedIntake.indexOf("try Task.checkCancellation()") >= 0 &&
      preparedIntake.lastIndexOf("try Task.checkCancellation()") >
        preparedIntake.indexOf("recordIntakePending()") &&
      preparedIntake.lastIndexOf("try Task.checkCancellation()") <
        preparedIntake.indexOf("receipt = try await commitDeletion()"),
    "A cancelled non-destructive preparation must retain recovery state without dispatching destructive commit.",
  );
  assert(
    (swiftDeletionOrchestration.match(
          /\.performDefinitiveIntakeRejectionRetirement\(/g,
        ) ?? []).length >= 1 &&
      (swiftDeletionRecoveryCoordinator.match(
          /retireDefinitiveRejectionProof\(/g,
        ) ?? []).length >= 3,
    "Interactive and relaunched definitive rejections must use their crash-safe retirement owners.",
  );

  const configStart = config.indexOf(
    "[functions.recover-account-deletion]",
  );
  const configEnd = config.indexOf("\n[functions.", configStart + 1);
  assert(configStart >= 0, "Recovery function configuration is missing.");
  assertStringIncludes(
    config.slice(configStart, configEnd),
    "verify_jwt = false",
  );
  for (
    const fragment of [
      "/functions/v1/recover-account-deletion",
      "request_account_deletion_with_recovery",
      "recover_account_deletion",
      "get_account_deletion_recovery_health",
      "prepare_account_deletion_recovery_v2",
      "request_account_deletion_with_recovery_v2",
      "recover_account_deletion_v2",
      "acknowledge_account_deletion_recovery_v2",
      "prune_account_deletion_recovery_preparations",
      "get_account_deletion_recovery_preparation_health",
    ]
  ) {
    assertStringIncludes(workflow, fragment);
  }

  for (
    const fragment of [
      "internal.account_deletion_recovery_preparations",
      "internal.bind_account_deletion_recovery_preparations",
      "AFTER INSERT ON internal.account_deletion_jobs",
      "'not_committed'::TEXT",
      "acknowledgement_secret_hash",
      "prune_account_deletion_recovery_preparations",
      "get_account_deletion_recovery_preparation_health",
    ]
  ) {
    assertStringIncludes(preparedRecoveryV2Migration, fragment);
  }
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
      "actions: read",
      "contents: read",
      "fetch-depth: 0",
      "persist-credentials: false",
      "resolve_project_api_keys.ts",
      "resolve_deployed_health_monitor_modes.ts",
      "--feature account-deletion-recovery",
      "SUPABASE_ACCESS_TOKEN",
      "monitor_account_deletion_health.ts",
      "--warning-due-after-minutes",
      "--critical-sla-hours",
      "RECOVERY_HEALTH_MODE",
      '--recovery-health-mode "$RECOVERY_HEALTH_MODE"',
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
      '"get_account_deletion_recovery_health"',
      '"get_account_deletion_recovery_preparation_health"',
      "createServiceRoleClientFromEnvironment",
      "reaper_cron_active",
      "reaper_credentials_configured",
      "orphaned_storage_job_count",
      "oldest_pending_age_seconds",
      "oldest_storage_due_age_seconds",
      "expired_unacknowledged_count",
      "maximum_active_capabilities_per_job",
      "active_preparation_count",
      "expired_preparation_count",
      "recovery_health_availability",
      "recovery_preparation_health_availability",
      'error.code === "PGRST202"',
      'mode === "expand-compatible"',
    ]
  ) {
    assertStringIncludes(monitor, fragment);
  }
  assert(
    !workflow.includes("--recovery-health-mode expand-compatible"),
    "The production schedule must resolve recovery strictness from immutable deploy evidence.",
  );
});
