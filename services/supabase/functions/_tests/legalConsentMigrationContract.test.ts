import { assert, assertEquals, assertStringIncludes } from "@std/assert";

const migrationUrl = new URL(
  "../../migrations/20260804020351_record_legal_consent_receipts.sql",
  import.meta.url,
);
const currentGateMigrationUrl = new URL(
  "../../migrations/20260804033307_add_adult_and_analytics_consent.sql",
  import.meta.url,
);
const currentDisclosureMigrationUrl = new URL(
  "../../migrations/20260804215234_bump_consent_disclosure_versions.sql",
  import.meta.url,
);
const causalConsentMigrationUrl = new URL(
  "../../migrations/20260806024844_enforce_causal_consent_streams.sql",
  import.meta.url,
);
const providerHeadAuthorityMigrationUrl = new URL(
  "../../migrations/20260806144105_authorize_consent_from_provider_stream_heads.sql",
  import.meta.url,
);
const iosConsentRootUrl = new URL(
  "../../../../apps/ios/Merian/Core/Security/",
  import.meta.url,
);

function normalized(value: string): string {
  return value.replaceAll(/\s+/g, " ").trim();
}

function iosConsentSource(relativePath: string): Promise<string> {
  return Deno.readTextFile(new URL(relativePath, iosConsentRootUrl));
}

Deno.test("legal receipts are append-only, owner-scoped, and merge-safe", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "CREATE TABLE public.user_terms_acceptance_receipts",
      "CREATE TABLE public.user_ai_consent_events",
      "recorded_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW()",
      "ALTER TABLE public.user_terms_acceptance_receipts ENABLE ROW LEVEL SECURITY",
      "ALTER TABLE public.user_ai_consent_events ENABLE ROW LEVEL SECURITY",
      "GRANT SELECT ON TABLE public.user_terms_acceptance_receipts TO authenticated, service_role",
      "GRANT SELECT ON TABLE public.user_ai_consent_events TO authenticated, service_role",
      "FOR INSERT TO authenticated WITH CHECK ((SELECT auth.uid()) = user_id)",
      "'user_terms_acceptance_receipts', 'user_id', 'public', 'users', 'id', 'reparent'",
      "'user_ai_consent_events', 'user_id', 'public', 'users', 'id', 'reparent'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(!sql.includes("GRANT UPDATE ON TABLE public.user_terms"));
  assert(!sql.includes("GRANT DELETE ON TABLE public.user_terms"));
  assert(!sql.includes("GRANT UPDATE ON TABLE public.user_ai_consent"));
  assert(!sql.includes("GRANT DELETE ON TABLE public.user_ai_consent"));
});

