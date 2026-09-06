import { assert, assertStringIncludes } from "@std/assert";

const managerUrl = new URL(
  "../../../../apps/ios/Merian/Core/Network/SupabaseManager.swift",
  import.meta.url,
);
const ghostMergeStoreUrl = new URL(
  "../../../../apps/ios/Merian/Core/Security/GhostProfileMerge/Stores/GhostProfileMergeStore.swift",
  import.meta.url,
);
const ghostMergePolicyUrl = new URL(
  "../../../../apps/ios/Merian/Core/Network/Auth/Policies/GhostProfileMergePolicy.swift",
  import.meta.url,
);
const ghostMergeWorkflowUrl = new URL(
  "../../../../apps/ios/Merian/Core/Network/Auth/Coordinators/GhostProfileMergeWorkflow.swift",
  import.meta.url,
);
const ghostMergePolicyTestsUrl = new URL(
  "../../../../apps/ios/MerianTests/Core/Network/Auth/GhostProfileMergePolicyTests.swift",
  import.meta.url,
);
const ghostMergeErrorAdapterTestsUrl = new URL(
  "../../../../apps/ios/MerianTests/Core/Network/Auth/GhostProfileMergeEndpointErrorAdapterTests.swift",
  import.meta.url,
);
const consentManagerUrl = new URL(
  "../../../../apps/ios/Merian/Core/Security/ConsentManager.swift",
  import.meta.url,
);
const consentLedgerRepositoryUrl = new URL(
  "../../../../apps/ios/Merian/Core/Security/Consent/Repositories/ConsentLedgerRepository.swift",
  import.meta.url,
);
const consentRetryPolicyUrl = new URL(
  "../../../../apps/ios/Merian/Core/Security/Consent/Policies/ConsentRetryPolicy.swift",
  import.meta.url,
);
const consentSynchronizationMergePolicyUrl = new URL(
  "../../../../apps/ios/Merian/Core/Security/Consent/Policies/ConsentSynchronizationMergePolicy.swift",
  import.meta.url,
);
const consentRealtimeCoordinatorUrl = new URL(
  "../../../../apps/ios/Merian/Core/Security/Consent/Coordinators/ConsentRealtimeCoordinator.swift",
  import.meta.url,
);
const consentSynchronizationCoordinatorUrl = new URL(
  "../../../../apps/ios/Merian/Core/Security/Consent/Coordinators/ConsentSynchronizationCoordinator.swift",
  import.meta.url,
);
const requiredConsentRestorationCoordinatorUrl = new URL(
  "../../../../apps/ios/Merian/Core/Security/Consent/Coordinators/RequiredConsentRestorationCoordinator.swift",
  import.meta.url,
);
const consentRealtimeLiveAdapterUrl = new URL(
  "../../../../apps/ios/Merian/Core/Security/Consent/Services/ConsentRealtimeCoordinator+Live.swift",
  import.meta.url,
);
const consentRealtimeTestsUrl = new URL(
  "../../../../apps/ios/MerianTests/Core/Security/Consent/ConsentRealtimeCoordinatorTests.swift",
  import.meta.url,
);
const consentAuthorityTestsUrl = new URL(
  "../../../../apps/ios/MerianTests/Core/Security/Consent/ConsentManagerAuthorityTests.swift",
  import.meta.url,
);
const consentSynchronizationTestsUrl = new URL(
  "../../../../apps/ios/MerianTests/Core/Security/Consent/ConsentSynchronizationCoordinatorTests.swift",
  import.meta.url,
);
const requiredConsentRestorationTestsUrl = new URL(
  "../../../../apps/ios/MerianTests/Core/Security/Consent/ConsentRestorationCoordinatorTests.swift",
  import.meta.url,
);

function compact(value: string): string {
  return value.replaceAll(/\s+/g, " ").trim();
}

