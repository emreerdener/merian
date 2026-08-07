import { assert, assertStringIncludes } from "@std/assert";

const migrationUrl = new URL(
  "../../migrations/20260725030308_durable_account_deletion.sql",
  import.meta.url,
);
const tombstoneRepairMigrationUrl = new URL(
  "../../migrations/20260725035737_repair_tombstone_profile_seed.sql",
  import.meta.url,
);
const ownerlessTombstoneMigrationUrl = new URL(
  "../../migrations/20260725041308_ownerless_account_deletion_tombstones.sql",
  import.meta.url,
);
const storageErasureMigrationUrl = new URL(
  "../../migrations/20260725052337_enforce_account_storage_erasure.sql",
  import.meta.url,
);
const storageErasureFenceMigrationUrl = new URL(
  "../../migrations/20260726041109_fence_storage_erasure_claims.sql",
  import.meta.url,
);
const healthMonitorMigrationUrl = new URL(
  "../../migrations/20260727001630_monitor_account_deletion_health.sql",
  import.meta.url,
);
const scientificRetentionMigrationUrl = new URL(
  "../../migrations/20260731154139_retain_scientific_coordinates_after_account_deletion.sql",
  import.meta.url,
);
const appleRevocationMigrationUrl = new URL(
  "../../migrations/20260806203700_durable_apple_provider_revocation.sql",
  import.meta.url,
);

function normalized(sql: string): string {
  return sql.replaceAll(/\s+/g, " ").trim();
}

Deno.test("account deletion migration persists and fences every destructive phase", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "CREATE TABLE internal.account_deletion_jobs",
      "CHECK (status IN ('pending', 'auth_pending', 'completed'))",
      "CONSTRAINT account_deletion_jobs_claim_check",
      "CREATE INDEX account_deletion_jobs_due_idx",
      "WHERE status IN ('pending', 'auth_pending')",
      "CREATE OR REPLACE FUNCTION internal.reject_account_deletion_profile_recreation",
      "CREATE TRIGGER trg_reject_account_deletion_profile_recreation",
      "BEFORE INSERT ON public.users",
      "account_deletion_in_progress",
      "REVOKE ALL ON FUNCTION internal.reject_account_deletion_profile_recreation() FROM PUBLIC, anon, authenticated, service_role",
      "CREATE UNIQUE INDEX pending_storage_deletions_target_user_unique_idx",
      "CREATE OR REPLACE FUNCTION public.request_account_deletion",
      "CREATE OR REPLACE FUNCTION public.claim_account_deletion_jobs",
      "FOR UPDATE OF deletion_job SKIP LOCKED",
      "CREATE OR REPLACE FUNCTION public.complete_account_deletion_cleanup",
      "INSERT INTO public.pending_storage_deletions",
      "PERFORM public.apply_user_tombstone(deletion_job.user_id)",
      "account_deletion_cleanup_verification_failed",
      "status NOT IN ('pending', 'auth_pending')",
      "SET status = 'auth_pending'",
      "CREATE OR REPLACE FUNCTION public.finish_account_deletion_attempt",
      "account_deletion_cleanup_required",
      "SET user_id = NULL, status = 'completed'",
      "ELSE INTERVAL '1 hour'",
      "PERFORM internal.require_service_role()",
      "REVOKE ALL ON TABLE internal.account_deletion_jobs FROM PUBLIC, anon, authenticated, service_role",
      "'public.request_account_deletion(uuid)'",
      "'public.claim_account_deletion_jobs(integer,uuid)'",
      "'public.complete_account_deletion_cleanup(uuid,uuid)'",
      "'public.finish_account_deletion_attempt(uuid,uuid,boolean,text)'",
      "reconcile_account_deletions_every_five_minutes",
      "/functions/v1/reconcile-account-deletions",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  const cleanupStart = sql.indexOf(
    "CREATE OR REPLACE FUNCTION public.complete_account_deletion_cleanup",
  );
  const cleanupEnd = sql.indexOf(
    "COMMENT ON FUNCTION public.complete_account_deletion_cleanup",
    cleanupStart,
  );
  const cleanup = sql.slice(cleanupStart, cleanupEnd);
  assert(
    cleanup.indexOf("INSERT INTO public.pending_storage_deletions") <
      cleanup.indexOf("PERFORM public.apply_user_tombstone"),
    "The durable storage outbox must be written before tombstoning.",
  );
  assert(
    cleanup.indexOf("PERFORM public.apply_user_tombstone") <
      cleanup.indexOf("SET status = 'auth_pending'"),
    "Only verified cleanup may authorize Auth deletion.",
  );
});

