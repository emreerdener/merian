import { assert, assertEquals, assertStringIncludes } from "@std/assert";

const migrationUrl = new URL(
  "../../migrations/20260801210102_make_ghost_merge_schema_aware.sql",
  import.meta.url,
);
const hardeningMigrationUrl = new URL(
  "../../migrations/20260801220318_harden_ghost_merge_concurrency_and_provider_repair.sql",
  import.meta.url,
);
const healthIndexMigrationUrl = new URL(
  "../../migrations/20260802025258_index_ghost_merge_health_audits.sql",
  import.meta.url,
);
const healthMonitorUrl = new URL(
  "../../scripts/monitor_ghost_profile_merges.ts",
  import.meta.url,
);
const pgTapUrl = new URL(
  "../../tests/ghost_profile_merge_security.sql",
  import.meta.url,
);
const concurrencyFixtureUrl = new URL(
  "./ghostProfileMergeConcurrencyDb.test.ts",
  import.meta.url,
);

function normalized(sql: string): string {
  return sql.replaceAll(/\s+/g, " ").trim();
}

Deno.test("Ghost merge classifies user references and fails closed", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "CREATE TABLE internal.ghost_profile_merge_reference_policies",
      "strategy IN ( 'reparent', 'handler_then_reparent', 'derived', 'preserve', 'delete_source', 'blocked' )",
      "ALTER TABLE internal.ghost_profile_merge_reference_policies ENABLE ROW LEVEL SECURITY",
      "REVOKE ALL ON TABLE internal.ghost_profile_merge_reference_policies FROM PUBLIC, anon, authenticated, service_role",
      "ghost_merge_schema_requires_composite_fk_policy",
      "ghost_merge_unclassified_reference",
      "ghost_merge_stale_reference_policy",
      "ghost_merge_blocked_reference",
      "ghost_merge_preserved_reference_present",
      "SELECT internal.assert_ghost_profile_merge_reference_policy_coverage()",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes("EXECUTE policy.handler_key"),
    "handler documentation must never become dynamically executable SQL",
  );
});

Deno.test("Ghost merge concurrency preflight inspects installed lock semantics", async () => {
  const fixture = normalized(await Deno.readTextFile(concurrencyFixtureUrl));

  for (
    const fragment of [
      "from public.users as users where users.id = p_user_id for update",
      "from internal.revenuecat_reconciliation_queue as queue where queue.merian_user_id = p_user_id and queue.claim_token = p_claim_token and queue.claim_expires_at > pg_catalog.clock_timestamp() for update",
      "revenuecatQueueLock > revenuecatUserLock",
      'revenuecatDefinition.includes("revenuecat_reconciliation_claim_lost")',
      "!communityDefinition.includes",
      "insert into internal.community_identification_activity_actors",
    ]
  ) {
    assertStringIncludes(fixture, fragment);
  }

  assert(
    !fixture.includes("Match Ghost merge ordering: parent user first"),
    "installed hardening must be detected from executable lock semantics rather than a mutable SQL comment",
  );
});

Deno.test("Ghost merge moves scans before validating their derived ledger", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));
  const reparentStart = sql.indexOf(
    "CREATE OR REPLACE FUNCTION internal.reparent_ghost_user_foreign_keys",
  );
  const reparentEnd = sql.indexOf("$function$;", reparentStart);
  const reparentRoutine = sql.slice(reparentStart, reparentEnd);

  for (
    const fragment of [
      "'internal', 'user_species_scan_counts', 'user_id', 'public', 'users', 'id', 'derived', 900, 'scan_species_ledger'",
      "'public', 'scans', 'user_id', 'public', 'users', 'id', 'reparent', 100, NULL",
      "JOIN internal.ghost_profile_merge_reference_policies AS policy",
      "AND policy.strategy IN ( 'reparent', 'handler_then_reparent' )",
      "ORDER BY policy.execution_order",
      "PERFORM internal.assert_ghost_profile_merge_species_ledger( ARRAY[p_ghost_user_id, p_target_user_id] )",
      "AND policy.strategy <> 'delete_source'",
      "ghost_merge_unhandled_reference",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    reparentStart >= 0 && reparentEnd > reparentStart,
    "the policy-driven reparent routine must be present",
  );
  assert(
    reparentRoutine.indexOf("UPDATE %I.%I SET %I = $1 WHERE %I = $2") <
      reparentRoutine.indexOf(
        "PERFORM internal.assert_ghost_profile_merge_species_ledger",
      ),
    "the scan trigger must finish ownership deltas before ledger validation",
  );
});

