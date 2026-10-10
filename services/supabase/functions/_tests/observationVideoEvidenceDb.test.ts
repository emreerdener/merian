import {
  buildVideoEvidenceUploadRequest,
  decodeVideoEvidenceAllocation,
  decodeVideoEvidenceReceipt,
} from "../_shared/analysisHistory/videoEvidence.ts";
import { assert, assertEquals, assertRejects } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import vectors from "../_shared/analysisHistory/fixtures/video-source-fingerprint-v1.json" with {
  type: "json",
};
import { videoSourceFingerprint } from "../_shared/analysisHistory/videoSourceFingerprint.ts";
import {
  buildVideoSourceRetirementRequest,
} from "../_shared/analysisHistory/videoSourceRetirement.ts";
const url = Deno.env.get("SUPABASE_DB_TEST_URL");
const gates = [
  "append_enabled",
  "media_enabled",
  "video_evidence_enabled",
  "private_evidence_erasure_enabled",
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
      gates.map((x) => `${x}=${x !== "private_evidence_erasure_enabled"}`).join(
        ",",
      )
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
      "reserve_owned_observation_video_evidence",
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

const allocate = (db: Client, owner: string, request: unknown, reader = 12) =>
  call(db, "reserve_owned_observation_video_evidence", owner, request, reader);
const bytes = (v: unknown) => new TextEncoder().encode(JSON.stringify(v));
async function complete(
  db: Client,
  owner: string,
  request: unknown,
  item: { media_id: string; object_id: string },
  reader = 12,
) {
  return (await db.queryObject<{ value: unknown }>(
    "SELECT public.complete_owned_observation_video_evidence($1,$2::jsonb,$3::uuid,$4::uuid,$5) value",
    [owner, JSON.stringify(request), item.media_id, item.object_id, reader],
  )).rows[0].value;
}
for (const withCohort of [false, true]) {
  Deno.test({
    name:
      `video allocation complete inventory and fixed replay cohort=${withCohort}`,
    ignore: !url,
    async fn() {
      const db = await connect();
      try {
        await fixture(db);
        for (let i = 0; i < 3; i++) {
          await db.queryArray("BEGIN");
          try {
            const [owner, parent, source, child] = Array.from(
              { length: 4 },
              () => crypto.randomUUID(),
            );
            await seed(db, owner, parent, source);
            const c = await candidate(parent, source, child, i),
              request = await buildVideoEvidenceUploadRequest(c);
            await reserve(db, owner, c);
            if (withCohort) await cohort(db, child);
            await db.queryArray(
              "UPDATE internal.observation_history_rollout SET video_evidence_enabled=false",
            );
            await denied(db, () => allocate(db, owner, request));
            await db.queryArray(
              "UPDATE internal.observation_history_rollout SET video_evidence_enabled=true",
            );
            const allocated = await decodeVideoEvidenceAllocation(
              bytes(await allocate(db, owner, request)),
              c,
              owner,
            );
            assertEquals(allocated.items.length, request.items.length);
            const objects = allocated.items.map((x) => x.object_id);
            assertEquals(new Set(objects).size, objects.length);
            assert(allocated.items.every((x) => x.ready_at === null));
            assertEquals(await allocate(db, owner, request), allocated);
            for (
              const patch of [
                { schema_version: 1 },
                { fingerprint: "0".repeat(64) },
                { unexpected: true },
                { items: [...request.items].reverse() },
                { items: request.items.slice(1) },
                { analysis_id: source },
                { source_analysis_id: child },
              ]
            ) {
              await denied(
                db,
                () => allocate(db, owner, { ...request, ...patch }),
              );
            }
            await denied(db, () => allocate(db, crypto.randomUUID(), request));
            await denied(db, () => allocate(db, owner, request, 11));
            for (const role of ["anon", "authenticated"]) {
              await denied(db, async () => {
                await db.queryArray(`SET LOCAL ROLE ${role}`);
                await allocate(db, owner, request);
              });
            }
            const retirement = await buildVideoSourceRetirementRequest(
              c,
              crypto.randomUUID(),
            );
            await denied(db, () => retire(db, owner, retirement));
            await db.queryArray(
              "UPDATE internal.observation_history_rollout SET video_evidence_enabled=false,media_enabled=false",
            );
            assertEquals(await allocate(db, owner, request), allocated);
            await denied(
              db,
              () => complete(db, owner, request, allocated.items[0]),
            );
            await db.queryArray(
              "UPDATE internal.observation_history_rollout SET video_evidence_enabled=true,media_enabled=true",
            );
            for (
              const invalid of [
                { ...allocated.items[0], object_id: crypto.randomUUID() },
                { ...allocated.items[0], media_id: crypto.randomUUID() },
                {
                  ...allocated.items[0],
                  object_id: allocated.items[1].object_id,
                },
              ]
            ) await denied(db, () => complete(db, owner, request, invalid));
            let ready = allocated;
            for (const [index, item] of allocated.items.entries()) {
              const previous = ready;
              ready = await decodeVideoEvidenceReceipt(
                bytes(await complete(db, owner, request, item)),
                c,
                owner,
                bytes(previous),
              );
              assertEquals(
                ready.items.filter((x) => x.ready_at !== null).length,
                index + 1,
              );
              assertEquals(
                ready.state,
                index === allocated.items.length - 1 ? "ready" : "allocated",
              );
              assertEquals(await complete(db, owner, request, item), ready);
            }
            assertEquals(ready.state, "ready");
            assert(ready.items.every((x) => x.ready_at !== null));
            assertEquals(ready.expires_at, allocated.expires_at);
            await db.queryArray(
              "UPDATE internal.observation_history_rollout SET video_evidence_enabled=false,media_enabled=false",
            );
            assertEquals(
              await complete(db, owner, request, allocated.items[0]),
              ready,
            );
            assertEquals(await allocate(db, owner, request), ready);
            await denied(db, () => retire(db, owner, retirement));
          } finally {
            await db.queryArray("ROLLBACK");
          }
        }
      } finally {
        await db.end();
      }
    },
  });
}
Deno.test({
  name:
    "video allocation never replaces missing objects or permits retirement after cleanup",
  ignore: !url,
  async fn() {
    const db = await connect();
    await db.queryArray("BEGIN");
    try {
      await fixture(db);
      const [owner, parent, source, child] = Array.from(
        { length: 4 },
        () => crypto.randomUUID(),
      );
      await seed(db, owner, parent, source);
      const c = await candidate(parent, source, child),
        request = await buildVideoEvidenceUploadRequest(c);
      await reserve(db, owner, c);
      const a = await decodeVideoEvidenceAllocation(
        bytes(await allocate(db, owner, request)),
        c,
        owner,
      );
      await db.queryArray(
        "DELETE FROM internal.observation_evidence_objects WHERE media_id=$1",
        [a.items[0].media_id],
      );
      await denied(db, () => allocate(db, owner, request));
      await denied(db, () =>
        complete(
          db,
          owner,
          request,
          a.items[0],
        ));
      await db.queryArray(
        "DELETE FROM internal.observation_evidence_objects WHERE analysis_id=$1",
        [child],
      );
      await denied(db, () => allocate(db, owner, request));
      const retirement = await buildVideoSourceRetirementRequest(
        c,
        crypto.randomUUID(),
      );
      await denied(db, () => retire(db, owner, retirement));
      const counts =
        (await db.queryObject<{ allocation: number; erasure: number }>(
          "SELECT (SELECT count(*)::int FROM internal.observation_video_evidence_allocations WHERE analysis_id=$1) allocation,(SELECT count(*)::int FROM internal.observation_evidence_erasure WHERE object_id=ANY($2::uuid[])) erasure",
          [child, a.items.map((x) => x.object_id)],
        )).rows[0];
      assertEquals(counts, { allocation: 1, erasure: a.items.length });
    } finally {
      await db.queryArray("ROLLBACK");
      await db.end();
    }
  },
});

// Privileged fixture aging bypasses only immutable-field triggers, then restores
// them before exercising the real service. No clock waits or production mutation.
async function age(db: Client, child: string) {
  await db.queryArray(
    `ALTER TABLE internal.observation_video_evidence_allocations DISABLE TRIGGER guard_video_evidence_allocation;
 ALTER TABLE internal.observation_evidence_objects DISABLE TRIGGER USER;
 UPDATE internal.observation_video_evidence_allocations SET expires_at=date_trunc('milliseconds',clock_timestamp())-interval '1 second' WHERE analysis_id='${child}';
 UPDATE internal.observation_evidence_objects SET expires_at=(SELECT expires_at FROM internal.observation_video_evidence_allocations WHERE analysis_id='${child}') WHERE analysis_id='${child}';
 ALTER TABLE internal.observation_evidence_objects ENABLE TRIGGER USER;
 ALTER TABLE internal.observation_video_evidence_allocations ENABLE TRIGGER guard_video_evidence_allocation;`,
  );
}
Deno.test({
  name:
    "video expiry is whole inventory only and retains allocation permanently",
  ignore: !url,
  async fn() {
    const db = await connect();
    await db.queryArray("BEGIN");
    try {
      await fixture(db);
      const [owner, parent, source, child] = Array.from(
        { length: 4 },
        () => crypto.randomUUID(),
      );
      await seed(db, owner, parent, source);
      const c = await candidate(parent, source, child),
        request = await buildVideoEvidenceUploadRequest(c);
      await reserve(db, owner, c);
      const a = await decodeVideoEvidenceAllocation(
        bytes(await allocate(db, owner, request)),
        c,
        owner,
      );
      await age(db, child);
      for (
        const routine of [
          "expire_observation_evidence",
          "expire_unbound_observation_evidence",
        ]
      ) {
        const result = (await db.queryObject<{ value: boolean }>(
          `SELECT internal.${routine}($1) value`,
          [a.items[0].media_id],
        )).rows[0].value;
        assertEquals(result, false);
      }
      await denied(db, () => complete(db, owner, request, a.items[0]));
      const cleanup = async () =>
        (await db.queryObject<{ value: number }>(
          "SELECT public.retire_expired_observation_video_evidence() value",
        )).rows[0].value;
      assertEquals(await cleanup(), 0);
      await db.queryArray(
        "UPDATE internal.observation_history_rollout SET private_evidence_erasure_enabled=true",
      );
      await db.queryArray(
        "SELECT public.retire_expired_observation_evidence()",
      );
      assertEquals(
        (await db.queryObject<{ n: number }>(
          "SELECT count(*)::int n FROM internal.observation_evidence_objects WHERE analysis_id=$1",
          [child],
        )).rows[0].n,
        a.items.length,
      );
      assertEquals(await cleanup(), a.items.length);
      assertEquals(await cleanup(), 0);
      await denied(db, () => allocate(db, owner, request));
      await denied(db, async () =>
        retire(
          db,
          owner,
          await buildVideoSourceRetirementRequest(c, crypto.randomUUID()),
        ));
      assertEquals(
        (await db.queryObject<{ n: number }>(
          "SELECT count(*)::int n FROM internal.observation_evidence_erasure WHERE object_id=ANY($1::uuid[])",
          [a.items.map((x) => x.object_id)],
        )).rows[0].n,
        a.items.length,
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
    "retire-first",
    "allocate-first",
    "delete-first",
    "delete-after",
    "complete",
  ]
) {
  Deno.test({
    name: `video allocation actual canonical blocking ${scenario}`,
    ignore: !url,
    async fn() {
      const first = await connect(), second = await connect();
      const [owner, parent, source, child] = Array.from(
        { length: 4 },
        () => crypto.randomUUID(),
      );
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
        const c = await candidate(parent, source, child),
          request = await buildVideoEvidenceUploadRequest(c),
          undo = await buildVideoSourceRetirementRequest(
            c,
            crypto.randomUUID(),
          );
        await reserve(first, owner, c);
        await first.queryArray("BEGIN");
        await second.queryArray("BEGIN");
        let a:
          | Awaited<ReturnType<typeof decodeVideoEvidenceAllocation>>
          | undefined;
        if (scenario === "retire-first") await retire(first, owner, undo);
        else if (scenario === "delete-first") {
          await first.queryArray("SELECT public.apply_user_tombstone($1)", [
            owner,
          ]);
        } else {a = await decodeVideoEvidenceAllocation(
            bytes(await allocate(first, owner, request)),
            c,
            owner,
          );}
        const pid = (await second.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() pid",
        )).rows[0].pid;
        const pending = (scenario === "allocate-first"
          ? retire(second, owner, undo)
          : scenario === "delete-after"
          ? second.queryArray("SELECT public.apply_user_tombstone($1)", [owner])
          : scenario === "complete"
          ? complete(second, owner, request, a!.items[0])
          : allocate(second, owner, request)).then(
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
        if (
          ["allocate-first", "retire-first", "delete-first"].includes(scenario)
        ) {
          assert(settled.error);
          await second.queryArray("ROLLBACK");
        } else {
          if (settled.error) {
            throw settled.error;
          }
          await second.queryArray("COMMIT");
          if (scenario === "duplicate") {
            assertEquals(settled.value, a);
          }
        }
        if (scenario === "duplicate" || scenario === "complete") {
          const restarted = await connect();
          try {
            await restarted.queryArray(
              "SELECT set_config('request.jwt.claim.role','service_role',false)",
            );
            assertEquals(
              await allocate(restarted, owner, request),
              settled.value,
            );
          } finally {
            await restarted.end();
          }
        }
        if (scenario === "delete-after") {
          assertEquals(
            (await first.queryObject<{ n: number }>(
              "SELECT count(*)::int n FROM internal.observation_evidence_erasure WHERE object_id=ANY($1::uuid[])",
              [a!.items.map((x) =>
                x.object_id
              )],
            )).rows[0].n,
            a!.items.length,
          );
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
    "video duplicate expiry waits then returns zero after committed whole cleanup",
  ignore: !url,
  async fn() {
    const first = await connect(), second = await connect();
    const [owner, parent, source, child] = Array.from(
      { length: 4 },
      () => crypto.randomUUID(),
    );
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
      const c = await candidate(parent, source, child),
        request = await buildVideoEvidenceUploadRequest(c);
      await reserve(first, owner, c);
      const a = await decodeVideoEvidenceAllocation(
        bytes(await allocate(first, owner, request)),
        c,
        owner,
      );
      await age(first, child);
      await first.queryArray(
        "UPDATE internal.observation_history_rollout SET private_evidence_erasure_enabled=true",
      );
      await first.queryArray("BEGIN");
      await second.queryArray("BEGIN");
      const cleanup = async (db: Client) =>
        (await db.queryObject<{ n: number }>(
          "SELECT public.retire_expired_observation_video_evidence() n",
        )).rows[0].n;
      assertEquals(await cleanup(first), a.items.length);
      const pid = (await second.queryObject<{ pid: number }>(
        "SELECT pg_backend_pid() pid",
      )).rows[0].pid;
      const pending = cleanup(second).then(
        (value) => ({ value, error: undefined }),
        (error) => ({ value: undefined, error }),
      );
      let blocked = false;
      for (let i = 0; i < 100 && !blocked; i++) {
        blocked = (await first.queryObject<{ blocked: boolean }>(
          "SELECT cardinality(pg_blocking_pids($1))>0 blocked",
          [pid],
        )).rows[0].blocked;
        if (!blocked) await new Promise((r) => setTimeout(r, 5));
      }
      assert(blocked);
      await first.queryArray("COMMIT");
      const settled = await pending;
      if (settled.error) throw settled.error;
      assertEquals(settled.value, 0);
      await second.queryArray("COMMIT");
      assertEquals(
        (await first.queryObject<{ n: number }>(
          "SELECT count(*)::int n FROM internal.observation_evidence_erasure WHERE object_id=ANY($1::uuid[])",
          [a.items.map((x) => x.object_id)],
        )).rows[0].n,
        a.items.length,
      );
    } finally {
      await first.queryArray("ROLLBACK").catch(() => {});
      await second.queryArray("ROLLBACK").catch(() => {});
      await first.queryArray("SELECT public.apply_user_tombstone($1)", [owner])
        .catch(() => {});
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
