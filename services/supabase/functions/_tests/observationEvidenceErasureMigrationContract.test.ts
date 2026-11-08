import { assert, assertStringIncludes } from "@std/assert";

const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261006222120_prepare_private_evidence_erasure_worker.sql",
    import.meta.url,
  ),
);

Deno.test("private evidence cleanup preserves independent gate and immutable cohort", () => {
  assertStringIncludes(
    sql,
    "private_evidence_erasure_enabled BOOLEAN NOT NULL DEFAULT FALSE",
  );
  assert(
    !/DELETE FROM internal\.observation_evidence_upload_cohorts/i.test(sql),
  );
  assert(!/UPDATE internal\.observation_evidence_upload_cohorts/i.test(sql));
  const retire = sql.slice(
    sql.indexOf("CREATE FUNCTION public.retire_expired"),
  );
  assert(
    retire.indexOf("lock_owned_observation_evidence") <
      retire.indexOf("FOR UPDATE"),
  );
  assertStringIncludes(retire, "candidate.media_id IS NULL");
  assertStringIncludes(retire, "IF FOUND THEN RETURN 0; END IF;");
  assertStringIncludes(
    retire,
    "valid_observation_erasure_cohort_items(c.items)",
  );
});

Deno.test("private evidence cleanup exposes only service facades and allows late gate-off settlement", () => {
  for (
    const name of [
      "retire_expired_observation_evidence",
      "claim_observation_evidence_erasure",
      "finish_observation_evidence_erasure",
    ]
  ) {
    const body =
      sql.slice(sql.indexOf(`CREATE FUNCTION public.${name}`)).split("$$;")[0];
    assertStringIncludes(body, "internal.require_service_role()");
    assertStringIncludes(sql, `'service_role','public.${name}(`);
  }
  const finish = sql.slice(
    sql.indexOf("CREATE FUNCTION public.finish_observation_evidence_erasure"),
  ).split("$$;")[0];
  assert(!finish.includes("private_evidence_erasure_enabled"));
  assertStringIncludes(sql, "'claim_expires_at',claim->'claim_expires_at'");
});
