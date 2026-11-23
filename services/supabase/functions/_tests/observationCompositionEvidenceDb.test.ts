import { assert, assertEquals, assertRejects } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import vectors from "../_shared/analysisHistory/fixtures/composition-request-v5.json" with {
  type: "json",
};
import { compositionFingerprint } from "../_shared/analysisHistory/compositionFingerprint.ts";
import { compositionCohortItems } from "../_shared/analysisHistory/compositionCohort.ts";
import { parseCompositionAdmission } from "../_shared/analysisHistory/compositionAdmission.ts";
import { compositionExecutionProfile } from "../_shared/analysisHistory/compositionExecutionPolicy.ts";
import {
  compositionEvidenceIdentity,
  decodeCompositionEvidenceReceipt,
} from "../_shared/analysisHistory/compositionEvidence.ts";
import { evidenceDispatchFixture } from "./observationEvidenceDispatchFixture.ts";
const url = Deno.env.get("SUPABASE_DB_TEST_URL");
async function connect() {
  assert(
    url && ["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname),
  );
  const db = new Client(url);
  await db.connect();
  return db;
}
async function fixture(db: Client, index: number) {
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
  const [owner, parent, source, child] = Array.from(
    { length: 4 },
    () => crypto.randomUUID(),
  );
  await db.queryArray("SELECT pg_temp.seed_history_append($1,$2)", [
    owner,
    parent,
  ]);
  await db.queryArray(
    "UPDATE internal.observation_history_rollout SET append_enabled=true,source_reservation_enabled=true,source_discovery_enabled=true,composition_source_reservation_enabled=true,composition_source_recovery_enabled=true,composition_runtime_enabled=true,composition_evidence_enabled=true,media_enabled=true",
  );
  await db.queryArray(
    "SELECT internal.append_observation_analysis($1,pg_temp.history_append_request($2,$3))",
    [owner, parent, source],
  );
  const input = {
    ...structuredClone(vectors.filter((v) => v.valid)[index].input),
    observation_id: parent,
    source_analysis_id: source,
    analysis_id: child,
  };
  const envelope = {
    schema_version: 3,
    input,
    fingerprint_version: 1,
    fingerprint: await compositionFingerprint(input),
  };
  await db.queryArray(
    "SELECT public.reserve_owned_observation_composition_source($1,$2::jsonb,14)",
    [owner, JSON.stringify(envelope)],
  );
  const request = {
    ...await compositionEvidenceIdentity(input),
    items: compositionCohortItems(input),
  };
  return { owner, parent, source, child, input, request };
}
async function denied(db: Client, action: () => Promise<unknown>) {
  await db.queryArray("SAVEPOINT denied");
  await assertRejects(action);
  await db.queryArray("ROLLBACK TO SAVEPOINT denied");
}
async function allocate(
  db: Client,
  owner: string,
  request: unknown,
  reader = 14,
) {
  return (await db.queryObject<{ value: unknown }>(
    "SELECT public.reserve_owned_observation_composition_evidence($1,$2::jsonb,$3) value",
    [owner, JSON.stringify(request), reader],
  )).rows[0].value;
}
const encode = (value: unknown) =>
  new TextEncoder().encode(JSON.stringify(value));
for (const [index, vector] of vectors.filter((v) => v.valid).entries()) {
  Deno.test({
    name:
      `composition whole-inventory allocation and readiness: ${vector.name}`,
    ignore: !url,
    async fn() {
      const db = await connect();
      await db.queryArray("BEGIN");
      try {
        const f = await fixture(db, index);
        const ready = (owner = f.owner, input: unknown = f.input) =>
          db.queryArray(
            "SELECT internal.assert_ready_composition_analysis_evidence($1,$2,$3,$4::jsonb)",
            [owner, f.parent, f.child, JSON.stringify(input)],
          );
        assertEquals(
          (await db.queryObject<{ profile: string }>(
            "SELECT internal.observation_composition_execution_profile($1::jsonb) profile",
            [JSON.stringify(f.input)],
          )).rows[0].profile,
          compositionExecutionProfile(parseCompositionAdmission(f.input))
            .profile,
        );
        await denied(db, () => ready());
        await denied(db, () => allocate(db, f.owner, f.request, 12));
        await denied(db, () => allocate(db, crypto.randomUUID(), f.request));
        await denied(
          db,
          () => allocate(db, f.owner, { ...f.request, schema_version: 2 }),
        );
        await denied(db, () =>
          allocate(db, f.owner, {
            ...f.request,
            items: f.request.items.slice(1),
          }));
        await db.queryArray(
          "UPDATE internal.observation_history_rollout SET composition_evidence_enabled=false",
        );
        await denied(db, () => allocate(db, f.owner, f.request));
        await db.queryArray(
          "UPDATE internal.observation_history_rollout SET composition_evidence_enabled=true,composition_runtime_enabled=false",
        );
        await denied(db, () => allocate(db, f.owner, f.request));
        await db.queryArray(
          "UPDATE internal.observation_history_rollout SET composition_runtime_enabled=true",
        );
        let raw = await allocate(db, f.owner, f.request);
        let receipt = await decodeCompositionEvidenceReceipt(
          encode(raw),
          f.input,
          f.owner,
        );
        assertEquals(receipt.state, "allocated");
        assertEquals(receipt.items.length, f.request.items.length);
        await denied(db, () => ready());
        assertEquals(await allocate(db, f.owner, f.request), raw);
        await denied(db, () =>
          db.queryArray(
            "UPDATE internal.observation_composition_evidence_allocations SET items=items WHERE analysis_id=$1",
            [f.child],
          ));
        await denied(db, () =>
          db.queryArray(
            "DELETE FROM internal.observation_composition_evidence_allocations WHERE analysis_id=$1",
            [f.child],
          ));
        await denied(db, () =>
          db.queryArray(
            "SELECT public.complete_owned_observation_composition_evidence($1,$2::jsonb,$3,$4,14)",
            [
              f.owner,
              JSON.stringify(f.request),
              receipt.items[0].media_id,
              crypto.randomUUID(),
            ],
          ));
        await db.queryArray(
          "UPDATE internal.observation_history_rollout SET composition_evidence_enabled=false",
        );
        await denied(
          db,
          () =>
            db.queryArray(
              "SELECT public.complete_owned_observation_composition_evidence($1,$2::jsonb,$3,$4,14)",
              [
                f.owner,
                JSON.stringify(f.request),
                receipt.items[0].media_id,
                receipt.items[0].object_id,
              ],
            ),
        );
        await db.queryArray(
          "UPDATE internal.observation_history_rollout SET composition_evidence_enabled=true,composition_runtime_enabled=false",
        );
        await denied(
          db,
          () =>
            db.queryArray(
              "SELECT public.complete_owned_observation_composition_evidence($1,$2::jsonb,$3,$4,14)",
              [
                f.owner,
                JSON.stringify(f.request),
                receipt.items[0].media_id,
                receipt.items[0].object_id,
              ],
            ),
        );
        await db.queryArray(
          "UPDATE internal.observation_history_rollout SET composition_runtime_enabled=true",
        );
        await denied(
          db,
          () =>
            db.queryArray(
              "UPDATE internal.observation_evidence_objects SET object_id=$1 WHERE media_id=$2",
              [crypto.randomUUID(), receipt.items[0].media_id],
            ),
        );
        for (const item of receipt.items) {
          const previous = encode(raw);
          raw = (await db.queryObject<{ value: unknown }>(
            "SELECT public.complete_owned_observation_composition_evidence($1,$2::jsonb,$3,$4,14) value",
            [
              f.owner,
              JSON.stringify(f.request),
              item.media_id,
              item.object_id,
            ],
          )).rows[0].value;
          receipt = await decodeCompositionEvidenceReceipt(
            encode(raw),
            f.input,
            f.owner,
            previous,
          );
          if (receipt.state !== "ready") await denied(db, () => ready());
        }
        assertEquals(receipt.state, "ready");
        await ready();
        await denied(db, () => ready(crypto.randomUUID()));
        await denied(
          db,
          () => ready(f.owner, { ...f.input, request_digest: "0".repeat(64) }),
        );
        // A retained ready receipt can still be replayed, but an expired cohort
        // cannot authorize fresh funding/execution. This is rollback-only.
        await db.queryArray("SAVEPOINT expired_ready");
        await db.queryArray(
          "ALTER TABLE internal.observation_composition_evidence_allocations DISABLE TRIGGER USER",
        );
        await db.queryArray(
          "ALTER TABLE internal.observation_evidence_objects DISABLE TRIGGER USER",
        );
        await db.queryArray(
          "UPDATE internal.observation_composition_evidence_allocations SET expires_at=date_trunc('milliseconds',clock_timestamp())-interval '1 minute' WHERE analysis_id=$1",
          [f.child],
        );
        await db.queryArray(
          "UPDATE internal.observation_evidence_objects e SET expires_at=a.expires_at FROM internal.observation_composition_evidence_allocations a WHERE a.analysis_id=e.analysis_id AND e.analysis_id=$1",
          [f.child],
        );
        await db.queryArray(
          "ALTER TABLE internal.observation_composition_evidence_allocations ENABLE TRIGGER USER",
        );
        await db.queryArray(
          "ALTER TABLE internal.observation_evidence_objects ENABLE TRIGGER USER",
        );
        await denied(db, () => ready());
        await db.queryArray("ROLLBACK TO SAVEPOINT expired_ready");
        await ready();
        await db.queryArray(
          "UPDATE internal.observation_history_rollout SET composition_evidence_enabled=false,composition_runtime_enabled=false",
        );
        assertEquals(await allocate(db, f.owner, f.request), raw);
        assertEquals(
          (await db.queryObject<{ n: number }>(
            "SELECT count(*)::int n FROM internal.observation_analysis_intents WHERE analysis_id=$1",
            [f.child],
          )).rows[0].n,
          0,
        );
        await db.queryArray(
          "INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES($1,$2)",
          [f.parent, f.owner],
        );
        await denied(db, () => ready());
        assertEquals(
          (await db.queryObject<{ n: number }>(
            "SELECT count(*)::int n FROM internal.observation_composition_evidence_allocations WHERE analysis_id=$1",
            [f.child],
          )).rows[0].n,
          0,
        );
        assertEquals(
          (await db.queryObject<{ n: number }>(
            "SELECT count(*)::int n FROM internal.observation_evidence_erasure WHERE object_id=ANY($1::uuid[])",
            [receipt.items.map((i) => i.object_id)],
          )).rows[0].n,
          receipt.items.length,
        );
      } finally {
        await db.queryArray("ROLLBACK");
        await db.end();
      }
    },
  });
}
Deno.test({
  name:
    "expired mixed allocation requires current cleanup dispatch and retains permanent object identities",
  ignore: !url,
  async fn() {
    const db = await connect();
    await db.queryArray("BEGIN");
    try {
      const f = await fixture(db, 5);
      const raw = await allocate(db, f.owner, f.request);
      const receipt = await decodeCompositionEvidenceReceipt(
        encode(raw),
        f.input,
        f.owner,
      );
      // Rollback-only clock fixture moves both immutable expiry records together.
      await db.queryArray(
        "ALTER TABLE internal.observation_composition_evidence_allocations DISABLE TRIGGER USER",
      );
      await db.queryArray(
        "ALTER TABLE internal.observation_evidence_objects DISABLE TRIGGER USER",
      );
      await db.queryArray(
        "UPDATE internal.observation_composition_evidence_allocations SET expires_at=date_trunc('milliseconds',clock_timestamp())-interval '1 minute' WHERE analysis_id=$1",
        [f.child],
      );
      await db.queryArray(
        "UPDATE internal.observation_evidence_objects e SET expires_at=a.expires_at FROM internal.observation_composition_evidence_allocations a WHERE a.analysis_id=e.analysis_id AND e.analysis_id=$1",
        [f.child],
      );
      await db.queryArray(
        "ALTER TABLE internal.observation_evidence_objects ENABLE TRIGGER USER",
      );
      await db.queryArray(
        "ALTER TABLE internal.observation_composition_evidence_allocations ENABLE TRIGGER USER",
      );
      await db.queryArray(
        "UPDATE internal.observation_history_rollout SET private_evidence_erasure_enabled=true",
      );
      await denied(db, () =>
        db.queryArray(
          "SELECT public.retire_expired_observation_composition_evidence_for_dispatch($1)",
          [crypto.randomUUID()],
        ));
      // Old per-object expiry cannot split a mixed allocation.
      for (const item of receipt.items) {
        await db.queryArray("SELECT internal.expire_observation_evidence($1)", [
          item.media_id,
        ]);
        await db.queryArray(
          "SELECT internal.expire_unbound_observation_evidence($1)",
          [item.media_id],
        );
      }
      assertEquals(
        (await db.queryObject<{ n: number }>(
          "SELECT count(*)::int n FROM internal.observation_evidence_objects WHERE analysis_id=$1",
          [f.child],
        )).rows[0].n,
        receipt.items.length,
      );
      const health = (await db.queryObject<
        {
          value: {
            retirement: {
              composition: number;
              orphan: number;
              objects: number;
            };
          };
        }
      >("SELECT public.get_observation_evidence_erasure_health() value"))
        .rows[0].value;
      assertEquals(health.retirement.composition, 1);
      assertEquals(health.retirement.orphan, 0);
      assertEquals(health.retirement.objects, receipt.items.length);
      const dispatch = await evidenceDispatchFixture(db);
      const retired = (await db.queryObject<{ n: number }>(
        "SELECT public.retire_expired_observation_composition_evidence_for_dispatch($1) n",
        [dispatch.dispatch],
      )).rows[0].n;
      assertEquals(retired, receipt.items.length);
      assertEquals(
        (await db.queryObject<{ n: number }>(
          "SELECT public.retire_expired_observation_composition_evidence_for_dispatch($1) n",
          [dispatch.dispatch],
        )).rows[0].n,
        0,
      );
      await dispatch.restore();
      assertEquals(
        (await db.queryObject<{ n: number }>(
          "SELECT count(*)::int n FROM internal.observation_composition_evidence_allocations WHERE analysis_id=$1",
          [f.child],
        )).rows[0].n,
        1,
      );
      assertEquals(
        (await db.queryObject<{ n: number }>(
          "SELECT count(*)::int n FROM internal.observation_evidence_erasure WHERE object_id=ANY($1::uuid[])",
          [receipt.items.map((i) => i.object_id)],
        )).rows[0].n,
        receipt.items.length,
      );
      await denied(db, () => allocate(db, f.owner, f.request));
    } finally {
      await db.queryArray("ROLLBACK");
      await db.end();
    }
  },
});
