import { assert, assertEquals, assertStringIncludes } from "@std/assert";

const migrationUrl = new URL(
  "../../migrations/20260812144948_introduce_stable_purchase_principals.sql",
  import.meta.url,
);
const legacyQueueFenceMigrationUrl = new URL(
  "../../migrations/20260813012852_fence_empty_legacy_revenuecat_queue_after_stable_binding.sql",
  import.meta.url,
);
const stablePrincipalLintRepairMigrationUrl = new URL(
  "../../migrations/20260813020636_repair_stable_purchase_principal_lint_warnings.sql",
  import.meta.url,
);
const signoutRotationMigrationUrl = new URL(
  "../../migrations/20260816033107_add_stable_purchase_principal_signout_rotations.sql",
  import.meta.url,
);
const signoutRotationRepairMigrationUrl = new URL(
  "../../migrations/20260819194315_repair_stable_signout_rotation_routine_definitions.sql",
  import.meta.url,
);
const resolverHandlerUrl = new URL(
  "../resolve-purchase-principal/handler.ts",
  import.meta.url,
);
const resolverDbUrl = new URL(
  "../resolve-purchase-principal/db.ts",
  import.meta.url,
);
const revenueCatManagerUrl = new URL(
  "../../../../apps/ios/Merian/Core/Security/RevenueCatManager.swift",
  import.meta.url,
);
const supabaseManagerUrl = new URL(
  "../../../../apps/ios/Merian/Core/Network/SupabaseManager.swift",
  import.meta.url,
);
const purchasePrincipalResolverUrl = new URL(
  "../../../../apps/ios/Merian/Core/Security/PurchasePrincipalResolver.swift",
  import.meta.url,
);
const securityFixtureUrl = new URL(
  "../../tests/purchase_principal_security.sql",
  import.meta.url,
);
const revenueCatSecurityFixtureUrl = new URL(
  "../../tests/revenuecat_webhook_security.sql",
  import.meta.url,
);
const compatibilityConcurrencyFixtureUrl = new URL(
  "./purchasePrincipalCompatibilityConcurrencyDb.test.ts",
  import.meta.url,
);
const signoutRotationConcurrencyFixtureUrl = new URL(
  "./purchasePrincipalSignoutRotationConcurrencyDb.test.ts",
  import.meta.url,
);

function serviceRoleBlocks(sql: string): string[] {
  return [...sql.matchAll(
    /SET LOCAL ROLE service_role;([\s\S]*?)RESET ROLE;/gi,
  )].map((match) => match[1]);
}

function compact(value: string): string {
  return value.replaceAll(/\s+/g, " ").trim();
}

function compactFunctionDefinition(
  source: string,
  functionName: string,
): string {
  const start = source.indexOf(
    `CREATE OR REPLACE FUNCTION public.${functionName}(`,
  );
  assert(start >= 0, `missing ${functionName} definition`);
  const terminator = "$function$;";
  const end = source.indexOf(terminator, start);
  assert(end >= 0, `missing ${functionName} terminator`);
  return compact(source.slice(start, end + terminator.length));
}

Deno.test("purchase principals are private, capability-bound, and disabled by default", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "principal_mode TEXT NOT NULL DEFAULT 'legacy'",
      "account_grant_mode TEXT NOT NULL DEFAULT 'dual_read'",
      "CREATE TABLE internal.purchase_principals",
      "CREATE INDEX purchase_principals_grant_owner_idx ON internal.purchase_principals (account_grant_owner_user_id)",
      "capability_hash TEXT NOT NULL UNIQUE",
      "latest_binding_intent_generation BIGINT NOT NULL DEFAULT 0",
      "latest_binding_intent_generation BETWEEN 0 AND 9007199254740991",
      "capability_hash ~ '^[0-9a-f]{64}$'",
      "CREATE TABLE internal.purchase_principal_bindings",
      "purchase_principal_id UUID PRIMARY KEY",
      "CREATE TABLE internal.purchase_principal_binding_history",
      "next_auth_user_id UUID",
      "CREATE INDEX purchase_principal_binding_history_previous_user_idx",
      "CREATE INDEX purchase_principal_binding_history_next_user_idx",
      "CREATE OR REPLACE FUNCTION internal.scrub_purchase_identity_auth_references()",
      "WHERE principal.account_grant_owner_user_id = OLD.id",
      "SET projected_auth_user_id = NULL",
      "BEFORE DELETE ON public.users",
      "CREATE OR REPLACE FUNCTION internal.lock_purchase_principals_for_auth_users",
      "ghost_merge_purchase_principal_source_drift",
      "seen_identity_keys TEXT[] := ARRAY[]::TEXT[]",
      "principal.updated_at < pg_catalog.NOW() - INTERVAL '24 hours'",
      "FOR UPDATE OF principal SKIP LOCKED",
      "REVOKE ALL ON FUNCTION internal.normalize_purchase_principal_binding()",
      "REVOKE ALL ON FUNCTION internal.audit_purchase_principal_binding()",
      "REVOKE ALL ON FUNCTION internal.refresh_purchase_projection_from_binding()",
      "REVOKE ALL ON FUNCTION internal.refresh_purchase_projection_from_state()",
      "REVOKE ALL ON FUNCTION internal.refresh_purchase_projection_from_grant()",
      "ALTER TABLE internal.purchase_principals ENABLE ROW LEVEL SECURITY",
      "REVOKE ALL ON TABLE internal.purchase_principals FROM PUBLIC, anon, authenticated, service_role",
      "REVOKE ALL ON TABLE internal.purchase_principal_bindings FROM PUBLIC, anon, authenticated, service_role",
      "REVOKE ALL ON TABLE internal.purchase_principal_binding_history FROM PUBLIC, anon, authenticated, service_role",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes("GRANT SELECT ON TABLE internal.purchase_principals") &&
      !sql.includes("GRANT INSERT ON TABLE internal.purchase_principals") &&
      !sql.includes("GRANT UPDATE ON TABLE internal.purchase_principals"),
    "purchase-principal tables must not be directly exposed through Data API roles",
  );
});

