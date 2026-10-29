import { assert } from "@std/assert";

const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261029194445_prepare_initial_cpm_photo_observation_snapshot.sql",
    import.meta.url,
  ),
);

Deno.test("CPM observation read adds no API or mutation authority", () => {
  assert(!/\bGRANT\s|CREATE(?: OR REPLACE)? FUNCTION public\./i.test(sql));
  assert(!/\b(?:INSERT INTO|UPDATE internal\.|DELETE FROM)\b/i.test(sql));
  assert(sql.includes(
    "REVOKE ALL ON FUNCTION internal.read_initial_cpm_photo_observation(UUID,TEXT,UUID,JSONB) FROM PUBLIC,anon,authenticated,service_role",
  ));
  assert(!sql.includes("SECURITY DEFINER"));
});

Deno.test("CPM observation read serializes in existing lifecycle order", () => {
  const capacity = sql.indexOf(
    "PERFORM internal.lock_initial_cpm_photo_capacity()",
  );
  const registry = sql.indexOf("WHERE object_id=a.object_id FOR UPDATE");
  const attempt = sql.indexOf("WHERE attempt_id=p_attempt FOR UPDATE");
  assert(capacity > 0 && capacity < registry && registry < attempt);
  for (
    const clause of [
      "r.claim_token IS DISTINCT FROM p_claim",
      "r.claim_expires_at<=clock_timestamp()",
      "p_expected IS DISTINCT FROM result",
      "internal.assert_initial_preparation_unfunded(owner_id,a.scan_id)",
      "internal.initial_cpm_photo_cohort_complete(a.scan_id)",
      "FOR SHARE OF p,e NOWAIT",
      "e.configuration_digest=a.backend_configuration_digest",
    ]
  ) assert(sql.includes(clause), clause);
});

Deno.test("CPM observation read narrows microsecond windows without renewing claims", () => {
  assert(sql.includes(
    "ceil(extract(epoch FROM r.claim_expires_at-INTERVAL '1 minute')*1000)",
  ));
  assert(sql.includes("floor(extract(epoch FROM r.claim_expires_at)*1000)"));
  assert(sql.includes("ceil(extract(epoch FROM a.issued_at)*1000)"));
  assert(
    sql.includes("floor(extract(epoch FROM a.admission_expires_at)*1000)"),
  );
  assert(!sql.includes("gen_random_uuid"));
});
