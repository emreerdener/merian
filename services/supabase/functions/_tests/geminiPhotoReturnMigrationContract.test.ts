import { assert, assertStringIncludes } from "@std/assert";

Deno.test("Gemini photo return changes only fresh photo catalog assignments", async () => {
  const sql = (await Deno.readTextFile(
    new URL(
      "../../migrations/20261003063950_restore_gemini_beta_photo_identification.sql",
      import.meta.url,
    ),
  )).replace(/\s+/g, " ");
  for (
    const text of [
      "provider = 'gemini'",
      "binding = 'gemini_baseline_v1'",
      "processor_permission = 'google_gemini'",
      "provider_model = NULL",
      "minimum_identification_protocol = 0",
      "input_profile = 'multimodal_photo_v1'",
      "operation = 'scan_identification'",
      "Gemini photo return source assignment drift",
      "GET DIAGNOSTICS updated_count = ROW_COUNT",
      "updated_count <> photo_count",
    ]
  ) assertStringIncludes(sql, text);
  assertEqualsTargets(sql);
});

function assertEqualsTargets(sql: string) {
  const targets = [...sql.matchAll(/\bUPDATE\s+([a-z_.]+)/gi)].map((m) => m[1]);
  assert(
    targets.length === 1 &&
      targets[0] === "internal.identification_provider_bindings",
  );
  assert(
    !/\b(?:ALTER TABLE|CREATE FUNCTION|DELETE FROM|INSERT INTO|GRANT)\b/i.test(
      sql,
    ),
  );
  assert(!/SET model\s*=|SET minimum_client_protocol\s*=/i.test(sql));
}
