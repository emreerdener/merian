import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260728035237_harden_dwca_downloads_and_scan_finalization.sql",
    import.meta.url,
  ),
);
const postgrestReloadMigration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260728144336_reload_postgrest_after_health_routines.sql",
    import.meta.url,
  ),
);
const downloadAndFinalizationCatalog = await Deno.readTextFile(
  new URL(
    "../../tests/dwca_download_and_scan_finalization_security.sql",
    import.meta.url,
  ),
);
const exportCatalog = await Deno.readTextFile(
  new URL("../../tests/export_dwca_security.sql", import.meta.url),
);
const exportSnapshotCatalog = await Deno.readTextFile(
  new URL("../../tests/export_dwca_snapshot_security.sql", import.meta.url),
);
const speciesCountCatalog = await Deno.readTextFile(
  new URL("../../tests/species_count_trigger_security.sql", import.meta.url),
);
const replayDb = await Deno.readTextFile(
  new URL("../replay-scan-ingestion/db.ts", import.meta.url),
);
const reconciliationDb = await Deno.readTextFile(
  new URL("../reconcile-scan-media-assets/db.ts", import.meta.url),
);
const compatibilityIngestion = await Deno.readTextFile(
  new URL("../_shared/scanIngestionCompatibility.ts", import.meta.url),
);
const audioSpec = await Deno.readTextFile(
  new URL("../audio-spec/index.ts", import.meta.url),
);
const identify = await Deno.readTextFile(
  new URL("../identify/index.ts", import.meta.url),
);
const identifyDescribe = await Deno.readTextFile(
  new URL("../identify-describe/index.ts", import.meta.url),
);
const deleteScan = await Deno.readTextFile(
  new URL("../delete-scan/index.ts", import.meta.url),
);
const deleteScanDb = await Deno.readTextFile(
  new URL("../delete-scan/db.ts", import.meta.url),
);
const scanDeletionWorker = await Deno.readTextFile(
  new URL("../reconcile-scan-deletions/worker.ts", import.meta.url),
);
const scanMediaHealth = await Deno.readTextFile(
  new URL("../scan-media-health/health.ts", import.meta.url),
);
const aws = await Deno.readTextFile(
  new URL("../_shared/aws.ts", import.meta.url),
);
const autoPurgeNonBio = await Deno.readTextFile(
  new URL("../auto-purge-nonbio/index.ts", import.meta.url),
);
const autoPurgeNonBioDb = await Deno.readTextFile(
  new URL("../auto-purge-nonbio/db.ts", import.meta.url),
);

for (
  const sqlExpression of [
    "COALESCE",
    "GREATEST",
    "LEAST",
    "NULLIF",
    "EXTRACT",
  ]
) {
  assertEquals(
    migration.includes(`pg_catalog.${sqlExpression}(`),
    false,
    `${sqlExpression} is SQL grammar, not a schema-callable pg_catalog routine.`,
  );
}

function routineBody(name: string, nextName: string): string {
  const start = migration.indexOf(
    `CREATE OR REPLACE FUNCTION ${name}`,
  );
  const end = migration.indexOf(
    `CREATE OR REPLACE FUNCTION ${nextName}`,
    start + 1,
  );
  assert(start >= 0 && end > start, `${name} must precede ${nextName}.`);
  return migration.slice(start, end);
}

