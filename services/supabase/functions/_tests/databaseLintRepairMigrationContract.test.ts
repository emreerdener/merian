import { assert, assertEquals, assertStringIncludes } from "@std/assert";

const initialMigrationUrl = new URL(
  "../../migrations/20260802031840_clean_database_lint_warnings.sql",
  import.meta.url,
);

const remainingMigrationUrl = new URL(
  "../../migrations/20260802033853_finish_database_lint_warning_repair.sql",
  import.meta.url,
);

const speciesStatsMigrationUrl = new URL(
  "../../migrations/20260724170709_harden_species_observation_stats.sql",
  import.meta.url,
);
const dwcaSnapshotMigrationUrl = new URL(
  "../../migrations/20260728001723_repair_dwca_privacy_visibility_and_snapshot_work.sql",
  import.meta.url,
);
const scanIngestionMigrationUrl = new URL(
  "../../migrations/20260728035237_harden_dwca_downloads_and_scan_finalization.sql",
  import.meta.url,
);

async function migrationSql(migrationUrl: URL): Promise<string> {
  return (await Deno.readTextFile(migrationUrl)).replaceAll(/\s+/g, " ")
    .trim();
}

Deno.test("database lint repair uses a guarded forward migration", async () => {
  const sql = await migrationSql(initialMigrationUrl);

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

Deno.test("remaining database lint warnings use guarded repairs", async () => {
  const sql = await migrationSql(remainingMigrationUrl);
  const [speciesStatsSource, dwcaSnapshotSource, scanIngestionSource] =
    await Promise.all([
      Deno.readTextFile(speciesStatsMigrationUrl),
      Deno.readTextFile(dwcaSnapshotMigrationUrl),
      Deno.readTextFile(scanIngestionMigrationUrl),
    ]);

  for (
    const fragment of [
      "public.authorize_species_observation_stats_request(uuid,text,uuid)",
      "public.claim_species_observation_stats_population(uuid,uuid,text)",
      "public.begin_scan_ingestion(text,uuid,text,jsonb,jsonb,jsonb,text[],text,text,boolean,boolean,jsonb,integer,integer)",
      "internal.materialize_dwca_export_source_snapshot(uuid)",
      "ALTER FUNCTION internal.inline_scan_recovery_ledger_matches(",
      "PERFORM internal.consume_species_observation_stats_rate(",
      "PERFORM p_manifest_checksum, p_payload_checksum;",
      "''dwca_export_snapshot_cursor''::REFCURSOR",
      "PG_GET_FUNCTIONDEF",
      "EXECUTE patched_sql",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assertEquals(
    sql.match(/EXECUTE patched_sql/g)?.length,
    4,
    "each remaining PL/pgSQL body repair must rebuild exactly one routine",
  );
  assertStringIncludes(sql, "ignored_count INTEGER;");
  assertStringIncludes(
    sql,
    "ignored_count := internal.consume_species_observation_stats_rate(",
  );
  assertStringIncludes(speciesStatsSource, "    ignored_count INTEGER;\n");
  assertStringIncludes(
    speciesStatsSource,
    "ignored_count := internal.consume_species_observation_stats_rate(",
  );
  assertStringIncludes(
    dwcaSnapshotSource,
    "source_cursor REFCURSOR := 'dwca_export_snapshot_cursor';",
  );
  assertStringIncludes(
    scanIngestionSource,
    "BEGIN\n    PERFORM internal.require_service_role();\n",
  );
  assert(
    !/\b(?:GRANT|REVOKE)\b/i.test(sql),
    "remaining lint repairs must preserve existing routine ACLs",
  );
});
