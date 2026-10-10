import { buildPreparedVideoDraft } from "../_shared/analysisHistory/videoAdmission.ts";
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

Deno.test({
  name:
    "video execution prerequisite requires exact bound whole ready unexpired evidence",
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
          const c = await candidate(parent, source, child, i);
          const request = await buildVideoEvidenceUploadRequest(c);
          const check = (who = owner, input = c.input) =>
            db.queryArray(
              "SELECT internal.assert_ready_video_analysis_evidence($1,$2,$3,$4::jsonb)",
              [who, parent, child, JSON.stringify(input)],
            );
          await denied(db, () => check());
          await reserve(db, owner, c);
          await denied(db, () => check());
          const allocation = await decodeVideoEvidenceAllocation(
            bytes(await allocate(db, owner, request)),
            c,
            owner,
          );
          for (const item of allocation.items) {
            await denied(db, () => check());
            await complete(db, owner, request, item);
          }
          await check();
          await denied(db, () => check(crypto.randomUUID()));
          await denied(
            db,
            () => check(owner, { ...c.input, request_digest: "0".repeat(64) }),
          );
          for (const role of ["anon", "authenticated", "service_role"]) {
            await denied(db, async () => {
              await db.queryArray(`SET LOCAL ROLE ${role}`);
              await check();
            });
          }
          // This helper grants nothing: closed gates remain closed and no
          // execution intent or quota reservation is created by an assertion.
          await db.queryArray(
            "UPDATE internal.observation_history_rollout SET media_enabled=false,video_evidence_enabled=false",
          );
          await check();
          assertEquals(
            (await db.queryObject<{ n: number }>(
              "SELECT ((SELECT count(*) FROM internal.observation_analysis_intents WHERE analysis_id=$1)+(SELECT count(*) FROM internal.ai_quota_reservations WHERE original_analysis_id=$1))::int n",
              [child],
            )).rows[0].n,
            0,
          );
          await db.queryArray("SAVEPOINT missing");
          await db.queryArray(
            "DELETE FROM internal.observation_evidence_objects WHERE media_id=$1",
            [allocation.items[0].media_id],
          );
          await denied(db, () => check());
          await db.queryArray("ROLLBACK TO SAVEPOINT missing");
          await check();
          // Superuser-only corruption fixtures restore triggers before checking.
          // The production writers never permit these substitutions.
          for (
            const mutation of [
              "UPDATE internal.observation_video_evidence_upload_cohorts SET items=jsonb_set(items,'{0,sha256}',to_jsonb(repeat('0',64))) WHERE analysis_id=$1",
              "UPDATE internal.observation_video_evidence_allocations SET items=(SELECT jsonb_agg(value ORDER BY ord DESC) FROM jsonb_array_elements(items) WITH ORDINALITY q(value,ord)) WHERE analysis_id=$1",
              "UPDATE internal.observation_evidence_objects SET sha256=repeat('0',64) WHERE analysis_id=$1",
            ]
          ) {
            await db.queryArray("SAVEPOINT corrupt");
            await db.queryArray(
              "ALTER TABLE internal.observation_video_evidence_upload_cohorts DISABLE TRIGGER USER; ALTER TABLE internal.observation_video_evidence_allocations DISABLE TRIGGER USER; ALTER TABLE internal.observation_evidence_objects DISABLE TRIGGER USER",
            );
            await db.queryArray(mutation, [child]);
            await db.queryArray(
              "ALTER TABLE internal.observation_video_evidence_upload_cohorts ENABLE TRIGGER USER; ALTER TABLE internal.observation_video_evidence_allocations ENABLE TRIGGER USER; ALTER TABLE internal.observation_evidence_objects ENABLE TRIGGER USER",
            );
            await denied(db, () => check());
            await db.queryArray("ROLLBACK TO SAVEPOINT corrupt");
          }
          await db.queryArray("SAVEPOINT erased");
          await db.queryArray(
            "INSERT INTO internal.observation_evidence_erasure(object_id) VALUES($1)",
            [allocation.items[0].object_id],
          );
          await denied(db, () => check());
          await db.queryArray("ROLLBACK TO SAVEPOINT erased");
          await check();
          await age(db, child);
          await denied(db, () => check());
        } finally {
          await db.queryArray("ROLLBACK");
        }
      }
      await db.queryArray("BEGIN ISOLATION LEVEL REPEATABLE READ");
      await denied(
        db,
        () =>
          db.queryArray(
            "SELECT internal.assert_ready_video_analysis_evidence(NULL,NULL,NULL,NULL)",
          ),
      );
      await db.queryArray("ROLLBACK");
    } finally {
      await db.end();
    }
  },
});

for (const deletionFirst of [false, true]) {
  Deno.test({
    name:
      `video ready-evidence guard serializes account erasure deletionFirst=${deletionFirst}`,
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
        prior = (await first.queryObject<Record<string, boolean>>(
          `SELECT ${gates.join(",")} FROM internal.observation_history_rollout`,
        )).rows[0];
        await seed(first, owner, parent, source);
        const c = await candidate(parent, source, child);
        const request = await buildVideoEvidenceUploadRequest(c);
        await reserve(first, owner, c);
        const allocation = await decodeVideoEvidenceAllocation(
          bytes(await allocate(first, owner, request)),
          c,
          owner,
        );
        for (const item of allocation.items) {
          await complete(first, owner, request, item);
        }
        const check = (db: Client) =>
          db.queryArray(
            "SELECT internal.assert_ready_video_analysis_evidence($1,$2,$3,$4::jsonb)",
            [owner, parent, child, JSON.stringify(c.input)],
          );
        const erase = (db: Client) =>
          db.queryArray("SELECT public.apply_user_tombstone($1)", [owner]);
        await first.queryArray("BEGIN");
        await second.queryArray("BEGIN");
        await (deletionFirst ? erase(first) : check(first));
        const pid = (await second.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() pid",
        )).rows[0].pid;
        const pending = (deletionFirst ? check(second) : erase(second)).then(
          () => ({ ok: true }),
          () => ({ ok: false }),
        );
        let blocked = false;
        for (let n = 0; n < 100 && !blocked; n++) {
          blocked = (await first.queryObject<{ blocked: boolean }>(
            "SELECT cardinality(pg_blocking_pids($1))>0 blocked",
            [pid],
          )).rows[0].blocked;
          if (!blocked) await new Promise((r) => setTimeout(r, 5));
        }
        assert(
          blocked,
          "guard and account erasure must share the canonical lock",
        );
        await first.queryArray("COMMIT");
        assertEquals((await pending).ok, !deletionFirst);
        await second.queryArray(deletionFirst ? "ROLLBACK" : "COMMIT");
        await assertRejects(() => check(first));
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

async function videoAdmissionEligibility(
  db: Client,
  owner: string,
  parent: string,
) {
  const fixture = await Deno.readTextFile(
    new URL(
      "../../tests/observation_source_initial_admission.sql",
      import.meta.url,
    ),
  );
  const helper = fixture.slice(
    fixture.indexOf("CREATE FUNCTION pg_temp.seed_funded_history"),
    fixture.indexOf("CREATE FUNCTION pg_temp.admission_input"),
  )
    .replace(
      "    PERFORM pg_temp.seed_history_append(owner_id,observation);",
      "",
    );
  await db.queryArray(
    helper.replaceAll(
      "pg_temp.seed_funded_history",
      "pg_temp.video_admission_eligibility",
    ),
  );
  await db.queryArray("SELECT pg_temp.video_admission_eligibility($1,$2)", [
    owner,
    parent,
  ]);
}
const admitVideo = (db: Client, owner: string, input: unknown) =>
  db.queryObject<{ value: Record<string, unknown> }>(
    "SELECT internal.admit_video_observation_analysis($1::uuid,$2::jsonb,encode(extensions.digest($1::text,'sha256'),'hex')) value",
    [owner, JSON.stringify(input)],
  );
for (let variant = 0; variant < 3; variant++) {
  Deno.test({
    name:
      `video private admission funds once and exact replay never renews variant=${variant}`,
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
        const c = await candidate(parent, source, child, variant),
          request = await buildVideoEvidenceUploadRequest(c);
        await reserve(db, owner, c);
        const allocation = await decodeVideoEvidenceAllocation(
          bytes(await allocate(db, owner, request)),
          c,
          owner,
        );
        await db.queryArray(
          "UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current'",
        );
        await db.queryArray(
          "UPDATE internal.observation_history_rollout SET admission_enabled=true,protected_analysis_enabled=true",
        );
        const count = async () =>
          (await db.queryObject<{ n: number }>(
            "SELECT ((SELECT count(*) FROM internal.observation_analysis_intents WHERE analysis_id=$1)+(SELECT count(*) FROM internal.ai_quota_reservations WHERE original_analysis_id=$1)+(SELECT count(*) FROM internal.complimentary_scan_usage WHERE client_scan_id=$1))::int n",
            [child],
          )).rows[0].n;
        await denied(db, () => admitVideo(db, owner, c.input));
        assertEquals(await count(), 0);
        for (const item of allocation.items) {
          await complete(db, owner, request, item);
        }
        await denied(db, () => admitVideo(db, owner, c.input));
        assertEquals(await count(), 0);
        await db.queryArray(
          "UPDATE internal.observation_history_rollout SET video_analysis_enabled=true",
        );
        // Required legal/processor consent failure must roll the inserted intent back.
        await denied(db, () => admitVideo(db, owner, c.input));
        assertEquals(await count(), 0);
        await videoAdmissionEligibility(db, owner, parent);
        for (const role of ["anon", "authenticated", "service_role"]) {
          await denied(db, async () => {
            await db.queryArray(`SET LOCAL ROLE ${role}`);
            await admitVideo(db, owner, c.input);
          });
        }
        const original = (await admitVideo(db, owner, c.input)).rows[0].value;
        assertEquals(original.state, "admitted");
        assertEquals(await count(), 3);
        assertEquals(
          (await admitVideo(db, owner, c.input)).rows[0].value,
          original,
        );
        const profile = (await db.queryObject<{ profile: string }>(
          "SELECT a.input_profile profile FROM internal.identification_provider_attempts a JOIN internal.ai_quota_reservations r ON r.id=a.reservation_id WHERE r.original_analysis_id=$1 AND a.attempt_count=1",
          [child],
        )).rows[0].profile;
        assertEquals(
          profile,
          c.input.evidence_manifest.provenance.audio === null
            ? "multimodal_video_frames_v1"
            : "multimodal_video_audio_v1",
        );
        // Even a funded V4 intent cannot enter the existing source dispatch path.
        await db.queryArray(
          "UPDATE internal.observation_history_rollout SET source_dispatch_enabled=true,dispatch_enabled=true",
        );
        await denied(db, () =>
          db.queryArray(
            "SELECT internal.prepare_source_dispatch_witness($1,$2,$3,$4,'{}'::jsonb)",
            [
              owner,
              parent,
              child,
              (original.quota as { lease_token: string }).lease_token,
            ],
          ));
        assertEquals(
          (await db.queryObject<{ n: number }>(
            "SELECT count(*)::int n FROM internal.observation_analysis_dispatch_witnesses WHERE analysis_id=$1",
            [child],
          )).rows[0].n,
          0,
        );
        await denied(db, () => admitVideo(db, crypto.randomUUID(), c.input));
        await denied(
          db,
          () =>
            admitVideo(db, owner, {
              ...c.input,
              request_digest: "0".repeat(64),
            }),
        );
        await db.queryArray(
          "UPDATE internal.observation_history_rollout SET admission_enabled=false,protected_analysis_enabled=false,media_enabled=false,video_analysis_enabled=false",
        );
        await age(db, child);
        await db.queryArray(
          "UPDATE internal.ai_quota_reservations SET lease_expires_at=clock_timestamp()-interval '1 second' WHERE original_analysis_id=$1",
          [child],
        );
        assertEquals(
          (await admitVideo(db, owner, c.input)).rows[0].value,
          original,
        );
        assertEquals(await count(), 3);
        // Simulated uncertain execution is lookup-only: no new funding or claim.
        await db.queryArray(
          "UPDATE internal.observation_analysis_intents SET state='dispatched' WHERE analysis_id=$1",
          [child],
        );
        const unknown = (await admitVideo(db, owner, c.input)).rows[0].value;
        assertEquals(unknown.state, "dispatched");
        assertEquals(unknown.quota, original.quota);
        assertEquals(await count(), 3);
        assertEquals(unknown.work_token, null);
        await db.queryArray("SELECT public.apply_user_tombstone($1)", [owner]);
        await denied(db, () => admitVideo(db, owner, c.input));
      } finally {
        await db.queryArray("ROLLBACK");
        await db.end();
      }
    },
  });
}

