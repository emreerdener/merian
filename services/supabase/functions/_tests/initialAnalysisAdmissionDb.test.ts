import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import vectors from "../_shared/initialAnalysis/fixtures/admission-v1.json" with {
  type: "json",
};
import { initialCanonicalText } from "../_shared/initialAnalysis/canonical.ts";

const url = Deno.env.get("SUPABASE_DB_TEST_URL");
function localURL(): string {
  assert(url);
  assert(["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname));
  return url;
}
async function install(client: Client) {
  await client.connect();
  const sql = await Deno.readTextFile(
    new URL("../../tests/initial_analysis_admission.sql", import.meta.url),
  );
  await client.queryArray(
    sql.split("-- BEGIN INITIAL ADMISSION HELPERS\n")[1].split(
      "-- END INITIAL ADMISSION HELPERS",
    )[0],
  );
  await client.queryArray("SET statement_timeout='10s'");
  await client.queryArray(
    "SELECT set_config('request.jwt.claim.role','service_role',false)",
  );
}
async function admit(
  client: Client,
  owner: string,
  scan: string,
  changed = false,
) {
  return (await client.queryObject<
    { value: { outcome: string; binding: unknown } }
  >(
    "SELECT pg_temp.admit_initial($1,$2,CASE WHEN $3 THEN jsonb_set(pg_temp.admission_input(),'{ordered_descriptions}','[\"Changed synthetic text\"]') ELSE pg_temp.admission_input() END) AS value",
    [owner, scan, changed],
  )).rows[0].value;
}
Deno.test({
  name: "IC-1 database canonical and semantic vectors match TypeScript",
  ignore: !url,
  async fn() {
    const db = new Client(localURL());
    try {
      await install(db);
      for (const vector of vectors.valid) {
        const actual = (await db.queryObject<
          { canonical: string; digest: string; profile: string }
        >(
          "SELECT internal.initial_canonical(internal.parse_initial_input($1)) AS canonical, internal.initial_digest('input',$1) AS digest,internal.initial_input_semantics(internal.parse_initial_input($1)) AS profile",
          [vector.canonical],
        )).rows[0];
        assertEquals(actual, {
          canonical: vector.canonical,
          digest: vector.digest,
          profile: vector.profile,
        }, vector.name);
      }
      for (const vector of vectors.invalid) {
        // Raw strings intentionally include invalid encodings that JSONB would otherwise normalize.
        let encoded: string;
        try {
          encoded = "canonical" in vector
            ? vector.canonical!
            : initialCanonicalText(vector.input);
        } catch {
          encoded = JSON.stringify(vector.input);
        }
        const error = await db.queryArray(
          "SELECT internal.parse_initial_input($1)",
          [encoded],
        ).then(() => null, (error: unknown) => error);
        assert(error instanceof Error, vector.name);
      }
    } finally {
      await db.end();
    }
  },
});

for (
  const scenario of [
    "duplicate",
    "conflict",
    "cross-owner",
    "legacy-first",
    "admission-first",
    "null-first",
    "null-second",
    "alias-first",
    "alias-second",
    "delete-first",
    "delete-second",
    "account-first",
    "account-second",
  ] as const
) {
  Deno.test({
    name: `IC-1 database admission race - ${scenario}`,
    ignore: !url,
    async fn() {
      const first = new Client(localURL()),
        second = new Client(localURL()),
        observer = new Client(localURL());
      const owner = crypto.randomUUID(),
        other = crypto.randomUUID(),
        scan = crypto.randomUUID();
      let previous:
        | { enabled: boolean; mode: string; protocol: number }
        | undefined;
      try {
        await install(first);
        await install(second);
        await observer.connect();
        previous = (await first.queryObject<
          { enabled: boolean; mode: string; protocol: number }
        >("SELECT initial_analysis_lifecycle_enabled AS enabled,entitlement_mode AS mode,required_client_protocol AS protocol FROM internal.initial_analysis_rollout CROSS JOIN internal.entitlement_rollout_config WHERE config_key='current'"))
          .rows[0];
        await first.queryArray(
          "UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE",
        );
        await first.queryArray(
          "UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current'",
        );
        await first.queryArray("SELECT pg_temp.admission_owner($1)", [owner]);
        await first.queryArray("SELECT pg_temp.admission_owner($1)", [other]);
        const alias = scenario.startsWith("alias"),
          omitted = scenario.startsWith("null");
        const originalID = alias ? crypto.randomUUID() : omitted ? null : scan;
        const legacyOwner = alias || omitted ? other : owner;
        await first.queryArray(
          "UPDATE public.users SET subscription_tier='pro',subscription_expires_at=NULL WHERE id=$1",
          [other],
        );
        const legacy = (db: Client) =>
          db.queryArray(
            "SELECT public.reserve_identification_quota($1,'scan_identification',$2,repeat('a',64),$3,TRUE,3,FALSE,'description_compat_v1','google_gemini',6)",
            [legacyOwner, scan, originalID],
          );
        const erase = async (db: Client) => {
          if (scenario.startsWith("account")) {
            await db.queryArray("DELETE FROM public.users WHERE id=$1", [
              owner,
            ]);
          } else {
            await db.queryArray(
              "SELECT id FROM public.users WHERE id=$1 FOR UPDATE",
              [owner],
            );
            await db.queryArray(
              "SELECT pg_advisory_xact_lock(hashtextextended('merian-scan-ingestion:'||$1::text,0::bigint))",
              [scan],
            );
            await db.queryArray(
              "INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id,completed_at) VALUES($1,NULL,now())",
              [scan],
            );
          }
        };
        await first.queryArray("BEGIN");
        await second.queryArray("BEGIN");
        const pid = (await second.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() AS pid",
        )).rows[0].pid;
        let original: { outcome: string; binding: unknown } | undefined;
        if (["legacy-first", "null-first", "alias-first"].includes(scenario)) {
          await legacy(first);
        } else if (
          scenario === "delete-first" || scenario === "account-first"
        ) await erase(first);
        else original = await admit(first, owner, scan);
        const action =
          ["admission-first", "null-second", "alias-second"].includes(scenario)
            ? legacy(second)
            : scenario === "delete-second" || scenario === "account-second"
            ? erase(second)
            : admit(
              second,
              scenario === "cross-owner" ? other : owner,
              scan,
              scenario === "conflict",
            );
        const pending = action.then(
          (value) => ({ value, error: null }),
          (error: unknown) => ({ value: null, error }),
        );
        const failFast = scenario === "null-second" ||
          scenario === "alias-second";
        if (!failFast) {
          let blocked = false;
          for (let i = 0; i < 100; i++) {
            if (
              (await observer.queryObject<{ blocked: boolean }>(
                "SELECT cardinality(pg_blocking_pids($1))>0 AS blocked",
                [pid],
              )).rows[0].blocked
            ) {
              blocked = true;
              break;
            }
            await new Promise((resolve) => setTimeout(resolve, 10));
          }
          assert(
            blocked,
            "competing statement must demonstrably wait on first transaction",
          );
        } else {
          const early = await pending;
          assert(early.error instanceof Error);
          assert(early.error.message.includes("initial_analysis_scope_busy"));
        }
        await first.queryArray("COMMIT");
        const result = await pending;
        const expected: Partial<Record<typeof scenario, string>> = {
          conflict: "initial_analysis_identity_conflict",
          "cross-owner": "initial_analysis_owner_unavailable",
          "legacy-first": "initial_analysis_identity_conflict",
          "null-first": "initial_analysis_identity_conflict",
          "alias-first": "initial_analysis_identity_conflict",
          "null-second": "initial_analysis_scope_busy",
          "alias-second": "initial_analysis_scope_busy",
          "admission-first": "initial_analysis_admission_required",
          "delete-first": "initial_analysis_deleted",
          "account-first": "initial_analysis_owner_unavailable",
        };
        if (expected[scenario]) {
          assert(result.error instanceof Error);
          assert(result.error.message.includes(expected[scenario]!));
          await second.queryArray("ROLLBACK");
        } else {
          assertEquals(result.error, null);
          await second.queryArray("COMMIT");
          if (scenario === "duplicate") {
            assertEquals(result.value, {
              ...original!,
              outcome: "replay",
            });
          }
        }
        const erased = scenario.startsWith("delete") ||
          scenario.startsWith("account");
        const counts = (await first.queryObject<
          { admissions: bigint; funding: bigint; invocations: bigint }
        >(
          "SELECT (SELECT count(*) FROM internal.initial_analysis_admissions WHERE scan_id=$1) AS admissions,(SELECT count(*) FROM internal.ai_quota_reservations WHERE original_analysis_id=$1 OR request_id=$1) AS funding,(SELECT count(*) FROM internal.identification_invocations WHERE scan_id=$1) AS invocations",
          [scan],
        )).rows[0];
        assertEquals(
          counts.admissions,
          erased ||
            ["legacy-first", "null-first", "alias-first"].includes(scenario)
            ? 0n
            : 1n,
        );
        assertEquals(
          counts.funding,
          scenario.startsWith("account") || scenario === "delete-first"
            ? 0n
            : 1n,
          "exact original funding survives scan erasure; owner erasure cascades",
        );
        const usage = (await first.queryObject<{ state: string }>(
          "SELECT state FROM internal.complimentary_scan_usage WHERE client_scan_id=$1",
          [scan],
        )).rows;
        assertEquals(
          usage,
          scenario.startsWith("account") ||
            ["delete-first", "null-first", "alias-first"].includes(scenario)
            ? []
            : [{ state: "held" }],
          "no consumption or speculative refund; only owner erasure cascades the hold",
        );
        assertEquals(counts.invocations, 0n);
        if (erased) {
          const retry = await admit(first, owner, scan).then(
            () => null,
            (error: unknown) => error,
          );
          assert(retry instanceof Error);
          assert(
            ["initial_analysis_deleted", "initial_analysis_owner_unavailable"]
              .some((code) => retry.message.includes(code)),
          );
        }
      } finally {
        await second.queryArray("ROLLBACK").catch(() => {});
        await first.queryArray("ROLLBACK").catch(() => {});
        await first.queryArray(
          "DELETE FROM public.users WHERE id=ANY($1::uuid[])",
          [[owner, other]],
        );
        await first.queryArray(
          "DELETE FROM auth.users WHERE id=ANY($1::uuid[])",
          [[owner, other]],
        );
        // Content-free permanent operation/deletion fences intentionally survive fixture erasure.
        if (previous) {
          await first.queryArray(
            "UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=$1",
            [previous.enabled],
          );
          await first.queryArray(
            "UPDATE internal.entitlement_rollout_config SET entitlement_mode=$1,required_client_protocol=$2 WHERE config_key='current'",
            [previous.mode, previous.protocol],
          );
        }
        await first.end();
        await second.end();
        await observer.end();
      }
    },
  });
}

Deno.test({
  name:
    "IC-1 every retained input profile freezes original selectors and funding",
  ignore: !url,
  async fn() {
    const db = new Client(localURL());
    try {
      await install(db);
      await db.queryArray("BEGIN");
      await db.queryArray(
        "UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE",
      );
      await db.queryArray(
        "UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current'",
      );
      for (const vector of vectors.valid) {
        const owner = crypto.randomUUID(), scan = crypto.randomUUID();
        await db.queryArray("SELECT pg_temp.admission_owner($1)", [owner]);
        const result = (await db.queryObject<
          { value: { outcome: string; binding: unknown } }
        >("SELECT pg_temp.admit_initial($1,$2,$3::jsonb) AS value", [
          owner,
          scan,
          JSON.stringify(vector.input),
        ])).rows[0].value;
        assertEquals(result.outcome, "admitted", vector.name);
        const saved = (await db.queryObject<
          { profile: string; funding: boolean; configuration: boolean }
        >(
          "SELECT s.configuration_snapshot#>>'{assignment,input_profile}' AS profile,a.funding_digest=internal.initial_digest('funding',internal.initial_canonical(s.funding_snapshot)) AS funding,a.configuration_digest=internal.initial_digest('configuration',internal.initial_canonical(s.configuration_snapshot)) AS configuration FROM internal.initial_analysis_submissions s JOIN internal.initial_analysis_admissions a USING(scan_id) WHERE scan_id=$1",
          [scan],
        )).rows[0];
        assertEquals(saved, {
          profile: vector.profile,
          funding: true,
          configuration: true,
        });
        const replay = (await db.queryObject<
          { value: { outcome: string; binding: unknown } }
        >(
          "SELECT public.admit_initial_analysis($1,$2,$3,$4,NULL,NULL) AS value",
          [owner, scan, vector.canonical, vector.digest],
        )).rows[0].value;
        assertEquals(replay, { ...result, outcome: "replay" });
      }
    } finally {
      await db.queryArray("ROLLBACK").catch(() => {});
      await db.end();
    }
  },
});