Deno.test("scan deletion durably fences a UUID before external erasure", () => {
  const requestDeletion = routineBody(
    "public.request_scan_deletion",
    "public.complete_scan_deletion",
  );
  const completeDeletion = routineBody(
    "public.complete_scan_deletion",
    "public.request_nonbiological_scan_retention_deletions",
  );
  const retentionDeletion = routineBody(
    "public.request_nonbiological_scan_retention_deletions",
    "public.claim_scan_deletion_jobs",
  );
  const claimDeletion = routineBody(
    "public.claim_scan_deletion_jobs",
    "public.release_scan_deletion_job",
  );
  const releaseDeletion = routineBody(
    "public.release_scan_deletion_job",
    "public.get_scan_deletion_health",
  );
  const deletionHealth = routineBody(
    "public.get_scan_deletion_health",
    "public.claim_scan_ingestion_job",
  );

  assertStringIncludes(
    migration,
    "CREATE TABLE internal.scan_deletion_tombstones",
  );
  assertStringIncludes(
    migration,
    "ALTER TABLE internal.scan_deletion_tombstones ENABLE ROW LEVEL SECURITY",
  );
  assertStringIncludes(
    migration,
    "REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER",
  );
  assertStringIncludes(
    migration,
    "GRANT UPDATE (\n    custom_tags,",
  );
  assertStringIncludes(
    migration,
    "CREATE OR REPLACE FUNCTION public.update_owned_scan_custom_tags(",
  );
  assertStringIncludes(
    migration,
    "CREATE OR REPLACE FUNCTION public.update_owned_scan_identification_review(",
  );
  assertStringIncludes(
    migration,
    "scans_scan_media_video_urls_bounded_check",
  );
  assertStringIncludes(
    migration,
    "scans_scan_media_audio_urls_bounded_check",
  );
  assertStringIncludes(migration, "scans_custom_tags_bounded_check");
  assertStringIncludes(
    migration,
    "CREATE TRIGGER reject_deleted_scan_generation_mutation",
  );
  assertStringIncludes(
    migration,
    "CREATE TRIGGER record_deleted_scan_generation",
  );
  assertStringIncludes(
    migration,
    "CREATE TRIGGER unlink_deleted_user_scan_tombstones",
  );
  for (
    const body of [
      requestDeletion,
      completeDeletion,
      retentionDeletion,
      claimDeletion,
      releaseDeletion,
      deletionHealth,
    ]
  ) {
    assertStringIncludes(body, "PERFORM internal.require_service_role()");
    assertStringIncludes(body, "SET search_path = ''");
  }
  for (const body of [requestDeletion, completeDeletion]) {
    assertStringIncludes(body, "PG_ADVISORY_XACT_LOCK");
    assertStringIncludes(body, "HASHTEXTEXTENDED(");
  }
  assertStringIncludes(retentionDeletion, "PG_ADVISORY_XACT_LOCK");
  assertStringIncludes(retentionDeletion, "HASHTEXTEXTENDED(");
  assertStringIncludes(retentionDeletion, "WITH candidates AS MATERIALIZED");
  assertStringIncludes(retentionDeletion, "FOR UPDATE");
  assertStringIncludes(
    retentionDeletion,
    "public.request_scan_deletion(",
  );
  assertStringIncludes(
    retentionDeletion,
    "scans.is_biological_subject IS FALSE",
  );
  assertStringIncludes(retentionDeletion, "scans.is_tombstoned IS FALSE");
  assertStringIncludes(
    retentionDeletion,
    "<> '00000000-0000-0000-0000-000000000000'::UUID",
  );
  assertStringIncludes(
    retentionDeletion,
    "pg_catalog.MAKE_INTERVAL(days => 30)",
  );
  assertStringIncludes(requestDeletion, "RETURN 'already_deleted'");
  assertStringIncludes(
    requestDeletion,
    "terminal_reason_code = 'user_deleted'",
  );
  assertStringIncludes(completeDeletion, "DELETE FROM public.scans");
  assertStringIncludes(
    migration,
    "REVOKE ALL ON FUNCTION public.request_scan_deletion(UUID, UUID)",
  );
  assertStringIncludes(
    migration,
    "REVOKE ALL ON FUNCTION public.complete_scan_deletion(UUID, UUID)",
  );
  assertStringIncludes(
    migration,
    "public.request_nonbiological_scan_retention_deletions(INTEGER)",
  );
  assertStringIncludes(claimDeletion, "FOR UPDATE SKIP LOCKED");
  assertStringIncludes(claimDeletion, "tombstones.next_attempt_at");
  assertStringIncludes(
    releaseDeletion,
    "tombstones.claim_token = p_claim_token",
  );
  assertStringIncludes(deletionHealth, "oldest_pending_age_seconds");
  assertStringIncludes(
    migration,
    "'reconcile_scan_deletions_every_five_minutes'",
  );
  assertStringIncludes(
    migration,
    "'/functions/v1/reconcile-scan-deletions'",
  );
  assertStringIncludes(scanDeletionWorker, "RUNTIME_BUDGET_MS = 40_000");
  assertStringIncludes(scanDeletionWorker, "DELETE_CONCURRENCY = 4");
  assertStringIncludes(
    scanMediaHealth,
    '"scan_deletion_cleanup_backlog"',
  );
  assertStringIncludes(deleteScanDb, ".maybeSingle()");
  assertEquals(
    deleteScan.indexOf("requestScanDeletion(") <
      deleteScan.indexOf("fetchScanRecord("),
    true,
  );
  assertEquals(
    deleteScan.indexOf("fetchScanRecord(") <
      deleteScan.indexOf("deleteScanMediaR2Objects("),
    true,
  );
  assertStringIncludes(
    deleteScan,
    "deleteScanMediaR2Objects(mediaUrls, user.id, r2Config)",
  );
  assertStringIncludes(aws, "isOwnedScanMediaR2Url(url, ownerUserId)");
  assertStringIncludes(autoPurgeNonBio, "RUNTIME_BUDGET_MS = 40_000");
  assertStringIncludes(
    autoPurgeNonBio,
    "requestNonBiologicalScanRetentionDeletions(",
  );
  assertStringIncludes(
    autoPurgeNonBioDb,
    '"request_nonbiological_scan_retention_deletions"',
  );
  assertEquals(autoPurgeNonBio.includes("deleteScanMediaR2Objects"), false);
  assertEquals(autoPurgeNonBioDb.includes('.from("scans")'), false);
  assertEquals(autoPurgeNonBioDb.includes(".delete()"), false);
  assertEquals(
    deleteScan.indexOf("deleteScanMediaR2Objects(") <
      deleteScan.indexOf("completeScanDeletion("),
    true,
  );
  assertEquals(deleteScanDb.includes('.from("scans")\n    .delete()'), false);
});