Deno.test("iOS persists a Ghost merge proof before switching sessions", async () => {
  const [source, storeSource] = await Promise.all([
    Deno.readTextFile(managerUrl).then(compact),
    Deno.readTextFile(ghostMergeStoreUrl).then(compact),
  ]);
  const conflictFallback = source.indexOf(
    "guard Self.requiresProviderBoundGhostMerge(after: error)",
  );
  const prepare = source.indexOf(
    "_ = try await prepareGhostProfileMerge(",
    conflictFallback,
  );
  const sessionSwitch = source.indexOf(
    "let targetSession = try await installOAuthSessionReplacingCurrentAccount(",
    prepare,
  );
  const prepareDefinition = source.indexOf(
    "private func prepareGhostProfileMerge(",
    sessionSwitch,
  );
  const persist = source.indexOf(
    "try persistPendingGhostProfileMergeQueue(queue)",
    prepareDefinition,
  );
  const prepareReturn = source.indexOf(
    "return pending",
    persist,
  );

  assert(
    conflictFallback >= 0 &&
      prepare > conflictFallback &&
      sessionSwitch > prepare &&
      prepareDefinition > sessionSwitch &&
      persist > prepareDefinition &&
      prepareReturn > persist,
    "The provider-bound proof must be durably persisted before leaving the anonymous session",
  );
  assertStringIncludes(
    source,
    "try ghostProfileMergeStore.persistPendingHandoffs(handoffs)",
  );
  assertStringIncludes(
    storeSource,
    "KeychainKeys.pendingGhostProfileMerge",
  );
  assertStringIncludes(storeSource, ".whenUnlockedThisDeviceOnly");
  assertStringIncludes(
    storeSource,
    "try dependencies.loadData(key) == encoded",
  );
  assert(
    !source.includes("KeychainKeys.pendingGhostProfileMerge"),
    "SupabaseManager must delegate Ghost queue persistence to the secure-store owner",
  );
  assertStringIncludes(
    source,
    "try await self.client.auth.signInWithIdToken( credentials: credentials )",
  );
});

Deno.test("iOS retries every retained Ghost handoff after permanent-session restoration", async () => {
  const source = compact(await Deno.readTextFile(managerUrl));
  const performer = source.indexOf(
    "private func performPendingGhostProfileMerge(",
  );
  const performerEnd = source.indexOf(
    "private func refreshPublicAuthorIdentity(",
    performer,
  );
  const performerSource = source.slice(performer, performerEnd);

  assertStringIncludes(
    performerSource,
    "for pending in pendingHandoffs",
  );
  assertStringIncludes(
    performerSource,
    'try await self.client.functions.invoke( "merge-ghost-profile"',
  );
  assertStringIncludes(
    performerSource,
    "allHandoffsResolved = false",
  );

  const restoration = source.indexOf(
    "private func refreshPublicAuthorIdentityForRestoredSession",
  );
  const retry = source.indexOf(
    "_ = await completePendingGhostProfileMergeIfNeeded(",
    restoration,
  );
  const identityRefresh = source.indexOf(
    "guard await refreshPublicAuthorIdentity(",
    restoration,
  );
  assert(
    restoration >= 0 && retry > restoration && identityRefresh > retry,
    "Restored permanent sessions must retry retained proofs before refreshing public identity",
  );
  assertStringIncludes(
    source.slice(identityRefresh, identityRefresh + 180),
    "expectedUserID: expectedUserID",
  );
});

