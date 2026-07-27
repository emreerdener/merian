import {
  assert,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";

const migrationUrl = new URL(
  "../../migrations/20260723144640_harden_privileged_routine_execution.sql",
  import.meta.url,
);
const serviceRoleGuardFixUrl = new URL(
  "../../migrations/20260727010340_fix_service_role_authorization_guard.sql",
  import.meta.url,
);

function normalized(sql: string): string {
  return sql.replaceAll(/\s+/g, " ").trim();
}

function assertBefore(
  sql: string,
  earlier: string,
  later: string,
  message: string,
): void {
  const earlierIndex = sql.indexOf(earlier);
  const laterIndex = sql.indexOf(later);
  assert(earlierIndex >= 0, `Missing expected SQL fragment: ${earlier}`);
  assert(laterIndex >= 0, `Missing expected SQL fragment: ${later}`);
  assert(earlierIndex < laterIndex, message);
}

Deno.test("privileged routine migration is deny-by-default", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated, service_role",
      "ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated, service_role",
      "REVOKE CREATE ON SCHEMA public FROM PUBLIC, anon, authenticated, service_role",
      "CREATE TABLE IF NOT EXISTS internal.privileged_routine_grants",
      "CREATE OR REPLACE FUNCTION internal.require_service_role()",
      "SET search_path = ''",
      "REVOKE ALL ON FUNCTION internal.require_service_role() FROM PUBLIC, anon, authenticated, service_role",
      "WHERE namespace_row.nspname = 'public' AND function_row.prosecdef",
      "REVOKE ALL ON FUNCTION %I.%I(%s) FROM PUBLIC, anon, authenticated, service_role",
      "ALTER FUNCTION %I.%I(%s) SET search_path TO %L",
      "An authenticated definer function lacks caller-bound authorization.",
      "A service-role definer function lacks in-function authorization.",
      "A routine creator still has an unsafe default EXECUTE privilege.",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assertBefore(
    sql,
    "ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE EXECUTE",
    "CREATE OR REPLACE FUNCTION public.apply_user_tombstone",
    "Default privileges must be hardened before privileged functions are replaced.",
  );
  assertBefore(
    sql,
    "REVOKE ALL ON FUNCTION %I.%I(%s) FROM PUBLIC, anon, authenticated, service_role",
    "GRANT EXECUTE ON FUNCTION %I.%I(%s) TO %I",
    "The migration must revoke every historical grant before applying the allowlist.",
  );
});

Deno.test("high-impact maintenance routines are bounded and explicitly authorized", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION public.apply_user_tombstone(target_user_id UUID)",
      "PERFORM internal.require_service_role()",
      "CREATE OR REPLACE FUNCTION public.merge_common_name_en_batch(p_updates JSONB)",
      "SET statement_timeout = '5s'",
      "IF update_count < 1 OR update_count > 50",
      "p_updates contains duplicate species ids.",
      "CREATE OR REPLACE FUNCTION public.process_community_consensus_jobs",
      "WHERE candidate.status IN ('pending', 'failed')",
      "FOR UPDATE OF candidate SKIP LOCKED",
      "('service_role', 'public.apply_user_tombstone(uuid)'",
      "('service_role', 'public.merge_common_name_en_batch(jsonb)'",
      "('service_role', 'public.refresh_taxonomy_nodes_from_species_dictionary(text,boolean)'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  for (
    const forbiddenGrant of [
      "('service_role', 'public.reparent_user_follows(uuid,uuid)'",
      "('service_role', 'public.refresh_all_explore_post_media()'",
      "('service_role', 'public.merge_common_name_en(uuid,text)'",
    ]
  ) {
    assert(
      !sql.includes(forbiddenGrant),
      `Dangerous internal helper must not be service-role allowlisted: ${forbiddenGrant}`,
    );
  }
});

Deno.test("service allowlist is coupled to in-function authorization", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));

  assertStringIncludes(
    sql,
    "WHERE allowlist.role_name = 'service_role' AND language_row.lanname = 'sql'",
  );
  assertStringIncludes(
    sql,
    "LANGUAGE[[:space:]]+sql', 'LANGUAGE plpgsql'",
  );
  assertStringIncludes(
    sql,
    "RETURN QUERY",
  );
  assertStringIncludes(
    sql,
    "WHERE allowlist.role_name = 'service_role' AND language_row.lanname = 'plpgsql' AND function_row.prosrc NOT LIKE '%internal.require_service_role()%'",
  );
});

Deno.test("service-role guard supports JWT and opaque server keys", async () => {
  const sql = normalized(await Deno.readTextFile(serviceRoleGuardFixUrl));

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION internal.require_service_role()",
      "auth.role() IS DISTINCT FROM 'service_role'",
      "pg_catalog.CURRENT_SETTING('role', TRUE) NOT IN ('service_role', 'postgres')",
      "pg_catalog.CURRENT_SETTING('role', TRUE) = 'none'",
      "SESSION_USER IN ('postgres', 'service_role')",
      "RAISE EXCEPTION 'service_role authorization required'",
      "REVOKE ALL ON FUNCTION internal.require_service_role() FROM PUBLIC, anon, authenticated, service_role",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});
