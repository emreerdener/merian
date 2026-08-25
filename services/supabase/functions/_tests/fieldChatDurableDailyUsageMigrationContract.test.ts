import { assert, assertStringIncludes } from "@std/assert";

const migrationUrl = new URL(
  "../../migrations/20260824210544_preserve_field_chat_daily_usage.sql",
  import.meta.url,
);
const reservationFixtureUrl = new URL(
  "../../tests/field_chat_reservation_security.sql",
  import.meta.url,
);
const dictionaryFixtureUrl = new URL(
  "../../tests/species_dictionary_chat_security.sql",
  import.meta.url,
);
const sharedReservationUrl = new URL(
  "../_shared/fieldChatReservation.ts",
  import.meta.url,
);
const fieldChatRouteUrls = [
  new URL("../insight-chat/index.ts", import.meta.url),
  new URL("../explore-post-chat/index.ts", import.meta.url),
  new URL("../species-dictionary-chat/index.ts", import.meta.url),
];

function compact(sql: string): string {
  return sql.replaceAll(/\s+/g, " ").trim();
}

Deno.test("Field Chat daily admission accounting is private and content independent", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));
  for (
    const fragment of [
      "CREATE TABLE internal.field_chat_daily_admissions",
      "PRIMARY KEY (user_id, admission_day)",
      "REFERENCES public.users(id) ON DELETE CASCADE",
      "ALTER TABLE internal.field_chat_daily_admissions ENABLE ROW LEVEL SECURITY",
      "REVOKE ALL ON TABLE internal.field_chat_daily_admissions FROM PUBLIC, anon, authenticated, service_role",
      "CREATE OR REPLACE FUNCTION internal.prune_empty_field_chat_conversations()",
      "LOCK TABLE public.insight_chat_conversations, public.insight_chat_messages, public.explore_post_chat_conversations, public.explore_post_chat_messages, public.species_dictionary_chat_conversations, public.species_dictionary_chat_messages IN SHARE ROW EXCLUSIVE MODE",
      "DELETE FROM public.insight_chat_conversations AS conversation WHERE NOT EXISTS",
      "DELETE FROM public.explore_post_chat_conversations AS conversation WHERE NOT EXISTS",
      "DELETE FROM public.species_dictionary_chat_conversations AS conversation WHERE NOT EXISTS",
      "REVOKE ALL ON FUNCTION internal.prune_empty_field_chat_conversations() FROM PUBLIC, anon, authenticated, service_role",
      "SELECT * FROM internal.prune_empty_field_chat_conversations()",
      "CREATE OR REPLACE FUNCTION public.get_field_chat_daily_usage",
      "PERFORM internal.require_service_role()",
      "GRANT EXECUTE ON FUNCTION public.get_field_chat_daily_usage(UUID) TO service_role",
      "'public.get_field_chat_daily_usage(uuid)'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("latest Field Chat reservation consumes the durable counter atomically", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));
  const reserveStart = sql.indexOf(
    "CREATE FUNCTION public.reserve_field_chat_send",
  );
  const reserveEnd = sql.indexOf(
    "COMMENT ON FUNCTION public.reserve_field_chat_send",
    reserveStart,
  );
  const reserve = sql.slice(reserveStart, reserveEnd);

  for (
    const fragment of [
      "FROM internal.field_chat_daily_admissions AS admission",
      "IF existing_message IS NOT NULL THEN",
      "SELECT resolved_conversation_id, existing_message, TRUE, daily_count",
      "FROM public.users AS profile WHERE profile.id = p_user_id FOR KEY SHARE",
      "'merian:field-chat:subject:' || p_subject_type || ':' || p_subject_id::TEXT || ':user:' || p_user_id::TEXT",
      "INSERT INTO internal.field_chat_daily_admissions AS admission",
      "ON CONFLICT (user_id, admission_day) DO UPDATE",
      "WHERE admission.admitted_count < daily_send_limit",
      "IF daily_count IS NULL THEN RAISE EXCEPTION 'field_chat_daily_limit_reached'",
      "SELECT resolved_conversation_id, inserted_message, FALSE, daily_count",
    ]
  ) {
    assertStringIncludes(reserve, fragment);
  }

  assert(
    !reserve.includes("COUNT(*)::INTEGER FROM public.insight_chat_messages"),
    "The effective admission function must not derive capacity from deletable messages.",
  );
  assert(
    reserve.indexOf("IF existing_message IS NOT NULL THEN") <
      reserve.indexOf("INSERT INTO internal.field_chat_daily_admissions"),
    "An exact replay must return before admission accounting is consumed.",
  );
  assert(
    reserve.indexOf("FROM public.users AS profile") <
      reserve.indexOf("'merian:field-chat:user:' || p_user_id::TEXT"),
    "Admission must take its parent-user key lock before the shared merge lock namespace.",
  );
  assert(
    reserve.indexOf("INSERT INTO internal.field_chat_daily_admissions") <
      reserve.indexOf("INSERT INTO public.insight_chat_conversations"),
    "A daily slot must be consumed in the same transaction before first-conversation creation.",
  );
});