Deno.test({
  name:
    "video concurrent private admission replays one original funding receipt",
  ignore: !url,
  async fn() {
    const first = await connect(), second = await connect();
    const [owner, parent, source, child] = Array.from(
      { length: 4 },
      () => crypto.randomUUID(),
    );
    const admissionGates = [
      ...gates,
      "admission_enabled",
      "protected_analysis_enabled",
      "video_analysis_enabled",
    ];
    let prior: Record<string, boolean> | undefined;
    let entitlement: { mode: string; protocol: number } | undefined;
    try {
      await fixture(first);
      prior = (await first.queryObject<Record<string, boolean>>(
        `SELECT ${
          admissionGates.join(",")
        } FROM internal.observation_history_rollout`,
      )).rows[0];
      entitlement =
        (await first.queryObject<{ mode: string; protocol: number }>(
          "SELECT entitlement_mode mode,required_client_protocol protocol FROM internal.entitlement_rollout_config WHERE config_key='current'",
        )).rows[0];
      await seed(first, owner, parent, source);
      const c = await candidate(parent, source, child, 1);
      const request = await buildVideoEvidenceUploadRequest(c);
      await reserve(first, owner, c);
      const allocation = await decodeVideoEvidenceAllocation(
        bytes(await allocate(first, owner, request)),
        c,
        owner,
      );
      for (const item of allocation.items) {
        await complete(first, owner, request, item);
      }
      await videoAdmissionEligibility(first, owner, parent);
      await first.queryArray(
        "UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current'",
      );
      await first.queryArray(
        "UPDATE internal.observation_history_rollout SET admission_enabled=true,protected_analysis_enabled=true,video_analysis_enabled=true",
      );
      await first.queryArray("BEGIN");
      await second.queryArray("BEGIN");
      const original = (await admitVideo(first, owner, c.input)).rows[0].value;
      const pid = (await second.queryObject<{ pid: number }>(
        "SELECT pg_backend_pid() pid",
      )).rows[0].pid;
      const pending = admitVideo(second, owner, c.input).then(
        (value) => ({ value }),
        (error) => ({ error }),
      );
      let blocked = false;
      for (let n = 0; n < 100 && !blocked; n++) {
        blocked = (await first.queryObject<{ blocked: boolean }>(
          "SELECT cardinality(pg_blocking_pids($1))>0 blocked",
          [pid],
        )).rows[0].blocked;
        if (!blocked) await new Promise((r) => setTimeout(r, 5));
      }
      assert(
        blocked,
        "duplicate admission must wait for original funding transaction",
      );
      await first.queryArray("COMMIT");
      const replay = await pending;
      assert("value" in replay);
      assertEquals(replay.value.rows[0].value, original);
      await second.queryArray("COMMIT");
      assertEquals(
        (await first.queryObject<{ n: number }>(
          "SELECT ((SELECT count(*) FROM internal.observation_analysis_intents WHERE analysis_id=$1)+(SELECT count(*) FROM internal.ai_quota_reservations WHERE original_analysis_id=$1)+(SELECT count(*) FROM internal.complimentary_scan_usage WHERE client_scan_id=$1))::int n",
          [child],
        )).rows[0].n,
        3,
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
            admissionGates.map((g, i) => `${g}=$${i + 1}`).join(",")
          }`,
          admissionGates.map((g) => prior![g]),
        );
      }
      if (entitlement) {
        await first.queryArray(
          "UPDATE internal.entitlement_rollout_config SET entitlement_mode=$1,required_client_protocol=$2 WHERE config_key='current'",
          [entitlement.mode, entitlement.protocol],
        );
      }
      await first.end();
      await second.end();
    }
  },
});

async function fundedVideo(db: Client, variant = 0, paid = false) {
  const [owner, parent, source, child] = Array.from(
    { length: 4 },
    () => crypto.randomUUID(),
  );
  await seed(db, owner, parent, source);
  const c = await candidate(parent, source, child, variant);
  const request = await buildVideoEvidenceUploadRequest(c);
  await reserve(db, owner, c);
  const allocation = await decodeVideoEvidenceAllocation(
    bytes(await allocate(db, owner, request)),
    c,
    owner,
  );
  for (const item of allocation.items) await complete(db, owner, request, item);
  await videoAdmissionEligibility(db, owner, parent);
  await db.queryArray(
    "UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current'",
  );
  await db.queryArray(
    "UPDATE internal.observation_history_rollout SET admission_enabled=true,protected_analysis_enabled=true,video_analysis_enabled=true,source_dispatch_enabled=true,dispatch_enabled=true",
  );
  if (paid) {
    await db.queryArray(
      "UPDATE public.users SET subscription_tier='pro',subscription_expires_at=NULL WHERE id=$1",
      [owner],
    );
  }
  const admitted = (await admitVideo(db, owner, c.input)).rows[0].value;
  const q = admitted.quota as Record<string, unknown>;
  const provenance = {
    version: 1,
    provider: q.provider,
    binding: q.binding,
    model: q.model,
    variant: "multimodal",
    operation: "scan_identification",
    policy_version: q.policy_version,
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
  return { owner, parent, child, c, allocation, admitted, provenance };
}
const claimVideo = (
  db: Client,
  f: { owner: string; parent: string; child: string },
) =>
  db.queryObject<{ value: Record<string, unknown> }>(
    "SELECT internal.claim_video_observation_analysis($1,$2,$3) value",
    [f.owner, f.parent, f.child],
  );
const dispatchVideo = (
  db: Client,
  f: { owner: string; parent: string; child: string; provenance: unknown },
  token: unknown,
  provenance = f.provenance,
) =>
  db.queryObject<{ value: Record<string, unknown> }>(
    "SELECT internal.dispatch_video_observation_analysis($1,$2,$3,$4,$5::jsonb) value",
    [f.owner, f.parent, f.child, token, JSON.stringify(provenance)],
  );
for (let variant = 0; variant < 3; variant++) {
  Deno.test({
    name:
      `private video dispatch is atomic and unknown execution cannot rearm variant=${variant}`,
    ignore: !url,
    async fn() {
      const db = await connect();
      await db.queryArray("BEGIN");
      try {
        await fixture(db);
        const f = await fundedVideo(db, variant);
        await denied(db, () => claimVideo(db, f));
        await db.queryArray(
          "UPDATE internal.observation_history_rollout SET video_dispatch_enabled=true",
        );
        const claim = (await claimVideo(db, f)).rows[0].value;
        assertEquals(claim.claimed, true);
        assertEquals((await claimVideo(db, f)).rows[0].value.claimed, false);
        await denied(db, () => dispatchVideo(db, f, crypto.randomUUID()));
        const quota = f.admitted.quota as { lease_token: string };
        await denied(db, () =>
          db.queryArray(
            "SELECT internal.dispatch_observation_analysis($1,$2,$3,$4,$5::jsonb)",
            [
              f.owner,
              f.parent,
              f.child,
              quota.lease_token,
              JSON.stringify(f.provenance),
            ],
          ));
        for (
          const mutation of [
            "UPDATE internal.ai_quota_reservations SET lease_expires_at=clock_timestamp()-interval '1 second' WHERE original_analysis_id=$1",
            "UPDATE internal.ai_quota_reservations SET attempt_count=2 WHERE original_analysis_id=$1",
            "UPDATE internal.identification_provider_attempts SET input_profile='multimodal_text_v1' WHERE reservation_id=(SELECT id FROM internal.ai_quota_reservations WHERE original_analysis_id=$1)",
            "UPDATE internal.observation_analysis_intents SET provider_outcome='{}' WHERE analysis_id=$1",
            "UPDATE internal.observation_analysis_intents SET work_expires_at=clock_timestamp()-interval '1 second' WHERE analysis_id=$1",
            "INSERT INTO internal.observation_evidence_erasure(object_id) SELECT object_id FROM internal.observation_evidence_objects WHERE analysis_id=$1 LIMIT 1",
          ]
        ) {
          await db.queryArray("SAVEPOINT corrupt_dispatch");
          await db.queryArray(mutation, [f.child]);
          await denied(db, () => dispatchVideo(db, f, claim.work_token));
          await db.queryArray("ROLLBACK TO SAVEPOINT corrupt_dispatch");
        }
        await db.queryArray("SAVEPOINT expired_evidence");
        await age(db, f.child);
        await denied(db, () => dispatchVideo(db, f, claim.work_token));
        await db.queryArray("ROLLBACK TO SAVEPOINT expired_evidence");
        await denied(db, () => dispatchVideo(db, f, claim.work_token, {}));
        // Structurally valid but unassigned provenance reaches core commit after
        // witness insertion; its failure must roll the entire operation back.
        const mismatch = { ...f.provenance, model: "unassigned_model" };
        assertEquals(
          (await db.queryObject<{ valid: boolean }>(
            "SELECT internal.identification_provenance_is_valid($1::jsonb) valid",
            [JSON.stringify(mismatch)],
          )).rows[0].valid,
          true,
        );
        await db.queryArray("SAVEPOINT provenance_mismatch");
        await assertRejects(
          () => dispatchVideo(db, f, claim.work_token, mismatch),
          Error,
          "identification_invocation_provenance_conflict",
        );
        await db.queryArray("ROLLBACK TO SAVEPOINT provenance_mismatch");
        assertEquals(
          (await db.queryObject<{ n: number }>(
            "SELECT count(*)::int n FROM internal.observation_analysis_dispatch_witnesses WHERE analysis_id=$1",
            [f.child],
          )).rows[0].n,
          0,
        );
        assertEquals(
          (await db.queryObject<{ state: string }>(
            "SELECT state FROM internal.ai_quota_reservations WHERE original_analysis_id=$1",
            [f.child],
          )).rows[0].state,
          "reserved",
        );
        await db.queryArray(
          "UPDATE internal.observation_analysis_intents SET work_expires_at=clock_timestamp()-interval '1 second' WHERE analysis_id=$1",
          [f.child],
        );
        const replacement = (await claimVideo(db, f)).rows[0].value;
        assertEquals(replacement.claimed, true);
        assert(replacement.work_token !== claim.work_token);
        assertEquals(replacement.quota, claim.quota);
        await denied(db, () => dispatchVideo(db, f, claim.work_token));
        const first =
          (await dispatchVideo(db, f, replacement.work_token)).rows[0].value;
        assertEquals(first.may_dispatch, true);
        const state = (await db.queryObject<
          { w: number; v: number; q: string; usage: string }
        >(
          "SELECT (SELECT count(*)::int FROM internal.observation_analysis_dispatch_witnesses WHERE analysis_id=$1) w,(SELECT count(*)::int FROM internal.identification_invocations WHERE scan_id=$1) v,(SELECT state FROM internal.ai_quota_reservations WHERE original_analysis_id=$1) q,(SELECT state FROM internal.complimentary_scan_usage WHERE client_scan_id=$1) usage",
          [f.child],
        )).rows[0];
        assertEquals(state, { w: 1, v: 1, q: "committed", usage: "held" });
        await db.queryArray(
          "UPDATE internal.observation_history_rollout SET video_dispatch_enabled=false,video_analysis_enabled=false,dispatch_enabled=false,admission_enabled=false",
        );
        await age(db, f.child);
        await db.queryArray(
          "UPDATE internal.observation_analysis_intents SET work_expires_at=clock_timestamp()-interval '1 second' WHERE analysis_id=$1",
          [f.child],
        );
        const replay =
          (await dispatchVideo(db, f, replacement.work_token)).rows[0].value;
        assertEquals(replay, {
          invocation_id: first.invocation_id,
          may_dispatch: false,
        });
        assertEquals((await claimVideo(db, f)).rows[0].value, {
          state: "dispatched",
          claimed: false,
        });
        await denied(db, () =>
          dispatchVideo(db, f, replacement.work_token, {
            ...f.provenance,
            timeout_ms: 80000,
          }));
        await denied(db, () =>
          db.queryArray(
            "SELECT public.claim_observation_analysis_recovery($1,$2,$3)",
            [f.owner, f.parent, f.child],
          ));
        await db.queryArray("SELECT public.apply_user_tombstone($1)", [
          f.owner,
        ]);
        await denied(db, () => dispatchVideo(db, f, replacement.work_token));
      } finally {
        await db.queryArray("ROLLBACK");
        await db.end();
      }
    },
  });
}

Deno.test({
  name: "private video concurrent dispatch grants one provider attempt",
  ignore: !url,
  async fn() {
    const first = await connect(), second = await connect();
    const dispatchGates = [
      ...gates,
      "admission_enabled",
      "protected_analysis_enabled",
      "video_analysis_enabled",
      "source_dispatch_enabled",
      "dispatch_enabled",
      "video_dispatch_enabled",
    ];
    let prior: Record<string, boolean> | undefined;
    let entitlement: { mode: string; protocol: number } | undefined;
    let owner: string | undefined;
    try {
      await fixture(first);
      prior = (await first.queryObject<Record<string, boolean>>(
        `SELECT ${
          dispatchGates.join(",")
        } FROM internal.observation_history_rollout`,
      )).rows[0];
      entitlement =
        (await first.queryObject<{ mode: string; protocol: number }>(
          "SELECT entitlement_mode mode,required_client_protocol protocol FROM internal.entitlement_rollout_config WHERE config_key='current'",
        )).rows[0];
      const f = await fundedVideo(first, 1);
      owner = f.owner;
      await first.queryArray(
        "UPDATE internal.observation_history_rollout SET video_dispatch_enabled=true",
      );
      const claim = (await claimVideo(first, f)).rows[0].value;
      await first.queryArray("BEGIN");
      await second.queryArray("BEGIN");
      const original =
        (await dispatchVideo(first, f, claim.work_token)).rows[0].value;
      const pid = (await second.queryObject<{ pid: number }>(
        "SELECT pg_backend_pid() pid",
      )).rows[0].pid;
      const pending = dispatchVideo(second, f, claim.work_token).then(
        (value) => ({ value }),
        (error) => ({ error }),
      );
      let blocked = false;
      for (let n = 0; n < 100 && !blocked; n++) {
        blocked = (await first.queryObject<{ blocked: boolean }>(
          "SELECT cardinality(pg_blocking_pids($1))>0 blocked",
          [pid],
        )).rows[0].blocked;
        if (!blocked) await new Promise((r) => setTimeout(r, 5));
      }
      assert(blocked, "duplicate dispatch must await original commit");
      await first.queryArray("COMMIT");
      const result = await pending;
      assert("value" in result);
      assertEquals(original.may_dispatch, true);
      assertEquals(result.value.rows[0].value, {
        invocation_id: original.invocation_id,
        may_dispatch: false,
      });
      await second.queryArray("COMMIT");
      assertEquals(
        (await first.queryObject<{ n: number }>(
          "SELECT ((SELECT count(*) FROM internal.observation_analysis_dispatch_witnesses WHERE analysis_id=$1)+(SELECT count(*) FROM internal.identification_invocations WHERE scan_id=$1))::int n",
          [f.child],
        )).rows[0].n,
        2,
      );
    } finally {
      await first.queryArray("ROLLBACK").catch(() => {});
      await second.queryArray("ROLLBACK").catch(() => {});
      if (owner) {
        await first.queryArray("SELECT public.apply_user_tombstone($1)", [
          owner,
        ]).catch(() => {});
        await first.queryArray("DELETE FROM auth.users WHERE id=$1", [owner])
          .catch(() => {});
      }
      if (prior) {
        await first.queryArray(
          `UPDATE internal.observation_history_rollout SET ${
            dispatchGates.map((g, i) => `${g}=$${i + 1}`).join(",")
          }`,
          dispatchGates.map((g) => prior![g]),
        );
      }
      if (entitlement) {
        await first.queryArray(
          "UPDATE internal.entitlement_rollout_config SET entitlement_mode=$1,required_client_protocol=$2 WHERE config_key='current'",
          [entitlement.mode, entitlement.protocol],
        );
      }
      await first.end();
      await second.end();
    }
  },
});

for (let variant = 0; variant < 3; variant++) {
  Deno.test({
    name:
      `private video received outcome stays immutable and recovery-only variant=${variant}`,
    ignore: !url,
    async fn() {
      const db = await connect();
      await db.queryArray("BEGIN");
      try {
        await fixture(db);
        const f = await fundedVideo(db, variant);
        const token = (f.admitted.quota as { lease_token: string }).lease_token;
        const read = (owner = f.owner) =>
          db.queryObject<{ value: Record<string, unknown> }>(
            "SELECT internal.read_video_observation_outcome($1,$2,$3) value",
            [owner, f.parent, f.child],
          );
        const outcome = {
          schema_version: 1,
          provenance: f.provenance,
          outcome: variant === 0
            ? {
              kind: "draft",
              result: { identification_provenance: f.provenance },
            }
            : { kind: variant === 1 ? "refusal" : "invalid_output" },
          usage: {},
        };
        const record = (value: unknown = outcome, quota = token) =>
          db.queryArray(
            "SELECT internal.record_video_observation_outcome($1,$2,$3,$4,$5::jsonb)",
            [f.owner, f.parent, f.child, quota, JSON.stringify(value)],
          );
        await denied(db, () => read());
        await denied(db, () => record());
        await db.queryArray(
          "UPDATE internal.observation_history_rollout SET video_dispatch_enabled=true",
        );
        const claim = (await claimVideo(db, f)).rows[0].value;
        await dispatchVideo(db, f, claim.work_token);
        assertEquals((await read()).rows[0].value.provider_outcome, null);
        await denied(db, () => read(crypto.randomUUID()));
        await denied(db, () => record(outcome, crypto.randomUUID()));
        for (
          const malformed of [
            null,
            { ...outcome, extra: true },
            { ...outcome, schema_version: 2 },
            { ...outcome, provenance: {} },
            { ...outcome, outcome: { kind: "timeout" } },
            { ...outcome, outcome: { kind: "draft", result: null } },
            { ...outcome, outcome: { kind: "refusal", extra: true } },
            { ...outcome, usage: { extra: 1 } },
            { ...outcome, usage: { service_tier: "a".repeat(2048) } },
            {
              ...outcome,
              outcome: {
                kind: "draft",
                result: { large: "a".repeat(1048576) },
              },
            },
          ]
        ) {
          await denied(db, () => record(malformed));
        }
        await age(db, f.child);
        await db.queryArray(
          "UPDATE internal.observation_history_rollout SET video_dispatch_enabled=false,dispatch_enabled=false,admission_enabled=false,media_enabled=false",
        );
        await db.queryArray(
          "UPDATE internal.observation_analysis_intents SET work_expires_at=clock_timestamp()-interval '1 second' WHERE analysis_id=$1",
          [f.child],
        );
        await db.queryArray("SAVEPOINT retained_invocation");
        await db.queryArray(
          "DELETE FROM internal.identification_invocations WHERE scan_id=$1",
          [f.child],
        );
        await denied(db, () => record());
        await db.queryArray("ROLLBACK TO SAVEPOINT retained_invocation");
        await record();
        await record();
        await db.queryArray(
          "DELETE FROM internal.identification_invocations WHERE scan_id=$1",
          [f.child],
        );
        await record();
        const recovered = (await read()).rows[0].value;
        assertEquals(recovered, {
          state: "dispatched",
          input: f.c.input,
          provider_outcome: outcome,
        });
        assertEquals((await claimVideo(db, f)).rows[0].value.claimed, false);
        await denied(
          db,
          () => record({ ...outcome, usage: { input_tokens: 1 } }),
        );
        await db.queryArray(
          "UPDATE internal.observation_history_rollout SET orchestration_enabled=true",
        );
        await denied(
          db,
          () =>
            db.queryArray(
              "SELECT public.claim_observation_analysis_recovery($1,$2,$3)",
              [f.owner, f.parent, f.child],
            ),
        );
        await denied(
          db,
          () =>
            db.queryArray(
              "SELECT public.advance_owned_observation_analysis($1,$2,$3,$4,'release','{}'::jsonb)",
              [f.owner, f.parent, f.child, claim.work_token],
            ),
        );
        const listed =
          (await db.queryObject<{ value: Array<{ analysis_id: string }> }>(
            "SELECT public.list_observation_analysis_recovery() value",
          )).rows[0].value;
        assert(!listed.some((x) => x.analysis_id === f.child));
        const state = (await db.queryObject<
          { quota: string; credit: string; usage: unknown }
        >(
          "SELECT q.state quota,c.state credit,i.provider_usage usage FROM internal.observation_analysis_intents i JOIN internal.ai_quota_reservations q ON q.original_analysis_id=i.analysis_id JOIN internal.complimentary_scan_usage c ON c.client_scan_id=i.analysis_id WHERE i.analysis_id=$1",
          [f.child],
        )).rows[0];
        assertEquals(state, {
          quota: "committed",
          credit: "held",
          usage: null,
        });
        await db.queryArray("SELECT public.apply_user_tombstone($1)", [
          f.owner,
        ]);
        await denied(db, () => read());
        await denied(db, () => record());
      } finally {
        await db.queryArray("ROLLBACK");
        await db.end();
      }
    },
  });
}

Deno.test({
  name: "private video concurrent outcome capture keeps one immutable answer",
  ignore: !url,
  async fn() {
    const first = await connect(), second = await connect();
    const dispatchGates = [
      ...gates,
      "admission_enabled",
      "protected_analysis_enabled",
      "video_analysis_enabled",
      "source_dispatch_enabled",
      "dispatch_enabled",
      "video_dispatch_enabled",
    ];
    let prior: Record<string, boolean> | undefined;
    let entitlement: { mode: string; protocol: number } | undefined;
    let owner: string | undefined;
    try {
      await fixture(first);
      prior = (await first.queryObject<Record<string, boolean>>(
        `SELECT ${
          dispatchGates.join(",")
        } FROM internal.observation_history_rollout`,
      )).rows[0];
      entitlement =
        (await first.queryObject<{ mode: string; protocol: number }>(
          "SELECT entitlement_mode mode,required_client_protocol protocol FROM internal.entitlement_rollout_config WHERE config_key='current'",
        )).rows[0];
      const f = await fundedVideo(first, 1);
      owner = f.owner;
      await first.queryArray(
        "UPDATE internal.observation_history_rollout SET video_dispatch_enabled=true",
      );
      const claim = (await claimVideo(first, f)).rows[0].value;
      await dispatchVideo(first, f, claim.work_token);
      const outcome = {
        schema_version: 1,
        provenance: f.provenance,
        outcome: { kind: "refusal" },
        usage: {},
      };
      const record = (db: Client) =>
        db.queryArray(
          "SELECT internal.record_video_observation_outcome($1,$2,$3,$4,$5::jsonb)",
          [
            f.owner,
            f.parent,
            f.child,
            (f.admitted.quota as { lease_token: string }).lease_token,
            JSON.stringify(outcome),
          ],
        );
      await first.queryArray("BEGIN");
      await second.queryArray("BEGIN");
      await record(first);
      const pid = (await second.queryObject<{ pid: number }>(
        "SELECT pg_backend_pid() pid",
      )).rows[0].pid;
      const pending = record(second).then(
        (value) => ({ value }),
        (error) => ({ error }),
      );
      let blocked = false;
      for (let n = 0; n < 100 && !blocked; n++) {
        blocked = (await first.queryObject<{ blocked: boolean }>(
          "SELECT cardinality(pg_blocking_pids($1))>0 blocked",
          [pid],
        )).rows[0].blocked;
        if (!blocked) await new Promise((r) => setTimeout(r, 5));
      }
      assert(blocked, "duplicate outcome must await original commit");
      await first.queryArray("COMMIT");
      const result = await pending;
      assert("value" in result);
      await second.queryArray("COMMIT");
      const read = (await first.queryObject<{ value: Record<string, unknown> }>(
        "SELECT internal.read_video_observation_outcome($1,$2,$3) value",
        [f.owner, f.parent, f.child],
      )).rows[0].value;
      assertEquals(read.provider_outcome, outcome);
      assertEquals(read.state, "dispatched");
    } finally {
      await first.queryArray("ROLLBACK").catch(() => {});
      await second.queryArray("ROLLBACK").catch(() => {});
      if (owner) {
        await first.queryArray("SELECT public.apply_user_tombstone($1)", [
          owner,
        ]).catch(() => {});
        await first.queryArray("DELETE FROM auth.users WHERE id=$1", [owner])
          .catch(() => {});
      }
      if (prior) {
        await first.queryArray(
          `UPDATE internal.observation_history_rollout SET ${
            dispatchGates.map((g, i) => `${g}=$${i + 1}`).join(",")
          }`,
          dispatchGates.map((g) => prior![g]),
        );
      }
      if (entitlement) {
        await first.queryArray(
          "UPDATE internal.entitlement_rollout_config SET entitlement_mode=$1,required_client_protocol=$2 WHERE config_key='current'",
          [entitlement.mode, entitlement.protocol],
        );
      }
      await first.end();
      await second.end();
    }
  },
});

for (const captureFirst of [true, false]) {
  Deno.test({
    name:
      `private video outcome and invocation retention serialize captureFirst=${captureFirst}`,
    ignore: !url,
    async fn() {
      const first = await connect(), second = await connect();
      const dispatchGates = [
        ...gates,
        "admission_enabled",
        "protected_analysis_enabled",
        "video_analysis_enabled",
        "source_dispatch_enabled",
        "dispatch_enabled",
        "video_dispatch_enabled",
      ];
      let prior: Record<string, boolean> | undefined;
      let entitlement: { mode: string; protocol: number } | undefined;
      let owner: string | undefined;
      try {
        await fixture(first);
        prior = (await first.queryObject<Record<string, boolean>>(
          `SELECT ${
            dispatchGates.join(",")
          } FROM internal.observation_history_rollout`,
        )).rows[0];
        entitlement =
          (await first.queryObject<{ mode: string; protocol: number }>(
            "SELECT entitlement_mode mode,required_client_protocol protocol FROM internal.entitlement_rollout_config WHERE config_key='current'",
          )).rows[0];
        const f = await fundedVideo(first, 1);
        owner = f.owner;
        await first.queryArray(
          "UPDATE internal.observation_history_rollout SET video_dispatch_enabled=true",
        );
        const claim = (await claimVideo(first, f)).rows[0].value;
        await dispatchVideo(first, f, claim.work_token);
        const outcome = {
          schema_version: 1,
          provenance: f.provenance,
          outcome: { kind: "refusal" },
          usage: {},
        };
        const record = (db: Client) =>
          db.queryArray(
            "SELECT internal.record_video_observation_outcome($1,$2,$3,$4,$5::jsonb)",
            [
              f.owner,
              f.parent,
              f.child,
              (f.admitted.quota as { lease_token: string }).lease_token,
              JSON.stringify(outcome),
            ],
          );
        await first.queryArray("BEGIN");
        await second.queryArray("BEGIN");
        if (captureFirst) await record(first);
        else {await first.queryArray(
            "DELETE FROM internal.identification_invocations WHERE scan_id=$1",
            [f.child],
          );}
        const pid = (await second.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() pid",
        )).rows[0].pid;
        const pending = (captureFirst
          ? second.queryArray(
            "DELETE FROM internal.identification_invocations WHERE scan_id=$1",
            [f.child],
          )
          : record(second)).then(
            (value) => ({ value }),
            (error) => ({ error }),
          );
        let blocked = false;
        for (let n = 0; n < 100 && !blocked; n++) {
          blocked = (await first.queryObject<{ blocked: boolean }>(
            "SELECT cardinality(pg_blocking_pids($1))>0 blocked",
            [pid],
          )).rows[0].blocked;
          if (!blocked) await new Promise((r) => setTimeout(r, 5));
        }
        assert(blocked, "duplicate outcome must await original commit");
        await first.queryArray("COMMIT");
        const result = await pending;
        if (captureFirst) {
          assert("value" in result);
          await second.queryArray("COMMIT");
        } else {
          assert("error" in result);
          await second.queryArray("ROLLBACK");
        }
        const read =
          (await first.queryObject<{ value: Record<string, unknown> }>(
            "SELECT internal.read_video_observation_outcome($1,$2,$3) value",
            [f.owner, f.parent, f.child],
          )).rows[0].value;
        assertEquals(read.provider_outcome, captureFirst ? outcome : null);
        assertEquals(read.state, "dispatched");
      } finally {
        await first.queryArray("ROLLBACK").catch(() => {});
        await second.queryArray("ROLLBACK").catch(() => {});
        if (owner) {
          await first.queryArray("SELECT public.apply_user_tombstone($1)", [
            owner,
          ]).catch(() => {});
          await first.queryArray("DELETE FROM auth.users WHERE id=$1", [owner])
            .catch(() => {});
        }
        if (prior) {
          await first.queryArray(
            `UPDATE internal.observation_history_rollout SET ${
              dispatchGates.map((g, i) => `${g}=$${i + 1}`).join(",")
            }`,
            dispatchGates.map((g) => prior![g]),
          );
        }
        if (entitlement) {
          await first.queryArray(
            "UPDATE internal.entitlement_rollout_config SET entitlement_mode=$1,required_client_protocol=$2 WHERE config_key='current'",
            [entitlement.mode, entitlement.protocol],
          );
        }
        await first.end();
        await second.end();
      }
    },
  });
}

async function preparedDraft(
  db: Client,
  f: Awaited<ReturnType<typeof fundedVideo>>,
) {
  const page = JSON.parse(
    await Deno.readTextFile(
      new URL(
        "../_shared/analysisHistory/fixtures/page-v1.json",
        import.meta.url,
      ),
    ),
  );
  const result = {
    ...JSON.parse(page.items[0].snapshot).result,
    scan_id: f.parent,
    identification_provenance: f.provenance,
  };
  const species =
    (await db.queryObject<{ id: string; scientific_name: string }>(
      "INSERT INTO public.species_dictionary(scientific_name,common_names) VALUES($1,'{}') ON CONFLICT(scientific_name) DO UPDATE SET scientific_name=EXCLUDED.scientific_name RETURNING id,scientific_name",
      [result.scientific_name],
    )).rows[0];
  const draft = buildPreparedVideoDraft(
    JSON.stringify(f.c.input),
    result,
    species,
  );
  const { species_id: _species, ...canonical } = draft.result_snapshot;
  const outcome = {
    schema_version: 1,
    provenance: f.provenance,
    outcome: { kind: "draft", result: canonical },
    usage: {},
  };
  return { draft, outcome };
}
const recordVideoDraft = (
  db: Client,
  f: Awaited<ReturnType<typeof fundedVideo>>,
  draft: unknown,
  token = (f.admitted.quota as { lease_token: string }).lease_token,
) =>
  db.queryArray(
    "SELECT internal.record_video_observation_draft($1,$2,$3,$4,$5::jsonb)",
    [f.owner, f.parent, f.child, token, JSON.stringify(draft)],
  );
const saveVideoDraftOutcome = (
  db: Client,
  f: Awaited<ReturnType<typeof fundedVideo>>,
  outcome: unknown,
) =>
  db.queryArray(
    "SELECT internal.record_video_observation_outcome($1,$2,$3,$4,$5::jsonb)",
    [
      f.owner,
      f.parent,
      f.child,
      (f.admitted.quota as { lease_token: string }).lease_token,
      JSON.stringify(outcome),
    ],
  );
for (let variant = 0; variant < 3; variant++) {
  Deno.test({
    name:
      `private video canonical draft persists without accounting or completion variant=${variant}`,
    ignore: !url,
    async fn() {
      const db = await connect();
      await db.queryArray("BEGIN");
      try {
        await fixture(db);
        const f = await fundedVideo(db, variant);
        const { draft, outcome } = await preparedDraft(db, f);
        await denied(db, () => recordVideoDraft(db, f, draft));
        await db.queryArray(
          "UPDATE internal.observation_history_rollout SET video_dispatch_enabled=true",
        );
        const claim = (await claimVideo(db, f)).rows[0].value;
        await dispatchVideo(db, f, claim.work_token);
        await denied(db, () => recordVideoDraft(db, f, draft));
        for (const kind of ["refusal", "invalid_output"]) {
          await db.queryArray("SAVEPOINT wrong_outcome");
          await saveVideoDraftOutcome(db, f, { ...outcome, outcome: { kind } });
          await denied(db, () => recordVideoDraft(db, f, draft));
          await db.queryArray("ROLLBACK TO SAVEPOINT wrong_outcome");
        }
        await saveVideoDraftOutcome(db, f, outcome);
        await denied(
          db,
          () => recordVideoDraft(db, f, draft, crypto.randomUUID()),
        );
        await denied(
          db,
          () =>
            recordVideoDraft(db, { ...f, owner: crypto.randomUUID() }, draft),
        );
        for (
          const malformed of [
            null,
            {},
            { ...draft, extra: true },
            { ...draft, schema_version: 3 },
            { ...draft, source_analysis_id: null },
            { ...draft, evidence_manifest: {} },
            {
              ...draft,
              result_snapshot: {
                ...draft.result_snapshot,
                common_name: "changed",
              },
            },
            {
              ...draft,
              result_snapshot: { ...draft.result_snapshot, species_id: null },
            },
            {
              ...draft,
              result_snapshot: {
                ...draft.result_snapshot,
                species_id: crypto.randomUUID(),
              },
            },
            {
              ...draft,
              result_snapshot: {
                ...draft.result_snapshot,
                species_id: "invalid",
              },
            },
            {
              ...draft,
              result_snapshot: {
                ...draft.result_snapshot,
                entitlement: { credit_consumed: true },
              },
            },
            {
              ...draft,
              result_snapshot: {
                ...draft.result_snapshot,
                ai_reasoning: "a".repeat(1048576),
              },
            },
          ]
        ) {
          await denied(db, () => recordVideoDraft(db, f, malformed));
        }
        // Independently reject malformed received results even when caller equality holds.
        for (
          const patch of [
            { scan_id: f.child },
            { confidence_score: 2 },
            { is_live_capture: "yes" },
            { entitlement: {} },
            { identification_provenance: {} },
          ]
        ) {
          await db.queryArray("SAVEPOINT malformed_saved");
          const result = { ...draft.result_snapshot, ...patch };
          const { species_id: _s, ...received } = result;
          await db.queryArray(
            "UPDATE internal.observation_analysis_intents SET provider_outcome=$2::jsonb WHERE analysis_id=$1",
            [
              f.child,
              JSON.stringify({
                ...outcome,
                outcome: { kind: "draft", result: received },
              }),
            ],
          );
          await denied(
            db,
            () =>
              recordVideoDraft(db, f, { ...draft, result_snapshot: result }),
          );
          await db.queryArray("ROLLBACK TO SAVEPOINT malformed_saved");
        }
        await db.queryArray("SAVEPOINT taxonomy_changed");
        await db.queryArray(
          "UPDATE public.species_dictionary SET scientific_name=$2 WHERE id=$1",
          [draft.result_snapshot.species_id, "Synthetic unmatched taxonomy"],
        );
        await denied(db, () => recordVideoDraft(db, f, draft));
        await db.queryArray("ROLLBACK TO SAVEPOINT taxonomy_changed");
        await age(db, f.child);
        await db.queryArray(
          "UPDATE internal.observation_history_rollout SET video_dispatch_enabled=false,dispatch_enabled=false,admission_enabled=false,media_enabled=false",
        );
        await db.queryArray(
          "UPDATE internal.observation_analysis_intents SET work_expires_at=clock_timestamp()-interval '1 second' WHERE analysis_id=$1",
          [f.child],
        );
        await db.queryArray(
          "DELETE FROM internal.identification_invocations WHERE scan_id=$1",
          [f.child],
        );
        const before = (await db.queryObject<{ value: unknown }>(
          "SELECT to_jsonb(i)-'draft' value FROM internal.observation_analysis_intents i WHERE analysis_id=$1",
          [f.child],
        )).rows[0].value;
        await recordVideoDraft(db, f, draft);
        await recordVideoDraft(db, f, draft);
        assertEquals(
          (await db.queryObject<{ value: unknown }>(
            "SELECT to_jsonb(i)-'draft' value FROM internal.observation_analysis_intents i WHERE analysis_id=$1",
            [f.child],
          )).rows[0].value,
          before,
        );
        assertEquals(
          (await db.queryObject<{ value: unknown }>(
            "SELECT draft value FROM internal.observation_analysis_intents WHERE analysis_id=$1",
            [f.child],
          )).rows[0].value,
          draft,
        );
        const state = (await db.queryObject<
          {
            state: string;
            quota: string;
            credit: string;
            usage: unknown;
            receipt: unknown;
            results: number;
          }
        >(
          "SELECT i.state,q.state quota,c.state credit,i.provider_usage usage,i.receipt,(SELECT count(*)::int FROM internal.observation_analysis_results WHERE analysis_id=$1) results FROM internal.observation_analysis_intents i JOIN internal.ai_quota_reservations q ON q.original_analysis_id=i.analysis_id JOIN internal.complimentary_scan_usage c ON c.client_scan_id=i.analysis_id WHERE i.analysis_id=$1",
          [f.child],
        )).rows[0];
        assertEquals(state, {
          state: "dispatched",
          quota: "committed",
          credit: "held",
          usage: null,
          receipt: null,
          results: 0,
        });
        assertEquals((await claimVideo(db, f)).rows[0].value.claimed, false);
        await db.queryArray(
          "UPDATE internal.observation_history_rollout SET orchestration_enabled=true",
        );
        await denied(
          db,
          () =>
            db.queryArray(
              "SELECT public.claim_observation_analysis_recovery($1,$2,$3)",
              [f.owner, f.parent, f.child],
            ),
        );
        await denied(
          db,
          () =>
            db.queryArray(
              "SELECT public.advance_owned_observation_analysis($1,$2,$3,$4,'complete','{}'::jsonb)",
              [f.owner, f.parent, f.child, claim.work_token],
            ),
        );
        await denied(
          db,
          () =>
            db.queryArray(
              "SELECT internal.complete_observation_analysis($1,$2,$3)",
              [f.owner, f.parent, f.child],
            ),
        );
        await db.queryArray("SAVEPOINT replay_dictionary");
        await db.queryArray(
          "UPDATE public.species_dictionary SET scientific_name=$2 WHERE id=$1",
          [
            draft.result_snapshot.species_id,
            "Synthetic replay taxonomy change",
          ],
        );
        await recordVideoDraft(db, f, draft);
        await db.queryArray("ROLLBACK TO SAVEPOINT replay_dictionary");

        await denied(db, () =>
          recordVideoDraft(db, f, {
            ...draft,
            result_snapshot: { ...draft.result_snapshot, species_id: null },
          }));
        await db.queryArray("SELECT public.apply_user_tombstone($1)", [
          f.owner,
        ]);
        await denied(db, () => recordVideoDraft(db, f, draft));
      } finally {
        await db.queryArray("ROLLBACK");
        await db.end();
      }
    },
  });
}

Deno.test({
  name: "private video concurrent draft persistence waits for original commit",
  ignore: !url,
  async fn() {
    const first = await connect(), second = await connect();
    const dispatchGates = [
      ...gates,
      "admission_enabled",
      "protected_analysis_enabled",
      "video_analysis_enabled",
      "source_dispatch_enabled",
      "dispatch_enabled",
      "video_dispatch_enabled",
    ];
    let prior: Record<string, boolean> | undefined;
    let entitlement: { mode: string; protocol: number } | undefined;
    let owner: string | undefined;
    try {
      await fixture(first);
      prior = (await first.queryObject<Record<string, boolean>>(
        `SELECT ${
          dispatchGates.join(",")
        } FROM internal.observation_history_rollout`,
      )).rows[0];
      entitlement =
        (await first.queryObject<{ mode: string; protocol: number }>(
          "SELECT entitlement_mode mode,required_client_protocol protocol FROM internal.entitlement_rollout_config WHERE config_key='current'",
        )).rows[0];
      const f = await fundedVideo(first, 1);
      owner = f.owner;
      await first.queryArray(
        "UPDATE internal.observation_history_rollout SET video_dispatch_enabled=true",
      );
      const claim = (await claimVideo(first, f)).rows[0].value;
      await dispatchVideo(first, f, claim.work_token);
      const { draft, outcome } = await preparedDraft(first, f);
      await saveVideoDraftOutcome(first, f, outcome);
      const record = (db: Client) => recordVideoDraft(db, f, draft);
      await first.queryArray("BEGIN");
      await second.queryArray("BEGIN");
      await record(first);
      const pid = (await second.queryObject<{ pid: number }>(
        "SELECT pg_backend_pid() pid",
      )).rows[0].pid;
      const pending = record(second).then(
        (value) => ({ value }),
        (error) => ({ error }),
      );
      let blocked = false;
      for (let n = 0; n < 100 && !blocked; n++) {
        blocked = (await first.queryObject<{ blocked: boolean }>(
          "SELECT cardinality(pg_blocking_pids($1))>0 blocked",
          [pid],
        )).rows[0].blocked;
        if (!blocked) await new Promise((r) => setTimeout(r, 5));
      }
      assert(blocked, "duplicate draft must await original commit");
      await first.queryArray("COMMIT");
      const result = await pending;
      assert("value" in result);
      await second.queryArray("COMMIT");
      const read = (await first.queryObject<{ value: Record<string, unknown> }>(
        "SELECT jsonb_build_object('draft',draft,'state',state) value FROM internal.observation_analysis_intents WHERE owner_id=$1 AND observation_id=$2 AND analysis_id=$3",
        [f.owner, f.parent, f.child],
      )).rows[0].value;
      assertEquals(read.draft, draft);
      assertEquals(read.state, "dispatched");
    } finally {
      await first.queryArray("ROLLBACK").catch(() => {});
      await second.queryArray("ROLLBACK").catch(() => {});
      if (owner) {
        await first.queryArray("SELECT public.apply_user_tombstone($1)", [
          owner,
        ]).catch(() => {});
        await first.queryArray("DELETE FROM auth.users WHERE id=$1", [owner])
          .catch(() => {});
      }
      if (prior) {
        await first.queryArray(
          `UPDATE internal.observation_history_rollout SET ${
            dispatchGates.map((g, i) => `${g}=$${i + 1}`).join(",")
          }`,
          dispatchGates.map((g) => prior![g]),
        );
      }
      if (entitlement) {
        await first.queryArray(
          "UPDATE internal.entitlement_rollout_config SET entitlement_mode=$1,required_client_protocol=$2 WHERE config_key='current'",
          [entitlement.mode, entitlement.protocol],
        );
      }
      await first.end();
      await second.end();
    }
  },
});

const accountVideo = (
  db: Client,
  f: Awaited<ReturnType<typeof fundedVideo>>,
  token = (f.admitted.quota as { lease_token: string }).lease_token,
) =>
  db.queryObject<{ value: Record<string, unknown> }>(
    "SELECT internal.account_video_observation_draft($1,$2,$3,$4) value",
    [f.owner, f.parent, f.child, token],
  );
for (let variant = 0; variant < 3; variant++) {
  Deno.test({
    name:
      `private video accounting proves original successful event and retains completion hold variant=${variant}`,
    ignore: !url,
    async fn() {
      const db = await connect();
      await db.queryArray("BEGIN");
      try {
        await fixture(db);
        const f = await fundedVideo(db, variant);
        await denied(db, () => accountVideo(db, f));
        await db.queryArray(
          "UPDATE internal.observation_history_rollout SET video_dispatch_enabled=true",
        );
        const claim = (await claimVideo(db, f)).rows[0].value;
        await dispatchVideo(db, f, claim.work_token);
        const { draft, outcome } = await preparedDraft(db, f);
        const usage = variant === 0
          ? {}
          : variant === 1
          ? { input_tokens: 100, output_tokens: 20, total_tokens: 120 }
          : { input_tokens: -1, output_tokens: "invalid" };
        await saveVideoDraftOutcome(db, f, { ...outcome, usage });
        await denied(db, () => accountVideo(db, f));
        await recordVideoDraft(db, f, draft);
        await denied(db, () => accountVideo(db, f, crypto.randomUUID()));
        await denied(
          db,
          () => accountVideo(db, { ...f, owner: crypto.randomUUID() }),
        );
        await db.queryArray("SAVEPOINT missing_invocation");
        await db.queryArray(
          "DELETE FROM internal.identification_invocations WHERE scan_id=$1",
          [f.child],
        );
        await denied(db, () => accountVideo(db, f));
        await db.queryArray("ROLLBACK TO SAVEPOINT missing_invocation");
        for (
          const kind of ["unknown_execution", "refusal", "operational_failure"]
        ) {
          await db.queryArray("SAVEPOINT existing_event");
          await db.queryArray(
            "SELECT internal.complete_identification_usage(invocation_id,$2,'{}') FROM internal.observation_analysis_intents WHERE analysis_id=$1",
            [f.child, kind],
          );
          await denied(db, () => accountVideo(db, f));
          assertEquals(
            (await db.queryObject<{ state: string }>(
              "SELECT state FROM internal.observation_analysis_intents WHERE analysis_id=$1",
              [f.child],
            )).rows[0].state,
            "dispatched",
          );
          await db.queryArray("ROLLBACK TO SAVEPOINT existing_event");
        }
        await db.queryArray("SAVEPOINT wrong_usage");
        await db.queryArray(
          "SELECT internal.complete_identification_usage(invocation_id,'draft','{\"input_tokens\":999}') FROM internal.observation_analysis_intents WHERE analysis_id=$1",
          [f.child],
        );
        await denied(db, () => accountVideo(db, f));
        await db.queryArray("ROLLBACK TO SAVEPOINT wrong_usage");
        await db.queryArray("SAVEPOINT insert_rollback");
        await db.queryArray(
          "ALTER TABLE internal.observation_video_accounting_receipts ADD CONSTRAINT synthetic_reject CHECK(false) NOT VALID",
        );
        await denied(db, () => accountVideo(db, f));
        assertEquals(
          (await db.queryObject<{ count: number }>(
            "SELECT count(*)::int count FROM public.ai_usage_events WHERE scan_id=$1",
            [f.child],
          )).rows[0].count,
          0,
        );
        await db.queryArray("ROLLBACK TO SAVEPOINT insert_rollback");
        if (variant === 1) {
          await db.queryArray(
            "SELECT internal.complete_identification_usage(invocation_id,'draft',$2::jsonb) FROM internal.observation_analysis_intents WHERE analysis_id=$1",
            [f.child, JSON.stringify(usage)],
          );
        }
        const proof = (await accountVideo(db, f)).rows[0].value;
        await denied(db, () => settleVideoTerminal(db, f));
        await denied(
          db,
          () =>
            db.queryArray(
              "SELECT internal.complete_observation_analysis($1,$2,$3)",
              [f.owner, f.parent, f.child],
            ),
        );
        await db.queryArray(
          "UPDATE internal.observation_history_rollout SET orchestration_enabled=true",
        );
        await denied(
          db,
          () =>
            db.queryArray(
              "SELECT public.advance_owned_observation_analysis($1,$2,$3,$4,'complete','{}'::jsonb)",
              [f.owner, f.parent, f.child, claim.work_token],
            ),
        );

        assertEquals((await accountVideo(db, f)).rows[0].value, proof);
        const state = (await db.queryObject<{ value: unknown }>(
          "SELECT jsonb_build_object('state',i.state,'usage',i.provider_usage,'receipt',i.receipt,'credit',c.state,'quota',q.state,'work_token',i.work_token,'results',(SELECT count(*) FROM internal.observation_analysis_results WHERE analysis_id=$1),'proofs',(SELECT count(*) FROM internal.observation_video_accounting_receipts WHERE analysis_id=$1),'events',(SELECT count(*) FROM public.ai_usage_events WHERE scan_id=$1)) value FROM internal.observation_analysis_intents i JOIN internal.complimentary_scan_usage c ON c.client_scan_id=i.analysis_id JOIN internal.ai_quota_reservations q ON q.original_analysis_id=i.analysis_id WHERE i.analysis_id=$1",
          [f.child],
        )).rows[0].value;
        assertEquals(state, {
          state: "draft",
          usage,
          receipt: null,
          credit: "held",
          quota: "committed",
          work_token: claim.work_token,
          results: 0,
          proofs: 1,
          events: 1,
        });
        await denied(db, () =>
          db.queryArray(
            "UPDATE internal.observation_video_accounting_receipts SET proof=proof WHERE analysis_id=$1",
            [f.child],
          ));
        await denied(db, () =>
          db.queryArray(
            "DELETE FROM internal.observation_video_accounting_receipts WHERE analysis_id=$1",
            [f.child],
          ));
        await denied(db, () =>
          db.queryArray(
            "INSERT INTO internal.observation_video_accounting_receipts SELECT * FROM internal.observation_video_accounting_receipts WHERE analysis_id=$1",
            [f.child],
          ));
        await db.queryArray(
          "DELETE FROM internal.identification_invocations WHERE scan_id=$1",
          [f.child],
        );
        await db.queryArray(
          "UPDATE internal.observation_history_rollout SET video_dispatch_enabled=false,dispatch_enabled=false,admission_enabled=false,media_enabled=false",
        );
        await age(db, f.child);
        assertEquals((await accountVideo(db, f)).rows[0].value, proof);
        assertEquals((await claimVideo(db, f)).rows[0].value.claimed, false);
        await db.queryArray("SELECT public.apply_user_tombstone($1)", [
          f.owner,
        ]);
        await denied(db, () => accountVideo(db, f));
      } finally {
        await db.queryArray("ROLLBACK");
        await db.end();
      }
    },
  });
}
Deno.test({
  name: "private video concurrent accounting waits for original commit",
  ignore: !url,
  async fn() {
    const first = await connect(), second = await connect();
    const dispatchGates = [
      ...gates,
      "admission_enabled",
      "protected_analysis_enabled",
      "video_analysis_enabled",
      "source_dispatch_enabled",
      "dispatch_enabled",
      "video_dispatch_enabled",
    ];
    let prior: Record<string, boolean> | undefined;
    let entitlement: { mode: string; protocol: number } | undefined;
    let owner: string | undefined;
    try {
      await fixture(first);
      prior = (await first.queryObject<Record<string, boolean>>(
        `SELECT ${
          dispatchGates.join(",")
        } FROM internal.observation_history_rollout`,
      )).rows[0];
      entitlement =
        (await first.queryObject<{ mode: string; protocol: number }>(
          "SELECT entitlement_mode mode,required_client_protocol protocol FROM internal.entitlement_rollout_config WHERE config_key='current'",
        )).rows[0];
      const f = await fundedVideo(first, 1);
      owner = f.owner;
      await first.queryArray(
        "UPDATE internal.observation_history_rollout SET video_dispatch_enabled=true",
      );
      const claim = (await claimVideo(first, f)).rows[0].value;
      await dispatchVideo(first, f, claim.work_token);
      const { draft, outcome } = await preparedDraft(first, f);
      await saveVideoDraftOutcome(first, f, outcome);
      await recordVideoDraft(first, f, draft);
      const record = (db: Client) => accountVideo(db, f);
      await first.queryArray("BEGIN");
      await second.queryArray("BEGIN");
      await record(first);
      const pid = (await second.queryObject<{ pid: number }>(
        "SELECT pg_backend_pid() pid",
      )).rows[0].pid;
      const pending = record(second).then(
        (value) => ({ value }),
        (error) => ({ error }),
      );
      let blocked = false;
      for (let n = 0; n < 100 && !blocked; n++) {
        blocked = (await first.queryObject<{ blocked: boolean }>(
          "SELECT cardinality(pg_blocking_pids($1))>0 blocked",
          [pid],
        )).rows[0].blocked;
        if (!blocked) await new Promise((r) => setTimeout(r, 5));
      }
      assert(blocked, "duplicate accounting must await original commit");
      await first.queryArray("COMMIT");
      const result = await pending;
      assert("value" in result);
      await second.queryArray("COMMIT");
      const read = (await first.queryObject<{ value: Record<string, unknown> }>(
        "SELECT jsonb_build_object('draft',draft,'state',state) value FROM internal.observation_analysis_intents WHERE owner_id=$1 AND observation_id=$2 AND analysis_id=$3",
        [f.owner, f.parent, f.child],
      )).rows[0].value;
      assertEquals(read.draft, draft);
      assertEquals(read.state, "draft");
      assertEquals(
        (await accountVideo(first, f)).rows[0].value,
        (result.value as Awaited<ReturnType<typeof accountVideo>>).rows[0]
          .value,
      );
    } finally {
      await first.queryArray("ROLLBACK").catch(() => {});
      await second.queryArray("ROLLBACK").catch(() => {});
      if (owner) {
        await first.queryArray("SELECT public.apply_user_tombstone($1)", [
          owner,
        ]).catch(() => {});
        await first.queryArray("DELETE FROM auth.users WHERE id=$1", [owner])
          .catch(() => {});
      }
      if (prior) {
        await first.queryArray(
          `UPDATE internal.observation_history_rollout SET ${
            dispatchGates.map((g, i) => `${g}=$${i + 1}`).join(",")
          }`,
          dispatchGates.map((g) => prior![g]),
        );
      }
      if (entitlement) {
        await first.queryArray(
          "UPDATE internal.entitlement_rollout_config SET entitlement_mode=$1,required_client_protocol=$2 WHERE config_key='current'",
          [entitlement.mode, entitlement.protocol],
        );
      }
      await first.end();
      await second.end();
    }
  },
});
for (const captureFirst of [true, false]) {
  Deno.test({
    name:
      `private video accounting and invocation retention serialize captureFirst=${captureFirst}`,
    ignore: !url,
    async fn() {
      const first = await connect(), second = await connect();
      const dispatchGates = [
        ...gates,
        "admission_enabled",
        "protected_analysis_enabled",
        "video_analysis_enabled",
        "source_dispatch_enabled",
        "dispatch_enabled",
        "video_dispatch_enabled",
      ];
      let prior: Record<string, boolean> | undefined;
      let entitlement: { mode: string; protocol: number } | undefined;
      let owner: string | undefined;
      try {
        await fixture(first);
        prior = (await first.queryObject<Record<string, boolean>>(
          `SELECT ${
            dispatchGates.join(",")
          } FROM internal.observation_history_rollout`,
        )).rows[0];
        entitlement =
          (await first.queryObject<{ mode: string; protocol: number }>(
            "SELECT entitlement_mode mode,required_client_protocol protocol FROM internal.entitlement_rollout_config WHERE config_key='current'",
          )).rows[0];
        const f = await fundedVideo(first, 1);
        owner = f.owner;
        await first.queryArray(
          "UPDATE internal.observation_history_rollout SET video_dispatch_enabled=true",
        );
        const claim = (await claimVideo(first, f)).rows[0].value;
        await dispatchVideo(first, f, claim.work_token);
        const { draft, outcome } = await preparedDraft(first, f);
        await saveVideoDraftOutcome(first, f, outcome);
        await recordVideoDraft(first, f, draft);
        const record = (db: Client) => accountVideo(db, f);
        await first.queryArray("BEGIN");
        await second.queryArray("BEGIN");
        if (captureFirst) await record(first);
        else {await first.queryArray(
            "DELETE FROM internal.identification_invocations WHERE scan_id=$1",
            [f.child],
          );}
        const pid = (await second.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() pid",
        )).rows[0].pid;
        const pending = (captureFirst
          ? second.queryArray(
            "DELETE FROM internal.identification_invocations WHERE scan_id=$1",
            [f.child],
          )
          : record(second)).then(
            (value) => ({ value }),
            (error) => ({ error }),
          );
        let blocked = false;
        for (let n = 0; n < 100 && !blocked; n++) {
          blocked = (await first.queryObject<{ blocked: boolean }>(
            "SELECT cardinality(pg_blocking_pids($1))>0 blocked",
            [pid],
          )).rows[0].blocked;
          if (!blocked) await new Promise((r) => setTimeout(r, 5));
        }
        assert(blocked, "accounting and retention must serialize");
        await first.queryArray("COMMIT");
        const result = await pending;
        if (captureFirst) {
          assert("value" in result);
          await second.queryArray("COMMIT");
        } else {
          assert("error" in result);
          await second.queryArray("ROLLBACK");
        }
        const read =
          (await first.queryObject<{ value: Record<string, unknown> }>(
            "SELECT internal.read_video_observation_outcome($1,$2,$3) value",
            [f.owner, f.parent, f.child],
          )).rows[0].value;
        assertEquals(read.provider_outcome, outcome);
        assertEquals(read.state, captureFirst ? "draft" : "dispatched");
        if (captureFirst) await accountVideo(first, f);
      } finally {
        await first.queryArray("ROLLBACK").catch(() => {});
        await second.queryArray("ROLLBACK").catch(() => {});
        if (owner) {
          await first.queryArray("SELECT public.apply_user_tombstone($1)", [
            owner,
          ]).catch(() => {});
          await first.queryArray("DELETE FROM auth.users WHERE id=$1", [owner])
            .catch(() => {});
        }
        if (prior) {
          await first.queryArray(
            `UPDATE internal.observation_history_rollout SET ${
              dispatchGates.map((g, i) => `${g}=$${i + 1}`).join(",")
            }`,
            dispatchGates.map((g) => prior![g]),
          );
        }
        if (entitlement) {
          await first.queryArray(
            "UPDATE internal.entitlement_rollout_config SET entitlement_mode=$1,required_client_protocol=$2 WHERE config_key='current'",
            [entitlement.mode, entitlement.protocol],
          );
        }
        await first.end();
        await second.end();
      }
    },
  });
}

const settleVideoTerminal = (
  db: Client,
  f: Awaited<ReturnType<typeof fundedVideo>>,
  token = (f.admitted.quota as { lease_token: string }).lease_token,
) =>
  db.queryObject<{ value: Record<string, unknown> }>(
    "SELECT internal.settle_video_observation_terminal($1,$2,$3,$4) value",
    [f.owner, f.parent, f.child, token],
  );
for (const kind of ["refusal", "invalid_output"]) {
  for (let variant = 0; variant < 3; variant++) {
    Deno.test({
      name:
        `private video terminal settlement is exact and keeps source held kind=${kind} variant=${variant}`,
      ignore: !url,
      async fn() {
        const db = await connect();
        await db.queryArray("BEGIN");
        try {
          await fixture(db);
          const paid = variant === 2;
          const f = await fundedVideo(db, variant, paid);
          const reason = kind === "refusal"
            ? "provider_refusal"
            : "invalid_result";
          const usage = variant === 0
            ? {}
            : { input_tokens: 100, candidate_tokens: 20, total_tokens: 120 };
          const outcome = {
            schema_version: 1,
            provenance: f.provenance,
            outcome: { kind },
            usage,
          };
          await denied(db, () => settleVideoTerminal(db, f));
          await db.queryArray(
            "UPDATE internal.observation_history_rollout SET video_dispatch_enabled=true",
          );
          const claim = (await claimVideo(db, f)).rows[0].value;
          await dispatchVideo(db, f, claim.work_token);
          await denied(db, () => settleVideoTerminal(db, f));
          await saveVideoDraftOutcome(db, f, outcome);
          await db.queryArray(
            "UPDATE internal.observation_history_rollout SET orchestration_enabled=true",
          );
          const denyGeneric = async () => {
            await denied(
              db,
              () =>
                db.queryArray(
                  "SELECT public.advance_owned_observation_analysis($1,$2,$3,$4,'fail',$5::jsonb)",
                  [
                    f.owner,
                    f.parent,
                    f.child,
                    claim.work_token,
                    JSON.stringify({ reason }),
                  ],
                ),
            );
            await denied(
              db,
              () =>
                db.queryArray(
                  "SELECT public.advance_owned_observation_analysis($1,$2,$3,$4,'outcome',$5::jsonb)",
                  [
                    f.owner,
                    f.parent,
                    f.child,
                    claim.work_token,
                    JSON.stringify({
                      quota_token: (f.admitted.quota as { lease_token: string })
                        .lease_token,
                      value: outcome,
                    }),
                  ],
                ),
            );
          };
          await denyGeneric();

          await denied(
            db,
            () => settleVideoTerminal(db, f, crypto.randomUUID()),
          );
          await denied(
            db,
            () => settleVideoTerminal(db, { ...f, owner: crypto.randomUUID() }),
          );
          await denied(db, () => accountVideo(db, f));
          await db.queryArray("SAVEPOINT missing_invocation");
          await db.queryArray(
            "DELETE FROM internal.identification_invocations WHERE scan_id=$1",
            [f.child],
          );
          await denied(db, () => settleVideoTerminal(db, f));
          await db.queryArray("ROLLBACK TO SAVEPOINT missing_invocation");
          const unchanged = async () =>
            (await db.queryObject<{ value: unknown }>(
              "SELECT jsonb_build_object('intent',to_jsonb(i),'credit',(SELECT to_jsonb(c) FROM internal.complimentary_scan_usage c WHERE client_scan_id=$1),'epoch',(SELECT complimentary_entitlement_epoch FROM public.users WHERE id=i.owner_id),'quota',(SELECT to_jsonb(q) FROM internal.ai_quota_reservations q WHERE original_analysis_id=$1)) value FROM internal.observation_analysis_intents i WHERE analysis_id=$1",
              [f.child],
            )).rows[0].value;
          for (
            const existing of [
              "unknown_execution",
              "draft",
              "operational_failure",
              kind === "refusal" ? "invalid_output" : "refusal",
            ]
          ) {
            await db.queryArray("SAVEPOINT wrong_event");
            await db.queryArray(
              "SELECT internal.complete_identification_usage(invocation_id,$2,$3::jsonb) FROM internal.observation_analysis_intents WHERE analysis_id=$1",
              [f.child, existing, JSON.stringify(usage)],
            );
            const before = await unchanged();
            await denied(db, () => settleVideoTerminal(db, f));
            assertEquals(await unchanged(), before);
            await db.queryArray("ROLLBACK TO SAVEPOINT wrong_event");
          }
          await db.queryArray("SAVEPOINT wrong_usage");
          await db.queryArray(
            "SELECT internal.complete_identification_usage(invocation_id,$2,'{\"input_tokens\":999}') FROM internal.observation_analysis_intents WHERE analysis_id=$1",
            [f.child, kind],
          );
          await denied(db, () => settleVideoTerminal(db, f));
          await db.queryArray("ROLLBACK TO SAVEPOINT wrong_usage");
          if (!paid) {
            await db.queryArray("SAVEPOINT settled_credit");
            await db.queryArray(
              "SELECT internal.settle_complimentary_analysis($1,$2,NULL)",
              [f.owner, f.child],
            );
            await denied(db, () => settleVideoTerminal(db, f));
            await db.queryArray("ROLLBACK TO SAVEPOINT settled_credit");
          }
          await db.queryArray("SAVEPOINT insert_failure");
          await db.queryArray(
            "ALTER TABLE internal.observation_video_terminal_receipts ADD CONSTRAINT synthetic_reject_terminal CHECK(false) NOT VALID",
          );
          const before = await unchanged();
          await denied(db, () => settleVideoTerminal(db, f));
          assertEquals(await unchanged(), before);
          assertEquals(
            (await db.queryObject<{ count: number }>(
              "SELECT count(*)::int count FROM public.ai_usage_events WHERE scan_id=$1",
              [f.child],
            )).rows[0].count,
            0,
          );
          await db.queryArray("ROLLBACK TO SAVEPOINT insert_failure");
          if (variant === 1) {
            await db.queryArray(
              "SELECT internal.complete_identification_usage(invocation_id,$2,$3::jsonb) FROM internal.observation_analysis_intents WHERE analysis_id=$1",
              [f.child, kind, JSON.stringify(usage)],
            );
          }
          await age(db, f.child);
          await db.queryArray(
            "UPDATE internal.observation_history_rollout SET video_dispatch_enabled=false,dispatch_enabled=false,admission_enabled=false,media_enabled=false",
          );
          const proof = (await settleVideoTerminal(db, f)).rows[0].value;
          await denyGeneric();
          const epoch = (await db.queryObject<{ epoch: unknown }>(
            "SELECT complimentary_entitlement_epoch epoch FROM public.users WHERE id=$1",
            [f.owner],
          )).rows[0].epoch;
          assertEquals((await settleVideoTerminal(db, f)).rows[0].value, proof);
          const state = (await db.queryObject<{ value: unknown }>(
            "SELECT jsonb_build_object('state',i.state,'reason',i.terminal_reason,'usage',i.provider_usage,'draft',i.draft,'receipt',i.receipt,'work_token',i.work_token,'work_expires_at',i.work_expires_at,'quota',q.state,'refunds',q.refund_count,'credit',(SELECT state FROM internal.complimentary_scan_usage WHERE client_scan_id=$1),'credit_reason',(SELECT settlement_reason FROM internal.complimentary_scan_usage WHERE client_scan_id=$1),'events',(SELECT count(*) FROM public.ai_usage_events WHERE scan_id=$1),'results',(SELECT count(*) FROM internal.observation_analysis_results WHERE analysis_id=$1),'occupancy',(SELECT count(*) FROM internal.observation_analysis_source_occupancy WHERE analysis_id=$1),'proofs',(SELECT count(*) FROM internal.observation_video_terminal_receipts WHERE analysis_id=$1)) value FROM internal.observation_analysis_intents i JOIN internal.ai_quota_reservations q ON q.original_analysis_id=i.analysis_id WHERE i.analysis_id=$1",
            [f.child],
          )).rows[0].value;
          assertEquals(state, {
            state: "failed_terminal",
            reason,
            usage,
            draft: null,
            receipt: null,
            work_token: null,
            work_expires_at: null,
            quota: "committed",
            refunds: 0,
            credit: paid ? null : "released",
            credit_reason: paid ? null : reason,
            events: 1,
            results: 0,
            occupancy: 1,
            proofs: 1,
          });
          for (
            const sql of [
              "UPDATE internal.observation_video_terminal_receipts SET proof=proof WHERE analysis_id=$1",
              "DELETE FROM internal.observation_video_terminal_receipts WHERE analysis_id=$1",
              "INSERT INTO internal.observation_video_terminal_receipts SELECT * FROM internal.observation_video_terminal_receipts WHERE analysis_id=$1",
            ]
          ) await denied(db, () => db.queryArray(sql, [f.child]));
          await db.queryArray(
            "DELETE FROM internal.identification_invocations WHERE scan_id=$1",
            [f.child],
          );
          assertEquals((await settleVideoTerminal(db, f)).rows[0].value, proof);
          assertEquals(
            (await db.queryObject<{ epoch: unknown }>(
              "SELECT complimentary_entitlement_epoch epoch FROM public.users WHERE id=$1",
              [f.owner],
            )).rows[0].epoch,
            epoch,
          );
          assertEquals((await claimVideo(db, f)).rows[0].value.claimed, false);
          await denied(db, () => dispatchVideo(db, f, claim.work_token));
          await denied(db, () => accountVideo(db, f));
          await db.queryArray("SELECT public.apply_user_tombstone($1)", [
            f.owner,
          ]);
          await denied(db, () => settleVideoTerminal(db, f));
        } finally {
          await db.queryArray("ROLLBACK");
          await db.end();
        }
      },
    });
  }
}
Deno.test({
  name:
    "private video concurrent terminal settlement waits for original commit",
  ignore: !url,
  async fn() {
    const first = await connect(), second = await connect();
    const dispatchGates = [
      ...gates,
      "admission_enabled",
      "protected_analysis_enabled",
      "video_analysis_enabled",
      "source_dispatch_enabled",
      "dispatch_enabled",
      "video_dispatch_enabled",
    ];
    let prior: Record<string, boolean> | undefined;
    let entitlement: { mode: string; protocol: number } | undefined;
    let owner: string | undefined;
    try {
      await fixture(first);
      prior = (await first.queryObject<Record<string, boolean>>(
        `SELECT ${
          dispatchGates.join(",")
        } FROM internal.observation_history_rollout`,
      )).rows[0];
      entitlement =
        (await first.queryObject<{ mode: string; protocol: number }>(
          "SELECT entitlement_mode mode,required_client_protocol protocol FROM internal.entitlement_rollout_config WHERE config_key='current'",
        )).rows[0];
      const f = await fundedVideo(first, 1);
      owner = f.owner;
      await first.queryArray(
        "UPDATE internal.observation_history_rollout SET video_dispatch_enabled=true",
      );
      const claim = (await claimVideo(first, f)).rows[0].value;
      await dispatchVideo(first, f, claim.work_token);
      const outcome = {
        schema_version: 1,
        provenance: f.provenance,
        outcome: { kind: "refusal" },
        usage: {},
      };
      await saveVideoDraftOutcome(first, f, outcome);
      const record = (db: Client) => settleVideoTerminal(db, f);
      await first.queryArray("BEGIN");
      await second.queryArray("BEGIN");
      await record(first);
      const pid = (await second.queryObject<{ pid: number }>(
        "SELECT pg_backend_pid() pid",
      )).rows[0].pid;
      const pending = record(second).then(
        (value) => ({ value }),
        (error) => ({ error }),
      );
      let blocked = false;
      for (let n = 0; n < 100 && !blocked; n++) {
        blocked = (await first.queryObject<{ blocked: boolean }>(
          "SELECT cardinality(pg_blocking_pids($1))>0 blocked",
          [pid],
        )).rows[0].blocked;
        if (!blocked) await new Promise((r) => setTimeout(r, 5));
      }
      assert(
        blocked,
        "duplicate terminal settlement must await original commit",
      );
      await first.queryArray("COMMIT");
      const result = await pending;
      assert("value" in result);
      await second.queryArray("COMMIT");
      const read = (await first.queryObject<{ value: Record<string, unknown> }>(
        "SELECT jsonb_build_object('draft',draft,'state',state) value FROM internal.observation_analysis_intents WHERE owner_id=$1 AND observation_id=$2 AND analysis_id=$3",
        [f.owner, f.parent, f.child],
      )).rows[0].value;
      assertEquals(read.draft, null);
      assertEquals(read.state, "failed_terminal");
      assertEquals(
        (await settleVideoTerminal(first, f)).rows[0].value,
        (result.value as Awaited<ReturnType<typeof settleVideoTerminal>>)
          .rows[0]
          .value,
      );
    } finally {
      await first.queryArray("ROLLBACK").catch(() => {});
      await second.queryArray("ROLLBACK").catch(() => {});
      if (owner) {
        await first.queryArray("SELECT public.apply_user_tombstone($1)", [
          owner,
        ]).catch(() => {});
        await first.queryArray("DELETE FROM auth.users WHERE id=$1", [owner])
          .catch(() => {});
      }
      if (prior) {
        await first.queryArray(
          `UPDATE internal.observation_history_rollout SET ${
            dispatchGates.map((g, i) => `${g}=$${i + 1}`).join(",")
          }`,
          dispatchGates.map((g) => prior![g]),
        );
      }
      if (entitlement) {
        await first.queryArray(
          "UPDATE internal.entitlement_rollout_config SET entitlement_mode=$1,required_client_protocol=$2 WHERE config_key='current'",
          [entitlement.mode, entitlement.protocol],
        );
      }
      await first.end();
      await second.end();
    }
  },
});
for (const captureFirst of [true, false]) {
  Deno.test({
    name:
      `private video terminal settlement and invocation retention serialize captureFirst=${captureFirst}`,
    ignore: !url,
    async fn() {
      const first = await connect(), second = await connect();
      const dispatchGates = [
        ...gates,
        "admission_enabled",
        "protected_analysis_enabled",
        "video_analysis_enabled",
        "source_dispatch_enabled",
        "dispatch_enabled",
        "video_dispatch_enabled",
      ];
      let prior: Record<string, boolean> | undefined;
      let entitlement: { mode: string; protocol: number } | undefined;
      let owner: string | undefined;
      try {
        await fixture(first);
        prior = (await first.queryObject<Record<string, boolean>>(
          `SELECT ${
            dispatchGates.join(",")
          } FROM internal.observation_history_rollout`,
        )).rows[0];
        entitlement =
          (await first.queryObject<{ mode: string; protocol: number }>(
            "SELECT entitlement_mode mode,required_client_protocol protocol FROM internal.entitlement_rollout_config WHERE config_key='current'",
          )).rows[0];
        const f = await fundedVideo(first, 1);
        owner = f.owner;
        await first.queryArray(
          "UPDATE internal.observation_history_rollout SET video_dispatch_enabled=true",
        );
        const claim = (await claimVideo(first, f)).rows[0].value;
        await dispatchVideo(first, f, claim.work_token);
        const outcome = {
          schema_version: 1,
          provenance: f.provenance,
          outcome: { kind: "invalid_output" },
          usage: {},
        };
        await saveVideoDraftOutcome(first, f, outcome);
        const record = (db: Client) => settleVideoTerminal(db, f);
        await first.queryArray("BEGIN");
        await second.queryArray("BEGIN");
        if (captureFirst) await record(first);
        else {await first.queryArray(
            "DELETE FROM internal.identification_invocations WHERE scan_id=$1",
            [f.child],
          );}
        const pid = (await second.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() pid",
        )).rows[0].pid;
        const pending = (captureFirst
          ? second.queryArray(
            "DELETE FROM internal.identification_invocations WHERE scan_id=$1",
            [f.child],
          )
          : record(second)).then(
            (value) => ({ value }),
            (error) => ({ error }),
          );
        let blocked = false;
        for (let n = 0; n < 100 && !blocked; n++) {
          blocked = (await first.queryObject<{ blocked: boolean }>(
            "SELECT cardinality(pg_blocking_pids($1))>0 blocked",
            [pid],
          )).rows[0].blocked;
          if (!blocked) await new Promise((r) => setTimeout(r, 5));
        }
        assert(blocked, "accounting and retention must serialize");
        await first.queryArray("COMMIT");
        const result = await pending;
        if (captureFirst) {
          assert("value" in result);
          await second.queryArray("COMMIT");
        } else {
          assert("error" in result);
          await second.queryArray("ROLLBACK");
        }
        const read =
          (await first.queryObject<{ value: Record<string, unknown> }>(
            "SELECT internal.read_video_observation_outcome($1,$2,$3) value",
            [f.owner, f.parent, f.child],
          )).rows[0].value;
        assertEquals(read.provider_outcome, outcome);
        assertEquals(
          read.state,
          captureFirst ? "failed_terminal" : "dispatched",
        );
        if (captureFirst) await settleVideoTerminal(first, f);
      } finally {
        await first.queryArray("ROLLBACK").catch(() => {});
        await second.queryArray("ROLLBACK").catch(() => {});
        if (owner) {
          await first.queryArray("SELECT public.apply_user_tombstone($1)", [
            owner,
          ]).catch(() => {});
          await first.queryArray("DELETE FROM auth.users WHERE id=$1", [owner])
            .catch(() => {});
        }
        if (prior) {
          await first.queryArray(
            `UPDATE internal.observation_history_rollout SET ${
              dispatchGates.map((g, i) => `${g}=$${i + 1}`).join(",")
            }`,
            dispatchGates.map((g) => prior![g]),
          );
        }
        if (entitlement) {
          await first.queryArray(
            "UPDATE internal.entitlement_rollout_config SET entitlement_mode=$1,required_client_protocol=$2 WHERE config_key='current'",
            [entitlement.mode, entitlement.protocol],
          );
        }
        await first.end();
        await second.end();
      }
    },
  });
}
