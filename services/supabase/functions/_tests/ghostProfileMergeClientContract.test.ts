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
const consentAuthorityTestsUrl = new URL(
  "../../../../apps/ios/MerianTests/Core/Security/Consent/ConsentManagerAuthorityTests.swift",
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
  const [source, testSource] = await Promise.all([
    Deno.readTextFile(consentManagerUrl).then(compact),
    Deno.readTextFile(consentAuthorityTestsUrl).then(compact),
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

  const synchronizationStart = source.indexOf(
    "private func performSynchronization(",
  );
  const synchronizationEnd = source.indexOf(
    "private func activateLedger(",
    synchronizationStart,
  );
  const synchronization = source.slice(
    synchronizationStart,
    synchronizationEnd,
  );
  const activate = synchronization.indexOf("activateLedger(for: userId)");
  const push = synchronization.indexOf(
    "try await pushPendingRecords(for: userId, generation: generation)",
  );
  const fetch = synchronization.indexOf(
    "let remoteState = try await fetchRemoteState(",
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
    "for: userId, generation: generation",
  );

  const mergeStart = source.indexOf("func merge(");
  const mergeEnd = source.indexOf(
    "private func hasCloudReadyCurrentConsent(",
    mergeStart,
  );
  const mergeSource = source.slice(mergeStart, mergeEnd);
  const finalIdentityFence = mergeSource.indexOf(
    "try validateSynchronization(for: userId, generation: generation)",
  );
  const candidateSnapshot = mergeSource.indexOf("var candidate = ledger");
  const firstCandidateMutation = mergeSource.indexOf(
    "candidate.adultEligibilityReceipts",
  );
  const verifiedPersistence = mergeSource.indexOf(
    "try persistLedger(candidate)",
  );
  const authoritativeResolution = mergeSource.indexOf(
    "analyticsCloudAuthorityState = .resolvedRemote(",
  );
  const analyticsApplication = mergeSource.indexOf(
    "applyAnalyticsPermissionToSDK()",
  );
  assert(
    mergeStart >= 0 && mergeEnd > mergeStart && finalIdentityFence >= 0 &&
      candidateSnapshot > finalIdentityFence &&
      firstCandidateMutation > candidateSnapshot &&
      verifiedPersistence > firstCandidateMutation &&
      authoritativeResolution > verifiedPersistence &&
      analyticsApplication > authoritativeResolution,
    "The final identity fence must precede mutation and persistence, and only persisted authoritative state may reopen analytics",
  );
  assertStringIncludes(
    source,
    "static func isSynchronizationContextCurrent(",
  );
  assertStringIncludes(source, "isCancelled: Task.isCancelled");
  assert(
    !synchronization.includes("guard remoteState.hasEvidence"),
    "An empty target account must still become the active local ledger",
  );

  const activationStart = source.indexOf("private func activateLedger(");
  const activationEnd = source.indexOf(
    "private func bindUnownedRecords(",
    activationStart,
  );
  const activation = source.slice(activationStart, activationEnd);
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
    testSource,
    "testRestoredCachedAnalyticsGrantStaysClosedUntilRemoteRevocationMerges",
  );
  assertStringIncludes(
    testSource,
    "testRestoredCachedAnalyticsGrantStaysClosedWhenRemoteGrantIsAbsent",
  );
  assertStringIncludes(
    testSource,
    "testRestoredAnalyticsGrantOpensOnlyAfterAuthoritativeMerge",
  );
  assertStringIncludes(
    testSource,
    "testFailedAuthoritativeMergeKeepsRestoredAnalyticsClosed",
  );
});

Deno.test("iOS independently owns and retries analytics-consent Realtime", async () => {
  const source = compact(await Deno.readTextFile(consentManagerUrl));
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
    source,
    "private var analyticsConsentChannelUserId: UUID?",
  );
  assertStringIncludes(
    source,
    "private var analyticsConsentSubscribedUserId: UUID?",
  );
  assertStringIncludes(observe, "ensureAnalyticsConsentUpdates(for: userId)");
  assertStringIncludes(
    foreground,
    "ensureAnalyticsConsentUpdates(for: userId)",
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
    source,
    "self.analyticsConsentSubscribedUserId = userId",
  );
  assertStringIncludes(source, "scheduleAnalyticsConsentRetry(for: userId)");
  assertStringIncludes(
    source,
    "self.analyticsConsentSubscriptionGeneration == generation",
  );
  assertStringIncludes(source, "self.currentSessionUserId == userId");
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
  const suspend = helper.indexOf("let generation = suspendAnalytics()");
  const install = helper.indexOf(
    "let installedSession = try await installSession()",
  );

  assert(
    helperStart >= 0 && helperEnd > helperStart && suspend >= 0 &&
      install > suspend,
    "Analytics must be suspended synchronously before the SDK installs a replacement session",
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
    "ConsentManager.shared.resolveAnalyticsAccountTransition(",
  );
});
