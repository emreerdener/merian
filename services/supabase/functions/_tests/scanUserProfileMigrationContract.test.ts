import { assert, assertStringIncludes } from "@std/assert";

const migrationUrl = new URL(
  "../../migrations/20260728232000_ensure_scan_user_profile.sql",
  import.meta.url,
);
const sharedDbUrl = new URL("../_shared/identify/db.ts", import.meta.url);
const audioDbUrl = new URL("../audio-spec/db.ts", import.meta.url);

function normalized(source: string): string {
  return source.replaceAll(/\s+/g, " ").trim();
}

function assertBefore(
  source: string,
  earlier: string,
  later: string,
  message: string,
): void {
  const earlierIndex = source.indexOf(earlier);
  const laterIndex = source.indexOf(later);
  assert(earlierIndex >= 0, `Missing expected fragment: ${earlier}`);
  assert(laterIndex >= 0, `Missing expected fragment: ${later}`);
  assert(earlierIndex < laterIndex, message);
}

Deno.test("scan profile prerequisite is owner-exact, merge-aware, and fail closed", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));

  assertStringIncludes(sql, "pg_catalog.HASHTEXTEXTENDED(");
  assert(
    !sql.includes("pg_catalog.HASHTEXTENDED("),
    "Profile repair must use PostgreSQL's real extended text hash function.",
  );

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION public.ensure_scan_user_profile( p_user_id UUID ) RETURNS BOOLEAN LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = '' SET statement_timeout = '10s'",
      "PERFORM internal.require_service_role()",
      "'ghost-profile-merge:' || p_user_id::TEXT",
      "FROM auth.users AS auth_user WHERE auth_user.id = p_user_id FOR KEY SHARE",
      "RAISE EXCEPTION 'scan_user_auth_identity_missing'",
      "FROM internal.account_deletion_jobs AS deletion_job WHERE deletion_job.user_id = p_user_id",
      "'pending', 'storage_pending', 'auth_pending'",
      "FROM internal.ghost_profile_merge_handoffs AS handoff WHERE handoff.ghost_user_id = p_user_id AND handoff.status = 'merged'",
      "FROM internal.ghost_user_cleanup_reservations AS reservation WHERE reservation.ghost_user_id = p_user_id",
      "public.derive_public_author_identity( auth_metadata, p_user_id )",
      "public.build_unique_public_username( resolved_name, p_user_id )",
      "public.resolve_public_avatar_url( NULL, auth_metadata )",
      "public_author_name, public_identity_source, public_avatar_url, public_username",
      "WHEN unique_violation THEN GET STACKED DIAGNOSTICS violated_constraint = CONSTRAINT_NAME",
      "'users_public_username_unique_idx'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assertBefore(
    sql,
    "FROM internal.account_deletion_jobs",
    "IF EXISTS ( SELECT 1 FROM public.users AS profile",
    "Deletion state must win even when a profile appears concurrently.",
  );
  assertBefore(
    sql,
    "FROM internal.ghost_profile_merge_handoffs",
    "INSERT INTO public.users",
    "A retired ghost identity must be rejected before profile creation.",
  );
  assertBefore(
    sql,
    "FROM auth.users AS auth_user",
    "INSERT INTO public.users",
    "Profile creation must be backed by the exact Auth identity.",
  );
});

Deno.test("scan profile prerequisite has exact service ACL and reviewed allowlist", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "REVOKE ALL ON FUNCTION public.ensure_scan_user_profile(UUID) FROM PUBLIC, anon, authenticated, service_role",
      "GRANT EXECUTE ON FUNCTION public.ensure_scan_user_profile(UUID) TO service_role",
      "'service_role', 'public.ensure_scan_user_profile(uuid)'",
      "NOTIFY pgrst, 'reload schema'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("every scan route uses the guarded profile prerequisite instead of a partial users upsert", async () => {
  const sharedDb = normalized(await Deno.readTextFile(sharedDbUrl));
  const audioDb = normalized(await Deno.readTextFile(audioDbUrl));

  assertStringIncludes(
    sharedDb,
    'supabaseAdmin.rpc( "ensure_scan_user_profile", { p_user_id: userId }',
  );
  assert(
    !sharedDb.includes('.from("users") .upsert('),
    "Shared Identify must not direct-insert a partial mandatory profile.",
  );
  assertStringIncludes(
    audioDb,
    "await ensureSharedScanUserProfile(userId, supabaseAdmin)",
  );
  assert(
    !audioDb.includes('.from("users") .upsert('),
    "Audio Identify must use the same guarded profile prerequisite.",
  );
});
