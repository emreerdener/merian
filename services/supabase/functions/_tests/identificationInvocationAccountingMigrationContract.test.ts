import { assert, assertStringIncludes } from "@std/assert";

Deno.test("primary accounting migration preserves dispatch holds and append-only billing authority", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20260927230801_account_identification_invocations.sql",
      import.meta.url,
    ),
  );
  for (
    const text of [
      "UNIQUE (reservation_id, attempt_count)",
      "RETURN QUERY SELECT invocation.id, FALSE",
      "FOR UPDATE SKIP LOCKED",
      "INTERVAL '5 minutes'",
      "INTERVAL '30 days'",
      "ON CONFLICT (source_type, source_id, operation) DO NOTHING",
      "EXCLUDE USING gist",
      "internal.privileged_routine_grants",
      "trg_aa_anonymize_identification_invocations",
    ]
  ) assertStringIncludes(sql, text);
  assert(
    sql.indexOf("IF price IS NULL") <
      sql.indexOf("PERFORM public.finalize_ai_quota_reservation"),
  );
  assert(!/^\s*UPDATE public.ai_usage_events/m.test(sql));
  assert(!/REFERENCES internal.ai_quota/.test(sql));
  assert(
    !/(INSERT INTO|UPDATE) internal.identification_provider_bindings/.test(sql),
  );
  const production = await Deno.readTextFile(
    new URL("../_shared/ai/production.ts", import.meta.url),
  );
  assertStringIncludes(
    production,
    "OPENAI_PHOTO_DISPATCH_ENABLED: boolean = false",
  );
});
