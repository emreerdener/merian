import { assert, assertEquals, assertStringIncludes } from "@std/assert";

const migrationUrl = new URL(
  "../../migrations/20260802031840_clean_database_lint_warnings.sql",
  import.meta.url,
);

async function migrationSql(): Promise<string> {
  return (await Deno.readTextFile(migrationUrl)).replaceAll(/\s+/g, " ").trim();
}

Deno.test("database lint repair uses a guarded forward migration", async () => {
  const sql = await migrationSql();

  for (
    const fragment of [
      "ALTER FUNCTION public.sanitize_explore_location(TEXT) STABLE",
      "ALTER FUNCTION public.resolve_explore_location_label(TEXT, TEXT) STABLE",
      "ALTER FUNCTION internal.server_api_request_headers(TEXT) STABLE",
      "public.reserve_ai_quota(uuid,text,uuid,text)",
      "public.refresh_scan_visual_media_assets(uuid)",
      "public.apply_revenuecat_customer_state(text,bigint,text,text,bigint,jsonb)",
      "PG_GET_FUNCTIONDEF",
      "EXECUTE patched_sql",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assertEquals(
    sql.match(/EXECUTE patched_sql/g)?.length,
    3,
    "each reviewed PL/pgSQL warning repair must rebuild exactly one routine",
  );
  assertStringIncludes(
    sql,
    "ignored_count := internal.consume_ai_quota_counter(",
  );
  assertStringIncludes(sql, "PERFORM internal.consume_ai_quota_counter(");
  assertStringIncludes(sql, "i INTEGER;");
  assertStringIncludes(sql, "subject_index INTEGER;");
  assert(
    !/\b(?:GRANT|REVOKE)\b/i.test(sql),
    "lint repair must preserve existing routine ACLs",
  );
});
