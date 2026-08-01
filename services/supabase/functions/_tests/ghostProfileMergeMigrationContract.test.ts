import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";

const migrationUrl = new URL(
  "../../migrations/20260801210102_make_ghost_merge_schema_aware.sql",
  import.meta.url,
);
const pgTapUrl = new URL(
  "../../tests/ghost_profile_merge_security.sql",
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
      "ON CONFLICT (activity_group_id, user_id) DO UPDATE SET suggestion_count = target_actor.suggestion_count + EXCLUDED.suggestion_count",
      "ORDER BY actor.activity_group_id, actor.user_id FOR UPDATE",
      "DELETE FROM internal.revenuecat_webhook_event_subjects AS source_subject USING internal.revenuecat_webhook_event_subjects AS target_subject",
      "DELETE FROM internal.revenuecat_customer_state AS source_state USING internal.revenuecat_customer_state AS target_state",
      "SET lookup_app_user_id = p_target_user_id::TEXT",
      "next_reconcile_at = LEAST( source_queue.next_reconcile_at, pg_catalog.NOW() )",
      "claim_token = NULL, claimed_at = NULL, claim_expires_at = NULL",
      "ghost_merge_orchestrator_source_drift",
      "REVOKE ALL ON FUNCTION internal.perform_ghost_profile_merge(UUID, UUID) FROM PUBLIC, anon, authenticated, service_role",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("Ghost merge pgTAP covers topology drift and species overlap", async () => {
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
      "source RevenueCat state survived the merge",
      "RevenueCat conflict state was not normalized",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assertEquals(
    sql.match(/ghost_merge_unclassified_fixture/g)?.length,
    4,
    "the fixture must be created, diagnosed, checked, and dropped",
  );
});
