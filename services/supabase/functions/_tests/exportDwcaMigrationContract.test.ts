import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

const migrationUrl = new URL(
  "../../migrations/20260724230849_harden_dwca_export_jobs.sql",
  import.meta.url,
);
const migration = await Deno.readTextFile(migrationUrl);
const boundedMigrationUrl = new URL(
  "../../migrations/20260725052339_bound_dwca_export_work.sql",
  import.meta.url,
);
const boundedMigration = await Deno.readTextFile(boundedMigrationUrl);
const sourceBoundsMigrationUrl = new URL(
  "../../migrations/20260725175312_bound_dwca_export_source_bytes.sql",
  import.meta.url,
);
const sourceBoundsInstallMigration = await Deno.readTextFile(
  sourceBoundsMigrationUrl,
);
const sourceBoundsValidationMigrationUrl = new URL(
  "../../migrations/20260725180321_validate_dwca_export_source_bounds.sql",
  import.meta.url,
);
const sourceBoundsValidationMigration = await Deno.readTextFile(
  sourceBoundsValidationMigrationUrl,
);
const sourceBoundsMigrations = [
  sourceBoundsInstallMigration,
  sourceBoundsValidationMigration,
].join("\n");
const sourceSnapshotMigrationUrl = new URL(
  "../../migrations/20260726025103_snapshot_dwca_export_sources.sql",
  import.meta.url,
);
const sourceSnapshotMigration = await Deno.readTextFile(
  sourceSnapshotMigrationUrl,
);
const throughputMigrationUrl = new URL(
  "../../migrations/20260726230837_scale_dwca_export_continuations.sql",
  import.meta.url,
);
const throughputMigration = await Deno.readTextFile(
  throughputMigrationUrl,
);
const crcMigrationUrl = new URL(
  "../../migrations/20260726235158_amortize_dwca_archive_crc.sql",
  import.meta.url,
);
const crcMigration = await Deno.readTextFile(crcMigrationUrl);
const immutableRowsMigrationUrl = new URL(
  "../../migrations/20260727233841_add_public_web_explore_boundary_and_immutable_dwca_rows.sql",
  import.meta.url,
);
const immutableRowsMigration = await Deno.readTextFile(
  immutableRowsMigrationUrl,
);

Deno.test("DwC-A migration installs a private atomic claim lease", () => {
  for (
    const expected of [
      "CREATE TABLE internal.export_job_claims",
      "CREATE TABLE internal.export_worker_protocol",
      "claim_token UUID NOT NULL",
      "lease_expires_at TIMESTAMPTZ NOT NULL",
      "legacy_payload_until TIMESTAMPTZ NOT NULL",
      "CREATE OR REPLACE FUNCTION public.claim_export_job",
      "FOR UPDATE OF jobs",
      "ON CONFLICT ON CONSTRAINT export_job_claims_pkey DO UPDATE",
      "CREATE OR REPLACE FUNCTION public.renew_export_job_claim",
      "CREATE OR REPLACE FUNCTION public.stage_export_job_archive",
      "CREATE OR REPLACE FUNCTION public.complete_export_job",
      "CREATE OR REPLACE FUNCTION public.fail_export_job",
      "claims.claim_token = p_claim_token",
      "claims.lease_expires_at > pg_catalog.NOW()",
      "REVOKE ALL ON TABLE internal.export_job_claims",
      "REVOKE ALL ON TABLE internal.export_worker_protocol",
    ]
  ) {
    assertStringIncludes(migration, expected);
  }
});

Deno.test("DwC-A claim installs its fence before the processing trigger runs", () => {
  const claimStart = migration.indexOf(
    "CREATE OR REPLACE FUNCTION public.claim_export_job",
  );
  const claimEnd = migration.indexOf(
    "CREATE OR REPLACE FUNCTION public.renew_export_job_claim",
  );
  const claimBody = migration.slice(claimStart, claimEnd);
  const claimInsert = claimBody.indexOf(
    "INSERT INTO internal.export_job_claims",
  );
  const processingUpdate = claimBody.indexOf(
    "UPDATE public.export_jobs AS jobs",
  );

  assert(claimStart >= 0 && claimEnd > claimStart);
  assert(claimInsert >= 0 && processingUpdate > claimInsert);
  assertEquals(migration.includes("pg_catalog.EXISTS"), false);
  assertEquals(migration.includes("pg_catalog.COALESCE"), false);
});

