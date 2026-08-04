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

function normalized(value: string): string {
  return value.replaceAll(/\s+/g, " ").trim();
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

Deno.test("Swift and backend consent versions cannot drift", async () => {
  const sql = await Deno.readTextFile(currentDisclosureMigrationUrl);
  const swift = await Deno.readTextFile(
    new URL(
      "../../../../apps/ios/Merian/Core/Security/ConsentManager.swift",
      import.meta.url,
    ),
  );
  const quota = await Deno.readTextFile(
    new URL("../_shared/aiQuota.ts", import.meta.url),
  );
  const postHog = await Deno.readTextFile(
    new URL("../_shared/posthog.ts", import.meta.url),
  );

  assertStringIncludes(swift, 'adultEligibilityVersion = "2026-08-03"');
  assertStringIncludes(swift, 'termsVersion = "2026-08-03"');
  assertStringIncludes(swift, 'geminiDisclosureVersion = "2026-08-04.1"');
  assertStringIncludes(swift, 'analyticsDisclosureVersion = "2026-08-04"');
  assertStringIncludes(sql, "policy_version = '2026-08-03'");
  assertStringIncludes(sql, "terms_version = '2026-08-03'");
  assertStringIncludes(sql, "disclosure_version = '2026-08-04.1'");
  assertStringIncludes(
    postHog,
    'POSTHOG_DISCLOSURE_VERSION = "2026-08-04"',
  );
  assertStringIncludes(
    quota,
    'databaseMessage.includes("ai_consent_required")',
  );
  assertStringIncludes(quota, '"ai_consent_required"');
});