Deno.test("iOS keeps Ghost finalization cancellation-fenced and proof-removal-last", async () => {
  const [source, workflow] = await Promise.all([
    Deno.readTextFile(managerUrl).then(compact),
    Deno.readTextFile(ghostMergeWorkflowUrl).then(compact),
  ]);
  assertStringIncludes(
    source,
    "try await GhostProfileMergeWorkflow.finalizeHandoff(",
  );

  const preflight = workflow.indexOf("try Task.checkCancellation()");
  const server = workflow.indexOf(
    "try await completeServerHandoff()",
    preflight,
  );
  const serverFence = workflow.indexOf(
    "try Task.checkCancellation()",
    server,
  );
  const purchases = workflow.indexOf(
    "try await synchronizeProviderPurchases()",
    serverFence,
  );
  const purchaseFence = workflow.indexOf(
    "try Task.checkCancellation()",
    purchases,
  );
  const localEvidence = workflow.indexOf(
    "try await rebindAndSynchronizeLocalEvidence()",
    purchaseFence,
  );
  const localEvidenceFence = workflow.indexOf(
    "try Task.checkCancellation()",
    localEvidence,
  );
  const clearProof = workflow.indexOf(
    "try clearPendingHandoff()",
    localEvidenceFence,
  );

  assert(
    preflight >= 0 &&
      server > preflight &&
      serverFence > server &&
      purchases > serverFence &&
      purchaseFence > purchases &&
      localEvidence > purchaseFence &&
      localEvidenceFence > localEvidence &&
      clearProof > localEvidenceFence,
    "Ghost finalization must keep cancellation fences around every asynchronous phase and remove proof last",
  );
  assert(
    !workflow.includes(".shared") &&
      !workflow.includes("import Supabase") &&
      !workflow.includes("MerianLog"),
    "The deterministic Ghost workflow must not acquire live dependencies",
  );
});

Deno.test("iOS deletes Ghost proofs only for invalid or expired handoffs", async () => {
  const [source, policySource, policyTestSource, adapterTestSource] =
    await Promise.all([
      Deno.readTextFile(managerUrl).then(compact),
      Deno.readTextFile(ghostMergePolicyUrl).then(compact),
      Deno.readTextFile(ghostMergePolicyTestsUrl).then(compact),
      Deno.readTextFile(ghostMergeErrorAdapterTestsUrl).then(compact),
    ]);
  const discardStart = source.indexOf(
    "nonisolated static func shouldDiscardPendingGhostProfileMerge",
  );
  const discardEnd = source.indexOf(
    "nonisolated static func oauthProviderSubject",
    discardStart,
  );
  const discardSource = source.slice(discardStart, discardEnd);

  assertStringIncludes(
    discardSource,
    "GhostProfileMergePolicy.shouldDiscardPendingHandoff( serverCode: payload.code )",
  );
  assertStringIncludes(policySource, 'serverCode == "handoff_expired"');
  assertStringIncludes(policySource, 'serverCode == "handoff_invalid"');
  assert(
    !policySource.includes("merge_temporarily_unavailable"),
    "Retryable 503 responses must not discard a retained proof",
  );
  assertStringIncludes(
    policyTestSource,
    "terminalServerCodesAloneDiscardDurableProof",
  );
  assertStringIncludes(
    adapterTestSource,
    "testPendingMergeProofIsDiscardedOnlyForTerminalServerCodes",
  );
  assertStringIncludes(
    adapterTestSource,
    '"merge_temporarily_unavailable"',
  );
  assertStringIncludes(
    adapterTestSource,
    "(URLError(.timedOut), false)",
  );
});