Deno.test("DwC-A migration freezes canonical state behind a job-id-only worker", () => {
  assertStringIncludes(
    migration,
    "CREATE TRIGGER enforce_export_job_update",
  );
  assertStringIncludes(migration, "export_job_request_is_immutable");
  assertStringIncludes(
    migration,
    "The deployed worker reads only job_id",
  );
  assertStringIncludes(
    migration,
    "NEW.created_at <= legacy_payload_until",
  );
  assertStringIncludes(migration, "CASE NEW.failure_code");
  assertStringIncludes(
    migration,
    "Never persist provider or implementation details",
  );
  assertStringIncludes(
    migration,
    "claimed_export_job_failure_requires_rpc",
  );
  assertStringIncludes(
    migration,
    "claimed_export_job_result_requires_rpc",
  );
  assertStringIncludes(migration, "claimed_export_job_already_owned");
  assertStringIncludes(migration, "terminal_export_job_is_immutable");
  assertStringIncludes(
    migration,
    "Never recover",
  );
  assertStringIncludes(migration, "export_job_claim_required");
  assertStringIncludes(
    migration,
    "'user_id',",
  );
  assertStringIncludes(
    migration,
    'DROP POLICY IF EXISTS "Users can insert their own export jobs."',
  );
  assertStringIncludes(
    migration,
    "REVOKE INSERT ON TABLE public.export_jobs FROM anon, authenticated",
  );
});

Deno.test("DwC-A migration supports indexed keysets and versioned HMAC keys", () => {
  for (
    const expected of [
      "pseudonym_key_version SMALLINT NOT NULL DEFAULT 1",
      "idx_scans_dwca_personal_keyset",
      "ON public.scans (user_id, id)",
      "idx_scans_dwca_global_keyset",
      "ON public.scans (id)",
      "idx_export_jobs_user_recent_success",
      "public.claim_export_job(uuid,uuid)",
      "public.renew_export_job_claim(uuid,uuid)",
      "public.stage_export_job_archive(uuid,uuid,text,text)",
      "public.complete_export_job(uuid,uuid)",
      "public.fail_export_job(uuid,uuid,text)",
      "PERFORM internal.require_service_role()",
      "SET search_path = ''",
    ]
  ) {
    assertStringIncludes(migration, expected);
  }
});

