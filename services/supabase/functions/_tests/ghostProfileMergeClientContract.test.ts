import { assert, assertStringIncludes } from "@std/assert";

const managerUrl = new URL(
  "../../../../apps/ios/Merian/Core/Network/SupabaseManager.swift",
  import.meta.url,
);
const managerTestsUrl = new URL(
  "../../../../apps/ios/MerianTests/Core/Network/SupabaseManagerTests.swift",
  import.meta.url,
);

function compact(value: string): string {
  return value.replaceAll(/\s+/g, " ").trim();
}

Deno.test("iOS persists a Ghost merge proof before switching sessions", async () => {
  const source = compact(await Deno.readTextFile(managerUrl));
  const conflictFallback = source.indexOf(
    "guard Self.requiresProviderBoundGhostMerge(after: error)",
  );
  const prepare = source.indexOf(
    "_ = try await prepareGhostProfileMerge(",
    conflictFallback,
  );
  const sessionSwitch = source.indexOf(
    "let targetSession = try await client.auth.signInWithIdToken",
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
  assertStringIncludes(source, "accessibility: .whenUnlockedThisDeviceOnly");
  assertStringIncludes(
    source,
    "try KeychainManager.shared.dataOrThrow( forKey: KeychainKeys.pendingGhostProfileMerge ) == encoded",
  );
});

Deno.test("iOS retries every retained Ghost handoff after permanent-session restoration", async () => {
  const source = compact(await Deno.readTextFile(managerUrl));
  const performer = source.indexOf(
    "private func performPendingGhostProfileMerge(",
  );
  const performerEnd = source.indexOf(
    "private func refreshPublicAuthorIdentity()",
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
    "guard await refreshPublicAuthorIdentity()",
    restoration,
  );
  assert(
    restoration >= 0 && retry > restoration && identityRefresh > retry,
    "Restored permanent sessions must retry retained proofs before refreshing public identity",
  );
});

Deno.test("iOS deletes Ghost proofs only for invalid or expired handoffs", async () => {
  const [source, testSource] = await Promise.all([
    Deno.readTextFile(managerUrl).then(compact),
    Deno.readTextFile(managerTestsUrl).then(compact),
  ]);
  const discardStart = source.indexOf(
    "nonisolated static func shouldDiscardPendingGhostProfileMerge",
  );
  const discardEnd = source.indexOf(
    "nonisolated static func oauthProviderSubject",
    discardStart,
  );
  const discardSource = source.slice(discardStart, discardEnd);

  assertStringIncludes(discardSource, 'payload.code == "handoff_expired"');
  assertStringIncludes(discardSource, 'payload.code == "handoff_invalid"');
  assert(
    !discardSource.includes("merge_temporarily_unavailable"),
    "Retryable 503 responses must not discard a retained proof",
  );
  assertStringIncludes(
    testSource,
    "testPendingMergeProofIsDiscardedOnlyForTerminalServerCodes",
  );
  assertStringIncludes(testSource, '"merge_temporarily_unavailable"');
  assertStringIncludes(
    testSource,
    "XCTAssertFalse( SupabaseManager.shouldDiscardPendingGhostProfileMerge( after: mergeTemporarilyUnavailable ) )",
  );
});