Deno.test("Field Chat cutover is explicitly activated and exact-replay first", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));
  for (
    const fragment of [
      "CREATE TABLE internal.field_chat_admission_cutover",
      "activated_at IS NOT NULL AND activated_candidate_sha IS NOT NULL AND activated_migration_sha256 IS NOT NULL AND activated_explore_bundle_sha256 IS NOT NULL AND activated_insight_bundle_sha256 IS NOT NULL AND activated_species_dictionary_bundle_sha256 IS NOT NULL",
      "pg_catalog.DATE_TRUNC('day', cutover.database_now, 'UTC') + INTERVAL '1 day'",
      "CREATE OR REPLACE FUNCTION internal.assert_field_chat_admission_open()",
      "IF cutover_activated_at IS NULL OR pg_catalog.CLOCK_TIMESTAMP() < cutover_not_before THEN",
      "RAISE EXCEPTION 'field_chat_admission_cutover_pending'",
      "CREATE TRIGGER insight_chat_conversation_cutover_guard",
      "CREATE TRIGGER explore_post_chat_conversation_cutover_guard",
      "CREATE TRIGGER species_dictionary_chat_conversation_cutover_guard",
      "REVOKE INSERT ON TABLE public.insight_chat_conversations, public.explore_post_chat_conversations, public.species_dictionary_chat_conversations FROM PUBLIC, anon, authenticated, service_role",
      "CREATE OR REPLACE FUNCTION public.get_field_chat_admission_cutover_status()",
      "GRANT EXECUTE ON FUNCTION public.get_field_chat_admission_cutover_status() TO service_role",
      "WHEN observed_now < cutover.not_before_utc THEN 'pending' WHEN cutover.activated_at IS NULL THEN 'ready' ELSE 'active'",
      "CREATE OR REPLACE FUNCTION public.activate_field_chat_admission_cutover",
      "RAISE EXCEPTION 'field_chat_admission_cutover_not_ready'",
      "activated_candidate_sha = p_candidate_sha",
      "activated_migration_sha256 = p_migration_sha256",
      "activated_explore_bundle_sha256 = p_explore_bundle_sha256",
      "activated_insight_bundle_sha256 = p_insight_bundle_sha256",
      "activated_species_dictionary_bundle_sha256 = p_species_dictionary_bundle_sha256",
      "GRANT EXECUTE ON FUNCTION public.activate_field_chat_admission_cutover( TEXT, TEXT, TEXT, TEXT, TEXT ) TO service_role",
      "'public.activate_field_chat_admission_cutover(text,text,text,text,text)'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  const replay = sql.indexOf("IF existing_message IS NOT NULL THEN");
  const gate = sql.indexOf(
    "PERFORM internal.assert_field_chat_admission_open()",
    replay,
  );
  const ledger = sql.indexOf(
    "INSERT INTO internal.field_chat_daily_admissions AS admission",
    gate,
  );
  assert(
    replay >= 0 && gate > replay && ledger > gate,
    "Exact replay must precede the cutover check, which must precede every novel ledger write.",
  );
  assert(
    sql.indexOf("REVOKE INSERT ON TABLE public.insight_chat_conversations") <
      sql.indexOf(
        "CREATE OR REPLACE FUNCTION internal.prune_empty_field_chat_conversations()",
      ),
    "Direct conversation creation must be revoked before cleanup can release old writers.",
  );
  assert(
    sql.indexOf("LOCK TABLE public.insight_chat_conversations") <
        sql.indexOf(
          "DELETE FROM public.insight_chat_conversations AS conversation WHERE NOT EXISTS",
        ) &&
      sql.indexOf(
          "DELETE FROM public.species_dictionary_chat_conversations AS conversation WHERE NOT EXISTS",
        ) <
        sql.indexOf(
          "SELECT * FROM internal.prune_empty_field_chat_conversations()",
        ) &&
      sql.indexOf(
          "SELECT * FROM internal.prune_empty_field_chat_conversations()",
        ) <
        sql.indexOf("WITH utc_window AS"),
    "All six Field Chat tables must be locked while hidden empty threads are removed and retained messages are seeded.",
  );
});