Deno.test("DwC-A work is canonical, bounded, and resumable across invocations", () => {
  for (
    const expected of [
      "ADD COLUMN max_export_rows INTEGER NOT NULL DEFAULT 5000",
      "ADD COLUMN max_archive_bytes BIGINT NOT NULL DEFAULT 8388608",
      "export_job_budget_is_immutable",
      "idx_scans_dwca_personal_active_keyset",
      "idx_scans_dwca_global_active_keyset",
      "is_tombstoned = FALSE",
      "CREATE TABLE internal.export_job_work",
      "CREATE TABLE internal.export_job_chunks",
      "phase TEXT NOT NULL DEFAULT 'occurrence'",
      "occurrence_after_id UUID",
      "multimedia_after_id UUID",
      "csv_bytes BIGINT NOT NULL DEFAULT 0",
      "CREATE OR REPLACE FUNCTION public.get_due_export_job_ids",
      "CREATE OR REPLACE FUNCTION public.claim_export_job_step",
      "ON CONFLICT ON CONSTRAINT export_job_work_pkey DO NOTHING",
      "CREATE OR REPLACE FUNCTION public.advance_export_job_step",
      "p_next_after_id <= current_after_id",
      "|| '-' || p_claim_token::TEXT || '.csv'",
      "export_budget_exceeded",
      "work_row.occurrence_rows + work_row.multimedia_rows",
      "job_row.max_export_rows",
      "job_row.max_archive_bytes - 65536",
      "CREATE OR REPLACE FUNCTION public.get_export_job_chunks",
      "CREATE OR REPLACE FUNCTION public.stage_prepared_export_archive",
      "CREATE OR REPLACE FUNCTION public.complete_prepared_export_job",
      "CREATE OR REPLACE FUNCTION public.release_export_job_step",
      "resume_dwca_exports_every_minute",
      "'/functions/v1/export-dwca'",
      "PERFORM internal.require_service_role()",
      "SET search_path = ''",
    ]
  ) {
    assertStringIncludes(boundedMigration, expected);
  }

  const stepClaim = boundedMigration.slice(
    boundedMigration.indexOf(
      "CREATE OR REPLACE FUNCTION public.claim_export_job_step",
    ),
    boundedMigration.indexOf(
      "CREATE OR REPLACE FUNCTION public.advance_export_job_step",
    ),
  );
  assertStringIncludes(
    stepClaim,
    "ON CONFLICT ON CONSTRAINT export_job_work_pkey DO NOTHING",
  );
  assertEquals(
    stepClaim.includes("ON CONFLICT (job_id)"),
    false,
    "RETURNS TABLE exposes job_id as a PL/pgSQL variable, so the conflict arbiter must be unambiguous.",
  );

  assertEquals(
    boundedMigration.includes("pg_catalog.COALESCE"),
    false,
  );
  assertEquals(
    boundedMigration.includes("pg_catalog.GREATEST"),
    false,
  );
  assertEquals(
    boundedMigration.includes("pg_catalog.LEAST"),
    false,
  );
});

Deno.test("DwC-A source rows and pages are byte-bounded before Edge reads", () => {
  for (
    const expected of [
      "CREATE OR REPLACE FUNCTION internal.text_array_elements_are_bounded",
      "pg_catalog.CARDINALITY(p_values) <= p_max_cardinality",
      "pg_catalog.OCTET_LENGTH(elements.element_value)",
      "scans_dwca_image_urls_bounded_check",
      "image_storage_urls,\n                24,\n                4096",
      "scans_dwca_interactions_bounded_check",
      "ecological_interactions,\n                10,\n                2048",
      "species_dictionary_dwca_taxonomy_bounded_check",
      "pg_catalog.OCTET_LENGTH(scientific_name) <= 1024",
      "pg_catalog.OCTET_LENGTH(kingdom) <= 512",
      'pg_catalog.OCTET_LENGTH("order") <= 512',
      "pg_catalog.OCTET_LENGTH(iucn_red_list_status) <= 128",
      "VALIDATE CONSTRAINT scans_dwca_image_urls_bounded_check",
      "CREATE OR REPLACE VIEW internal.dwca_export_occurrence_source",
      "CREATE OR REPLACE VIEW internal.dwca_export_multimedia_source",
      "CREATE OR REPLACE FUNCTION public.get_dwca_export_scan_batch",
      "p_expected_phase IS NULL",
      "p_max_rows NOT BETWEEN 1 AND 100",
      "p_max_source_bytes NOT BETWEEN 1 AND 262144",
      "claims.claim_token = p_claim_token",
      "claims.lease_expires_at > pg_catalog.NOW()",
      "p_after_id IS DISTINCT FROM canonical_after_id",
      "LIMIT p_max_rows + 1",
      "candidates.scan_payload::TEXT",
      "running.running_byte_count <= p_max_source_bytes",
      "stats.candidate_count > 0",
      "PERFORM internal.require_service_role()",
      "SET search_path = ''",
      "TO service_role",
      "internal.privileged_routine_grants",
    ]
  ) {
    assertStringIncludes(sourceBoundsMigrations, expected);
  }

  assertEquals(sourceBoundsMigrations.includes(" OFFSET "), false);

  const occurrenceProjection = sourceBoundsValidationMigration.slice(
    sourceBoundsValidationMigration.indexOf(
      "CREATE OR REPLACE VIEW internal.dwca_export_occurrence_source",
    ),
    sourceBoundsValidationMigration.indexOf(
      "CREATE OR REPLACE VIEW internal.dwca_export_multimedia_source",
    ),
  );
  const multimediaProjection = sourceBoundsValidationMigration.slice(
    sourceBoundsValidationMigration.indexOf(
      "CREATE OR REPLACE VIEW internal.dwca_export_multimedia_source",
    ),
    sourceBoundsValidationMigration.indexOf("REVOKE ALL ON TABLE"),
  );
  assertEquals(occurrenceProjection.includes("image_storage_urls"), false);
  assertEquals(multimediaProjection.includes("species_dictionary"), false);
  assertEquals(
    multimediaProjection.includes("ecological_interactions"),
    false,
  );
});