Deno.test("account deletion RPCs remain service-only", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));

  for (
    const signature of [
      "public.request_account_deletion(UUID)",
      "public.claim_account_deletion_jobs(INTEGER, UUID)",
      "public.complete_account_deletion_cleanup(UUID, UUID)",
      "public.finish_account_deletion_attempt( UUID, UUID, BOOLEAN, TEXT )",
    ]
  ) {
    assertStringIncludes(
      sql,
      `REVOKE ALL ON FUNCTION ${signature}`,
    );
  }

  assert(
    !sql.includes(
      "GRANT EXECUTE ON FUNCTION public.request_account_deletion(UUID) TO authenticated",
    ),
  );
  assert(
    !sql.includes(
      "GRANT EXECUTE ON FUNCTION public.claim_account_deletion_jobs(INTEGER, UUID) TO authenticated",
    ),
  );

  assert(
    !/pg_catalog\.(?:COALESCE|NULLIF|GREATEST|LEAST)\s*\(/i.test(sql),
    "PostgreSQL conditional expressions are not schema-qualified functions and fail plpgsql_check.",
  );
});

Deno.test("Apple provider revocation is Vault-backed and database-fenced before Auth", async () => {
  const sql = normalized(
    await Deno.readTextFile(appleRevocationMigrationUrl),
  );

  for (
    const fragment of [
      "CREATE TABLE internal.apple_sign_in_revocation_credentials",
      "REFERENCES auth.users(id) ON DELETE RESTRICT",
      "REFERENCES vault.secrets(id) ON DELETE RESTRICT",
      "CREATE TABLE internal.apple_sign_in_credential_registrations",
      "provider_revocation_status TEXT NOT NULL",
      "manual_provider_revocation_required BOOLEAN NOT NULL",
      "'pending', 'completed', 'manual_required', 'not_required'",
      "CREATE OR REPLACE FUNCTION public.apple_revocation_registration_exists",
      "CREATE OR REPLACE FUNCTION public.store_apple_revocation_credential",
      "identity.provider = 'apple'",
      "vault.create_secret",
      "vault.update_secret",
      "CREATE OR REPLACE FUNCTION public.get_account_deletion_provider_token",
      "FROM internal.apple_sign_in_revocation_credentials AS credential INNER JOIN vault.decrypted_secrets AS secret",
      "CREATE OR REPLACE FUNCTION public.complete_account_deletion_provider_revocation",
      "DELETE FROM vault.secrets AS secret",
      "RETURN 'provider_revocation_pending'",
      "account_deletion_provider_revocation_required",
      "manual_provider_revocation_required BOOLEAN",
      "PERFORM internal.require_service_role()",
      "INSERT INTO internal.privileged_routine_grants",
      "'public.apple_revocation_registration_exists(uuid,uuid)'",
      "'public.store_apple_revocation_credential(uuid,uuid,text,text)'",
      "'public.get_account_deletion_provider_token(uuid,uuid)'",
      "'public.complete_account_deletion_provider_revocation(uuid,uuid)'",
      "apple_revocation_rpc_acl_invalid",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  const providerCompletion = sql.indexOf(
    "CREATE OR REPLACE FUNCTION public.complete_account_deletion_provider_revocation",
  );
  const credentialDelete = sql.indexOf(
    "DELETE FROM internal.apple_sign_in_revocation_credentials",
    providerCompletion,
  );
  const vaultDelete = sql.indexOf(
    "DELETE FROM vault.secrets",
    providerCompletion,
  );
  const providerCommit = sql.indexOf(
    "SET provider_revocation_status = 'completed'",
    providerCompletion,
  );
  assert(
    credentialDelete > providerCompletion &&
      vaultDelete > credentialDelete &&
      providerCommit > vaultDelete,
    "The token mapping and Vault secret must be destroyed before the provider stage is committed.",
  );

  const finishStart = sql.indexOf(
    "CREATE OR REPLACE FUNCTION public.finish_account_deletion_attempt",
  );
  const finishEnd = sql.indexOf(
    "REVOKE ALL ON FUNCTION public.apple_revocation_registration_exists",
    finishStart,
  );
  const finish = sql.slice(finishStart, finishEnd);
  assert(
    finish.indexOf("account_deletion_provider_revocation_required") <
      finish.indexOf("SET user_id = NULL"),
    "The SQL fence must reject pending provider work before terminal Auth completion.",
  );

  assert(
    !/pg_catalog\.(?:COALESCE|NULLIF|GREATEST|LEAST)\s*\(/i.test(sql),
    "PostgreSQL conditional expressions must not be schema-qualified.",
  );
});

Deno.test(
  "latest account tombstone retains every scientific field unchanged",
  async () => {
    const sql = normalized(
      await Deno.readTextFile(scientificRetentionMigrationUrl),
    );

    assert(
      !/\bCREATE\s+TABLE\b/i.test(sql),
      "Mandatory scientific retention must keep using the ownerless scans row, not create a parallel retention table.",
    );

    for (
      const fragment of [
        "CREATE OR REPLACE FUNCTION public.apply_user_tombstone",
        "PERFORM internal.require_service_role()",
        "SET search_path = ''",
        "SET user_id = NULL, is_tombstoned = TRUE",
        "image_storage_urls = ARRAY[]::TEXT[]",
        "captured_media = NULL",
        "semantic_location = NULL",
        "public_location_label = NULL",
        "device_locale = NULL",
        "device_time_zone = NULL",
        "user_observation_context = NULL",
        "custom_tags = ARRAY[]::TEXT[]",
        "human_intervention_notes = NULL",
        "including exact coordinates and elevation",
        "CREATE OR REPLACE FUNCTION internal.reject_deleted_scan_generation_mutation",
        "OLD.user_id IS NOT NULL",
        "NEW.user_id IS NULL",
        "pg_catalog.TO_JSONB(NEW) - account_detachment_columns",
        "pg_catalog.TO_JSONB(OLD) - account_detachment_columns",
        "REVOKE ALL ON FUNCTION public.apply_user_tombstone(UUID) FROM PUBLIC, anon, authenticated, service_role",
        "GRANT EXECUTE ON FUNCTION public.apply_user_tombstone(UUID) TO service_role",
        "REVOKE ALL ON FUNCTION internal.reject_deleted_scan_generation_mutation() FROM PUBLIC, anon, authenticated, service_role",
      ]
    ) {
      assertStringIncludes(sql, fragment);
    }

    const routineStart = sql.indexOf(
      "CREATE OR REPLACE FUNCTION public.apply_user_tombstone",
    );
    const routineEnd = sql.indexOf(
      "COMMENT ON FUNCTION public.apply_user_tombstone",
      routineStart,
    );
    const routine = sql.slice(routineStart, routineEnd);
    for (
      const retainedColumn of [
        "gps_lat_exact",
        "gps_long_exact",
        "gps_elevation",
        "gps_lat_public",
        "gps_long_public",
        "coordinate_uncertainty_in_meters",
        "timestamp",
        "species_id",
        "confirmed_species_id",
      ]
    ) {
      assert(
        !routine.includes(retainedColumn),
        `${retainedColumn} must not be changed by account detachment.`,
      );
    }

    const allowedChangesStart = sql.indexOf(
      "account_detachment_columns CONSTANT TEXT[]",
    );
    const allowedChangesEnd = sql.indexOf("]::TEXT[]", allowedChangesStart);
    const allowedChanges = sql.slice(allowedChangesStart, allowedChangesEnd);
    assert(
      !allowedChanges.includes("gps_") &&
        !allowedChanges.includes("species_id") &&
        !allowedChanges.includes("timestamp"),
      "The scan-generation exception must never allow retained scientific fields to change.",
    );
  },
);

Deno.test("account deletion requires verified object erasure before Auth", async () => {
  const sql = normalized(
    await Deno.readTextFile(storageErasureMigrationUrl),
  );

  for (
    const fragment of [
      "ADD COLUMN IF NOT EXISTS storage_completed_at TIMESTAMPTZ",
      "'storage_pending'",
      "CREATE OR REPLACE FUNCTION public.claim_pending_storage_deletions",
      "FOR UPDATE OF deletion SKIP LOCKED",
      "CREATE OR REPLACE FUNCTION public.advance_pending_storage_deletion",
      "phase = 'verification'",
      "verification_not_before",
      "status = 'completed'",
      "CREATE OR REPLACE FUNCTION public.fail_pending_storage_deletion",
      "PERFORM internal.require_service_role()",
      "image_storage_urls = ARRAY[]::TEXT[]",
      "video_storage_urls = ARRAY[]::TEXT[]",
      "audio_storage_urls = ARRAY[]::TEXT[]",
      "captured_media = NULL",
      "semantic_location = NULL",
      "device_locale = NULL",
      "device_time_zone = NULL",
      "user_observation_context = NULL",
      "custom_tags = ARRAY[]::TEXT[]",
      "UPDATE public.pending_storage_deletions AS deletion SET status = 'pending'",
      "WHERE scans.user_id IS NULL",
      "p_last_key <= deletion.start_after_key",
      "RETURN 'storage_pending'",
      "RETURN 'auth_pending'",
      "storage.status = 'completed'",
      "account_deletion_storage_required",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  const cleanupStart = sql.indexOf(
    "CREATE FUNCTION public.complete_account_deletion_cleanup",
  );
  const cleanupEnd = sql.indexOf(
    "COMMENT ON FUNCTION public.complete_account_deletion_cleanup",
    cleanupStart,
  );
  const cleanup = sql.slice(cleanupStart, cleanupEnd);
  assert(
    cleanup.indexOf("INSERT INTO public.pending_storage_deletions") <
      cleanup.indexOf("PERFORM public.apply_user_tombstone"),
  );
  assert(
    cleanup.indexOf("storage_status = 'completed'") <
      cleanup.indexOf("RETURN 'auth_pending'"),
  );
  assert(
    cleanup.indexOf("RETURN 'storage_pending'") >
      cleanup.indexOf("claim_token = NULL"),
    "The account claim must be released while the durable storage worker runs.",
  );

  for (
    const signature of [
      "public.account_deletion_is_active(UUID)",
      "public.claim_pending_storage_deletions(INTEGER)",
      "public.advance_pending_storage_deletion( UUID, UUID, TEXT, BOOLEAN )",
      "public.fail_pending_storage_deletion(UUID, UUID, TEXT)",
    ]
  ) {
    assertStringIncludes(sql, `REVOKE ALL ON FUNCTION ${signature}`);
  }
});

Deno.test("storage erasure claims cannot target a live or orphaned account", async () => {
  const sql = normalized(
    await Deno.readTextFile(storageErasureFenceMigrationUrl),
  );

  for (
    const fragment of [
      "INNER JOIN internal.account_deletion_jobs AS deletion_job",
      "deletion_job.user_id = deletion.target_user_id",
      "deletion_job.status = 'storage_pending'",
      "deletion_job.cleanup_completed_at IS NOT NULL",
      "deletion_job.storage_completed_at IS NULL",
      "FROM public.users AS live_user",
      "live_user.id = deletion.target_user_id",
      "FROM public.scans AS owned_scan",
      "owned_scan.user_id = deletion.target_user_id",
      "FOR UPDATE OF deletion SKIP LOCKED",
      "PERFORM internal.require_service_role()",
      "REVOKE ALL ON FUNCTION public.claim_pending_storage_deletions(INTEGER)",
      "GRANT EXECUTE ON FUNCTION public.claim_pending_storage_deletions(INTEGER) TO service_role",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("account deletion exposes indexed aggregate service-only health", async () => {
  const sql = normalized(
    await Deno.readTextFile(healthMonitorMigrationUrl),
  );

  for (
    const fragment of [
      "CREATE INDEX IF NOT EXISTS account_deletion_jobs_active_requested_idx",
      "CREATE INDEX IF NOT EXISTS account_deletion_jobs_active_error_idx",
      "CREATE INDEX IF NOT EXISTS pending_storage_deletions_active_created_idx",
      "CREATE INDEX IF NOT EXISTS pending_storage_deletions_expired_claim_idx",
      "CREATE INDEX IF NOT EXISTS pending_storage_deletions_active_error_idx",
      "CREATE OR REPLACE FUNCTION public.get_account_deletion_health()",
      "active_job_count BIGINT",
      "failed_job_count BIGINT",
      "expired_lease_count BIGINT",
      "oldest_pending_age_seconds BIGINT",
      "storage_failed_job_count BIGINT",
      "storage_expired_lease_count BIGINT",
      "orphaned_storage_job_count BIGINT",
      "reaper_cron_active BOOLEAN",
      "reaper_credentials_configured BOOLEAN",
      "PERFORM internal.require_service_role()",
      "configuration_values AS MATERIALIZED",
      "COALESCE( ( SELECT secret.decrypted_secret",
      "FROM vault.decrypted_secrets AS secret",
      "Match the reaper's Vault-first, NULL-only fallback exactly",
      "'reconcile_account_deletions_every_five_minutes'",
      "SET search_path = ''",
      "SET statement_timeout = '5s'",
      "REVOKE ALL ON FUNCTION public.get_account_deletion_health() FROM PUBLIC, anon, authenticated, service_role",
      "GRANT EXECUTE ON FUNCTION public.get_account_deletion_health() TO service_role",
      "'public.get_account_deletion_health()'",
      "NOTIFY pgrst, 'reload schema'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  const resultStart = sql.indexOf(
    "RETURNS TABLE ( generated_at TIMESTAMPTZ",
  );
  const resultEnd = sql.indexOf(
    ") LANGUAGE PLPGSQL SECURITY DEFINER",
    resultStart,
  );
  const resultShape = sql.slice(resultStart, resultEnd);
  assert(
    !resultShape.includes("user_id") &&
      !resultShape.includes("last_error_code"),
    "The health RPC must expose aggregate state only, without identity or raw error values.",
  );
  assert(
    !/pg_catalog\.(?:COALESCE|NULLIF|GREATEST|LEAST)\s*\(/i.test(sql),
    "PostgreSQL conditional expressions are not schema-qualified functions and fail plpgsql_check.",
  );
});

Deno.test("failed tombstone-owner rollout is an executable no-op bridge", async () => {
  const sql = normalized(
    await Deno.readTextFile(tombstoneRepairMigrationUrl),
  );

  assertStringIncludes(sql, "DO $migration$ BEGIN NULL; END; $migration$;");
  assert(
    !/\b(?:INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|TRUNCATE|GRANT|REVOKE)\b/i
      .test(
        sql.replaceAll(/--[^\r\n]*/g, " "),
      ),
    "The failed production migration must record only a no-op and never retry the invalid public-only user insert.",
  );
});

Deno.test(
  "account deletion uses ownerless tombstones and Auth-backed profiles",
  async () => {
    const sql = normalized(
      await Deno.readTextFile(ownerlessTombstoneMigrationUrl),
    );

    for (
      const fragment of [
        "BEGIN; SET LOCAL lock_timeout = '10s'; SET LOCAL statement_timeout = '2min'",
        "LOCK TABLE auth.users IN SHARE ROW EXCLUSIVE MODE",
        "LOCK TABLE public.scans IN SHARE ROW EXCLUSIVE MODE",
        "LOCK TABLE public.users IN SHARE ROW EXCLUSIVE MODE",
        "legacy_auth_sentinel_requires_operator_removal",
        "ALTER TABLE public.scans ALTER COLUMN user_id DROP NOT NULL",
        "ADD CONSTRAINT scans_ownerless_requires_tombstone_check CHECK (user_id IS NOT NULL OR is_tombstoned) NOT VALID",
        "SET user_id = NULL, is_tombstoned = TRUE, gps_lat_exact = NULL, gps_long_exact = NULL, gps_elevation = NULL, human_intervention_notes = NULL",
        "VALIDATE CONSTRAINT scans_ownerless_requires_tombstone_check",
        "DELETE FROM public.users AS users WHERE users.id = '00000000-0000-0000-0000-000000000000'::UUID",
        "FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE RESTRICT NOT VALID",
        'DROP POLICY IF EXISTS "Anyone can read open and live scans" ON public.scans',
        "AND is_tombstoned = FALSE",
        "CREATE OR REPLACE FUNCTION public.apply_user_tombstone",
        "PERFORM internal.require_service_role()",
        "SET search_path = ''",
        "WHERE scans.user_id = target_user_id",
        "DELETE FROM public.users AS users WHERE users.id = target_user_id",
        "CREATE OR REPLACE FUNCTION internal.reparent_ghost_user_foreign_keys",
        "REVOKE ALL ON FUNCTION public.apply_user_tombstone(UUID) FROM PUBLIC, anon, authenticated, service_role",
        "GRANT EXECUTE ON FUNCTION public.apply_user_tombstone(UUID) TO service_role",
        "COMMIT;",
      ]
    ) {
      assertStringIncludes(sql, fragment);
    }

    const profileIdentityPredicate =
      "constraint_row.conrelid = 'public.users'::REGCLASS AND constraint_row.confrelid = 'auth.users'::REGCLASS AND source_column.attname = 'id' AND target_column.attname = 'id'";
    assert(
      sql.split(profileIdentityPredicate).length - 1 >= 2,
      "Only the exact profile identity FK may be skipped in both Ghost reparenting passes.",
    );

    assert(
      !sql.includes("INSERT INTO auth.users") &&
        !sql.includes("INSERT INTO public.users"),
      "Deletion infrastructure must never manufacture an Auth or public user.",
    );

    const routineStart = sql.indexOf(
      "CREATE OR REPLACE FUNCTION public.apply_user_tombstone",
    );
    const routineEnd = sql.indexOf(
      "COMMENT ON FUNCTION public.apply_user_tombstone",
      routineStart,
    );
    const routineSql = sql.slice(routineStart, routineEnd);
    assert(
      routineSql.indexOf("SET user_id = NULL") <
        routineSql.indexOf("DELETE FROM public.users"),
      "Scan ownership must be erased before the Auth-backed profile is deleted.",
    );
  },
);