Deno.test("scan claim and recovery share one durable generation lock", () => {
  const compatibilityClaim = routineBody(
    "public.claim_scan_ingestion_job",
    "public.begin_scan_ingestion",
  );
  const begin = routineBody(
    "public.begin_scan_ingestion",
    "public.recover_missing_owned_scan",
  );
  const recovery = routineBody(
    "public.recover_missing_owned_scan",
    "public.complete_scan_ingestion_finalization",
  );

  for (const body of [compatibilityClaim, begin, recovery]) {
    assertStringIncludes(body, "PERFORM internal.require_service_role()");
    assertStringIncludes(body, "SET search_path = ''");
    assertStringIncludes(body, "PG_ADVISORY_XACT_LOCK");
    assertStringIncludes(body, "HASHTEXTEXTENDED(");
    assertStringIncludes(body, "0::BIGINT");
    assertStringIncludes(body, "'merian-scan-ingestion:'");
  }
  assertEquals(migration.includes("HASHTEXTENDED("), false);
  assertStringIncludes(
    compatibilityClaim,
    "WHEN existing_job.status = 'complete'",
  );
  assertStringIncludes(begin, "'already_complete',");
  assertStringIncludes(recovery, "terminal_reason_code = 'replay_exhausted'");
  assertStringIncludes(
    recovery,
    "IF NOT FOUND THEN\n        RETURN 'deferred'",
  );
  assertStringIncludes(recovery, "RETURN 'deferred'");
  assertStringIncludes(recovery, "RETURN 'deleted'");
  assertStringIncludes(recovery, "'client_recovery_complete'");
  assertStringIncludes(
    recovery,
    "recovered.geoprivacy::public.geoprivacy_enum",
  );
  assertStringIncludes(
    recovery,
    "recovered.ecology_type::public.ecology_type_enum",
  );
  assertStringIncludes(
    recovery,
    "recovered.user_review_state::public.user_review_state",
  );
  assertEquals(
    recovery.indexOf("INSERT INTO public.scans") <
      recovery.indexOf("INSERT INTO public.scan_ingestion_jobs"),
    true,
  );
});