Deno.test("DwC-A source constraints release the ALTER lock before validation", () => {
  assertStringIncludes(sourceBoundsInstallMigration, ") NOT VALID");
  assertEquals(
    sourceBoundsInstallMigration.includes("VALIDATE CONSTRAINT"),
    false,
  );
  assertEquals(
    sourceBoundsInstallMigration.includes(
      "CREATE OR REPLACE FUNCTION public.get_dwca_export_scan_batch",
    ),
    false,
  );

  const validation = sourceBoundsValidationMigration.indexOf(
    "VALIDATE CONSTRAINT species_dictionary_dwca_taxonomy_bounded_check",
  );
  const rpc = sourceBoundsValidationMigration.indexOf(
    "CREATE OR REPLACE FUNCTION public.get_dwca_export_scan_batch",
  );
  assert(validation >= 0 && rpc > validation);
});

Deno.test("DwC-A phases share one immutable creation-time membership snapshot", () => {
  for (
    const expected of [
      "CREATE TABLE internal.export_job_source_state",
      "CREATE TABLE internal.export_job_source_membership",
      "PRIMARY KEY (job_id, scan_id)",
      "pg_catalog.OCTET_LENGTH(eligibility_sha256) = 32",
      "CREATE OR REPLACE VIEW internal.dwca_export_current_source",
      "CREATE OR REPLACE FUNCTION internal.materialize_dwca_export_source_snapshot",
      "WITH eligible_membership AS MATERIALIZED",
      "LIMIT job_row.max_export_rows + 1",
      "extensions.digest(",
      "'sha256'",
      "CREATE TRIGGER initialize_dwca_export_source_snapshot",
      "AFTER INSERT ON public.export_jobs",
      "CREATE TRIGGER purge_dwca_export_source_snapshot",
      "DELETE FROM internal.export_job_source_membership",
      "DELETE FROM internal.export_job_chunks",
      "SET phase = 'occurrence'",
      "DROP VIEW internal.dwca_export_occurrence_source",
      "DROP VIEW internal.dwca_export_multimedia_source",
      "FROM internal.export_job_source_membership AS membership",
      "LEFT JOIN internal.dwca_export_current_source AS current_source",
      "source_revision_changed BOOLEAN",
      "current_source.eligibility_payload::TEXT",
      "IS DISTINCT FROM candidates.eligibility_sha256",
      "source_state.purged_at IS NULL",
      "PERFORM internal.require_service_role()",
      "SET search_path = ''",
      "TO service_role",
    ]
  ) {
    assertStringIncludes(sourceSnapshotMigration, expected);
  }

  const pageRpc = sourceSnapshotMigration.slice(
    sourceSnapshotMigration.indexOf(
      "CREATE FUNCTION public.get_dwca_export_scan_batch",
    ),
  );
  assertEquals(pageRpc.includes("FROM public.scans"), false);
  assertEquals(
    pageRpc.includes("internal.dwca_export_occurrence_source"),
    false,
  );
  assertEquals(
    pageRpc.includes("internal.dwca_export_multimedia_source"),
    false,
  );
  assertEquals(sourceSnapshotMigration.includes(" OFFSET "), false);
  assertEquals(
    sourceSnapshotMigration.includes("pg_catalog.COALESCE"),
    false,
  );
});

