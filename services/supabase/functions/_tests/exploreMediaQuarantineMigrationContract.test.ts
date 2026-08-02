import { assert, assertEquals, assertStringIncludes } from "@std/assert";

const enumMigrationUrl = new URL(
  "../../migrations/20260726144647_add_explore_media_quarantine_lifecycle.sql",
  import.meta.url,
);
const lifecycleMigrationUrl = new URL(
  "../../migrations/20260726144754_implement_explore_media_quarantine_state_machine.sql",
  import.meta.url,
);
const publicationContractMigrationUrl = new URL(
  "../../migrations/20260726174555_align_explore_author_publication_contract.sql",
  import.meta.url,
);
const projectionReadGrantMigrationUrl = new URL(
  "../../migrations/20260727035937_grant_authenticated_explore_projection_reads.sql",
  import.meta.url,
);
const shareStateMigrationUrl = new URL(
  "../../migrations/20260729120000_align_explore_share_state_media_health.sql",
  import.meta.url,
);
const catalogUrl = new URL(
  "../../tests/explore_media_quarantine_security.sql",
  import.meta.url,
);

function normalized(sql: string): string {
  return sql.replaceAll(/\s+/g, " ").trim();
}

Deno.test("Explore projection has explicit least-privilege source reads", async () => {
  const sql = normalized(
    await Deno.readTextFile(projectionReadGrantMigrationUrl),
  );

  assertStringIncludes(
    sql,
    "GRANT SELECT ON TABLE public.explore_posts, public.scans, public.users, public.species_dictionary, public.explore_observation_projection, public.taxon_nodes, public.explore_post_likes, public.explore_community_requests, public.explore_post_media, public.user_blocks TO authenticated",
  );
  assert(
    !sql.includes("TO anon") && !sql.includes("TO PUBLIC"),
    "Projection source-table reads must not be granted to anonymous callers.",
  );
});

Deno.test("Explore media lifecycle is reversible and independent from publication intent", async () => {
  const enumSql = normalized(await Deno.readTextFile(enumMigrationUrl));
  const sql = normalized(await Deno.readTextFile(lifecycleMigrationUrl));

  assertStringIncludes(enumSql, "ADD VALUE IF NOT EXISTS 'media_missing'");
  assertStringIncludes(enumSql, "ADD VALUE IF NOT EXISTS 'media_restored'");
  assertStringIncludes(
    sql,
    "health_status IN ('healthy', 'suspected_missing', 'missing')",
  );
  assertStringIncludes(
    sql,
    "media_health_status IN ('healthy', 'degraded', 'quarantined')",
  );
  assertStringIncludes(sql, "ep.media_health_status <> 'quarantined'");
  assertStringIncludes(sql, "post.media_health_status <> 'quarantined'");
  assertStringIncludes(
    sql,
    "FROM public.explore_projected_post_cards(self_id) AS visible_post",
  );
  assertStringIncludes(sql, "media.health_status <> 'missing'");
  assertStringIncludes(
    sql,
    "post.media_health_status IS DISTINCT FROM v_new_status",
  );
  assertStringIncludes(
    sql,
    "CREATE TABLE IF NOT EXISTS internal.explore_media_health_history",
  );
  assertStringIncludes(
    sql,
    "CREATE TRIGGER trg_restore_explore_media_health_before_insert",
  );
  assertStringIncludes(
    sql,
    "CREATE CONSTRAINT TRIGGER trg_finalize_explore_post_media_health_after_delete",
  );
  assert(
    !/\bSET\s+unshared_at\s*=/i.test(sql),
    "System media health must not overwrite the author's publication state.",
  );
});