Deno.test("media finalization is one transaction and marks the ledger complete last", () => {
  const finalization = routineBody(
    "public.complete_scan_ingestion_finalization",
    "internal.lock_dwca_export_generation",
  );

  for (
    const expected of [
      "scan_media_promotion_incomplete",
      "scan_media_deletion_incomplete",
      "scan_media_manifest_incomplete",
      "PERFORM public.refresh_scan_media_assets(p_scan_id)",
      "canonical_scan_media_incomplete",
      "SET status = 'complete'",
      "stage = 'media_finalization_complete'",
      "merian.scan_ingestion_completion_fence",
    ]
  ) {
    assertStringIncludes(finalization, expected);
  }
  assertEquals(
    finalization.indexOf("PERFORM public.refresh_scan_media_assets") <
      finalization.indexOf("stage = 'media_finalization_complete'"),
    true,
  );
  for (const alternateCompletionPath of [replayDb, reconciliationDb]) {
    assertStringIncludes(
      alternateCompletionPath,
      '"complete_scan_ingestion_finalization"',
    );
    assertEquals(
      alternateCompletionPath.includes('status: "complete"'),
      false,
    );
  }
  assertStringIncludes(
    compatibilityIngestion,
    "completeScanIngestionFinalization(",
  );
  assertStringIncludes(
    migration,
    "CREATE TRIGGER enforce_scan_ingestion_completion_fence",
  );
  for (
    const marker of [
      "internal.ai_usage_reparenting",
      "internal.ai_usage_reparent_source",
      "internal.ai_usage_reparent_target",
    ]
  ) {
    assertStringIncludes(migration, marker);
  }
  assertStringIncludes(
    migration,
    "scan_ingestion_completion_requires_finalization",
  );
  assertStringIncludes(compatibilityIngestion, "beginScanIngestion(");
  assertEquals(
    compatibilityIngestion.includes('mark("complete"'),
    false,
  );
  for (const compatibilityRoute of [identify, identifyDescribe, audioSpec]) {
    assertEquals(
      compatibilityRoute.indexOf(
        "createCompatibilityScanIngestionLedger(",
      ) < compatibilityRoute.lastIndexOf("_genAI.models.generateContent("),
      true,
      "Compatibility generation ownership must be durable before provider work.",
    );
  }
  assertStringIncludes(audioSpec, "await deleteR2ObjectIfPresent(");
  assertEquals(
    audioSpec.indexOf("await deleteR2ObjectIfPresent(") <
      audioSpec.indexOf("await compatibilityLedger.markComplete("),
    true,
  );
});

Deno.test("DwCA grants store only token hashes and revalidate privacy per download", () => {
  const authorization = routineBody(
    "public.authorize_dwca_archive_download",
    "public.claim_dwca_archive_cleanup_jobs",
  );
  for (
    const expected of [
      "CREATE TABLE internal.export_download_grants",
      "token_sha256 TEXT NOT NULL UNIQUE",
      "CREATE TABLE internal.export_download_rate_windows",
      "stage_prepared_export_archive_with_download_grant",
      "pg_catalog.SHA256",
      "internal.dwca_export_source_is_current",
      "'rate_limited'",
      "'not_ready'",
      "'authorized'",
      "internal.enqueue_dwca_archive_cleanup",
    ]
  ) {
    assertStringIncludes(migration, expected);
  }
  assertStringIncludes(
    authorization,
    "source_current := internal.dwca_export_source_is_current",
  );
  assertStringIncludes(
    authorization,
    "grant_row.expires_at > pg_catalog.NOW()",
  );
  const grantTable = migration.slice(
    migration.indexOf("CREATE TABLE internal.export_download_grants"),
    migration.indexOf("CREATE TABLE internal.export_archive_cleanup_jobs"),
  );
  assertEquals(grantTable.includes("download_token TEXT"), false);
  for (
    const expected of [
      "internal.revoke_completed_dwca_exports_for_scan",
      "internal.revoke_completed_dwca_exports_for_species",
      "CREATE TRIGGER revoke_completed_dwca_exports_for_scan",
      "CREATE TRIGGER revoke_completed_dwca_exports_for_species",
      "statement-snapshot race",
      "TRUNCATE already holds ACCESS EXCLUSIVE",
      "claimant performs parent-first grant revocation",
      "'source_snapshot_changed'",
    ]
  ) {
    assertStringIncludes(migration, expected);
  }
});