Deno.test("every corrected Field Chat bundle exposes its content identity", async () => {
  const shared = await Deno.readTextFile(sharedReservationUrl);
  assertStringIncludes(
    shared,
    '"X-Merian-Field-Chat-Contract"',
  );
  assertStringIncludes(
    shared,
    'FIELD_CHAT_DEPLOYMENT_CONTRACT_VERSION = "atomic-admission-v1"',
  );
  assertStringIncludes(shared, '"X-Merian-Field-Chat-Bundle-SHA256"');
  assertStringIncludes(shared, "FIELD_CHAT_BUNDLE_SHA256[functionName]");
  for (const routeUrl of fieldChatRouteUrls) {
    assertStringIncludes(
      await Deno.readTextFile(routeUrl),
      "fieldChatDeploymentContractHeaders",
      `${routeUrl.pathname} must expose its content identity before cutover activation.`,
    );
  }
});

Deno.test("Ghost merge conservatively coalesces Field Chat daily admissions", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));
  for (
    const fragment of [
      "'internal', 'field_chat_daily_admissions', 'user_id', 'public', 'users', 'id', 'handler_then_reparent'",
      "'field_chat_daily_admissions'",
      "ghost_merge_field_chat_allowlist_source_drift",
      "SELECT internal.assert_ghost_profile_merge_reference_policy_coverage()",
      "CREATE OR REPLACE FUNCTION internal.merge_ghost_chat_conversations",
      "'merian:field-chat:user:' || LEAST(p_ghost_user_id, p_target_user_id)::TEXT",
      "'merian:field-chat:user:' || GREATEST(p_ghost_user_id, p_target_user_id)::TEXT",
      "target_admission.admitted_count + EXCLUDED.admitted_count",
      "DELETE FROM internal.field_chat_daily_admissions AS ghost_admission WHERE ghost_admission.user_id = p_ghost_user_id",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
  assert(
    sql.indexOf(
      "'merian:field-chat:user:' || LEAST(p_ghost_user_id, p_target_user_id)::TEXT",
    ) < sql.indexOf(
      "INSERT INTO internal.field_chat_daily_admissions AS target_admission",
    ),
    "Ghost merge must serialize both Field Chat users before moving counters.",
  );
});

Deno.test("PostgreSQL fixtures preserve allowance across every conversation cascade", async () => {
  const reservationFixture = compact(
    await Deno.readTextFile(reservationFixtureUrl),
  );
  const dictionaryFixture = compact(
    await Deno.readTextFile(dictionaryFixtureUrl),
  );
  for (
    const fragment of [
      "DELETE FROM public.insight_chat_conversations",
      "DELETE FROM public.explore_post_chat_conversations",
      "DELETE FROM public.species_dictionary_chat_conversations",
      "'Insight reserve-delete-fresh-reserve consumes two durable admissions'",
      "'Explore reserve-delete-fresh-reserve consumes two more durable admissions'",
      "'Dictionary reserve-delete-fresh-reserve consumes two more durable admissions'",
      "'Dictionary quota denial creates neither a hidden conversation nor a user message'",
      "'field_chat_daily_limit_reached'",
    ]
  ) {
    assertStringIncludes(reservationFixture, fragment);
  }
  for (
    const fragment of [
      "public.get_field_chat_daily_usage",
      "'account merge conservatively sums both daily admission histories'",
      "'dictionary content deletion does not restore daily admission capacity'",
    ]
  ) {
    assertStringIncludes(dictionaryFixture, fragment);
  }
});
