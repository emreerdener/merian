import { assert, assertStringIncludes } from "@std/assert";

Deno.test("beta eligibility migration preserves admission authority and durable counts", async () => {
  const sql = (await Deno.readTextFile(
    new URL(
      "../../migrations/20260919125625_authorize_immediate_field_chat_beta_activation.sql",
      import.meta.url,
    ),
  )).replaceAll(/\s+/g, " ");
  for (
    const fragment of [
      "SELECT * INTO STRICT cutover",
      "WHERE singleton FOR UPDATE",
      "cutover.activated_at IS NULL AND eligible_at < cutover.not_before_utc",
      "beta_original_not_before_utc = cutover.not_before_utc",
      "beta_early_activation_at = eligible_at",
      "not_before_utc = eligible_at",
      "WHERE singleton AND activated_at IS NULL",
      "field_chat_beta_cutover_source_drift",
      "field_chat_beta_cutover_boundary_drift",
    ]
  ) assertStringIncludes(sql, fragment);
  assert(
    !/\b(?:INSERT INTO|UPDATE|DELETE FROM|TRUNCATE).*field_chat_daily_admissions/i
      .test(sql),
  );
  assert(!/\b(?:CREATE|REPLACE|DROP) FUNCTION/i.test(sql));
  assert(!/\bGRANT\b/.test(sql));
});
