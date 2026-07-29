import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";

const migrationUrl = new URL(
  "../../migrations/20260728233000_recover_identity_merge_interrupted_scans.sql",
  import.meta.url,
);
const securityFixtureUrl = new URL(
  "../../tests/identity_merge_scan_recovery_security.sql",
  import.meta.url,
);

function normalized(sql: string): string {
  return sql.replace(/\s+/g, " ").trim();
}

Deno.test("identity merge fences unfinished scans before generic ownership reparenting", async () => {
  const [sql, securityFixture] = await Promise.all([
    Deno.readTextFile(migrationUrl).then(normalized),
    Deno.readTextFile(securityFixtureUrl).then(normalized),
  ]);

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION internal.prepare_scan_ingestions_for_identity_merge",
      "stage = 'identity_merge_interrupted'",
      "failure_reason = 'superseded_identity_merge_staging'",
      "'identify-describe'",
      "PERFORM internal.release_ai_quota_reservation_counters",
      "state = 'refunded'",
      "state = 'failed'",
      "jobs.endpoint = 'audio-spec'",
      "'scan_audio_identification'",
      "PERFORM internal.prepare_scan_ingestions_for_identity_merge(",
      "PG_GET_FUNCTIONDEF",
      "REVOKE ALL ON FUNCTION internal.prepare_scan_ingestions_for_identity_merge",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  const hook = sql.indexOf(
    "PERFORM internal.prepare_scan_ingestions_for_identity_merge(",
  );
  const genericReparentComment = sql.indexOf(
    "-- Prevent uniqueness conflicts in operational ledgers before their new",
    hook,
  );
  assert(hook >= 0 && genericReparentComment > hook);
  assert(
    !sql.includes(
      "release_ai_quota_reservation_counters( collision_row.source_id )",
    ) || sql.includes("collision_row.source_state = 'reserved'"),
    "Only an undispatched reservation may release consumed counters.",
  );

  for (const username of ["identity_source_d801", "identity_target_d802"]) {
    assert(
      username.length >= 3 &&
        username.length <= 24 &&
        /^[a-z][a-z0-9_]*[a-z0-9]$/.test(username) &&
        !username.includes("__"),
      `Catalog fixture username violates public.users constraints: ${username}`,
    );
    assertStringIncludes(securityFixture, `'${username}'`);
  }
  assertStringIncludes(
    securityFixture,
    "ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email, public_username = EXCLUDED.public_username, public_author_name = EXCLUDED.public_author_name, public_identity_source = EXCLUDED.public_identity_source, subscription_tier = EXCLUDED.subscription_tier, created_at = EXCLUDED.created_at",
  );
  for (
    const diagnosticFragment of [
      "CREATE TEMP TABLE identity_merge_scan_recovery_result",
      "fixture_phase := 'atomic Ghost merge'",
      "fixture_phase := 'live target-lease recovery'",
      "fixture_phase := 'merged-source recovery'",
      "fixture_phase := 'metered retry reservation'",
      "EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS",
      "error_sqlstate = RETURNED_SQLSTATE",
      "error_message = MESSAGE_TEXT",
      "RAISE WARNING 'identity_merge_scan_recovery phase=% sqlstate=% message=% detail=% hint=%'",
      "results.error_sqlstate IS NULL",
      "identity-merge scan recovery failed at phase",
    ]
  ) {
    assertStringIncludes(securityFixture, diagnosticFragment);
  }
  assertEquals(
    (securityFixture.match(/SELECT extensions\.plan\(1\)/g) ?? []).length,
    1,
    "The diagnostic fixture must still emit exactly one planned TAP assertion.",
  );
  assert(
    !securityFixture.includes("'identity_merge_source_d801'") &&
      !securityFixture.includes("'identity_merge_target_d802'"),
    "Overlong pre-constraint fixture usernames returned.",
  );
});

Deno.test("historical scan-attempt recovery is exact, tombstone-aware, and never refunds committed usage", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION public.recover_stranded_scan_ingestion_attempt",
      "PERFORM internal.require_service_role()",
      "'merian-scan-ingestion:' || p_scan_id::TEXT",
      "FROM internal.scan_deletion_tombstones AS tombstones WHERE tombstones.scan_id = p_scan_id",
      "jobs.scan_id = p_scan_id::TEXT AND jobs.user_id = p_user_id FOR UPDATE",
      "job_row.endpoint NOT IN ( 'identify', 'identify-multimodal', 'identify-describe', 'audio-spec' )",
      "WHEN 'audio-spec' THEN 'scan_audio_identification'",
      "reservations.user_id = p_user_id AND reservations.operation = CASE job_row.endpoint",
      "reservations.state = 'committed'",
      "SET state = 'failed'",
      "job_row.lock_expires_at <= recovery_now",
      "reservation_row.state = 'reserved' AND reservation_row.lease_expires_at > recovery_now",
      "handoff.ghost_user_id = candidate_source_ids[1] AND handoff.target_user_id = p_user_id AND handoff.status = 'merged'",
      "SELECT pg_catalog.SUBSTRING( media_keys.storage_key, ( '^staging/('",
      "SELECT pg_catalog.SUBSTRING( media_urls.url, ( '^https://media[.]merian[.]app/'",
      "'media_restage_required'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  const recoveryStart = sql.indexOf(
    "CREATE OR REPLACE FUNCTION public.recover_stranded_scan_ingestion_attempt",
  );
  const recoveryEnd = sql.indexOf(
    "COMMENT ON FUNCTION public.recover_stranded_scan_ingestion_attempt",
    recoveryStart,
  );
  const recoveryBody = sql.slice(recoveryStart, recoveryEnd);
  assertEquals(
    recoveryBody.includes("release_ai_quota_reservation_counters"),
    false,
    "Historical committed-attempt recovery must preserve charged usage.",
  );
  assertEquals(
    recoveryBody.includes("request_count = request_count -"),
    false,
  );
  assertEquals(
    recoveryBody.includes("OR merged_source_user_id IS NOT NULL OR"),
    false,
    "Exact merge lineage must not override an active target-owned job lease.",
  );
});

Deno.test("identity-merge scan recovery has exact service ACL and allowlist", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));

  assertStringIncludes(
    sql,
    "REVOKE ALL ON FUNCTION public.recover_stranded_scan_ingestion_attempt( UUID, UUID ) FROM PUBLIC, anon, authenticated, service_role",
  );
  assertStringIncludes(
    sql,
    "GRANT EXECUTE ON FUNCTION public.recover_stranded_scan_ingestion_attempt( UUID, UUID ) TO service_role",
  );
  assertStringIncludes(
    sql,
    "'public.recover_stranded_scan_ingestion_attempt(uuid,uuid)'",
  );
  assertStringIncludes(
    sql,
    "RESET statement_timeout; RESET lock_timeout;",
  );
});
