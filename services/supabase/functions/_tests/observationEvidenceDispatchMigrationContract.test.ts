import { assert, assertEquals, assertStringIncludes } from "@std/assert";

const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261112003746_fence_legacy_private_cleanup_acquisition.sql",
    import.meta.url,
  ),
);
const names = [
  "retire_expired_observation_evidence",
  "retire_expired_observation_video_evidence",
  "claim_observation_evidence_erasure",
];

Deno.test("dispatch cutover denies original OIDs instead of renaming or dropping them", () => {
  assert(!/\b(?:DROP|ALTER)\s+FUNCTION/i.test(sql));
  for (const name of names) {
    const body = sql.split(`CREATE OR REPLACE FUNCTION public.${name}()`)[1]
      ?.split("$$;")[0];
    assert(body);
    assertStringIncludes(body, "legacy_private_evidence_acquisition_denied");
    assertStringIncludes(body, "ERRCODE='42501'");
    assertStringIncludes(
      sql,
      `REVOKE ALL ON FUNCTION public.${name}() FROM PUBLIC,anon,authenticated,service_role;`,
    );
  }
  assert(
    !/UPDATE\s+internal\.observation_evidence_worker_state|cron\.|CREATE OR REPLACE FUNCTION public\.finish_observation_evidence_erasure/i
      .test(sql),
  );
});

Deno.test("dispatch facades authorize directly and hold the current slot through acquisition", () => {
  for (const name of names) {
    const body = sql.split(
      `CREATE FUNCTION public.${name}_for_dispatch(p_dispatch_id UUID)`,
    )[1]?.split("$$;")[0];
    assert(body);
    assert(
      body.indexOf("internal.require_service_role()") <
        body.indexOf(
          "internal.require_observation_evidence_dispatch(p_dispatch_id)",
        ),
    );
    assert(
      body.indexOf(
        "internal.require_observation_evidence_dispatch(p_dispatch_id)",
      ) < body.indexOf(`internal.${name}_worker_impl()`),
    );
    assert(!/DEFAULT/i.test(body));
    assertStringIncludes(
      sql,
      `REVOKE ALL ON FUNCTION internal.${name}_worker_impl() FROM PUBLIC,anon,authenticated,service_role;`,
    );
  }
  const guard = sql.split(
    "CREATE FUNCTION internal.require_observation_evidence_dispatch",
  )[1].split("$$;")[0];
  assertStringIncludes(guard, "WHERE singleton FOR UPDATE");
  for (
    const condition of [
      "p_dispatch_id IS NULL",
      "NOT state.enabled",
      "state.pending_request_id IS NULL",
      "state.pending_dispatch_id IS DISTINCT FROM p_dispatch_id",
      "observation_evidence_worker_transport(state.approved_project) IS NULL",
      "private_evidence_erasure_enabled",
    ]
  ) assertStringIncludes(guard, condition);
  assertEquals([...sql.matchAll(/GRANT EXECUTE ON FUNCTION/g)].length, 3);
});
