import {
  assert,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";

const migrationUrl = new URL(
  "../../migrations/20260725030308_durable_account_deletion.sql",
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