Deno.test("stable bindings fence only evidence-free legacy reconciliation lanes", async () => {
  const sql = compact(await Deno.readTextFile(legacyQueueFenceMigrationUrl));

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION internal.has_active_purchase_principal_relationship",
      "principal.status = 'active'",
      "binding.auth_user_id = p_user_id",
      "principal.account_grant_owner_user_id = p_user_id",
      "internal.canonical_revenuecat_app_user_id(p_user_id)",
      "CREATE OR REPLACE FUNCTION internal.should_keep_legacy_revenuecat_reconciliation",
      "NOT internal.has_active_purchase_principal_relationship(p_user_id) OR EXISTS",
      "FROM internal.legacy_revenuecat_entitlement_state AS legacy",
      "CREATE TRIGGER guard_legacy_revenuecat_reconciliation_queue BEFORE INSERT OR UPDATE ON internal.revenuecat_reconciliation_queue",
      "CREATE TRIGGER fence_empty_legacy_revenuecat_queue_after_binding AFTER INSERT OR UPDATE OF auth_user_id ON internal.purchase_principal_bindings",
      "DELETE FROM internal.revenuecat_reconciliation_queue AS queue WHERE queue.merian_user_id = NEW.auth_user_id",
      "DELETE FROM internal.revenuecat_reconciliation_queue AS queue USING",
      "AS active_relationship WHERE queue.merian_user_id = active_relationship.user_id",
      "REVOKE ALL ON FUNCTION internal.has_active_purchase_principal_relationship(UUID) FROM PUBLIC, anon, authenticated, service_role",
      "REVOKE ALL ON FUNCTION internal.should_keep_legacy_revenuecat_reconciliation(UUID) FROM PUBLIC, anon, authenticated, service_role",
      "RESET statement_timeout",
      "RESET lock_timeout",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes(
      "DELETE FROM internal.legacy_revenuecat_entitlement_state",
    ),
    "stable binding must preserve a durable legacy provider input during the compatibility window",
  );
});

Deno.test("stable-principal lint repair validates claims before snapshots", async () => {
  const sql = compact(
    await Deno.readTextFile(stablePrincipalLintRepairMigrationUrl),
  );
  const performStart = sql.indexOf(
    "lock_only_perform CONSTANT TEXT :=",
  );
  const queueLockStart = sql.indexOf(
    "FROM internal.purchase_principal_reconciliation_queue AS queue",
    performStart,
  );
  const claimLostStart = sql.indexOf(
    "purchase_principal_reconciliation_claim_lost",
    queueLockStart,
  );
  const snapshotStart = sql.indexOf(
    "FROM internal.apply_purchase_principal_snapshot(",
    claimLostStart,
  );

  assert(
    performStart >= 0 &&
      queueLockStart > performStart &&
      claimLostStart > queueLockStart &&
      snapshotStart < 0,
    "the repair replacement must validate a live principal claim before the preserved routine can apply its snapshot",
  );
  assertStringIncludes(sql, "declaration_occurrences <> 1");
  assertStringIncludes(sql, "select_occurrences <> 1");
});

