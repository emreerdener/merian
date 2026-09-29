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

Deno.test("result readers preserve visibility and fail explicitly before legacy V2 decoding", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20260927185833_require_identification_result_reader.sql",
      import.meta.url,
    ),
  );
  for (
    const required of [
      "SECURITY INVOKER\nSET search_path = ''",
      "RAISE SQLSTATE 'PT426'",
      "MESSAGE = 'client_update_required'",
      "headers -> 'x-merian-identification-protocol' = '\"4\"'::JSONB",
      "p_provenance -> 'version' = '2'::JSONB",
      "CASE WHEN (SELECT auth.uid()) = user_id THEN",
      "CASE WHEN geoprivacy = 'open' AND is_live_capture = TRUE AND is_tombstoned = FALSE THEN",
      "unexpected_scan_reader_policies",
    ]
  ) assertStringIncludes(sql, required);
  assert(
    !/\b(?:UPDATE public|INSERT INTO|DELETE FROM|GRANT SELECT|GRANT UPDATE|SECURITY DEFINER)\b/
      .test(sql),
  );
  assert(!sql.includes("ai_confidence_score"));
  assert(!sql.includes("inference_tier"));
  const factory = await Deno.readTextFile(
    new URL(
      "../../../../apps/ios/Merian/Core/Network/MerianSupabaseClientFactory.swift",
      import.meta.url,
    ),
  );
  assertStringIncludes(
    factory,
    "IdentificationDispatchAuthorization.protocolHeader",
  );
  assertStringIncludes(
    factory,
    "IdentificationDispatchAuthorization.currentProtocol",
  );
});

Deno.test("primary-resolution foundation remains dormant and excludes client recovery authority", async () => {
  const base = new URL("../../", import.meta.url);
  const sql = await Deno.readTextFile(
    new URL(
      "migrations/20260929144441_prepare_primary_identification_resolution.sql",
      base,
    ),
  );
  assert(
    !/\b(?:INSERT INTO|UPDATE) internal\.(?:identification_provider_bindings|ai_quota_policies)\b/
      .test(sql),
  );
  assert(!sql.includes("p_recovery_scan"));
  assert(!/GRANT (?:INSERT|UPDATE)/.test(sql));
  const recovery = await Deno.readTextFile(
    new URL("functions/_shared/scanRecovery.ts", base),
  );
  assert(!recovery.includes("primary_identification"));
  const native = await Deno.readTextFile(
    new URL(
      "../../apps/ios/Merian/Core/Network/Inference/IdentificationPreflight.swift",
      base,
    ),
  );
  assertStringIncludes(native, "static let currentProtocol = 4");
});
