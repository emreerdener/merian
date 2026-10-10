import { assert, assertEquals, assertRejects } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import vectors from "../_shared/analysisHistory/fixtures/video-source-fingerprint-v1.json" with {
  type: "json",
};
import legacyVectors from "../_shared/analysisHistory/fixtures/source-fingerprint-v1.json" with {
  type: "json",
};
import { sourceReservationFingerprint } from "../_shared/analysisHistory/sourceFingerprint.ts";
import { videoSourceFingerprint } from "../_shared/analysisHistory/videoSourceFingerprint.ts";
import {
  buildVideoSourceRecoveryRequest,
} from "../_shared/analysisHistory/videoSourceReservation.ts";
import {
  buildVideoSourceRetirementRequest,
  decodeVideoSourceRetirementReceipt,
} from "../_shared/analysisHistory/videoSourceRetirement.ts";
const url = Deno.env.get("SUPABASE_DB_TEST_URL");
const gates = [
  "append_enabled",
  "video_source_retirement_enabled",
  "source_reservation_enabled",
  "source_discovery_enabled",
  "video_source_reservation_enabled",
  "video_source_recovery_enabled",
];
async function connect() {
  assert(
    url && ["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname),
  );
  const db = new Client(url);
  await db.connect();
  return db;
}
async function fixture(db: Client) {
  const sql = await Deno.readTextFile(
    new URL("../../tests/observation_source_reservation.sql", import.meta.url),
  );
  await db.queryArray(
    sql.slice(
      sql.indexOf("CREATE FUNCTION pg_temp.history_append_request"),
      sql.indexOf("SELECT extensions.ok(NOT source_reservation_enabled"),
    ),
  );
  await db.queryArray(
    "SELECT set_config('request.jwt.claim.role','service_role',false)",
  );
}
async function seed(db: Client, owner: string, parent: string, source: string) {
  await db.queryArray("SELECT pg_temp.seed_history_append($1,$2)", [
    owner,
    parent,
  ]);
  await db.queryArray(
    `UPDATE internal.observation_history_rollout SET ${
      gates.map((x) => `${x}=true`).join(",")
    }`,
  );
  await db.queryArray(
    "SELECT internal.append_observation_analysis($1,pg_temp.history_append_request($2,$3))",
    [owner, parent, source],
  );
}
async function candidate(parent: string, source: string, child: string, i = 0) {
  const input = {
    ...structuredClone(vectors[i].input),
    observation_id: parent,
    source_analysis_id: source,
    analysis_id: child,
  };
  return {
    schema_version: 2,
    input,
    fingerprint_version: 1,
    fingerprint: await videoSourceFingerprint(input),
  };
}
async function call(
  db: Client,
  routine: string,
  owner: string,
  request: unknown,
  reader = 12,
) {
  assert(
    [
      "retire_owned_observation_video_source",
      "reserve_owned_observation_video_source",
      "get_owned_observation_video_source",
      "reserve_owned_observation_analysis_source",
    ].includes(routine),
  );
  return (await db.queryObject<{ value: Record<string, unknown> }>(
    `SELECT public.${routine}($1,$2::jsonb,$3) value`,
    [owner, JSON.stringify(request), reader],
  )).rows[0].value;
}
const reserve = (db: Client, owner: string, request: unknown, reader = 12) =>
  call(db, "reserve_owned_observation_video_source", owner, request, reader);
const recover = (db: Client, owner: string, request: unknown, reader = 12) =>
  call(db, "get_owned_observation_video_source", owner, request, reader);
async function denied(db: Client, action: () => Promise<unknown>) {
  await db.queryArray("SAVEPOINT denied");
  await assertRejects(action);
  await db.queryArray("ROLLBACK TO SAVEPOINT denied");
}
const retire = (db: Client, owner: string, request: unknown, reader = 12) =>
  call(db, "retire_owned_observation_video_source", owner, request, reader);
async function cohort(db: Client, child: string) {
  await db.queryArray(
    "INSERT INTO internal.observation_video_evidence_upload_cohorts SELECT analysis_id,owner_id,observation_id,source_analysis_id,internal.observation_video_source_cohort_items(input_snapshot) FROM internal.observation_analysis_source_bindings WHERE analysis_id=$1",
    [child],
  );
}
async function count(db: Client, child: string) {
  return (await db.queryObject<
    { bindings: number; occupancy: number; cohort: number; retired: number }
  >(
    `
 SELECT (SELECT count(*)::int FROM internal.observation_analysis_source_bindings WHERE analysis_id=$1) bindings,
 (SELECT count(*)::int FROM internal.observation_analysis_source_occupancy WHERE analysis_id=$1) occupancy,
 (SELECT count(*)::int FROM internal.observation_video_evidence_upload_cohorts WHERE analysis_id=$1) cohort,
 (SELECT count(*)::int FROM internal.observation_video_source_retirements WHERE analysis_id=$1) retired`,
    [child],
  )).rows[0];
}
for (const withCohort of [false, true]) {
  Deno.test({
    name:
      `video retirement exact replay, private inventory, irreversible fences and successor - cohort=${withCohort}`,
    ignore: !url,
    async fn() {
      const db = await connect();
      await db.queryArray("BEGIN");
      try {
        await fixture(db);
        for (let i = 0; i < 3; i++) {
          const [owner, parent, source, child, next, operation] = Array.from({
            length: 6,
          }, () => crypto.randomUUID());
          await seed(db, owner, parent, source);
          const request = await candidate(parent, source, child, i),
            identity = await buildVideoSourceRecoveryRequest(request);
          const undo = await buildVideoSourceRetirementRequest(
            request,
            operation,
          );
          await reserve(db, owner, request);
          if (withCohort) await cohort(db, child);
          const before = await count(db, child);
          assertEquals(before, {
            bindings: 1,
            occupancy: 1,
            cohort: withCohort ? 1 : 0,
            retired: 0,
          });
          await db.queryArray(
            "UPDATE internal.observation_history_rollout SET video_source_retirement_enabled=false",
          );
          await denied(db, () => retire(db, owner, undo));
          await db.queryArray(
            "UPDATE internal.observation_history_rollout SET video_source_retirement_enabled=true",
          );
          for (
            const patch of [
              { schema_version: 1 },
              { fingerprint: "0".repeat(64) },
              { request_digest: "0".repeat(64) },
              { operation_id: child },
              { unexpected: true },
              { analysis_id: next },
              { source_analysis_id: next },
            ]
          ) {
            await denied(db, () => retire(db, owner, { ...undo, ...patch }));
          }
          await denied(db, () => retire(db, next, undo));
          await denied(db, () => retire(db, owner, undo, 11));
          for (const role of ["anon", "authenticated"]) {
            await denied(db, async () => {
              await db.queryArray(`SET LOCAL ROLE ${role}`);
              await retire(db, owner, undo);
            });
          }
          // Transaction rollback must restore both live rows and discard its proof.
          await db.queryArray("SAVEPOINT rollback_retirement");
          const receipt = await retire(db, owner, undo);
          assertEquals(receipt, {
            ...undo,
            owner_id: owner,
            state: "retired_pre_execution",
          });
          await decodeVideoSourceRetirementReceipt(
            new TextEncoder().encode(JSON.stringify(receipt)),
            request,
            undo,
            owner,
          );
          assertEquals(await count(db, child), {
            bindings: 1,
            occupancy: 0,
            cohort: 0,
            retired: 1,
          });
          await db.queryArray("ROLLBACK TO SAVEPOINT rollback_retirement");
          assertEquals(await count(db, child), before);
          await db.queryArray("SET LOCAL ROLE service_role");
          assertEquals(await retire(db, owner, undo), receipt);
          await db.queryArray("RESET ROLE");
          const inventory = (await db.queryObject<{ valid: boolean }>(
            `SELECT cohort_inventory IS NOT DISTINCT FROM
    CASE WHEN $2::boolean THEN internal.observation_video_source_cohort_items(b.input_snapshot) ELSE 'null'::jsonb END valid
    FROM internal.observation_video_source_retirements r JOIN internal.observation_analysis_source_bindings b USING(analysis_id) WHERE r.analysis_id=$1`,
            [child, withCohort],
          )).rows[0];
          assert(inventory.valid);
          await db.queryArray(
            "UPDATE internal.observation_history_rollout SET video_source_retirement_enabled=false",
          );
          assertEquals(await retire(db, owner, undo), receipt);
          await denied(
            db,
            () => retire(db, owner, { ...undo, operation_id: next }),
          );
          const held = {
            ...identity,
            owner_id: owner,
            state: "held",
            reason: "terminal_unproven",
          };
          assertEquals(await reserve(db, owner, request), held);
          assertEquals(await recover(db, owner, identity), held);
          for (
            const sql of [
              "INSERT INTO internal.observation_analysis_source_occupancy SELECT owner_id,observation_id,source_analysis_id,analysis_id FROM internal.observation_analysis_source_bindings WHERE analysis_id=$1",
              "DELETE FROM internal.observation_video_source_retirements WHERE analysis_id=$1",
              "UPDATE internal.observation_video_source_retirements SET cohort_inventory='null'::jsonb WHERE analysis_id=$1",
              "DELETE FROM internal.observation_analysis_source_bindings WHERE analysis_id=$1",
            ]
          ) {
            await denied(db, () => db.queryArray(sql, [child]));
          }
          await denied(db, () => cohort(db, child));
          await denied(db, () =>
            db.queryArray(
              "SELECT internal.assert_observation_source_input_chain($1,$2,$3,$4::jsonb)",
              [owner, parent, child, JSON.stringify(request.input)],
            ));
          await denied(db, () =>
            db.queryArray(
              "SELECT internal.lock_observation_analysis_source($1,$2,$3)",
              [owner, parent, child],
            ));
          await denied(db, () =>
            db.queryArray(
              "SELECT internal.lock_owned_observation_video_source_binding($1,$2,$3,$4::jsonb)",
              [owner, parent, child, JSON.stringify(request.input)],
            ));
          const legacyInput = {
            ...structuredClone(legacyVectors[0].input),
            observation_id: parent,
            source_analysis_id: source,
            analysis_id: next,
          };
          await denied(
            db,
            async () =>
              call(db, "reserve_owned_observation_analysis_source", owner, {
                schema_version: 1,
                input: legacyInput,
                fingerprint_version: 1,
                fingerprint: await sourceReservationFingerprint(legacyInput),
              }, 11),
          );
          const successor = await candidate(parent, source, next, i);
          assertEquals((await reserve(db, owner, successor)).state, "reserved");
          // Old operation replay remains its original receipt even after a successor.
          assertEquals(await retire(db, owner, undo), receipt);
          await denied(db, async () =>
            retire(db, owner, {
              ...await buildVideoSourceRetirementRequest(successor, operation),
            }));
          await db.queryArray("SELECT public.apply_user_tombstone($1)", [
            owner,
          ]);
          assertEquals(await count(db, child), {
            bindings: 0,
            occupancy: 0,
            cohort: 0,
            retired: 0,
          });
          await denied(db, () => retire(db, owner, undo));
        }
      } finally {
        await db.queryArray("ROLLBACK");
        await db.end();
      }
    },
  });
}

Deno.test({
  name:
    "video retirement rejects corrupt cohort and never infers release from a receipt alone",
  ignore: !url,
  async fn() {
    const db = await connect();
    await db.queryArray("BEGIN");
    try {
      await fixture(db);
      const [owner, parent, source, child, operation, next] = Array.from({
        length: 6,
      }, () => crypto.randomUUID());
      await seed(db, owner, parent, source);
      const request = await candidate(parent, source, child),
        undo = await buildVideoSourceRetirementRequest(request, operation);
      await reserve(db, owner, request);
      await cohort(db, child);
      await db.queryArray("SAVEPOINT corruption");
      await db.queryArray(
        "ALTER TABLE internal.observation_video_evidence_upload_cohorts DISABLE TRIGGER guard_observation_video_cohort",
      );
      await db.queryArray(
        "UPDATE internal.observation_video_evidence_upload_cohorts SET items=jsonb_set(items,'{0,sha256}',to_jsonb(repeat('0',64))) WHERE analysis_id=$1",
        [child],
      );
      await db.queryArray(
        "ALTER TABLE internal.observation_video_evidence_upload_cohorts ENABLE TRIGGER guard_observation_video_cohort",
      );
      await denied(db, () => retire(db, owner, undo));
      assertEquals((await count(db, child)).retired, 0);
      await db.queryArray("ROLLBACK TO SAVEPOINT corruption");
      // Trusted insertion exercises the same receipt guard, before either live row is deleted.
      const receipt = {
        ...undo,
        owner_id: owner,
        state: "retired_pre_execution",
      };
      await db.queryArray(
        `INSERT INTO internal.observation_video_source_retirements SELECT $1,analysis_id,owner_id,observation_id,source_analysis_id,$2::jsonb,$3::jsonb,internal.observation_video_source_cohort_items(input_snapshot) FROM internal.observation_analysis_source_bindings WHERE analysis_id=$4`,
        [operation, JSON.stringify(undo), JSON.stringify(receipt), child],
      );
      assertEquals(
        (await db.queryObject<{ valid: boolean }>(
          "SELECT internal.observation_video_source_release_proven(b) valid FROM internal.observation_analysis_source_bindings b WHERE analysis_id=$1",
          [child],
        )).rows[0].valid,
        false,
      );
      await denied(db, () =>
        db.queryArray(
          "DELETE FROM internal.observation_analysis_source_occupancy WHERE analysis_id=$1",
          [child],
        ));
      await db.queryArray(
        "DELETE FROM internal.observation_video_evidence_upload_cohorts WHERE analysis_id=$1",
        [child],
      );
      assertEquals(
        (await db.queryObject<{ valid: boolean }>(
          "SELECT internal.observation_video_source_release_proven(b) valid FROM internal.observation_analysis_source_bindings b WHERE analysis_id=$1",
          [child],
        )).rows[0].valid,
        false,
      );
      await db.queryArray(
        "DELETE FROM internal.observation_analysis_source_occupancy WHERE analysis_id=$1",
        [child],
      );
      assertEquals(
        (await reserve(db, owner, await candidate(parent, source, next))).state,
        "reserved",
      );
    } finally {
      await db.queryArray("ROLLBACK");
      await db.end();
    }
  },
});

for (
  const scenario of [
    "duplicate",
    "successor",
    "recovery",
    "cohort-after",
    "cohort-before",
    "delete-after",
    "delete-before",
    "dispatch-after",
    "admission-after",
  ]
) {
  Deno.test({
    name: `video retirement canonical blocking - ${scenario}`,
    ignore: !url,
    async fn() {
      const first = await connect(), second = await connect();
      const [owner, parent, source, child, next, operation] = Array.from({
        length: 6,
      }, () => crypto.randomUUID());
      let prior: Record<string, boolean> | undefined;
      try {
        await fixture(first);
        await second.queryArray(
          "SELECT set_config('request.jwt.claim.role','service_role',false)",
        );
        prior = (await first.queryObject<Record<string, boolean>>(
          `SELECT ${gates.join(",")} FROM internal.observation_history_rollout`,
        )).rows[0];
        await seed(first, owner, parent, source);
        const request = await candidate(parent, source, child),
          successor = await candidate(parent, source, next);
        const identity = await buildVideoSourceRecoveryRequest(request),
          undo = await buildVideoSourceRetirementRequest(request, operation);
        await reserve(first, owner, request);
        await first.queryArray("BEGIN");
        await second.queryArray("BEGIN");
        if (scenario === "delete-before") {
          await first.queryArray("SELECT public.apply_user_tombstone($1)", [
            owner,
          ]);
        } else if (scenario === "cohort-before") await cohort(first, child);
        else await retire(first, owner, undo);
        const pid = (await second.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() pid",
        )).rows[0].pid;
        const pending = (scenario === "successor"
          ? reserve(second, owner, successor)
          : scenario === "recovery"
          ? recover(second, owner, identity)
          : scenario === "cohort-after"
          ? cohort(second, child)
          : scenario === "delete-after"
          ? second.queryArray("SELECT public.apply_user_tombstone($1)", [owner])
          : scenario === "dispatch-after"
          ? second.queryArray(
            "SELECT internal.lock_observation_analysis_source($1,$2,$3)",
            [owner, parent, child],
          )
          : scenario === "admission-after"
          ? second.queryArray(
            "SELECT internal.lock_owned_observation_video_source_binding($1,$2,$3,$4::jsonb)",
            [owner, parent, child, JSON.stringify(request.input)],
          )
          : retire(second, owner, undo)).then(
            (value) => ({ value, error: undefined }),
            (error) => ({ value: undefined, error }),
          );
        let blocked = false;
        for (let i = 0; i < 100 && !blocked; i++) {
          blocked = (await first.queryObject<{ blocked: boolean }>(
            "SELECT cardinality(pg_blocking_pids($1))>0 blocked",
            [pid],
          )).rows[0].blocked;
          if (!blocked) {
            await new Promise((r) =>
              setTimeout(r, 5)
            );
          }
        }
        assert(blocked, "actual canonical lock blocking required");
        await first.queryArray("COMMIT");
        const settled = await pending;
        const deniedScenario = [
          "cohort-after",
          "delete-before",
          "dispatch-after",
          "admission-after",
        ].includes(scenario);
        if (deniedScenario) {
          assert(settled.error);
          await second.queryArray("ROLLBACK");
        } else {
          if (settled.error) {
            throw settled.error;
          }
          await second.queryArray("COMMIT");
          if (scenario !== "delete-after") {
            assertEquals(
              (settled.value as Record<string, unknown>).state,
              scenario === "successor"
                ? "reserved"
                : scenario === "recovery"
                ? "held"
                : "retired_pre_execution",
            );
          }
        }
        if (!["delete-after", "delete-before"].includes(scenario)) {
          // Fresh connection emulates response loss/restart: same UUID returns the
          // same durable result and does not invoke any execution routine.
          const restarted = await connect();
          try {
            await restarted.queryArray(
              "SELECT set_config('request.jwt.claim.role','service_role',false)",
            );
            assertEquals(await retire(restarted, owner, undo), {
              ...undo,
              owner_id: owner,
              state: "retired_pre_execution",
            });
          } finally {
            await restarted.end();
          }
        }
      } finally {
        await first.queryArray("ROLLBACK").catch(() => {});
        await second.queryArray("ROLLBACK").catch(() => {});
        await first.queryArray("SELECT public.apply_user_tombstone($1)", [
          owner,
        ]).catch(() => {});
        await first.queryArray("DELETE FROM auth.users WHERE id=$1", [owner])
          .catch(() => {});
        if (prior) {
          await first.queryArray(
            `UPDATE internal.observation_history_rollout SET ${
              gates.map((g, i) => `${g}=$${i + 1}`).join(",")
            }`,
            gates.map((g) => prior![g]),
          );
        }
        await first.end();
        await second.end();
      }
    },
  });
}

