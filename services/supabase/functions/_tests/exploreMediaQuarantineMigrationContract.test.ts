import {
  assert,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";

const enumMigrationUrl = new URL(
  "../../migrations/20260726144647_add_explore_media_quarantine_lifecycle.sql",
  import.meta.url,
);
const lifecycleMigrationUrl = new URL(
  "../../migrations/20260726144754_implement_explore_media_quarantine_state_machine.sql",
  import.meta.url,
);

function normalized(sql: string): string {
  return sql.replaceAll(/\s+/g, " ").trim();
}

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