Deno.test("DwC-A source snapshots materialize bounded immutable authoritative DTO rows", () => {
  for (
    const expected of [
      "CREATE TABLE internal.export_job_source_rows",
      "occurrence_payload JSONB NOT NULL",
      "occurrence_byte_count INTEGER NOT NULL",
      "multimedia_payload JSONB NOT NULL",
      "multimedia_byte_count INTEGER NOT NULL",
      "occurrence_byte_count BETWEEN 1 AND 262144",
      "multimedia_byte_count BETWEEN 1 AND 262144",
      "ALTER TABLE internal.export_job_source_rows ENABLE ROW LEVEL SECURITY",
      "REVOKE ALL ON TABLE internal.export_job_source_rows",
      "ALTER COLUMN snapshot_version SET DEFAULT 2",
      "ADD COLUMN source_byte_count BIGINT",
      "ADD COLUMN max_source_bytes BIGINT",
      "max_source_bytes BETWEEN 4194304 AND 67108864",
      "COALESCE(scans.confirmed_species_id, scans.species_id)",
      "CREATE VIEW internal.dwca_export_snapshot_source",
      "personal_eligibility_payload",
      "global_eligibility_payload",
      "coordinate_protection_required",
      "'critically_endangered'",
      "WITH eligible_membership AS MATERIALIZED",
      "projected_rows AS MATERIALIZED",
      "snapshot_rows AS MATERIALIZED",
      "source.occurrence_payload",
      "job_row.include_precise_coordinates",
      "- ARRAY['gps_lat_exact', 'gps_long_exact']::TEXT[]",
      "source.multimedia_payload",
      "stats.source_byte_count > budget.max_source_bytes",
      "INSERT INTO internal.export_job_source_rows",
      "DELETE FROM internal.export_job_source_rows",
      "FROM internal.export_job_source_rows AS source_rows",
      "source_rows.occurrence_payload",
      "source_rows.multimedia_payload",
      "source_rows.eligibility_sha256",
      "current_source.personal_eligibility_payload",
      "current_source.global_eligibility_payload",
      "source_state.snapshot_version = 2",
      "PERFORM internal.require_service_role()",
      "SET search_path = ''",
      "TO service_role",
      "RESET lock_timeout",
      "RESET statement_timeout",
    ]
  ) {
    assertStringIncludes(immutableRowsMigration, expected);
  }

  const snapshotProjection = immutableRowsMigration.slice(
    immutableRowsMigration.indexOf(
      "CREATE VIEW internal.dwca_export_snapshot_source",
    ),
    immutableRowsMigration.indexOf(
      "CREATE OR REPLACE FUNCTION internal.materialize_dwca_export_source_snapshot",
    ),
  );
  assertStringIncludes(
    snapshotProjection,
    "ON species.id = COALESCE(\n        scans.confirmed_species_id,\n        scans.species_id",
  );
  const personalEligibility = snapshotProjection.slice(
    snapshotProjection.indexOf(
      "pg_catalog.JSONB_BUILD_OBJECT(\n        'user_id'",
    ),
    snapshotProjection.indexOf(
      ") AS personal_eligibility_payload",
    ),
  );
  assertStringIncludes(
    personalEligibility,
    "'coordinate_protection_required'",
  );
  assertEquals(personalEligibility.includes("'effective_species_id'"), false);
  assertEquals(personalEligibility.includes("'iucn_red_list_status'"), false);
  const globalEligibility = snapshotProjection.slice(
    snapshotProjection.indexOf(
      ") AS personal_eligibility_payload",
    ),
    snapshotProjection.indexOf(
      ") AS global_eligibility_payload",
    ),
  );
  assertStringIncludes(
    globalEligibility,
    "'coordinate_protection_required'",
  );
  assertEquals(globalEligibility.includes("'effective_species_id'"), false);
  assertEquals(globalEligibility.includes("'iucn_red_list_status'"), false);

  const pageRpc = immutableRowsMigration.slice(
    immutableRowsMigration.indexOf(
      "CREATE OR REPLACE FUNCTION public.get_dwca_export_scan_batch",
    ),
  );
  assertEquals(
    pageRpc.includes("current_source.occurrence_payload"),
    false,
  );
  assertEquals(
    pageRpc.includes("current_source.multimedia_payload"),
    false,
  );
  assertEquals(
    pageRpc.includes("candidates.immutable_payload"),
    true,
  );
  assertEquals(immutableRowsMigration.includes(" OFFSET "), false);
  assertEquals(immutableRowsMigration.includes("GRANT SELECT"), false);
  assertEquals(immutableRowsMigration.includes("pg_catalog.LEAST"), false);
  assertEquals(immutableRowsMigration.includes("pg_catalog.COALESCE"), false);
});