Deno.test("iOS flushes target-owned pending consent before account refetch", async () => {
  const [
    source,
    synchronizationCoordinatorSource,
    synchronizationMergePolicySource,
    ledgerRepositorySource,
    retryPolicySource,
    authorityTestSource,
    synchronizationTestSource,
    restorationCoordinatorSource,
    restorationTestSource,
  ] = await Promise.all([
    Deno.readTextFile(consentManagerUrl).then(compact),
    Deno.readTextFile(consentSynchronizationCoordinatorUrl).then(compact),
    Deno.readTextFile(consentSynchronizationMergePolicyUrl).then(compact),
    Deno.readTextFile(consentLedgerRepositoryUrl).then(compact),
    Deno.readTextFile(consentRetryPolicyUrl).then(compact),
    Deno.readTextFile(consentAuthorityTestsUrl).then(compact),
    Deno.readTextFile(consentSynchronizationTestsUrl).then(compact),
    Deno.readTextFile(requiredConsentRestorationCoordinatorUrl).then(compact),
    Deno.readTextFile(requiredConsentRestorationTestsUrl).then(compact),
  ]);
  const observeStart = source.indexOf("func observeSession(userId: UUID?)");
  const observeEnd = source.indexOf(
    "func beginAnalyticsAccountTransition()",
    observeStart,
  );
  const observe = source.slice(observeStart, observeEnd);
  const awaitRemote = observe.indexOf(
    "requireAuthoritativeAnalyticsRefresh(for: userId)",
  );
  const applyObservedPermission = observe.indexOf(
    "applyAnalyticsPermissionToSDK()",
  );
  assert(
    observeStart >= 0 && observeEnd > observeStart && awaitRemote >= 0 &&
      applyObservedPermission > awaitRemote,
    "A restored session must enter its remote-authority wait state before analytics can be applied",
  );

  const synchronizationStart = synchronizationCoordinatorSource.indexOf(
    "private static func performSynchronization(",
  );
  const synchronizationEnd = synchronizationCoordinatorSource.indexOf(
    "private static func hasUnownedRecords(",
    synchronizationStart,
  );
  const synchronization = synchronizationCoordinatorSource.slice(
    synchronizationStart,
    synchronizationEnd,
  );
  const activate = synchronization.indexOf("activateLedger(for: userId)");
  const push = synchronization.indexOf(
    "try await pushPendingRecords(",
  );
  const fetch = synchronization.indexOf(
    "let remoteState = try await remoteService.fetchRemoteState(",
  );
  const merge = synchronization.indexOf("try merge(");

  assert(
    synchronizationStart >= 0 &&
      synchronizationEnd > synchronizationStart &&
      activate >= 0 &&
      push > activate &&
      fetch > push &&
      merge > fetch,
    "Target restoration must activate and flush its pending evidence before authoritative refetch",
  );
  assertStringIncludes(
    synchronization,
    "validateSynchronization: validateSynchronization",
  );

  const mergeStart = synchronizationCoordinatorSource.indexOf(
    "private static func merge(",
  );
  const mergeEnd = synchronizationCoordinatorSource.lastIndexOf("}");
  const mergeSource = synchronizationCoordinatorSource.slice(
    mergeStart,
    mergeEnd,
  );
  const finalIdentityFence = mergeSource.indexOf(
    "try validateSynchronization()",
  );
  const closePriorAuthority = mergeSource.indexOf("willMergeRemoteState()");
  const candidateMerge = mergeSource.indexOf(
    "ConsentSynchronizationMergePolicy.merging(",
  );
  const verifiedPersistence = mergeSource.indexOf(
    "try ledgerRepository.persistLedger(result.ledger)",
  );
  const publishMerge = mergeSource.indexOf(
    "didMergeRemoteState(result, userId)",
  );
  const mergeApplicationStart = source.indexOf(
    "private func applySynchronizationMerge(",
  );
  const mergeApplicationEnd = source.indexOf(
    "static let maximumAutomaticRestorationRetries",
    mergeApplicationStart,
  );
  const mergeApplication = source.slice(
    mergeApplicationStart,
    mergeApplicationEnd,
  );
  const authoritativeResolution = mergeApplication.indexOf(
    "analyticsCloudAuthorityState = result.analyticsCloudAuthorityState",
  );
  const analyticsApplication = mergeApplication.indexOf(
    "applyAnalyticsPermissionToSDK()",
  );
  assert(
    mergeStart >= 0 && mergeEnd > mergeStart && finalIdentityFence >= 0 &&
      closePriorAuthority > finalIdentityFence &&
      candidateMerge > closePriorAuthority &&
      verifiedPersistence > candidateMerge &&
      publishMerge > verifiedPersistence &&
      mergeApplicationStart >= 0 &&
      mergeApplicationEnd > mergeApplicationStart &&
      authoritativeResolution >= 0 &&
      analyticsApplication > authoritativeResolution,
    "The final identity fence must precede merge and persistence, and only the persisted result may reopen analytics",
  );
  assertStringIncludes(
    synchronizationMergePolicySource,
    "candidate.activeUserId = userId",
  );

  const repositoryPersistStart = ledgerRepositorySource.indexOf(
    "func persistLedger(",
  );
  const repositoryPersistEnd = ledgerRepositorySource.indexOf(
    "func persistConsentChange(",
    repositoryPersistStart,
  );
  const repositoryPersist = ledgerRepositorySource.slice(
    repositoryPersistStart,
    repositoryPersistEnd,
  );
  const verifiedStoreWrite = repositoryPersist.indexOf(
    "try store.saveLedgerData(data)",
  );
  const inMemoryPublication = repositoryPersist.indexOf(
    "ledger = candidate",
  );
  assert(
    repositoryPersistStart >= 0 &&
      repositoryPersistEnd > repositoryPersistStart &&
      verifiedStoreWrite >= 0 &&
      inMemoryPublication > verifiedStoreWrite,
    "Consent ledger state must publish only after the durable store verifies its write",
  );
  assertStringIncludes(
    retryPolicySource,
    "static func isSynchronizationContextCurrent(",
  );
  assertStringIncludes(
    synchronizationCoordinatorSource,
    "isCancelled: Task.isCancelled",
  );
  assertStringIncludes(
    synchronizationCoordinatorSource,
    "private var scheduledTasks: [UUID: Task<Void, Never>] = [:]",
  );
  assertStringIncludes(
    synchronizationCoordinatorSource,
    "private var activeTasks: [UUID: Task<Void, Error>] = [:]",
  );
  assertStringIncludes(
    synchronizationCoordinatorSource,
    "scheduledTasks: Array(scheduledTasks.values)",
  );
  assertStringIncludes(
    synchronizationCoordinatorSource,
    "activeTasks: Array(activeTasks.values)",
  );
  assertStringIncludes(
    source,
    "private let restorationCoordinator: RequiredConsentRestorationCoordinator",
  );
  assertStringIncludes(
    restorationCoordinatorSource,
    "private var retryTasks: [UUID: Task<Void, Never>] = [:]",
  );
  assertStringIncludes(
    restorationCoordinatorSource,
    "currentRetryTaskId == id",
  );
  assertStringIncludes(
    restorationCoordinatorSource,
    "retryTasks: Array(retryTasks.values)",
  );
  assertStringIncludes(
    source,
    "await restoration.wait()",
  );
  assertStringIncludes(
    restorationCoordinatorSource,
    "generation == context.synchronizationGeneration",
  );
  assertStringIncludes(
    restorationCoordinatorSource,
    "context.observedUserId == userId",
  );
  assertStringIncludes(
    restorationCoordinatorSource,
    "context.sdkUserId == userId",
  );
  const restorationBeginRetryStart = restorationCoordinatorSource.indexOf(
    "func beginRetry(",
  );
  const restorationBeginRetryEnd = restorationCoordinatorSource.indexOf(
    "func isRetryPending(",
    restorationBeginRetryStart,
  );
  const restorationBeginRetry = restorationCoordinatorSource.slice(
    restorationBeginRetryStart,
    restorationBeginRetryEnd,
  );
  assert(
    restorationBeginRetryStart >= 0 &&
      restorationBeginRetryEnd > restorationBeginRetryStart &&
      restorationBeginRetry.includes("guard !Task.isCancelled,"),
    "A canceled restoration timer must fail admission even when account, generation, and attempt are reused",
  );
  assert(
    !restorationCoordinatorSource.includes("SupabaseManager"),
    "Required-consent restoration state and retries must remain independent of the live Auth client",
  );
  assert(
    !synchronization.includes("guard remoteState.hasEvidence"),
    "An empty target account must still become the active local ledger",
  );

  const activationStart = ledgerRepositorySource.indexOf(
    "func activateLedger(",
  );
  const activationEnd = ledgerRepositorySource.indexOf(
    "func rebindLedger(",
    activationStart,
  );
  const activation = ledgerRepositorySource.slice(
    activationStart,
    activationEnd,
  );
  assert(
    activationStart >= 0 && activationEnd > activationStart &&
      !activation.includes("applyAnalyticsPermissionToSDK()"),
    "Account restoration must keep analytics closed until authoritative merge succeeds",
  );
  assertStringIncludes(
    source,
    "analyticsCloudAuthorityState.allowsCapture( for: currentSessionUserId )",
  );
  assertStringIncludes(
    authorityTestSource,
    "testRestoredCachedAnalyticsGrantStaysClosedUntilRemoteRevocationMerges",
  );
  assertStringIncludes(
    authorityTestSource,
    "testRestoredCachedAnalyticsGrantStaysClosedWhenRemoteGrantIsAbsent",
  );
  assertStringIncludes(
    authorityTestSource,
    "testRestoredAnalyticsGrantOpensOnlyAfterAuthoritativeMerge",
  );
  assertStringIncludes(
    authorityTestSource,
    "testFailedAuthoritativeMergeKeepsRestoredAnalyticsClosed",
  );
  assertStringIncludes(
    synchronizationTestSource,
    "testPipelinePushesPendingEvidenceInStableOrderBeforeFetch",
  );
  assertStringIncludes(
    synchronizationTestSource,
    "testCancelAndAwaitDrainsEarlierInvalidatedActiveTask",
  );
  assertStringIncludes(
    synchronizationTestSource,
    "testCancelAndAwaitDrainsSupersededActiveTask",
  );
  assertStringIncludes(
    synchronizationTestSource,
    "testCancelAndAwaitDrainsSupersededScheduledTask",
  );
  assertStringIncludes(
    restorationTestSource,
    "testCancelledUncooperativeRetryCannotCrossAccountReplacement",
  );
  assertStringIncludes(
    restorationTestSource,
    "await cancelledWork.wait()",
  );
  assertStringIncludes(
    restorationTestSource,
    "testCompletingRetryCannotClearItsReplacementTask",
  );
  assertStringIncludes(
    restorationTestSource,
    "testCancelledRetryCannotReenterAfterManualAttemptNumberReuse",
  );
});

