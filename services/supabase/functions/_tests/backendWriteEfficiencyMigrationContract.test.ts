import { assert, assertEquals, assertStringIncludes } from "@std/assert";

const read = (name: string) =>
  Deno.readTextFile(new URL(`../../migrations/${name}`, import.meta.url));
const dispatch = await read(
  "20260917144755_skip_idle_explore_media_dispatch.sql",
);
const lookalikes = await read(
  "20260917144804_avoid_unchanged_lookalike_writes.sql",
);
const normalized = (sql: string) => sql.replaceAll(/\s+/g, " ");

Deno.test("idle dispatch migration preserves paused state and credential transport", () => {
  const sql = normalized(dispatch);
  assertStringIncludes(sql, "INTO STRICT media_job");
  assertStringIncludes(sql, "media_job.schedule <> '*/5 * * * *'");
  assertStringIncludes(sql, "cron.alter_job(media_job.jobid, command :=");
  assert(!/cron\.(?:unschedule|schedule)\s*\(/i.test(sql));
  assert(!/\b(?:active|schedule)\s*:=/i.test(sql));
  const gate = sql.indexOf("IF pg_catalog.DATE_PART('minute', dispatch_at)");
  assert(gate >= 0 && gate < sql.indexOf("SELECT decrypted_secret"));
  assertStringIncludes(sql, "::INTEGER % 10 <> 0 AND NOT EXISTS");
  assertStringIncludes(
    sql,
    "headers := internal.server_api_request_headers(service_role_key)",
  );
  assertStringIncludes(sql, "'limit', 200, 'leaseSeconds', 300");
  assertStringIncludes(sql, "timeout_milliseconds := 120000");
});

Deno.test("dispatch eligibility matches the authoritative claim predicate without acquiring locks", async () => {
  const historical = await read(
    "20260726144754_implement_explore_media_quarantine_state_machine.sql",
  );
  const start = historical.indexOf(
    "CREATE OR REPLACE FUNCTION public.claim_explore_media_health_checks(",
  );
  const claim = normalized(
    historical.slice(start, historical.indexOf("\n$$;", start)),
  )
    .replaceAll("pg_catalog.NOW()", "dispatch_at");
  const gate = normalized(
    dispatch.slice(
      dispatch.indexOf("IF pg_catalog.DATE_PART"),
      dispatch.indexOf("SELECT decrypted_secret"),
    ),
  );
  for (
    const predicate of [
      "post.id = media.post_id",
      "scan.id = post.scan_id",
      "existing_claim.media_id = media.id",
      "existing_claim.claimed_until > dispatch_at",
      "media.next_health_check_at <= dispatch_at",
      "post.unshared_at IS NULL",
      "post.moderated_at IS NULL",
      "NOT scan.is_tombstoned",
      "existing_claim.media_id IS NULL",
    ]
  ) {
    assertStringIncludes(claim, predicate);
    assertStringIncludes(gate, predicate);
  }
  assert(
    !/FOR UPDATE|SKIP LOCKED|INSERT INTO|DELETE FROM|\bUPDATE\b/i.test(gate),
  );
});

Deno.test("no-op persistence retains service boundary, serialization and refresh accounting", () => {
  const sql = normalized(lookalikes);
  for (
    const contract of [
      "CREATE OR REPLACE FUNCTION public.persist_species_model_lookalikes(",
      "RETURNS TABLE (persisted_count INTEGER, unresolved_count INTEGER, rejected_count INTEGER)",
      "SECURITY DEFINER SET search_path = ''",
      "PERFORM internal.require_service_role()",
      "'merian:species-model-lookalikes'",
      "FOR NO KEY UPDATE",
      "relation.review_status = 'unreviewed'",
      "IS DISTINCT FROM",
      "IF model_refresh_count > 0 THEN",
      "provenance.source NOT IN ('manual_curation', 'user_review')",
      "REVOKE ALL ON FUNCTION public.persist_species_model_lookalikes(UUID, JSONB, BOOLEAN) FROM PUBLIC, anon, authenticated, service_role",
      "GRANT EXECUTE ON FUNCTION public.persist_species_model_lookalikes(UUID, JSONB, BOOLEAN) TO service_role",
    ]
  ) assertStringIncludes(sql, contract);
  assert(
    !sql.includes("GET DIAGNOSTICS"),
    "freshness cannot depend on physical affected-row counts",
  );
});

for (
  const [file, count] of [
    ["explore_media_dispatch.sql", 13],
    ["lookalike_write_efficiency.sql", 7],
  ] as const
) {
  Deno.test(`${file} is transactional and fully planned`, async () => {
    const sql = await Deno.readTextFile(
      new URL(`../../tests/${file}`, import.meta.url),
    );
    assertStringIncludes(sql, "BEGIN;");
    assert(sql.trimEnd().endsWith("ROLLBACK;"));
    assertEquals(Number(sql.match(/extensions\.plan\((\d+)\)/)?.[1]), count);
    assertEquals(
      sql.match(/^SELECT extensions\.(?:ok|is|pass|throws_ok)\(/gm)?.length,
      count,
    );
  });
}