Deno.test("DwC-A continuation dispatch has fair backlog telemetry and timeout headroom", () => {
  for (
    const expected of [
      "CREATE INDEX IF NOT EXISTS idx_export_jobs_nonterminal_created",
      "WHERE status IN ('pending', 'processing')",
      "CREATE OR REPLACE FUNCTION public.get_due_export_job_ids",
      "FROM internal.export_job_work AS work",
      "ORDER BY work.next_step_at, work.job_id",
      "REVOKE ALL ON FUNCTION public.get_due_export_job_ids(INTEGER)",
      "CREATE OR REPLACE FUNCTION public.get_dwca_export_queue_health()",
      "backlog_count BIGINT",
      "due_count BIGINT",
      "active_claim_count BIGINT",
      "expired_claim_count BIGINT",
      "oldest_due_age_seconds BIGINT",
      "PERFORM internal.require_service_role()",
      "SET search_path = ''",
      "REVOKE ALL ON FUNCTION public.get_dwca_export_queue_health()",
      "GRANT EXECUTE ON FUNCTION public.get_dwca_export_queue_health()",
      "'public.get_dwca_export_queue_health()'",
      "'resume_dwca_exports_every_minute'",
      "timeout_milliseconds := 120000",
      "NOTIFY pgrst, 'reload schema'",
    ]
  ) {
    assertStringIncludes(throughputMigration, expected);
  }

  assertEquals(throughputMigration.includes(" OFFSET "), false);
  assertEquals(
    throughputMigration.includes("pg_catalog.COALESCE"),
    false,
  );
});

Deno.test("DwC-A archive assembly combines durable bounded chunk CRCs", () => {
  for (
    const expected of [
      "ADD COLUMN crc32 BIGINT",
      "ALTER COLUMN crc32 SET NOT NULL",
      "crc32 BETWEEN 0 AND 4294967295",
      "byte_count <> 0 OR crc32 = 0",
      "work.phase IN ('occurrence', 'multimedia', 'assembling')",
      "DELETE FROM internal.export_job_chunks",
      "p_chunk_crc32 BIGINT",
      "p_chunk_crc32 NOT BETWEEN 0 AND 4294967295",
      "p_chunk_byte_count = 0 AND p_chunk_crc32 <> 0",
      "chunks.crc32",
      "CREATE FUNCTION public.get_export_job_chunks",
      "crc32 BIGINT",
      "PERFORM internal.require_service_role()",
      "SET search_path = ''",
      "REVOKE ALL ON FUNCTION public.advance_export_job_step",
      "GRANT EXECUTE ON FUNCTION public.advance_export_job_step",
      "'public.advance_export_job_step(uuid,uuid,text,uuid,integer,text,integer,bigint,boolean)'",
      "NOTIFY pgrst, 'reload schema'",
    ]
  ) {
    assertStringIncludes(crcMigration, expected);
  }

  assertEquals(
    crcMigration.includes(
      "'public.advance_export_job_step(uuid,uuid,text,uuid,integer,text,integer,boolean)'",
    ),
    true,
    "The migration must explicitly remove the retired allowlist signature before dropping the old routine.",
  );
  const jobFence = crcMigration.indexOf("FOR UPDATE OF jobs;");
  const chunkDdl = crcMigration.indexOf(
    "ALTER TABLE internal.export_job_chunks\nADD COLUMN crc32 BIGINT",
  );
  assert(
    jobFence >= 0 && chunkDdl > jobFence,
    "Canonical job rows must be fenced before chunk-table DDL to avoid a migration/worker lock inversion.",
  );
  assertEquals(crcMigration.includes("pg_catalog.COALESCE"), false);
});
