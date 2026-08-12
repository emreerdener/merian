import { assert, assertStringIncludes } from "@std/assert";

const migrationUrl = new URL(
  "../../migrations/20260812144948_introduce_stable_purchase_principals.sql",
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
const securityFixtureUrl = new URL(
  "../../tests/purchase_principal_security.sql",
  import.meta.url,
);

function compact(value: string): string {
  return value.replaceAll(/\s+/g, " ").trim();
}

Deno.test("purchase principals are private, capability-bound, and disabled by default", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "principal_mode TEXT NOT NULL DEFAULT 'legacy'",
      "account_grant_mode TEXT NOT NULL DEFAULT 'dual_read'",
      "CREATE TABLE internal.purchase_principals",
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
  for (
    const fragment of [
      "PERFORM internal.require_service_role()",
      "purchase-principal-capability:' || p_capability_hash",
      "WHERE principals.capability_hash = p_capability_hash FOR UPDATE",
      "principal.status = 'revoked'",
      "principal.status = 'active' AND p_client_protocol < rollout.minimum_client_protocol",
      "principal.status <> 'active' AND ( rollout.principal_mode = 'legacy'",
      "p_binding_intent_generation <= principal.latest_binding_intent_generation",
      "p_binding_intent_generation NOT BETWEEN 1 AND 9007199254740991",
      "purchase_principal_binding_intent_stale",
      "purchase-principal-auth-user:' || p_auth_user_id::TEXT",
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
      "rollout.principal_mode <> 'stable'",
      "principal.status <> 'active'",
      "purchase_principal_rollout_changed",
      "WHERE principals.id = p_purchase_principal_id AND principals.capability_hash = p_capability_hash",
      "principal.latest_binding_intent_generation <> p_binding_intent_generation",
      "ORDER BY users.id FOR UPDATE OF users, auth_user",
      "purchase_principal_entitlement_projection_changed",
      "current_projection_expires_at IS DISTINCT FROM p_store_expires_at",
      "INSERT INTO internal.purchase_principal_bindings",
      "binding_generation = EXCLUDED.binding_generation",
      "DELETE FROM internal.revenuecat_reconciliation_queue",
    ]
  ) {
    assertStringIncludes(complete, fragment);
  }

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

Deno.test("StoreKit state and account-issued access remain separate", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "CREATE TABLE internal.purchase_principal_store_state",
      "provider_account_grant_frozen BOOLEAN NOT NULL DEFAULT FALSE",
      "allow_non_subscription_pass_grant BOOLEAN NOT NULL DEFAULT FALSE",
      "CREATE TABLE internal.account_access_grants",
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
      "helper_result.account_grant_update_applied",
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
    !sql.includes(
      "UPDATE internal.purchase_principal_bindings SET auth_user_id = p_account_user_id",
    ),
    "an account grant must never choose or move the purchase-principal binding",
  );
});

Deno.test("webhook and reconciliation resolve stable identities before UUID fallback", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));
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
      "Lock every principal in UUID order before any public user row",
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
});

Deno.test("stable iOS linkage does not transfer receipts or write account PII", async () => {
  const [handler, resolverDb, manager, supabaseManager] = await Promise.all([
    Deno.readTextFile(resolverHandlerUrl),
    Deno.readTextFile(resolverDbUrl),
    Deno.readTextFile(revenueCatManagerUrl),
    Deno.readTextFile(supabaseManagerUrl),
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
  const compatibilityCompletion = supabaseManager.slice(
    supabaseManager.indexOf(
      "private func performPendingSignOutPurchaseHandoff",
    ),
    supabaseManager.indexOf("func hasPendingPurchaseIdentityHandoffFailClosed"),
  );
  assert(
    compatibilityCompletion.indexOf(
          ".linkLegacyRevenueCatIdentityForSignOutHandoff(",
        ) < compatibilityCompletion.indexOf(
          ".synchronizePurchasesAfterIdentityHandoff(",
        ) &&
      compatibilityCompletion.lastIndexOf(
          "ensureTelemetryLinkedIfNeeded(for: session.user)",
        ) > compatibilityCompletion.indexOf(
          "clearPendingSignOutPurchaseHandoff()",
        ),
    "an issued compatibility proof must finish on its legacy UUID before stable adoption",
  );
});

Deno.test("disposable database coverage exercises rotation and grant separation", async () => {
  const fixture = compact(await Deno.readTextFile(securityFixtureUrl));

  for (
    const fragment of [
      "SET principal_mode = 'stable'",
      "FROM public.begin_purchase_principal_resolution",
      "FROM public.complete_purchase_principal_resolution",
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
      "refunded pass policy was not durable through reconciliation claim",
      "provider transfer moved, extended, revoked, or created an account grant",
      "provider transfer grant freeze was not preserved or audited",
      "authoritative snapshot ordering yielded to event delivery time",
      "provider transfer did not freeze later grant imports",
      "deleted Auth UUID remained in purchase identity evidence",
      "ROLLBACK",
    ]
  ) {
    assertStringIncludes(fixture, fragment);
  }
});