Deno.test({
  name:
    "video retirement refuses each independent durable pre-execution namespace",
  ignore: !url,
  async fn() {
    const db = await connect();
    await db.queryArray("BEGIN");
    try {
      await fixture(db);
      const [owner, parent, source, child, operation] = Array.from({
        length: 5,
      }, () => crypto.randomUUID());
      await seed(db, owner, parent, source);
      const request = await candidate(parent, source, child),
        undo = await buildVideoSourceRetirementRequest(request, operation);
      await reserve(db, owner, request);
      await cohort(db, child);
      const before = await count(db, child);
      const provenance = {
        version: 1,
        provider: "gemini",
        binding: "gemini_baseline_v1",
        model: "gemini-2.5-flash",
        variant: "multimodal",
        operation: "scan_identification",
        policy_version: 1,
        prompt: "identify_vision_v1",
        schema: "merian_identify_v1",
        confidence: "unqualified",
        diagnostic_trigger: null,
        prompt_diagnostic_trigger: null,
        safety: null,
        timeout_ms: 90000,
        generation: {
          temperature: 0.1,
          seed: null,
          top_k: null,
          max_output_tokens: 8192,
          thinking_budget: 1024,
        },
      };
      const cases: Record<string, string> = {
        scans:
          "INSERT INTO public.scans SELECT (jsonb_populate_record(NULL::public.scans,to_jsonb(s)||jsonb_build_object('id',f.child))).* FROM public.scans s, f WHERE s.id=f.parent",
        ingestion_jobs:
          "INSERT INTO public.scan_ingestion_jobs(scan_id,user_id) SELECT child::text,owner FROM f",
        ingestion_intents:
          "INSERT INTO public.scan_ingestion_intents(scan_id,user_id) SELECT child::text,owner FROM f",
        tombstone:
          "INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) SELECT child,owner FROM f",
        admission:
          "INSERT INTO internal.observation_analysis_intents(analysis_id,observation_id,owner_id,input_snapshot) SELECT child,parent,owner,input FROM f",
        result:
          "INSERT INTO internal.observation_analysis_results SELECT (jsonb_populate_record(NULL::internal.observation_analysis_results,to_jsonb(r)||jsonb_build_object('analysis_id',f.child,'ordinal',99))).* FROM internal.observation_analysis_results r,f WHERE r.analysis_id=f.source",
        photo_cohort:
          "INSERT INTO internal.observation_evidence_upload_cohorts(analysis_id,observation_id,owner_id,items) SELECT child,parent,owner,'[{}]'::jsonb FROM f",
        audio_cohort:
          "INSERT INTO internal.observation_audio_evidence_upload_cohorts(analysis_id,observation_id,owner_id,media_id,content_type,byte_count,sha256) SELECT child,parent,owner,gen_random_uuid(),'audio/wav',46,repeat('a',64) FROM f",
        evidence_object:
          "INSERT INTO internal.observation_evidence_objects(media_id,observation_id,analysis_id,owner_id,content_type,byte_count,sha256) SELECT gen_random_uuid(),parent,child,owner,'video/mp4',100,repeat('a',64) FROM f",
        quota_original:
          "INSERT INTO internal.ai_quota_reservations(user_id,operation,request_id,model,effective_plan,effective_tier,subscription_tier,trial_active,entitlement_version,policy_version,original_analysis_id) SELECT owner,'scan_identification',gen_random_uuid(),'gemini-2.5-flash','free','free','free',false,1,1,child FROM f",
        quota_request:
          "INSERT INTO internal.ai_quota_reservations(user_id,operation,request_id,model,effective_plan,effective_tier,subscription_tier,trial_active,entitlement_version,policy_version) SELECT owner,'scan_identification',child,'gemini-2.5-flash','free','free','free',false,1,1 FROM f",
        complimentary:
          "INSERT INTO internal.complimentary_scan_usage(user_id,client_scan_id) SELECT owner,child FROM f",
        invocation:
          "INSERT INTO internal.identification_invocations(attempt_count,user_id,scan_id,provider,model,binding,input_profile,effective_plan,policy_version,provenance) SELECT 1,owner,child,'gemini','gemini-2.5-flash','gemini_baseline_v1','multimodal_photo_v1','free',1,provenance FROM f",
        witness:
          "INSERT INTO internal.observation_analysis_dispatch_witnesses(analysis_id,owner_id,observation_id,source_analysis_id,fingerprint,reservation_id,lease_sha256,attempt_count,provenance,dispatch_transaction) SELECT child,owner,parent,source,repeat('a',64),gen_random_uuid(),repeat('a',64),1,provenance,pg_current_xact_id() FROM f",
        funded_retirement:
          "INSERT INTO internal.observation_analysis_retirement_receipts(operation_id,analysis_id,observation_id,owner_id,request_identity,receipt) SELECT gen_random_uuid(),child,parent,owner,'{}'::jsonb,'{\"state\":\"retired_before_dispatch\"}'::jsonb FROM f",
        unfunded_retirement:
          "INSERT INTO internal.observation_source_unfunded_retirements(operation_id,analysis_id,owner_id,observation_id,source_analysis_id,request_identity,receipt) SELECT gen_random_uuid(),child,owner,parent,source,'{}'::jsonb,'{}'::jsonb FROM f",
        completion:
          "INSERT INTO internal.observation_source_completion_receipts(analysis_id,owner_id,observation_id,source_analysis_id,proof) SELECT child,owner,parent,source,'{}'::jsonb FROM f",
      };
      for (const [name, sql] of Object.entries(cases)) {
        await db.queryArray("SAVEPOINT namespace_fixture");
        // Privileged corruption fixture isolates one namespace at a time without
        // fabricating its prerequisite admission chain. Restore all triggers before
        // calling retirement; no function or CHECK constraint is changed.
        await db.queryArray("SET LOCAL session_replication_role=replica");
        await db.queryArray(
          `WITH f AS(SELECT $1::uuid owner,$2::uuid parent,$3::uuid source,$4::uuid child,$5::jsonb input,$6::jsonb provenance) ${sql}`,
          [
            owner,
            parent,
            source,
            child,
            JSON.stringify(request.input),
            JSON.stringify(provenance),
          ],
        );
        await db.queryArray("SET LOCAL session_replication_role=origin");
        assertEquals(
          (await db.queryObject<{ clear: boolean }>(
            "SELECT internal.observation_video_source_preexecution_clear($1) clear",
            [child],
          )).rows[0].clear,
          false,
          name,
        );
        await denied(db, () => retire(db, owner, undo));
        assertEquals(await count(db, child), before, name);
        await db.queryArray("ROLLBACK TO SAVEPOINT namespace_fixture");
      }
    } finally {
      await db.queryArray("ROLLBACK");
      await db.end();
    }
  },
});