Deno.test("iOS independently owns and retries analytics-consent Realtime", async () => {
  const [source, coordinator, liveAdapter, tests] = await Promise.all([
    Deno.readTextFile(consentManagerUrl).then(compact),
    Deno.readTextFile(consentRealtimeCoordinatorUrl).then(compact),
    Deno.readTextFile(consentRealtimeLiveAdapterUrl).then(compact),
    Deno.readTextFile(consentRealtimeTestsUrl).then(compact),
  ]);
  const observeStart = source.indexOf("func observeSession(userId: UUID?)");
  const observeEnd = source.indexOf(
    "func beginAnalyticsAccountTransition()",
    observeStart,
  );
  const observe = source.slice(observeStart, observeEnd);
  const foregroundStart = source.indexOf(
    "func synchronizeWithCurrentSession() async throws",
  );
  const foregroundEnd = source.indexOf(
    "private func scheduleSynchronization(",
    foregroundStart,
  );
  const foreground = source.slice(foregroundStart, foregroundEnd);

  assertStringIncludes(
    coordinator,
    "private var subscriptionUserId: UUID?",
  );
  assertStringIncludes(
    coordinator,
    "private var subscribedUserId: UUID?",
  );
  assertStringIncludes(
    observe,
    "realtimeCoordinator.ensureUpdates(for: userId)",
  );
  assertStringIncludes(
    foreground,
    "realtimeCoordinator.ensureUpdates(for: userId)",
  );
  assertStringIncludes(
    foreground,
    "beginUnownedAccountBoundWork()",
  );
  assertStringIncludes(
    foreground,
    "finishAccountBoundWork(accountWorkLease)",
  );
  assertStringIncludes(
    foreground,
    "isAccountBoundWorkLeaseCurrent(accountWorkLease)",
  );
  assertStringIncludes(
    foreground,
    "func synchronizeWithCurrentSession( ownedBy transition: AuthTransitionToken ) async throws",
  );
  assertStringIncludes(
    foreground,
    "currentSessionMatchesAuthTransition(transition)",
  );
  assertStringIncludes(
    coordinator,
    "self?.subscribedUserId = userId",
  );
  assertStringIncludes(coordinator, "scheduleRetry(for: userId)");
  assertStringIncludes(
    coordinator,
    "self.subscriptionGeneration == generation",
  );
  assertStringIncludes(
    coordinator,
    "self.currentUserIdProvider() == userId",
  );
  assertStringIncludes(
    coordinator,
    "private var teardownTasks: [UUID: Task<Void, Never>] = [:]",
  );
  assertStringIncludes(coordinator, "func awaitTeardown() async");
  assertStringIncludes(source, "await realtimeCoordinator.awaitTeardown()");
  assertStringIncludes(
    source,
    "func cancelAndAwaitAccountBoundWorkForAuthTransition() async",
  );
  assertStringIncludes(
    tests,
    "testTeardownDrainWaitsForCancellationUncooperativeRemoval",
  );
  assertStringIncludes(
    tests,
    "testAuthTransitionDrainIncludesRealtimeTeardown",
  );
  assertStringIncludes(liveAdapter, "SupabaseManager.shared.client");
  assertStringIncludes(
    liveAdapter,
    'table: "user_analytics_consent_events"',
  );
  assertStringIncludes(
    liveAdapter,
    'filter: .eq("user_id", value: userId.uuidString)',
  );
  assertStringIncludes(liveAdapter, "channel.subscribeWithError()");
  assertStringIncludes(liveAdapter, "client.removeChannel(channel)");
});