Deno.test("purchase-principal resolution is service-only and uses one lock order", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));
  const beginStart = sql.indexOf(
    "CREATE OR REPLACE FUNCTION public.begin_purchase_principal_resolution",
  );
  const completeStart = sql.indexOf(
    "CREATE OR REPLACE FUNCTION public.complete_purchase_principal_resolution",
  );
  const grantStart = sql.indexOf(
    "CREATE OR REPLACE FUNCTION public.record_account_access_grant",
  );
  assert(
    beginStart >= 0 && completeStart > beginStart && grantStart > completeStart,
    "resolver transitions must be defined in order",
  );

  const begin = sql.slice(beginStart, completeStart);
  const complete = sql.slice(completeStart, grantStart);
  assert(
    !sql.includes("pg_catalog.HASHTEXTENDED("),
    "purchase-principal advisory locks must call hashtextextended(text,bigint)",
  );
  assert(
    (sql.match(/pg_catalog\.HASHTEXTEXTENDED\(/g) ?? []).length === 5,
    "all five purchase-principal advisory locks must use the real catalog overload",
  );
  assert(
    (sql.match(/'purchase-principal-legacy-compatibility'/g) ?? []).length ===
      2,
    "stable completion and legacy adapters must share the cutover lock",
  );
  for (
    const fragment of [
      "PERFORM internal.require_service_role()",
      "purchase-principal-capability:' || p_capability_hash",
      "pg_catalog.HASHTEXTEXTENDED( 'purchase-principal-capability:' || p_capability_hash, 0::BIGINT )",
      "WHERE principals.capability_hash = p_capability_hash FOR UPDATE",
      "principal.status = 'revoked'",
      "principal.status = 'active' AND p_client_protocol < rollout.minimum_client_protocol",
      "principal.status <> 'active' AND ( rollout.principal_mode = 'legacy'",
      "p_binding_intent_generation <= principal.latest_binding_intent_generation",
      "p_binding_intent_generation NOT BETWEEN 1 AND 9007199254740991",
      "purchase_principal_binding_intent_stale",
      "purchase-principal-auth-user:' || p_auth_user_id::TEXT",
      "pg_catalog.HASHTEXTEXTENDED( 'purchase-principal-auth-user:' || p_auth_user_id::TEXT, 0::BIGINT )",
      "JOIN public.users AS profile ON profile.id = auth_user.id",
      "proposed_app_user_id := pg_catalog.UPPER(p_auth_user_id::TEXT)",
      "'MERIAN_PP_' || pg_catalog.REPLACE",
    ]
  ) {
    assertStringIncludes(begin, fragment);
  }
  for (
    const fragment of [
      "PERFORM internal.require_service_role()",
      "pg_catalog.HASHTEXTEXTENDED( 'purchase-principal-legacy-compatibility', 0::BIGINT )",
      "pg_catalog.HASHTEXTEXTENDED( 'purchase-principal:' || p_purchase_principal_id::TEXT, 0::BIGINT )",
      "rollout.principal_mode <> 'stable'",
      "principal.status <> 'active'",
      "purchase_principal_rollout_changed",
      "WHERE principals.id = p_purchase_principal_id AND principals.capability_hash = p_capability_hash",
      "principal.latest_binding_intent_generation <> p_binding_intent_generation",
      "ORDER BY users.id FOR UPDATE OF users, auth_user",
      "purchase_principal_entitlement_projection_changed",
      "current_projection_expires_at IS DISTINCT FROM p_store_expires_at",
      "ON CONFLICT ON CONSTRAINT purchase_principal_store_state_pkey DO UPDATE",
      "INSERT INTO internal.purchase_principal_bindings",
      "ON CONFLICT ON CONSTRAINT purchase_principal_bindings_pkey DO UPDATE",
      "binding_generation = EXCLUDED.binding_generation",
      "ON CONFLICT ON CONSTRAINT purchase_principal_reconciliation_queue_pkey DO UPDATE",
      "DELETE FROM internal.revenuecat_reconciliation_queue",
    ]
  ) {
    assertStringIncludes(complete, fragment);
  }
  assert(
    !complete.includes("ON CONFLICT (purchase_principal_id)"),
    "resolution completion must not confuse its purchase_principal_id output with an ON CONFLICT inference column",
  );

  for (
    const fragment of [
      "REVOKE ALL ON FUNCTION public.begin_purchase_principal_resolution( UUID, TEXT, INTEGER, BIGINT ) FROM PUBLIC, anon, authenticated, service_role",
      "GRANT EXECUTE ON FUNCTION public.begin_purchase_principal_resolution( UUID, TEXT, INTEGER, BIGINT ) TO service_role",
      "REVOKE ALL ON FUNCTION public.complete_purchase_principal_resolution( UUID, UUID, TEXT, BIGINT, BIGINT, TEXT, TIMESTAMPTZ, BOOLEAN, TEXT, TIMESTAMPTZ ) FROM PUBLIC, anon, authenticated, service_role",
      "GRANT EXECUTE ON FUNCTION public.complete_purchase_principal_resolution( UUID, UUID, TEXT, BIGINT, BIGINT, TEXT, TIMESTAMPTZ, BOOLEAN, TEXT, TIMESTAMPTZ ) TO service_role",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("stable sign-out rotations are private, one-use, and resolver-exclusive", async () => {
  const sql = compact(await Deno.readTextFile(signoutRotationMigrationUrl));

  for (
    const fragment of [
      "CREATE TABLE internal.purchase_principal_signout_rotations",
      "secret_hash TEXT NOT NULL UNIQUE",
      "protocol_version INTEGER NOT NULL DEFAULT 3",
      "binding_intent_generation_fence BIGINT NOT NULL",
      "binding_intent_generation_fence BETWEEN 0 AND 9007199254740991",
      "status IN ('prepared', 'completed', 'cancelled', 'expired')",
      "CREATE UNIQUE INDEX purchase_principal_signout_one_prepared_idx",
      "WHERE status = 'prepared'",
      "CREATE INDEX purchase_principal_signout_rotation_intent_fence_idx",
      "purchase_principal_id, binding_intent_generation_fence DESC",
      "ALTER TABLE internal.purchase_principal_signout_rotations ENABLE ROW LEVEL SECURITY",
      "REVOKE ALL ON TABLE internal.purchase_principal_signout_rotations FROM PUBLIC, anon, authenticated, service_role",
      "purchase_principal_signout_protocol_upgrade_required",
      "CREATE TRIGGER guard_purchase_principal_intent_during_signout_rotation",
      "CREATE TRIGGER guard_purchase_principal_binding_during_signout_rotation",
      "purchase_principal_signout_rotation_required",
      "rotation.binding_intent_generation_fence >= latest_binding_intent_generation",
      "purchase_principal_binding_intent_stale",
      "CREATE OR REPLACE FUNCTION public.prepare_purchase_principal_signout_rotation",
      "binding.auth_user_id <> p_auth_user_id",
      "source_is_anonymous IS DISTINCT FROM FALSE",
      "preparation.expires_at > rotation_prepared_at",
      "CREATE OR REPLACE FUNCTION public.claim_purchase_principal_signout_rotation",
      "'purchase-principal-legacy-compatibility'",
      "ORDER BY profile.id FOR UPDATE OF profile, auth_user",
      "auth_user.is_anonymous IS TRUE",
      "destination_created_at < rotation.created_at",
      "SET reason = 'stable_signout_rotation'",
      "CREATE OR REPLACE FUNCTION public.cancel_purchase_principal_signout_rotation",
      "CREATE OR REPLACE FUNCTION public.get_purchase_principal_signout_rotation_health",
      "generated_at TIMESTAMPTZ",
      "oldest_prepared_age_seconds BIGINT",
      "WITH expired_rotations AS ( UPDATE internal.purchase_principal_signout_rotations",
      "SELECT pg_catalog.COUNT(*) FROM expired_rotations",
      "reject_account_deletion_preparation_during_purchase_signout",
      "purchase_principal_signout_ghost_merge_in_progress",
      "identities_scrubbed_at = pg_catalog.CLOCK_TIMESTAMP()",
      "GRANT EXECUTE ON FUNCTION public.prepare_purchase_principal_signout_rotation( UUID, TEXT, UUID, TEXT, BIGINT, INTEGER ) TO service_role",
      "GRANT EXECUTE ON FUNCTION public.claim_purchase_principal_signout_rotation( UUID, TEXT, UUID, TEXT, INTEGER ) TO service_role",
      "GRANT EXECUTE ON FUNCTION public.cancel_purchase_principal_signout_rotation( UUID, TEXT, UUID, TEXT, INTEGER ) TO service_role",
      "GRANT EXECUTE ON FUNCTION public.get_purchase_principal_signout_rotation_health() TO service_role",
      "RESET statement_timeout",
      "RESET lock_timeout",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
  assert(
    !sql.includes(
      "GRANT SELECT ON TABLE internal.purchase_principal_signout_rotations",
    ),
    "rotation proofs must never be directly exposed to API roles",
  );
  assert(
    !sql.includes("current_time TIMESTAMPTZ"),
    "rotation routines must not shadow PostgreSQL's CURRENT_TIME value function",
  );
  assert(
    !sql.includes("preparation.expires_at > prepared_at"),
    "rotation preparation must not ambiguously reference the recovery preparation's prepared_at column",
  );
  assert(
    (sql.match(/IF rotation\.status = 'expired' THEN/g) ?? []).length === 2,
    "claim and cancellation must replay health-terminalized expiry receipts",
  );
});

Deno.test("stable sign-out forward repair installs the reviewed final routine definitions", async () => {
  const original = await Deno.readTextFile(signoutRotationMigrationUrl);
  const repair = await Deno.readTextFile(signoutRotationRepairMigrationUrl);
  const repairSql = compact(repair);

  for (
    const functionName of [
      "prepare_purchase_principal_signout_rotation",
      "claim_purchase_principal_signout_rotation",
      "cancel_purchase_principal_signout_rotation",
    ]
  ) {
    assertEquals(
      compactFunctionDefinition(repair, functionName),
      compactFunctionDefinition(original, functionName),
      `${functionName} forward repair drifted from the reviewed definition`,
    );
  }

  for (
    const fragment of [
      "rotation_prepared_at TIMESTAMPTZ := pg_catalog.CLOCK_TIMESTAMP()",
      "preparation.expires_at > rotation_prepared_at",
      "REVOKE ALL ON FUNCTION public.prepare_purchase_principal_signout_rotation( UUID, TEXT, UUID, TEXT, BIGINT, INTEGER ), public.claim_purchase_principal_signout_rotation( UUID, TEXT, UUID, TEXT, INTEGER ), public.cancel_purchase_principal_signout_rotation( UUID, TEXT, UUID, TEXT, INTEGER ) FROM PUBLIC, anon, authenticated, service_role",
      "GRANT EXECUTE ON FUNCTION public.prepare_purchase_principal_signout_rotation( UUID, TEXT, UUID, TEXT, BIGINT, INTEGER ) TO service_role",
      "GRANT EXECUTE ON FUNCTION public.claim_purchase_principal_signout_rotation( UUID, TEXT, UUID, TEXT, INTEGER ) TO service_role",
      "GRANT EXECUTE ON FUNCTION public.cancel_purchase_principal_signout_rotation( UUID, TEXT, UUID, TEXT, INTEGER ) TO service_role",
      "RESET statement_timeout",
      "RESET lock_timeout",
    ]
  ) {
    assertStringIncludes(repairSql, fragment);
  }

  assert(
    !repairSql.includes("preparation.expires_at > prepared_at"),
    "forward repair must not restore the ambiguous preparation timestamp",
  );
  assert(
    (repairSql.match(/IF rotation\.status = 'expired' THEN/g) ?? []).length ===
      2,
    "forward repair must preserve both health-terminalized expiry receipts",
  );
});

Deno.test("StoreKit state and account-issued access remain separate", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));
  const recomputeStart = sql.indexOf(
    "CREATE OR REPLACE FUNCTION internal.recompute_purchase_principal_entitlement",
  );
  const recomputeEnd = sql.indexOf(
    "CREATE OR REPLACE FUNCTION public.refresh_expired_entitlement_projection",
    recomputeStart,
  );
  const recompute = sql.slice(recomputeStart, recomputeEnd);

  for (
    const fragment of [
      "CREATE TABLE internal.purchase_principal_store_state",
      "provider_account_grant_frozen BOOLEAN NOT NULL DEFAULT FALSE",
      "allow_non_subscription_pass_grant BOOLEAN NOT NULL DEFAULT FALSE",
      "CREATE TABLE internal.account_access_grants",
      "projection_now := pg_catalog.CLOCK_TIMESTAMP()",
      "grant_row.starts_at <= projection_now",
      "grant_row.expires_at > projection_now",
      "CREATE INDEX account_access_grants_account_user_idx ON internal.account_access_grants (account_user_id)",
      "grant_kind IN ('beta', 'promotion', 'support')",
      "source_kind IN ('revenuecat_legacy', 'operator', 'migration')",
      "CREATE TABLE internal.account_access_grant_audit",
      "account_grant_update_applied BOOLEAN NOT NULL",
      "SELECT state.target_expires_at AS expires_at FROM internal.purchase_principal_bindings AS binding",
      "SELECT grant_row.expires_at FROM internal.account_access_grants AS grant_row",
      "IF rollout.account_grant_mode = 'authoritative' THEN",
      "account_grant_tier := 'free'::public.subscription_tier_enum",
      "IF account_grant_mode_value = 'authoritative' THEN",
      "grant_tier := 'free'::public.subscription_tier_enum",
      "WHEN p_allow_non_subscription_pass_grant IS NULL THEN internal.purchase_principal_store_state .allow_non_subscription_pass_grant",
      "account_grant_update_applied := FALSE",
      "account_grant_update_applied := account_grant_mode_value = 'dual_read'",
      "p_event_type = 'TRANSFER'",
      "snapshot_account_grant_update_applied",
      "SET provider_account_grant_frozen = TRUE",
      "principal.provider_account_grant_frozen IS FALSE",
      "CREATE OR REPLACE FUNCTION internal.prepare_purchase_principals_for_account_deletion",
      "SET account_grant_owner_user_id = NULL, provider_account_grant_frozen = TRUE",
      "purchase_principal_account_deletion_in_progress",
      "account_deletion_purchase_principal_source_drift",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
  assert(
    recomputeStart >= 0 &&
      recomputeEnd > recomputeStart &&
      recompute.indexOf("FOR UPDATE") >= 0 &&
      recompute.indexOf("projection_now := pg_catalog.CLOCK_TIMESTAMP()") >
        recompute.indexOf("FOR UPDATE") &&
      !recompute.includes("pg_catalog.NOW()"),
    "entitlement recomputation must evaluate CLOCK_TIMESTAMP-stamped grants against one current wall-clock instant",
  );

  assert(
    !sql.includes(
      "UPDATE internal.purchase_principal_bindings SET auth_user_id = p_account_user_id",
    ),
    "an account grant must never choose or move the purchase-principal binding",
  );
});

Deno.test("purchase-principal identity bounds use PostgreSQL-safe predicates", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));

  assert(
    !sql.includes("NOT BETWEEN 1 AND CASE"),
    "PostgreSQL does not accept a CASE expression as the upper BETWEEN bound in this migration",
  );
  for (
    const fragment of [
      "identity_kind_value IS NULL OR identity_kind_value NOT IN",
      "identity_kind_value = 'legacy_user' AND pg_catalog.CHAR_LENGTH(lookup_app_user_id_value) NOT BETWEEN 1 AND 1500",
      "identity_kind_value = 'purchase_principal' AND pg_catalog.CHAR_LENGTH(lookup_app_user_id_value) NOT BETWEEN 1 AND 255",
      "IF identity_kind IS NULL OR identity_kind NOT IN",
      "identity_kind = 'legacy_user' AND pg_catalog.CHAR_LENGTH(lookup_id_value) NOT BETWEEN 1 AND 1500",
      "identity_kind = 'purchase_principal' AND pg_catalog.CHAR_LENGTH(lookup_id_value) NOT BETWEEN 1 AND 255",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("legacy reconciliation replacement preserves claim and seed contracts", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));
  const start = sql.indexOf(
    "CREATE OR REPLACE FUNCTION public.apply_revenuecat_reconciliation",
  );
  const end = sql.indexOf(
    "CREATE OR REPLACE FUNCTION internal.merge_ghost_legacy_purchase_state",
    start,
  );
  assert(start >= 0 && end > start, "legacy reconciliation must be replaced");
  const reconciliation = sql.slice(start, end);

  for (
    const fragment of [
      "PERFORM 1 FROM internal.revenuecat_reconciliation_queue AS queue",
      "IF NOT FOUND THEN RAISE EXCEPTION 'revenuecat_reconciliation_claim_lost' USING ERRCODE = '55000'",
      "'RECONCILIATION', pg_catalog.REPEAT('0', 64)",
      "'ignored', 0, 0, 0",
    ]
  ) {
    assertStringIncludes(reconciliation, fragment);
  }
  assert(
    !reconciliation.includes(
      "queue_row internal.revenuecat_reconciliation_queue%ROWTYPE",
    ),
    "the queue lock must not reintroduce a lint-only row holder",
  );
});

Deno.test("webhook and reconciliation resolve stable identities before UUID fallback", async () => {
  const [migrationSource, revenueCatFixtureSource] = await Promise.all([
    Deno.readTextFile(migrationUrl),
    Deno.readTextFile(revenueCatSecurityFixtureUrl),
  ]);
  const sql = compact(migrationSource);
  const revenueCatFixture = compact(revenueCatFixtureSource);
  const snapshotStart = sql.indexOf(
    "CREATE OR REPLACE FUNCTION internal.apply_purchase_principal_snapshot",
  );
  const identityApplyStart = sql.indexOf(
    "CREATE OR REPLACE FUNCTION public.apply_revenuecat_identity_state",
  );
  assert(
    snapshotStart >= 0 && identityApplyStart > snapshotStart,
    "principal snapshot helper must precede the public identity apply routine",
  );
  const snapshot = sql.slice(snapshotStart, identityApplyStart);
  assert(
    (snapshot.match(/RETURN NEXT/g) ?? []).length === 1,
    "principal snapshot helper must emit exactly one result row",
  );

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION public.resolve_revenuecat_identity_subjects",
      "WHERE principals.status = 'active' AND principals.revenuecat_app_user_id = ANY(subject_identifiers)",
      "IF principal_match_count = 1 THEN",
      "identity_kind := 'purchase_principal'",
      "identity_kind := 'legacy_user'",
      "state.allow_non_subscription_pass_grant",
      "p_authoritative_snapshot_at_ms > state.authoritative_snapshot_at_ms",
      "snapshot_time > legacy_state.authoritative_snapshot_at_ms",
      "CREATE OR REPLACE FUNCTION public.apply_revenuecat_identity_state",
      "internal.lock_legacy_revenuecat_compatibility_users",
      "ORDER BY principal.id FOR UPDATE OF principal",
      "ORDER BY users.id FOR UPDATE OF users",
      "CREATE OR REPLACE FUNCTION public.apply_revenuecat_customer_state",
      "IF resolved_identity_kind <> 'legacy_user' THEN",
      "RAISE EXCEPTION 'revenuecat_legacy_identity_conflict' USING ERRCODE = '55000'",
      "IF SQLERRM = 'revenuecat_identity_mapping_ambiguous'",
      "RAISE EXCEPTION 'revenuecat_user_mapping_ambiguous' USING ERRCODE = 'P0001'",
      "PERFORM internal.lock_legacy_revenuecat_compatibility_users( legacy_user_ids )",
      "FROM public.apply_revenuecat_identity_state",
      "CREATE OR REPLACE FUNCTION public.schedule_revenuecat_reconciliation",
      "source_subject := p_subjects -> (resolved_subject_position - 1)",
      "'lookup_app_user_id', source_subject ->> 'lookup_app_user_id'",
      "RETURN public.schedule_revenuecat_identity_reconciliation( identity_subjects )",
      "REVOKE ALL ON FUNCTION public.schedule_revenuecat_reconciliation(JSONB)",
      "GRANT EXECUTE ON FUNCTION public.schedule_revenuecat_reconciliation(JSONB) TO service_role",
      "Lock every principal in UUID order before any public user row",
      "FROM ROWS FROM ( pg_catalog.UNNEST(identity_kinds), pg_catalog.UNNEST(identity_ids) ) AS ids(identity_kind, identity_id)",
      "ORDER BY principals.id FOR UPDATE OF principals",
      "CREATE TABLE internal.purchase_principal_reconciliation_queue",
      "INSERT INTO internal.revenuecat_reconciliation_queue ( merian_user_id, lookup_app_user_id, next_reconcile_at, updated_at ) SELECT users.id, lookup_id_value",
      "FOR UPDATE OF queue SKIP LOCKED",
      "state.allow_non_subscription_pass_grant FROM claimed JOIN internal.purchase_principal_store_state AS state",
      "queue.claim_token = p_claim_token AND queue.claim_expires_at > pg_catalog.CLOCK_TIMESTAMP()",
      "CREATE OR REPLACE FUNCTION public.get_purchase_principal_health()",
      "binding.purchase_principal_id IS NULL AND store_state.target_tier = 'pro'::public.subscription_tier_enum",
      "store_state.target_expires_at IS NULL OR store_state.target_expires_at > clock.observed_at",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
  const recordVariables = new Set(
    [...migrationSource.matchAll(/\b([a-z_]\w*)\s+RECORD\s*;/gi)]
      .map((match) => match[1]),
  );
  for (const recordVariable of recordVariables) {
    const escapedRecordVariable = recordVariable.replace(
      /[.*+?^${}()|[\]\\]/g,
      "\\$&",
    );
    const dynamicResultPatterns = [
      new RegExp(
        `\\bINTO\\s+(?:STRICT\\s+)?${escapedRecordVariable}\\b`,
        "i",
      ),
      new RegExp(
        `\\bFOR\\s+${escapedRecordVariable}\\s+IN\\s+` +
          "SELECT\\s+[a-z_]\\w*[.]\\*",
        "i",
      ),
    ];
    assert(
      dynamicResultPatterns.every((pattern) => !pattern.test(migrationSource)),
      "Nested RPC results must use statically typed scalar targets so plpgsql_check can validate every referenced field.",
    );
  }
  assertStringIncludes(
    revenueCatFixture,
    "legacy RevenueCat scheduler replaced its provider lookup alias",
  );
});

Deno.test("stable iOS linkage does not transfer receipts or write account PII", async () => {
  const [handler, resolverDb, manager, supabaseManager, resolver] =
    await Promise.all([
      Deno.readTextFile(resolverHandlerUrl),
      Deno.readTextFile(resolverDbUrl),
      Deno.readTextFile(revenueCatManagerUrl),
      Deno.readTextFile(supabaseManagerUrl),
      Deno.readTextFile(purchasePrincipalResolverUrl),
    ]);

  assertStringIncludes(handler, "deriveRevenueCatStoreEntitlementState");
  assertStringIncludes(handler, "deriveRevenueCatAccountGrantState");
  assertStringIncludes(handler, "readCurrentEntitlementProjection");
  assertStringIncludes(resolverDb, '"begin_purchase_principal_resolution"');
  assertStringIncludes(resolverDb, '"complete_purchase_principal_resolution"');
  assertStringIncludes(manager, "func linkResolvedPurchasePrincipal(");
  assertStringIncludes(manager, "legacyIdentityAttributes: nil");
  assertStringIncludes(
    manager,
    "RevenueCatStableIdentityPrivacyPolicy.deletionAttributes",
  );
  assertStringIncludes(manager, ".syncAttributesAndOfferingsIfNeeded()");
  assertStringIncludes(manager, "if !usesStablePurchasePrincipal {");
  assertStringIncludes(manager, "!usesStablePurchasePrincipal,");
  assertStringIncludes(manager, "The newest request always runs last.");
  assertStringIncludes(manager, "func beginPurchaseIdentityResolution()");
  assertStringIncludes(resolver, "static let current = 3");
  assertStringIncludes(
    supabaseManager,
    "RevenueCatManager.shared.beginPurchaseIdentityResolution()",
  );
  assertStringIncludes(
    supabaseManager,
    "case .awaitingRefresh(let userId):",
  );
  assertStringIncludes(
    supabaseManager,
    "await RevenueCatManager.shared.handleSupabaseSignOut()",
  );
  assertStringIncludes(
    supabaseManager,
    "linkLegacyRevenueCatIdentityForSignOutHandoff",
  );
  assertStringIncludes(
    supabaseManager,
    "!RevenueCatManager.shared.usesStablePurchasePrincipal",
  );
  assertStringIncludes(
    supabaseManager,
    "activePurchasePrincipalBinding = .legacyFallback",
  );
  assertStringIncludes(
    supabaseManager,
    ".linkLegacyRevenueCatIdentityForSignOutHandoff(",
  );
  assertStringIncludes(
    supabaseManager,
    ".claimSignoutRotation(",
  );
  const compactSupabaseManager = supabaseManager.replaceAll(/\s+/g, " ")
    .trim();
  const handoffReadinessStart = compactSupabaseManager.indexOf(
    "func hasPendingPurchaseIdentityHandoffFailClosed",
  );
  const handoffReadinessEnd = compactSupabaseManager.indexOf(
    "private func loadPendingSignOutPurchaseHandoff",
    handoffReadinessStart,
  );
  assert(
    handoffReadinessStart >= 0 && handoffReadinessEnd > handoffReadinessStart,
    "the fail-closed purchase handoff readiness boundary must remain explicit",
  );
  const handoffReadiness = compactSupabaseManager.slice(
    handoffReadinessStart,
    handoffReadinessEnd,
  );
  const legacyRead = handoffReadiness.indexOf(
    "loadPendingSignOutPurchaseHandoff()",
  );
  const stableRead = handoffReadiness.indexOf(
    "loadPendingPurchasePrincipalAuthRotation()",
  );
  const pendingProjection = handoffReadiness.indexOf(
    "let pending = pendingLegacyHandoff != nil || pendingStableRotation != nil",
  );
  const publishProjection = handoffReadiness.indexOf(
    "setPurchaseIdentityHandoffPending(pending)",
  );
  const returnProjection = handoffReadiness.indexOf("return pending");
  const publishFailure = handoffReadiness.indexOf(
    "setPurchaseIdentityHandoffPending(true)",
  );
  const returnFailure = handoffReadiness.indexOf("return true", publishFailure);
  assert(
    legacyRead >= 0 &&
      stableRead > legacyRead &&
      pendingProjection > stableRead &&
      publishProjection > pendingProjection &&
      returnProjection > publishProjection &&
      publishFailure > returnProjection &&
      returnFailure > publishFailure,
    "handoff readiness must re-read both durable proofs and fail closed when either read is unavailable",
  );
  const compatibilityCompletion = compactSupabaseManager.slice(
    compactSupabaseManager.indexOf(
      "private func performPendingSignOutPurchaseHandoff",
    ),
    compactSupabaseManager.indexOf(
      "func hasPendingPurchaseIdentityHandoffFailClosed",
    ),
  );
  assert(
    compatibilityCompletion.indexOf(
          ".linkLegacyRevenueCatIdentityForSignOutHandoff(",
        ) < compatibilityCompletion.indexOf(
          ".synchronizePurchasesAfterIdentityHandoff(",
        ) &&
      compatibilityCompletion.lastIndexOf(
          "ensureTelemetryLinkedWhenSafe( for: session.user, ownedBy: transition )",
        ) > compatibilityCompletion.indexOf(
          "clearPendingSignOutPurchaseHandoff()",
        ),
    "an issued compatibility proof must finish on its legacy UUID before stable adoption",
  );

  const stableCompletion = compactSupabaseManager.slice(
    compactSupabaseManager.indexOf(
      "private func completePendingPurchasePrincipalAuthRotationIfNeeded",
    ),
    compactSupabaseManager.indexOf(
      "private func performPendingSignOutPurchaseHandoff",
    ),
  );
  assert(
    stableCompletion.indexOf(".claimSignoutRotation(") >= 0 &&
      stableCompletion.indexOf(
          "guard await EntitlementManager.shared.beginSession(",
        ) >
        stableCompletion.indexOf(".claimSignoutRotation(") &&
      stableCompletion.indexOf(
          "try clearPendingPurchasePrincipalAuthRotation()",
        ) >
        stableCompletion.indexOf(
          "guard await EntitlementManager.shared.beginSession(",
        ),
    "stable rotation proof must survive until exact claim and server entitlement verification",
  );
});

Deno.test("disposable database coverage exercises rotation and grant separation", async () => {
  const fixtureSource = await Deno.readTextFile(securityFixtureUrl);
  const fixture = compact(fixtureSource);

  for (
    const fragment of [
      "SET principal_mode = 'stable'",
      "FROM public.begin_purchase_principal_resolution",
      "FROM public.complete_purchase_principal_resolution",
      "FROM public.prepare_purchase_principal_signout_rotation",
      "FROM public.claim_purchase_principal_signout_rotation",
      "prepared sign-out rotation allowed a permanent resolver bypass",
      "prepared stable sign-out allowed source account deletion",
      "stale anonymous destination claimed rotation",
      "prepared Ghost merge allowed a stable sign-out claim",
      "completed stable sign-out rotation replayed to another destination",
      "same capability did not resolve the same principal",
      "stale binding intent was allowed to overwrite a newer Auth session",
      "rollback rotated an activated purchase principal",
      "rollback admitted a new purchase principal",
      "anonymous session was allowed to consume account grants",
      "SET account_grant_mode = 'authoritative'",
      "authoritative cutover recreated a legacy provider grant",
      "FROM public.resolve_revenuecat_identity_subjects",
      "stable identity did not win before UUID fallback",
      "unbound paid purchase principal was not reported",
      "unbound free purchase principal created a permanent alert",
      "refunded pass policy was not returned by reconciliation claim",
      "missing purchase-principal claim reached entitlement mutation",
      "missing purchase-principal claim changed durable state",
      "purchase_principal_reconciliation_claim_lost",
      "refunded pass policy was not durable in principal state",
      "provider transfer moved, extended, revoked, or created an account grant",
      "provider transfer grant freeze was not preserved or audited",
      "authoritative snapshot ordering yielded to event delivery time",
      "legacy webhook reinterpreted an active stable purchase principal",
      "legacy scheduler recreated a stable principal reconciliation lane",
      "previous webhook bundle recreated legacy state after stable adoption",
      "account-switch target did not start with one evidence-free legacy queue",
      "stable account switch retained its evidence-free legacy queue",
      "identity update recreated an evidence-free stable legacy queue",
      "durable legacy provider state lost its compatibility queue",
      "stable binding deleted its pre-existing durable legacy lane",
      "provider transfer did not freeze later grant imports",
      "deleted Auth UUID remained in purchase identity evidence",
      "ON CONFLICT (id) DO UPDATE",
      "ROLLBACK",
    ]
  ) {
    assertStringIncludes(fixture, fragment);
  }
  const profileInsertCount =
    (fixture.match(/INSERT INTO public\.users/g) ?? []).length;
  const profileUpsertCount =
    (fixture.match(/ON CONFLICT \(id\) DO UPDATE/g) ?? []).length;
  assert(
    profileInsertCount > 0 && profileUpsertCount === profileInsertCount,
    "Every explicit Auth-trigger-backed purchase-principal profile must be upserted instead of inserted twice",
  );

  for (const block of serviceRoleBlocks(fixtureSource)) {
    assert(
      !/\b(?:FROM|JOIN|UPDATE|INSERT\s+INTO|DELETE\s+FROM)\s+internal\.[a-z_]+\b(?!\s*\()/i
        .test(block),
      "service_role fixture phases must exercise guarded RPCs, not private tables",
    );
  }

  const deletionSubjectStart = fixture.indexOf(
    "INSERT INTO internal.purchase_principal_webhook_event_subjects",
  );
  const deletionSubjectEnd = fixture.indexOf(
    "INSERT INTO internal.purchase_principals",
    deletionSubjectStart,
  );
  const deletionSubject = fixture.slice(
    deletionSubjectStart,
    deletionSubjectEnd,
  );
  assert(
    deletionSubjectStart >= 0 &&
      deletionSubjectEnd > deletionSubjectStart &&
      deletionSubject.includes("account_grant_update_applied") &&
      deletionSubject.includes("NULL, FALSE, 'applied'"),
    "the deletion-scrub subject fixture must explicitly record that it did not update an account grant",
  );

  const passRefundStart = fixture.indexOf(
    "'purchase-principal-pass-refund-test'",
  );
  const passRefundEnd = fixture.indexOf(
    "SELECT public.schedule_revenuecat_identity_reconciliation",
    passRefundStart,
  );
  const passRefund = fixture.slice(passRefundStart, passRefundEnd);
  const passRefundSnapshotCount = passRefund.split(
    "(EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT + 1000",
  ).length - 1;
  assert(
    passRefundStart >= 0 &&
      passRefundEnd > passRefundStart &&
      passRefundSnapshotCount === 2,
    "The pass-refund event and authoritative snapshot must be newer than the fixture's earlier +30 ms principal snapshot.",
  );
});

Deno.test("legacy compatibility mutation loses a concurrent stable activation", async () => {
  const fixture = compact(
    await Deno.readTextFile(compatibilityConcurrencyFixtureUrl),
  );
  for (
    const fragment of [
      "public.begin_purchase_principal_resolution",
      "public.complete_purchase_principal_resolution",
      "public.apply_revenuecat_customer_state",
      "same principal did not prepare target rebind",
      "target fixture did not establish the ordinary pre-binding legacy queue",
      "completionApplicationName, userBlockerPid",
      "legacyApplicationName, completionPid",
      "revenuecat_legacy_identity_conflict",
      "legacy_state_exists: false",
      "legacy_queue_exists: false",
      "rejected_event_exists: false",
      "identity update recreated an evidence-free legacy queue after stable binding",
      "target fixture did not retain its pre-binding claimed queue",
      "claimedCompletionApplicationName, queueBlockerPid",
      "claimedApplyApplicationName, claimedCompletionPid",
      "revenuecat_reconciliation_claim_lost",
      "claimed legacy reconciliation unexpectedly survived stable binding",
      "seed_event_exists: false",
    ]
  ) {
    assertStringIncludes(fixture, fragment);
  }
});

Deno.test("prepared sign-out rotation defeats a concurrent permanent resolver", async () => {
  const fixture = compact(
    await Deno.readTextFile(signoutRotationConcurrencyFixtureUrl),
  );
  for (
    const fragment of [
      "public.prepare_purchase_principal_signout_rotation",
      "public.begin_purchase_principal_resolution",
      "resolverApplicationName, preparationPid",
      "purchase_principal_signout_rotation_required",
      "unrelated permanent resolver survived a committed sign-out rotation",
      'rotation_status: "prepared"',
    ]
  ) {
    assertStringIncludes(fixture, fragment);
  }
});

Deno.test("stable sign-out terminal races and expiry stay in the disposable database gate", async () => {
  const fixture = compact(
    await Deno.readTextFile(signoutRotationConcurrencyFixtureUrl),
  );
  for (
    const fragment of [
      "claim and source cancellation have one terminal winner",
      'for (const winningOperation of ["claim", "cancel"] as const)',
      "waitUntilBlocked(observer, applicationName, winnerPid)",
      "purchase_principal_signout_rotation_terminal_conflict",
      'rotation_status: "completed"',
      'rotation_status: "cancelled"',
      "expiry is terminal before ordinary resolution resumes",
      "created_at = pg_catalog.CLOCK_TIMESTAMP() - INTERVAL '2 days'",
      "expires_at = pg_catalog.CLOCK_TIMESTAMP() - INTERVAL '1 day'",
      "public.get_purchase_principal_signout_rotation_health",
      "The health pass must report and terminalize the overdue preparation",
      'rotation_status: "expired"',
      "binding_generation: null",
      "public.begin_purchase_principal_resolution",
    ]
  ) {
    assertStringIncludes(fixture, fragment);
  }
});

Deno.test("terminal sign-out rotations fence every resolver begun before preparation", async () => {
  const fixture = compact(
    await Deno.readTextFile(signoutRotationConcurrencyFixtureUrl),
  );
  for (
    const fragment of [
      "resolver completion begun before prepare stays stale after every terminal outcome",
      'for (const terminalOperation of ["claim", "cancel", "expire"] as const)',
      "public.begin_purchase_principal_resolution",
      "public.prepare_purchase_principal_signout_rotation",
      "public.complete_purchase_principal_resolution",
      "purchase_principal_binding_intent_stale",
      "delayed resolver overwrote the terminal sign-out binding",
    ]
  ) {
    assertStringIncludes(fixture, fragment);
  }
});