Deno.test("Ghost merge installs preconditions and explicit conflict handlers", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));
  const replacementStart = sql.indexOf("replacement_fragment TEXT :=");
  const replacementEnd = sql.indexOf("BEGIN SELECT", replacementStart);
  const replacement = sql.slice(replacementStart, replacementEnd);
  const precondition = replacement.indexOf(
    "internal.assert_ghost_profile_merge_reference_preconditions",
  );
  const activityHandler = replacement.indexOf(
    "internal.merge_ghost_community_activity_actors",
  );
  const revenueCatHandler = replacement.indexOf(
    "internal.merge_ghost_revenuecat_state",
  );
  const firstExistingMutator = replacement.indexOf(
    "internal.merge_ghost_chat_conversations",
  );

  assert(
    replacementStart >= 0 && replacementEnd > replacementStart,
    "the guarded orchestrator rewrite must be present",
  );
  assert(
    precondition >= 0 &&
      precondition < activityHandler &&
      activityHandler < revenueCatHandler &&
      revenueCatHandler < firstExistingMutator,
    "coverage must run before every newly installed or existing mutating helper",
  );

  for (
    const fragment of [
      "ORDER BY actor.activity_group_id, actor.user_id FOR UPDATE",
      "DELETE FROM internal.revenuecat_webhook_event_subjects AS source_subject USING internal.revenuecat_webhook_event_subjects AS target_subject",
      "DELETE FROM internal.revenuecat_customer_state AS source_state USING internal.revenuecat_customer_state AS target_state",
      "SET lookup_app_user_id = p_target_user_id::TEXT",
      "claim_token = NULL, claimed_at = NULL, claim_expires_at = NULL",
      "ghost_merge_orchestrator_source_drift",
      "REVOKE ALL ON FUNCTION internal.perform_ghost_profile_merge(UUID, UUID) FROM PUBLIC, anon, authenticated, service_role",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("Ghost merge forward hardening enforces collision and lock-order contracts", async () => {
  const sql = normalized(await Deno.readTextFile(hardeningMigrationUrl));
  const communityStart = sql.indexOf(
    "CREATE OR REPLACE FUNCTION internal.merge_ghost_community_activity_actors",
  );
  const revenueCatStart = sql.indexOf(
    "CREATE OR REPLACE FUNCTION internal.merge_ghost_revenuecat_state",
    communityStart,
  );
  const applyStart = sql.indexOf(
    "CREATE OR REPLACE FUNCTION public.apply_revenuecat_reconciliation",
    revenueCatStart,
  );
  const commentsStart = sql.indexOf(
    "COMMENT ON FUNCTION internal.merge_ghost_community_activity_actors",
    applyStart,
  );

  assert(
    communityStart >= 0 &&
      revenueCatStart > communityStart &&
      applyStart > revenueCatStart &&
      commentsStart > applyStart,
    "all three corrected routine definitions must be present in forward order",
  );

  const communityRoutine = sql.slice(communityStart, revenueCatStart);
  for (
    const fragment of [
      "ORDER BY actor.activity_group_id, actor.user_id FOR UPDATE",
      "UPDATE internal.community_identification_activity_actors AS target_actor SET suggestion_count = target_actor.suggestion_count + source_actor.suggestion_count",
      "DELETE FROM internal.community_identification_activity_actors AS source_actor USING internal.community_identification_activity_actors AS target_actor",
      "target_actor.activity_group_id = source_actor.activity_group_id",
    ]
  ) {
    assertStringIncludes(communityRoutine, fragment);
  }
  assert(
    !communityRoutine.includes(
      "INSERT INTO internal.community_identification_activity_actors",
    ) && !communityRoutine.includes("ON CONFLICT"),
    "the active Community handler must never insert/upsert after actor locks",
  );

  const revenueCatRoutine = sql.slice(revenueCatStart, applyStart);
  for (
    const fragment of [
      "ORDER BY queue.merian_user_id FOR UPDATE",
      "INSERT INTO internal.revenuecat_reconciliation_queue AS destination_queue",
      "VALUES ( p_target_user_id, p_target_user_id::TEXT, pg_catalog.NOW(), 0, NULL, NULL, NULL",
      "ON CONFLICT (merian_user_id) DO UPDATE SET lookup_app_user_id = EXCLUDED.lookup_app_user_id, next_reconcile_at = pg_catalog.NOW(), attempt_count = 0, claim_token = NULL, claimed_at = NULL, claim_expires_at = NULL",
      "DELETE FROM internal.revenuecat_reconciliation_queue AS source_queue WHERE source_queue.merian_user_id = p_ghost_user_id",
    ]
  ) {
    assertStringIncludes(revenueCatRoutine, fragment);
  }

  const applyRoutine = sql.slice(applyStart, commentsStart);
  const userLock = applyRoutine.indexOf(
    "PERFORM users.id FROM public.users AS users WHERE users.id = p_user_id FOR UPDATE",
  );
  const queueLock = applyRoutine.indexOf(
    "SELECT queue.* INTO queue_row FROM internal.revenuecat_reconciliation_queue AS queue",
  );
  assert(
    userLock >= 0 && queueLock > userLock,
    "RevenueCat apply must lock the parent user before revalidating/locking its queue claim",
  );
  assertStringIncludes(
    applyRoutine,
    "WHERE queue.merian_user_id = p_user_id AND queue.claim_token = p_claim_token AND queue.claim_expires_at > pg_catalog.CLOCK_TIMESTAMP()",
  );
  assertEquals(
    applyRoutine.match(
      /queue\.claim_expires_at > pg_catalog\.CLOCK_TIMESTAMP\(\)/g,
    )?.length,
    2,
    "claim expiry must be checked under lock and again in the completion write",
  );
  assertStringIncludes(
    sql,
    "REVOKE ALL ON FUNCTION public.apply_revenuecat_reconciliation( UUID, UUID, BIGINT, TEXT, TIMESTAMPTZ ) FROM PUBLIC, anon, authenticated, service_role",
  );
  assertStringIncludes(
    sql,
    "GRANT EXECUTE ON FUNCTION public.apply_revenuecat_reconciliation( UUID, UUID, BIGINT, TEXT, TIMESTAMPTZ ) TO service_role",
  );
});

Deno.test("Ghost merge health indexes match the recurring audit predicates", async () => {
  const [migration, monitor] = await Promise.all([
    Deno.readTextFile(healthIndexMigrationUrl).then(normalized),
    Deno.readTextFile(healthMonitorUrl).then(normalized),
  ]);

  for (
    const fragment of [
      "CREATE INDEX ghost_profile_merge_recent_receipts_idx ON internal.ghost_profile_merge_handoffs (created_at) WHERE status IN ('prepared', 'merged', 'expired')",
      "CREATE INDEX ghost_profile_merge_recent_destinations_idx ON internal.ghost_profile_merge_handoffs (merged_at, target_user_id) WHERE status = 'merged'",
      "RESET lock_timeout",
      "RESET statement_timeout",
    ]
  ) {
    assertStringIncludes(migration, fragment);
  }
  assertStringIncludes(
    monitor,
    "ON handoff.status IN ('prepared', 'merged', 'expired') AND handoff.created_at >= clock.observed_at - INTERVAL '12 hours'",
  );
  assertStringIncludes(
    monitor,
    "ON handoff.status = 'merged' AND handoff.merged_at >= clock.observed_at - INTERVAL '24 hours'",
  );
});

Deno.test("Ghost merge pgTAP covers topology, ledger, actor, and provider repair", async () => {
  const sql = normalized(await Deno.readTextFile(pgTapUrl));

  for (
    const fragment of [
      "CREATE TABLE internal.ghost_merge_unclassified_fixture",
      "ghost_merge_unclassified_reference:%ghost_merge_unclassified_fixture%",
      "PERFORM internal.perform_ghost_profile_merge",
      "Mergea prima",
      "Mergea secunda",
      "AND scan_count = 3",
      "AND scan_count = 1",
      "SELECT total_species_discovered FROM public.users",
      ") <> 2 THEN",
      "FROM internal.user_species_scan_counts WHERE user_id = '00000000-0000-0000-0000-000000000601'",
      "INSERT INTO internal.revenuecat_webhook_event_subjects",
      "INSERT INTO internal.revenuecat_customer_state",
      "INSERT INTO internal.revenuecat_reconciliation_queue",
      "DELETE FROM internal.revenuecat_reconciliation_queue WHERE merian_user_id = '00000000-0000-0000-0000-000000000601'",
      "destination queue was not created from an entirely absent queue pair",
      "ON CONFLICT (merian_user_id) DO UPDATE",
      "displaced RevenueCat claim unexpectedly applied state",
      "revenuecat_reconciliation_claim_lost",
      "source RevenueCat state survived the merge",
      "RevenueCat conflict state was not normalized",
      "INSERT INTO internal.community_identification_activity_actors",
      "AND suggestion_count = 5",
      "AND suggestion_count = 4",
      "Community activity actors were not coalesced and reparented exactly",
      "user_species_scan_count_underflow",
      "species ledger failure did not roll back the merge",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  const displacedClaimProbe = sql.indexOf(
    "displaced RevenueCat claim unexpectedly applied state",
  );
  const ownerStateVerification = sql.indexOf(
    "IF EXISTS ( SELECT 1 FROM public.users WHERE id = '00000000-0000-0000-0000-000000000602' AND subscription_tier",
    displacedClaimProbe,
  );
  const resetAfterClaimProbe = sql.indexOf(
    "RESET ROLE;",
    displacedClaimProbe,
  );

  assert(
    displacedClaimProbe >= 0 &&
      resetAfterClaimProbe > displacedClaimProbe &&
      ownerStateVerification > resetAfterClaimProbe,
    "service_role must exercise the RPC before the test owner verifies private table state",
  );

  assertEquals(
    sql.match(/ghost_merge_unclassified_fixture/g)?.length,
    4,
    "the fixture must be created, diagnosed, checked, and dropped",
  );
});