Deno.test("OAuth replacement suppresses analytics and reconciles failures", async () => {
  const source = compact(await Deno.readTextFile(managerUrl));
  const helperStart = source.indexOf(
    "static func performOAuthSessionReplacement<Value>(",
  );
  const helperEnd = source.indexOf(
    "nonisolated static func shouldDiscardPendingGhostProfileMerge",
    helperStart,
  );
  const helper = source.slice(helperStart, helperEnd);
  const cancellation = helper.indexOf("try Task.checkCancellation()");
  const suspend = helper.indexOf("let generation = suspendAnalytics()");
  const postSuppressionCancellation = helper.indexOf(
    "try Task.checkCancellation()",
    cancellation + 1,
  );
  const install = helper.indexOf(
    "let installedSession = try await installSession()",
  );

  assert(
    helperStart >= 0 && helperEnd > helperStart && cancellation >= 0 &&
      cancellation < suspend && suspend >= 0 &&
      postSuppressionCancellation > suspend &&
      postSuppressionCancellation < install,
    "Cancellation must win before analytics suspension and again before SDK session replacement",
  );
  assertStringIncludes(
    helper,
    "reconcileSession(generation, currentSession())",
  );
  assertStringIncludes(
    source,
    "ConsentManager.shared.beginAnalyticsAccountTransition()",
  );
  assertStringIncludes(
    source,
    "cancelAndAwaitAccountBoundWorkForAuthTransition()",
  );
  assertStringIncludes(
    source,
    "ConsentManager.shared.resolveAnalyticsAccountTransition(",
  );
});