Deno.test("Explore scan share state uses the canonical visibility boundary", async () => {
  const [sql, catalog] = await Promise.all([
    Deno.readTextFile(shareStateMigrationUrl).then(normalized),
    Deno.readTextFile(catalogUrl),
  ]);

  for (
    const fragment of [
      "SET search_path = ''",
      "post.moderated_at IS NULL",
      "post.media_health_status <> 'quarantined'",
      "media.health_status <> 'missing'",
      "state.has_live_post AND state.is_projection_eligible",
      "WHEN state.has_live_post THEN state.post_id",
      "REVOKE ALL ON FUNCTION public.get_scan_explore_share_state(UUID, UUID) FROM PUBLIC, anon, authenticated, service_role",
      "GRANT EXECUTE ON FUNCTION public.get_scan_explore_share_state(UUID, UUID) TO service_role",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
  assertStringIncludes(catalog, "SELECT extensions.plan(25)");
  assertEquals(
    catalog.match(/^SELECT extensions.(?:ok|is|throws_ok)\(/gm)?.length,
    25,
    "Explore media quarantine pgTAP plan must match its executable assertions.",
  );
});

Deno.test("Explore media quarantine requires spaced direct-origin confirmation", async () => {
  const sql = normalized(await Deno.readTextFile(lifecycleMigrationUrl));

  assert(
    !/pg_catalog\.(?:GREATEST|LEAST)\s*\(/i.test(sql),
    "GREATEST and LEAST are SQL expressions and cannot be schema-qualified.",
  );
  assertStringIncludes(
    sql,
    "media_row.missing_first_observed_at <= v_now - INTERVAL '5 minutes'",
  );
  assertStringIncludes(
    sql,
    "p_outcome NOT IN ('healthy', 'missing', 'retryable_error')",
  );
  assertStringIncludes(
    sql,
    "v_next_check := v_now + INTERVAL '15 minutes'",
  );
  assertStringIncludes(
    sql,
    "ELSE v_now + INTERVAL '24 hours'",
  );
  assertStringIncludes(
    sql,
    "p_thumbnail_http_status NOT BETWEEN 200 AND 399",
  );
  assertStringIncludes(
    sql,
    "FOR UPDATE OF media SKIP LOCKED",
  );
  assertStringIncludes(
    sql,
    "ON CONFLICT ON CONSTRAINT explore_media_health_check_claims_pkey DO UPDATE",
  );
});

Deno.test("Explore media workers and owner recovery queue are explicitly authorized", async () => {
  const sql = normalized(await Deno.readTextFile(lifecycleMigrationUrl));

  for (
    const fragment of [
      "PERFORM internal.require_service_role()",
      "REVOKE ALL ON FUNCTION public.claim_explore_media_health_checks(INTEGER, INTEGER) FROM PUBLIC, anon, authenticated, service_role",
      "GRANT EXECUTE ON FUNCTION public.claim_explore_media_health_checks(INTEGER, INTEGER) TO service_role",
      "GRANT EXECUTE ON FUNCTION public.record_explore_media_health_check( UUID, UUID, TEXT, INTEGER, INTEGER ) TO service_role",
      "auth.uid() IS DISTINCT FROM self_id",
      "GRANT EXECUTE ON FUNCTION public.get_owned_explore_media_incidents(UUID) TO authenticated, service_role",
      "'public.expedite_explore_media_health_checks(text[])'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("media notifications preserve engagement and restored events stay in-app", async () => {
  const sql = normalized(await Deno.readTextFile(lifecycleMigrationUrl));

  assertStringIncludes(sql, "type IN ('media_missing', 'media_restored')");
  assertStringIncludes(
    sql,
    "n.type IN (''media_missing'', ''media_restored'')\\n' || E' OR (\\n' || E' COALESCE(ARRAY_LENGTH(s.image_storage_urls, 1), 0) > 0",
  );
  assertStringIncludes(
    sql,
    "NEW.type NOT IN (''follow'', ''media_restored'')",
  );
  assertStringIncludes(sql, "type = 'media_missing'");
  assertStringIncludes(sql, "type = 'media_restored'");
  assertStringIncludes(
    sql,
    "WHEN post_media.url = p_source_url THEN ''healthy''",
  );
  assertStringIncludes(
    sql,
    "WHEN post_media.url = p_source_url\\n' || E' AND post_media.health_status = ''missing''",
  );
  assertStringIncludes(
    sql,
    "WHEN post_media.thumbnail_url = p_source_url THEN 200",
  );
});

Deno.test("Explore author publication totals share one public projection and keep owner recovery separate", async () => {
  const sql = normalized(
    await Deno.readTextFile(publicationContractMigrationUrl),
  );

  assertStringIncludes(
    sql,
    "FROM public.explore_projected_post_cards(self_id) AS visible_post",
  );
  assertStringIncludes(
    sql,
    "visible_post.author_user_id = target_author_user_id",
  );
  assertStringIncludes(
    sql,
    "self_id IS DISTINCT FROM target_author_user_id",
  );
  assertStringIncludes(
    sql,
    "INTO[[:space:]]+visible_post_count[[:space:]]+[^;]*;",
  );
  assertStringIncludes(
    sql,
    "REGEXP_REPLACE( function_sql, count_statement_pattern, canonical_count_fragment, 'i' )",
  );
  assert(
    !sql.includes("original_count_fragment"),
    "The migration must not depend on byte-identical pg_get_functiondef output.",
  );
  assertStringIncludes(
    sql,
    "CREATE OR REPLACE FUNCTION public.get_owned_explore_publication_summary",
  );
  assertStringIncludes(
    sql,
    "IF auth.uid() IS NULL THEN PERFORM internal.require_service_role()",
  );
  assertStringIncludes(
    sql,
    "ELSIF auth.uid() IS DISTINCT FROM self_id",
  );
  assertStringIncludes(
    sql,
    "GRANT EXECUTE ON FUNCTION public.get_owned_explore_publication_summary(UUID) TO authenticated, service_role",
  );
  assertStringIncludes(
    sql,
    "CREATE OR REPLACE FUNCTION public.get_explore_publication_health_summary()",
  );
  assertStringIncludes(
    sql,
    "COUNT(DISTINCT user_id) FILTER ( WHERE media_health_status <> 'healthy' )",
  );
  assertStringIncludes(
    sql,
    "GRANT EXECUTE ON FUNCTION public.get_explore_publication_health_summary() TO service_role",
  );
});
