import {
  assert,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";

const migrationUrl = new URL(
  "../../migrations/20260724170709_harden_species_observation_stats.sql",
  import.meta.url,
);
const catalogTestUrl = new URL(
  "../../tests/species_observation_stats_security.sql",
  import.meta.url,
);

function normalized(sql: string): string {
  return sql.replaceAll(/\s+/g, " ").trim();
}

Deno.test("species stats migration keeps abuse-control state private", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "CREATE TABLE internal.species_observation_stats_rate_counters",
      "CREATE TABLE internal.species_observation_stats_population_leases",
      "PRIMARY KEY (scope_type, scope_key, bucket, window_start)",
      "lease_token UUID NOT NULL DEFAULT pg_catalog.GEN_RANDOM_UUID()",
      "lease_expires_at TIMESTAMPTZ NOT NULL",
      "REVOKE ALL ON TABLE internal.species_observation_stats_rate_counters, internal.species_observation_stats_population_leases FROM PUBLIC, anon, authenticated, service_role",
      "CREATE INDEX species_observation_stats_rate_cleanup_idx",
      "CREATE INDEX species_observation_stats_population_expiry_idx",
      "CREATE OR REPLACE FUNCTION internal.prune_species_observation_stats_guards()",
      "'prune_species_observation_stats_guards_hourly', '23 * * * *'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("species stats request and cold-population limits are atomic", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION internal.consume_species_observation_stats_rate",
      "CREATE OR REPLACE FUNCTION public.preflight_species_observation_stats_request",
      "ON CONFLICT (scope_type, scope_key, bucket, window_start) DO UPDATE",
      "WHERE internal.species_observation_stats_rate_counters.request_count < p_limit",
      "'request_user', p_user_id::TEXT, 'species_stats_request', rate_window_start, 60, 60",
      "'request_ip', p_ip_hash, 'species_stats_request', rate_window_start, 60, 120",
      "'population_user', p_user_id::TEXT, 'species_stats_population', rate_window_start, 60, 12",
      "'population_ip', p_ip_hash, 'species_stats_population', rate_window_start, 60, 30",
      "'population_global', 'global', 'species_stats_population', rate_window_start, 60, 4",
      "p_ip_hash !~ '^[0-9a-f]{64}$'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("species stats rate-limit catalog follows wall-clock buckets", async () => {
  const sql = await Deno.readTextFile(catalogTestUrl);
  const wallClockBuckets = sql.match(
    /DATE_PART\s*\(\s*'epoch'\s*,\s*pg_catalog\.CLOCK_TIMESTAMP\(\)\s*\)\s*\/\s*60/g,
  );

  assert(
    wallClockBuckets?.length === 2,
    "User and IP fixtures must use the RPCs' wall clock instead of transaction-scoped NOW().",
  );
  assert(
    !/UPDATE\s+internal\.species_observation_stats_rate_counters/i.test(sql),
    "Rate-limit fixtures must upsert because an earlier call may belong to the preceding minute.",
  );
  assertStringIncludes(
    normalized(sql),
    "ON CONFLICT (scope_type, scope_key, bucket, window_start) DO UPDATE",
  );
});

Deno.test("species stats population is dictionary-bound, distributed, and fenced", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION public.authorize_species_observation_stats_request",
      "FROM public.species_dictionary AS species WHERE species.id = p_species_id FOR SHARE",
      "species_stats_species_mismatch",
      "CREATE OR REPLACE FUNCTION public.claim_species_observation_stats_population",
      "PG_ADVISORY_XACT_LOCK",
      "'species-observation-stats:' || p_species_id::TEXT",
      "lease_expires_at = EXCLUDED.lease_expires_at",
      "next_lease_expiry := quota_now + INTERVAL '90 seconds'",
      "cache.expires_at > quota_now",
      "CREATE OR REPLACE FUNCTION public.finalize_species_observation_stats_population",
      "IF NOT FOUND OR lease_row.lease_token <> p_lease_token THEN RETURN FALSE",
      "p_status NOT IN ('fresh', 'no_data', 'unavailable', 'partial')",
      "WHEN 'no_data' THEN INTERVAL '24 hours'",
      "ELSE INTERVAL '5 minutes'",
      "IF p_status = 'unavailable' THEN UPDATE public.species_observation_stats_cache AS cache",
      "cache.status IN ('fresh', 'partial', 'stale')",
      "cache.fetched_at >= finalized_at - INTERVAL '37 days'",
      "status = 'stale'",
      "ON CONFLICT (species_id, source, scope) DO UPDATE",
      "DELETE FROM internal.species_observation_stats_population_leases AS leases WHERE leases.species_id = p_species_id AND leases.lease_token = p_lease_token",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
  assert(
    !/\bpg_catalog\.(?:coalesce|greatest|least|nullif|extract)\b/i.test(sql),
    "PostgreSQL conditional/special expressions must not be schema-qualified.",
  );
});

Deno.test("species stats privileged RPCs are service-only and allowlisted", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));
  const signatures = [
    "public.preflight_species_observation_stats_request(text)",
    "public.authorize_species_observation_stats_request(uuid,text,uuid)",
    "public.claim_species_observation_stats_population(uuid,uuid,text)",
    "public.finalize_species_observation_stats_population(uuid,uuid,integer,jsonb,text,text)",
  ];

  for (const signature of signatures) {
    assertStringIncludes(sql, `'service_role', '${signature}'`);
  }
  for (
    const functionName of [
      "preflight_species_observation_stats_request",
      "authorize_species_observation_stats_request",
      "claim_species_observation_stats_population",
      "finalize_species_observation_stats_population",
    ]
  ) {
    const start = sql.indexOf(
      `CREATE OR REPLACE FUNCTION public.${functionName}`,
    );
    assert(start >= 0);
    const nextComment = sql.indexOf("COMMENT ON FUNCTION", start);
    const body = sql.slice(start, nextComment);
    assertStringIncludes(
      body,
      "SECURITY DEFINER SET search_path = '' SET statement_timeout = '5s'",
    );
    assertStringIncludes(body, "PERFORM internal.require_service_role()");
  }

  assert(
    !sql.includes(
      "GRANT EXECUTE ON FUNCTION public.authorize_species_observation_stats_request( UUID, TEXT, UUID ) TO anon",
    ),
  );
  assert(
    !sql.includes(
      "GRANT EXECUTE ON FUNCTION public.claim_species_observation_stats_population( UUID, UUID, TEXT ) TO authenticated",
    ),
  );
});