Deno.test("DwCA mixed-object transitions share a parent-first generation lock", () => {
  const generationLock = routineBody(
    "internal.lock_dwca_export_generation",
    "internal.enqueue_dwca_archive_cleanup",
  );
  assertStringIncludes(generationLock, "FROM public.export_jobs AS jobs");
  assertStringIncludes(generationLock, "FOR UPDATE");
  assertStringIncludes(generationLock, "PG_ADVISORY_XACT_LOCK");
  assertStringIncludes(generationLock, "HASHTEXTEXTENDED(");
  assertStringIncludes(generationLock, "0::BIGINT");
  assertStringIncludes(generationLock, "'merian-dwca-export:'");
  assertEquals(
    generationLock.indexOf("FOR UPDATE") <
      generationLock.indexOf("PG_ADVISORY_XACT_LOCK"),
    true,
  );
  for (
    const retiredTrigger of [
      "DROP TRIGGER IF EXISTS invalidate_dwca_exports_for_scan",
      "DROP TRIGGER IF EXISTS invalidate_dwca_exports_for_scan_truncate",
      "DROP TRIGGER IF EXISTS invalidate_dwca_exports_for_species",
      "DROP TRIGGER IF EXISTS invalidate_dwca_exports_for_species_truncate",
    ]
  ) {
    assertStringIncludes(migration, retiredTrigger);
  }
  assertStringIncludes(
    migration,
    "DROP FUNCTION IF EXISTS internal.invalidate_dwca_exports_for_scan()",
  );
  assertStringIncludes(
    migration,
    "DROP FUNCTION IF EXISTS internal.invalidate_dwca_exports_for_species()",
  );

  for (
    const [name, nextName] of [
      [
        "internal.enqueue_dwca_archive_cleanup",
        "public.check_dwca_export_source_fence",
      ],
      [
        "public.check_dwca_export_source_fence",
        "internal.revoke_completed_dwca_exports_for_scan",
      ],
      [
        "internal.revoke_completed_dwca_exports_for_scan",
        "internal.revoke_completed_dwca_exports_for_species",
      ],
      [
        "internal.revoke_completed_dwca_exports_for_species",
        "internal.purge_dwca_export_source_snapshot",
      ],
      [
        "internal.purge_dwca_export_source_snapshot",
        "internal.enqueue_dwca_cleanup_before_job_delete",
      ],
      [
        "public.stage_prepared_export_archive_with_download_grant",
        "public.complete_prepared_export_job_with_download_grant",
      ],
      [
        "public.complete_prepared_export_job_with_download_grant",
        "public.enqueue_dwca_archive_cleanup",
      ],
      [
        "public.authorize_dwca_archive_download",
        "public.claim_dwca_archive_cleanup_jobs",
      ],
      [
        "public.complete_dwca_archive_cleanup_job",
        "public.release_dwca_archive_cleanup_job",
      ],
    ] as const
  ) {
    assertStringIncludes(
      routineBody(name, nextName),
      "internal.lock_dwca_export_generation",
    );
  }
});

