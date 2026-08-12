import { assert, assertStringIncludes } from "@std/assert";

const migrationUrl = new URL(
  "../../migrations/20260812032543_harden_signout_purchase_handoff_interlocks.sql",
  import.meta.url,
);

function compact(sql: string): string {
  return sql.replaceAll(/\s+/g, " ").trim();
}

Deno.test("sign-out handoff interlocks every destructive identity path", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION internal.reject_account_deletion_during_signout_handoff",
      "CREATE TRIGGER reject_account_deletion_during_signout_handoff",
      "BEFORE INSERT OR UPDATE OF user_id, status ON internal.account_deletion_jobs",
      "handoff.status = 'bound' AND NEW.user_id IN ( handoff.source_user_id, handoff.destination_user_id )",
      "signout_handoff_destination_deletion_blocked",
      "CREATE OR REPLACE FUNCTION internal.reject_ghost_merge_during_signout_handoff",
      "CREATE TRIGGER reject_ghost_merge_during_signout_handoff",
      "ON internal.ghost_profile_merge_handoffs",
      "signout_purchase_handoff_pending",
      "'signout_purchase_handoff_active'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes("DELETE FROM auth.users") &&
      !sql.includes("DELETE FROM public.users"),
    "an interlock migration must not perform destructive cleanup",
  );
});

Deno.test("sign-out bind accepts only a fresh destination outside deletion", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));
  const start = sql.indexOf(
    "CREATE OR REPLACE FUNCTION public.bind_signout_purchase_handoff",
  );
  const end = sql.indexOf(
    "COMMENT ON FUNCTION public.bind_signout_purchase_handoff",
    start,
  );
  const bind = sql.slice(start, end);

  for (
    const fragment of [
      "WHERE auth_user.id IN (handoff_record.source_user_id, caller_id) ORDER BY auth_user.id FOR UPDATE",
      "SELECT auth_user.created_at INTO destination_created_at",
      "destination_created_at < handoff_record.created_at",
      "signout_handoff_fresh_anonymous_destination_required",
      "FROM internal.account_deletion_jobs AS deletion_job",
      "WHERE deletion_job.user_id IN ( handoff_record.source_user_id, caller_id )",
      "signout_handoff_destination_deletion_in_progress",
      "SET destination_user_id = caller_id, status = 'bound'",
    ]
  ) {
    assertStringIncludes(bind, fragment);
  }

  assert(
    bind.indexOf("FOR UPDATE") <
        bind.indexOf("FROM internal.account_deletion_jobs") &&
      bind.indexOf("FROM internal.account_deletion_jobs") <
        bind.indexOf("SET destination_user_id = caller_id"),
    "the Auth identities must be locked before the deletion check and bind",
  );
});

Deno.test("account deletion serializes on Auth before checking handoff state", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));
  const start = sql.indexOf(
    "CREATE OR REPLACE FUNCTION public.request_account_deletion",
  );
  const end = sql.indexOf(
    "COMMENT ON FUNCTION public.request_account_deletion",
    start,
  );
  const intake = sql.slice(start, end);

  assertStringIncludes(intake, "WHERE auth_user.id = p_user_id FOR UPDATE");
  assertStringIncludes(
    intake,
    "FROM internal.signout_purchase_handoffs AS handoff",
  );
  assertStringIncludes(
    intake,
    "handoff.status = 'bound' AND p_user_id IN ( handoff.source_user_id, handoff.destination_user_id )",
  );
  assert(
    !intake.includes("handoff.status = 'prepared'"),
    "an unbound proof must not strand account deletion when its device secret is unavailable",
  );
  assertStringIncludes(
    intake,
    "INSERT INTO internal.account_deletion_jobs AS deletion_job",
  );
  assert(
    intake.indexOf("WHERE auth_user.id = p_user_id FOR UPDATE") <
        intake.indexOf("FROM internal.signout_purchase_handoffs") &&
      intake.indexOf("FROM internal.signout_purchase_handoffs") <
        intake.indexOf("INSERT INTO internal.account_deletion_jobs"),
    "deletion must observe a serialized handoff state before durable intake",
  );
});

Deno.test("replaced routines preserve their reviewed role boundaries", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));
  for (
    const fragment of [
      "REVOKE ALL ON FUNCTION public.request_account_deletion(UUID) FROM PUBLIC, anon, authenticated",
      "REVOKE ALL ON FUNCTION public.bind_signout_purchase_handoff(UUID, TEXT) FROM PUBLIC, anon, service_role",
      "REVOKE ALL ON FUNCTION public.inspect_empty_ghost_cleanup_candidate(UUID, INTEGER) FROM PUBLIC, anon, authenticated",
      "GRANT EXECUTE ON FUNCTION public.request_account_deletion(UUID) TO service_role",
      "GRANT EXECUTE ON FUNCTION public.bind_signout_purchase_handoff(UUID, TEXT) TO authenticated",
      "GRANT EXECUTE ON FUNCTION public.inspect_empty_ghost_cleanup_candidate(UUID, INTEGER) TO service_role",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});
