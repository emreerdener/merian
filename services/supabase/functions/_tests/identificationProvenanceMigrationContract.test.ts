import { assert, assertStringIncludes } from "@std/assert";

Deno.test("provenance migration is additive, content-free and compatible with existing recovery", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20260926160249_persist_identification_result_provenance.sql",
      import.meta.url,
    ),
  );
  for (
    const expected of [
      "AFTER INSERT ON public.scans",
      "BEFORE UPDATE OF identification_provenance ON public.scan_ingestion_jobs",
      "jobs.scan_id = NEW.id::TEXT AND jobs.user_id = NEW.user_id",
      "identification_provenance_immutable",
      "identification_provenance_job_mismatch",
      "SECURITY DEFINER\nSET search_path = ''",
      "p_value - ARRAY[",
      "generation - ARRAY[",
      "> 2048",
    ]
  ) {
    assertStringIncludes(sql, expected);
  }
  assert(
    !sql.includes(
      "CREATE OR REPLACE FUNCTION public.recover_missing_owned_scan",
    ),
  );
  assert(!sql.includes("p_recovery_scan"));
  assert(!sql.includes("UPDATE internal.ai_quota_policies"));
  assert(!sql.includes("GRANT INSERT"));
  assert(!sql.includes("GRANT UPDATE"));
  assert(!sql.includes("REFERENCES internal.ai_quota_reservations"));
});

Deno.test("v2 provenance migration preserves the v1 generation validator and existing routing, rows and permissions", async () => {
  const original = await Deno.readTextFile(
    new URL(
      "../../migrations/20260926160249_persist_identification_result_provenance.sql",
      import.meta.url,
    ),
  );
  const forward = await Deno.readTextFile(
    new URL(
      "../../migrations/20260927165545_accept_openai_identification_provenance_v2.sql",
      import.meta.url,
    ),
  );
  const start = original.indexOf("    IF NOT generation ?& ARRAY[");
  assertStringIncludes(
    forward,
    original.slice(start, original.indexOf("-- Pure CHECK predicate")),
  );
  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION internal.identification_provenance_is_valid",
      "> 2048",
      "NOT IN ('1'::JSONB, '2'::JSONB)",
      "p_value ->> 'provider' <> 'openai'",
      "generation - ARRAY['max_output_tokens', 'reasoning_effort', 'image_detail']",
      "SET search_path = ''",
    ]
  ) assertStringIncludes(forward, fragment);
  assert(
    !/\b(?:ALTER TABLE|UPDATE|INSERT|GRANT|REVOKE|CREATE TRIGGER)\b/.test(
      forward,
    ),
  );
});