Deno.test("adult and analytics evidence is append-only, owner-scoped, merge-safe, and realtime-enabled", async () => {
  const sql = normalized(await Deno.readTextFile(currentGateMigrationUrl));

  for (
    const fragment of [
      "CREATE TABLE public.user_adult_eligibility_receipts",
      "CREATE TABLE public.user_analytics_consent_events",
      "ALTER TABLE public.user_adult_eligibility_receipts ENABLE ROW LEVEL SECURITY",
      "ALTER TABLE public.user_analytics_consent_events ENABLE ROW LEVEL SECURITY",
      "GRANT SELECT ON TABLE public.user_adult_eligibility_receipts TO authenticated, service_role",
      "GRANT SELECT ON TABLE public.user_analytics_consent_events TO authenticated, service_role",
      "FOR INSERT TO authenticated WITH CHECK ((SELECT auth.uid()) = user_id)",
      "'user_adult_eligibility_receipts', 'user_id', 'public', 'users', 'id', 'reparent'",
      "'user_analytics_consent_events', 'user_id', 'public', 'users', 'id', 'reparent'",
      "ADD TABLE public.user_analytics_consent_events",
      "CREATE TABLE internal.ai_consent_rollout_config",
      "'legacy_compatible'",
      "'strict_2026_08_03'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(!sql.includes("GRANT UPDATE ON TABLE public.user_adult"));
  assert(!sql.includes("GRANT DELETE ON TABLE public.user_adult"));
  assert(!sql.includes("GRANT UPDATE ON TABLE public.user_analytics"));
  assert(!sql.includes("GRANT DELETE ON TABLE public.user_analytics"));
});

Deno.test("quota gate supports the reviewed cutover to current adult, Terms, and Gemini permission", async () => {
  const originalSql = normalized(await Deno.readTextFile(migrationUrl));
  const sql = normalized(await Deno.readTextFile(currentGateMigrationUrl));
  const marker = "PERFORM internal.require_current_ai_consent(p_user_id)";

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION internal.require_current_ai_consent",
      "FROM public.user_adult_eligibility_receipts",
      "receipts.policy_version = '2026-08-03'",
      "receipts.terms_version = '2026-08-03'",
      "events.provider = 'google_gemini'",
      "events.disclosure_version = '2026-08-03.1'",
      "IF latest_event_kind IS NOT NULL",
      "Once this account has acted on the current disclosure",
      "fall back to a historical TestFlight grant during transition",
      "IF enforcement_mode = 'strict_2026_08_03'",
      "ORDER BY events.recorded_at DESC, events.id DESC",
      "IF latest_event_kind IS DISTINCT FROM 'granted'",
      "RAISE EXCEPTION 'ai_consent_required'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assertEquals(originalSql.split(marker).length - 1, 1);
  assertStringIncludes(
    originalSql,
    "FOREACH identity_arguments IN ARRAY ARRAY[",
  );

  const cutover = normalized(
    await Deno.readTextFile(
      new URL("../../scripts/cutover_strict_ai_consent.sql", import.meta.url),
    ),
  );
  assertStringIncludes(
    cutover,
    "SET enforcement_mode = 'strict_2026_08_04'",
  );
  assertStringIncludes(
    cutover,
    "WHERE config_key = 'current' AND enforcement_mode IN ( 'legacy_compatible', 'strict_2026_08_03' )",
  );
});

Deno.test("disclosure bump is forward-only, authoritative, and preserves bounded beta compatibility", async () => {
  const sql = normalized(
    await Deno.readTextFile(currentDisclosureMigrationUrl),
  );

  for (
    const fragment of [
      "DROP CONSTRAINT ai_consent_rollout_config_enforcement_mode_check",
      "'strict_2026_08_04'",
      "CREATE OR REPLACE FUNCTION internal.require_current_ai_consent",
      "events.disclosure_version = '2026-08-04.1'",
      "A grant, revocation, or partial bundle for the newest disclosure",
      "IF enforcement_mode = 'strict_2026_08_04'",
      "events.disclosure_version = '2026-08-03.1'",
      "OR enforcement_mode = 'strict_2026_08_03'",
      "events.disclosure_version = '2026-08-03'",
      "receipts.policy_version = '2026-08-03'",
      "receipts.terms_version = '2026-08-03'",
      "ORDER BY events.recorded_at DESC, events.id DESC",
      "RAISE EXCEPTION 'ai_consent_required'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(!sql.includes("CREATE TABLE public.user_ai_consent_events"));
  assert(!sql.includes("UPDATE public.user_ai_consent_events"));
});

Deno.test("consent appends are atomically causal and server-revisioned", async () => {
  const sql = normalized(await Deno.readTextFile(causalConsentMigrationUrl));

  for (
    const fragment of [
      "ADD COLUMN consent_revision BIGINT",
      "ADD COLUMN causal_parent_id UUID",
      "ALTER COLUMN consent_revision SET NOT NULL",
      "UNIQUE (consent_revision)",
      "CREATE INDEX user_ai_consent_stream_head_idx",
      "CREATE INDEX user_analytics_consent_stream_head_idx",
      "CREATE INDEX user_ai_consent_causal_parent_idx",
      "CREATE INDEX user_analytics_consent_causal_parent_idx",
      "REVOKE INSERT ON TABLE public.user_ai_consent_events, public.user_analytics_consent_events FROM PUBLIC, anon, authenticated, service_role",
      "REVOKE INSERT ( id, user_id, provider, disclosure_version, event_kind, occurred_at, disclosure_text, action_text, platform, app_version, app_build ) ON TABLE public.user_ai_consent_events FROM authenticated",
      'DROP POLICY "Users can append their own AI consent events"',
      "CREATE OR REPLACE FUNCTION public.append_user_ai_consent_event",
      "CREATE OR REPLACE FUNCTION public.append_user_analytics_consent_event",
      "SECURITY DEFINER SET search_path = ''",
      "FOR KEY SHARE",
      "PG_ADVISORY_XACT_LOCK",
      "HASHTEXTEXTENDED",
      "0::BIGINT",
      "IF p_event_kind IS DISTINCT FROM 'revoked' AND p_causal_parent_id IS DISTINCT FROM current_event_id",
      "accepted_parent_id UUID",
      "accepted_parent_id := current_event_id",
      "accepted := FALSE",
      "ORDER BY events.consent_revision DESC",
      "GRANT EXECUTE ON FUNCTION public.append_user_ai_consent_event",
      "GRANT EXECUTE ON FUNCTION public.append_user_analytics_consent_event",
      "'authenticated', 'public.append_user_ai_consent_event(uuid,text,text,timestamp with time zone,text,text,text,text,text,uuid)'",
      "'authenticated', 'public.append_user_analytics_consent_event(uuid,text,text,timestamp with time zone,text,text,text,text,text,uuid)'",
      "REVOKE ALL ON SEQUENCE public.user_ai_consent_revision_seq, public.user_analytics_consent_revision_seq FROM PUBLIC, anon, authenticated, service_role",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  const manager = normalized(await iosConsentSource("ConsentManager.swift"));
  const synchronizationCoordinator = normalized(
    await iosConsentSource(
      "Consent/Coordinators/ConsentSynchronizationCoordinator.swift",
    ),
  );
  const remoteModels = normalized(
    await iosConsentSource("Consent/Services/ConsentRemoteModels.swift"),
  );
  const remoteService = normalized(
    await iosConsentSource("Consent/Services/ConsentRemoteService.swift"),
  );
  const liveRemoteService = normalized(
    await iosConsentSource("Consent/Services/ConsentRemoteService+Live.swift"),
  );
  assertStringIncludes(
    liveRemoteService,
    'rpc( "append_user_ai_consent_event"',
  );
  assertStringIncludes(
    liveRemoteService,
    'rpc( "append_user_analytics_consent_event"',
  );
  assertStringIncludes(remoteService, "causalParentId");
  assertStringIncludes(remoteService, "consentRevision");
  assertStringIncludes(remoteService, "supersededByEventId");
  assertStringIncludes(remoteModels, "let accepted_parent_id: UUID?");
  assertStringIncludes(remoteService, "matchesAdultEligibilityReceipt");
  assertStringIncludes(remoteService, "matchesTermsReceipt");
  assertStringIncludes(remoteService, "matchesAIConsentAppendRetry");
  assertStringIncludes(remoteService, "matchesAnalyticsConsentAppendRetry");
  assertStringIncludes(remoteService, "firstMappedRemoteRow");
  assertEquals(
    remoteService.match(/try Self\.firstMappedRemoteRow\(/g)?.length,
    10,
  );
  assert(
    !remoteService.includes(".first.flatMap("),
    "Malformed present consent rows must not collapse into authoritative absence",
  );
  for (
    const fragment of [
      "let p_id: UUID",
      "let p_disclosure_version: String",
      "let p_event_kind: String",
      "let p_occurred_at: String",
      "let p_disclosure_text: String",
      "let p_action_text: String",
      "let p_platform: String",
      "let p_app_version: String",
      "let p_app_build: String",
      "let p_causal_parent_id: UUID?",
      "let accepted: Bool",
      "let event_revision: Int64?",
      "let authoritative_revision: Int64",
      "let authoritative_event_id: UUID?",
      "let recorded_at: String?",
    ]
  ) {
    assertStringIncludes(remoteModels, fragment);
  }
  assertStringIncludes(
    remoteModels,
    'static let adultEligibilityReceiptColumns = "id,user_id,policy_version,confirmed_at,confirmation_method," + "confirmation_text,platform,app_version,app_build,recorded_at"',
  );
  assertStringIncludes(
    remoteModels,
    'static let termsReceiptColumns = "id,user_id,terms_version,accepted_at,acceptance_text,platform," + "app_version,app_build,recorded_at"',
  );
  assertStringIncludes(
    remoteModels,
    'static let consentEventColumns = "id,user_id,provider,disclosure_version,event_kind,occurred_at," + "disclosure_text,action_text,platform,app_version,app_build," + "recorded_at,causal_parent_id,consent_revision"',
  );
  assertEquals(
    remoteService.match(/causalParentId: row\.causal_parent_id/g)?.length,
    2,
  );
  assertEquals(
    remoteService.match(/consentRevision: row\.consent_revision/g)?.length,
    2,
  );
  assertEquals(sql.match(/FOR KEY SHARE/g)?.length, 2);
  assertEquals(sql.match(/PG_ADVISORY_XACT_LOCK/g)?.length, 2);
  assertEquals(sql.match(/HASHTEXTEXTENDED/g)?.length, 2);
  assertEquals(sql.match(/0::BIGINT/g)?.length, 2);
  assert(
    sql.indexOf("FOR KEY SHARE") < sql.indexOf("PG_ADVISORY_XACT_LOCK"),
    "Consent RPCs must take the account row lock before their advisory lock.",
  );
  assertStringIncludes(
    synchronizationCoordinator,
    "remoteService.insertAIConsentEvent(",
  );
  assertStringIncludes(
    synchronizationCoordinator,
    ".insertAnalyticsConsentEvent(",
  );
  assertStringIncludes(
    synchronizationCoordinator,
    "try self.validateSynchronization(",
  );
  assertStringIncludes(remoteService, "try validateSynchronization()");
  assert(!manager.includes(".rpc("));
  assert(!synchronizationCoordinator.includes(".rpc("));
  for (
    const table of [
      "user_adult_eligibility_receipts",
      "user_terms_acceptance_receipts",
      "user_ai_consent_events",
      "user_analytics_consent_events",
    ]
  ) {
    assertEquals(liveRemoteService.split(table).length - 1, 3);
  }
  assertEquals(liveRemoteService.match(/async let/g)?.length, 6);
  assertEquals(liveRemoteService.match(/\.limit\(1\)/g)?.length, 10);
  assertEquals(
    liveRemoteService.match(/\.eq\("id", value: id\)/g)?.length,
    4,
  );
  assertEquals(
    liveRemoteService.match(/\.eq\("user_id", value: userId\)/g)?.length,
    10,
  );
  assertEquals(
    liveRemoteService.match(
      /\.select\(ConsentRemoteWire\.adultEligibilityReceiptColumns\)/g,
    )?.length,
    2,
  );
  assertEquals(
    liveRemoteService.match(
      /\.select\(ConsentRemoteWire\.termsReceiptColumns\)/g,
    )?.length,
    2,
  );
  assertEquals(
    liveRemoteService.match(
      /\.select\(ConsentRemoteWire\.consentEventColumns\)/g,
    )?.length,
    6,
  );
  assertStringIncludes(
    liveRemoteService,
    '.eq( "policy_version", value: ConsentPolicy.adultEligibilityVersion ) .order("recorded_at", ascending: false) .order("id", ascending: false) .limit(1)',
  );
  assertStringIncludes(
    liveRemoteService,
    '.eq("terms_version", value: ConsentPolicy.termsVersion) .order("recorded_at", ascending: false) .order("id", ascending: false) .limit(1)',
  );
  assertEquals(
    liveRemoteService.match(
      /\.eq\("provider", value: ConsentPolicy\.geminiProvider\)/g,
    )?.length,
    2,
  );
  assertEquals(
    liveRemoteService.match(
      /\.eq\("provider", value: ConsentPolicy\.analyticsProvider\)/g,
    )?.length,
    2,
  );
  assertEquals(
    liveRemoteService.match(/\.eq\( "disclosure_version",/g)?.length,
    2,
  );
  assertEquals(
    liveRemoteService.match(
      /\.order\("consent_revision", ascending: false\)/g,
    )?.length,
    4,
  );
  assertStringIncludes(
    liveRemoteService,
    "let rows = try await ( adultRows, termsRows, aiRows, analyticsRows, aiStreamHeadRows, analyticsStreamHeadRows )",
  );
  assert(
    !liveRemoteService.includes('.from("user_ai_consent_events") .insert'),
  );
  assert(
    !liveRemoteService.includes(
      '.from("user_analytics_consent_events") .insert',
    ),
  );
});

Deno.test("consent authorization starts from the all-version provider stream head", async () => {
  const sql = normalized(
    await Deno.readTextFile(providerHeadAuthorityMigrationUrl),
  );
  const headSelectionStart = sql.indexOf(
    "SELECT events.event_kind, events.disclosure_version",
  );
  const headSelectionEnd = sql.indexOf("LIMIT 1", headSelectionStart);
  assert(headSelectionStart >= 0 && headSelectionEnd > headSelectionStart);
  const headSelection = sql.slice(headSelectionStart, headSelectionEnd);
  const headGrantCheck = sql.indexOf(
    "IF stream_head_event_kind IS DISTINCT FROM 'granted'",
    headSelectionEnd,
  );
  const rolloutLookup = sql.indexOf(
    "SELECT config.enforcement_mode",
    headSelectionEnd,
  );
  assert(
    headGrantCheck > headSelectionEnd && rolloutLookup > headGrantCheck,
    "Authorization must resolve and deny from the provider head before reading rollout configuration.",
  );

  for (
    const fragment of [
      "INTO stream_head_event_kind, stream_head_disclosure_version",
      "events.provider = 'google_gemini'",
      "ORDER BY events.consent_revision DESC",
      "IF stream_head_event_kind IS DISTINCT FROM 'granted'",
      "stream_head_disclosure_version = '2026-08-04.1'",
      "stream_head_disclosure_version = '2026-08-03.1'",
      "stream_head_disclosure_version = '2026-08-03'",
      "enforcement_mode <> 'strict_2026_08_04'",
      "enforcement_mode = 'legacy_compatible'",
      "Unknown/future disclosure versions fail closed",
      "REVOKE ALL ON FUNCTION internal.require_current_ai_consent(UUID) FROM PUBLIC, anon, authenticated, service_role",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
  assert(
    !headSelection.includes("events.disclosure_version ="),
    "The authoritative provider-head query must not pre-filter a disclosure version.",
  );

  const postHog = normalized(
    await Deno.readTextFile(new URL("../_shared/posthog.ts", import.meta.url)),
  );
  assertStringIncludes(postHog, '.select("event_kind,disclosure_version")');
  assertStringIncludes(
    postHog,
    '.order("consent_revision", { ascending: false })',
  );
  assert(!postHog.includes('.eq("disclosure_version"'));

  const synchronizationMergePolicy = normalized(
    await iosConsentSource(
      "Consent/Policies/ConsentSynchronizationMergePolicy.swift",
    ),
  );
  const authority = normalized(
    await iosConsentSource(
      "Consent/Policies/ConsentAuthorityPolicy.swift",
    ),
  );
  assertStringIncludes(
    synchronizationMergePolicy,
    "granted: ConsentAuthorityPolicy.isAuthoritativeAnalyticsGrant( remoteState.analyticsConsentStreamHead",
  );
  assertStringIncludes(
    authority,
    "guard let streamHead = currentAIConsentStreamHead(",
  );
  assertStringIncludes(
    authority,
    "guard let streamHead = currentAnalyticsConsentStreamHead(",
  );
});

Deno.test("consent concurrency coverage overlaps both provider conflict orders", async () => {
  const fixture = normalized(
    await Deno.readTextFile(
      new URL("./legalConsentConcurrencyDb.test.ts", import.meta.url),
    ),
  );
  for (
    const fragment of [
      "append_user_ai_consent_event",
      "append_user_analytics_consent_event",
      "FOR UPDATE",
      "wait_event_type = 'Lock'",
      '"granted"',
      '"revoked"',
      "Promise.all([ delayedGrant, revocation, ])",
      "revocationRevision > baselineRevision",
      'assertEquals(latest.event_kind, "revoked")',
    ]
  ) {
    assertStringIncludes(fixture, fragment);
  }
});

Deno.test("Swift and backend consent versions cannot drift", async () => {
  const disclosureSql = await Deno.readTextFile(currentDisclosureMigrationUrl);
  const causalSql = await Deno.readTextFile(causalConsentMigrationUrl);
  const policy = await iosConsentSource(
    "Consent/Models/ConsentPolicy.swift",
  );
  const quota = await Deno.readTextFile(
    new URL("../_shared/aiQuota.ts", import.meta.url),
  );
  const postHog = await Deno.readTextFile(
    new URL("../_shared/posthog.ts", import.meta.url),
  );

  assertStringIncludes(policy, 'adultEligibilityVersion = "2026-08-03"');
  assertStringIncludes(policy, 'termsVersion = "2026-08-03"');
  assertStringIncludes(policy, 'geminiDisclosureVersion = "2026-08-04.1"');
  assertStringIncludes(policy, 'analyticsDisclosureVersion = "2026-08-04"');
  assertStringIncludes(causalSql, "policy_version = '2026-08-03'");
  assertStringIncludes(causalSql, "terms_version = '2026-08-03'");
  assertStringIncludes(causalSql, "disclosure_version = '2026-08-04.1'");
  assertStringIncludes(disclosureSql, "'strict_2026_08_04'");
  assertStringIncludes(
    postHog,
    'POSTHOG_DISCLOSURE_VERSION = "2026-08-04"',
  );
  assertStringIncludes(
    postHog,
    '.order("consent_revision", { ascending: false })',
  );
  assertStringIncludes(
    quota,
    'databaseMessage.includes("ai_consent_required")',
  );
  assertStringIncludes(quota, '"ai_consent_required"');
});