Deno.test("DwCA deletion is a leased retry outbox with independent health", () => {
  const claim = routineBody(
    "public.claim_dwca_archive_cleanup_jobs",
    "public.complete_dwca_archive_cleanup_job",
  );
  const completion = routineBody(
    "public.complete_dwca_archive_cleanup_job",
    "public.release_dwca_archive_cleanup_job",
  );
  for (
    const expected of [
      "CREATE TABLE internal.export_archive_cleanup_jobs",
      "export_archive_cleanup_due_idx",
      "export_archive_cleanup_expired_lease_idx",
      "export_download_grants_revoked_due_idx",
      "export_job_source_state_invalidated_cleanup_idx",
      "FOR UPDATE SKIP LOCKED",
      "complete_dwca_archive_cleanup_job",
      "release_dwca_archive_cleanup_job",
      "get_dwca_archive_cleanup_health",
      "reconcile_dwca_archive_cleanup_every_five_minutes",
      "'/functions/v1/reconcile-dwca-archive-cleanup'",
    ]
  ) {
    assertStringIncludes(migration, expected);
  }
  assertStringIncludes(
    completion,
    "current_archive_object_key",
  );
  assertStringIncludes(
    completion,
    "IS DISTINCT FROM cleanup_row.object_key",
  );
  assertStringIncludes(
    completion,
    "current_job_status IN ('completed', 'failed')",
  );
  assertStringIncludes(claim, "ORDER BY grants.job_id");
  assertStringIncludes(claim, "LIMIT 100");
  assertStringIncludes(claim, "source_state.invalidated_at IS NOT NULL");
  assertStringIncludes(claim, "source_state.purged_at IS NOT NULL");
  assertStringIncludes(
    claim,
    "internal.enqueue_dwca_archive_cleanup(",
  );
  assertStringIncludes(claim, "AND NOT EXISTS (");
  assertStringIncludes(migration, "unenqueued_grants AS");
  assertStringIncludes(
    migration,
    "source_state.invalidated_at,\n                source_state.purged_at",
  );
  assertStringIncludes(
    postgrestReloadMigration,
    "NOTIFY pgrst, 'reload schema';",
  );
});

Deno.test("new privileged routines are deny-by-default and narrowly ledgered", () => {
  for (
    const signature of [
      "public.claim_scan_ingestion_job(",
      "public.begin_scan_ingestion(",
      "public.recover_missing_owned_scan(UUID, UUID, JSONB)",
      "public.complete_scan_ingestion_finalization(",
      "public.authorize_dwca_archive_download(TEXT, TEXT)",
      "public.check_dwca_export_source_fence(",
      "public.claim_dwca_archive_cleanup_jobs(",
      "public.complete_dwca_archive_cleanup_job(UUID, UUID)",
      "public.release_dwca_archive_cleanup_job(",
      "public.get_dwca_archive_cleanup_health()",
    ]
  ) {
    assertStringIncludes(migration, `REVOKE ALL ON FUNCTION ${signature}`);
  }
  assertStringIncludes(
    migration,
    "INSERT INTO internal.privileged_routine_grants",
  );
});

Deno.test("fresh-catalog scan ACL uses one exact compatibility allowlist", () => {
  assertStringIncludes(
    downloadAndFinalizationCatalog,
    "allowed_authenticated_scan_update_columns CONSTANT TEXT[] := ARRAY[",
  );
  assertStringIncludes(
    downloadAndFinalizationCatalog,
    "attributes.attname::TEXT <> ALL (\n" +
      "                        allowed_authenticated_scan_update_columns",
  );
  assertStringIncludes(
    downloadAndFinalizationCatalog,
    "FROM pg_catalog.UNNEST(\n" +
      "            allowed_authenticated_scan_update_columns",
  );
  assertStringIncludes(
    downloadAndFinalizationCatalog,
    "'authenticated',\n        'public.scans',\n        'UPDATE'",
  );
});

Deno.test("fresh-catalog fixtures follow current identifiers and generations", () => {
  assertStringIncludes(
    downloadAndFinalizationCatalog,
    "authorization_result JSONB",
  );
  assertEquals(
    downloadAndFinalizationCatalog.includes("authorization JSONB"),
    false,
  );
  for (
    const catalog of [exportCatalog, exportSnapshotCatalog]
  ) {
    assertStringIncludes(
      catalog,
      "internal.revoke_completed_dwca_exports_for_scan()",
    );
    assertStringIncludes(
      catalog,
      "internal.revoke_completed_dwca_exports_for_species()",
    );
  }
  assertStringIncludes(speciesCountCatalog, "dictionary_scan_id UUID");
  assertStringIncludes(
    speciesCountCatalog,
    "VALUES (\n        dictionary_scan_id,",
  );
  assertStringIncludes(
    speciesCountCatalog,
    "WHERE scans.id = dictionary_scan_id",
  );
});
