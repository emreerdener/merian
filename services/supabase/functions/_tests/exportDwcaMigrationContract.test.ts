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
