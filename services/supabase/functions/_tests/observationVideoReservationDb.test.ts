import { assert, assertEquals, assertRejects } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import vectors from "../_shared/analysisHistory/fixtures/video-source-fingerprint-v1.json" with {
  type: "json",
};
import { videoSourceFingerprint } from "../_shared/analysisHistory/videoSourceFingerprint.ts";
import {
  buildVideoSourceRecoveryRequest,
  decodeVideoSourceReservationReceipt,
} from "../_shared/analysisHistory/videoSourceReservation.ts";
const url = Deno.env.get("SUPABASE_DB_TEST_URL");
const gates = [
  "append_enabled",
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
Deno.test({
  name:
    "video reservation/recovery preserves exact identity, gates, ownership and legacy denial",
  ignore: !url,
  async fn() {
    const db = await connect();
    await db.queryArray("BEGIN");
    try {
      await fixture(db);
      for (let i = 0; i < 3; i++) {
        const [owner, parent, source, child, other] = Array.from(
          { length: 5 },
          () => crypto.randomUUID(),
        );
        await seed(db, owner, parent, source);
        const request = await candidate(parent, source, child, i),
          identity = await buildVideoSourceRecoveryRequest(request);
        const unavailable = {
          ...identity,
          owner_id: owner,
          state: "unavailable",
        };
        assertEquals(await recover(db, owner, identity), unavailable);
        await db.queryArray(
          "UPDATE internal.observation_history_rollout SET video_source_reservation_enabled=false",
        );
        assertEquals(await reserve(db, owner, request), unavailable);
        await db.queryArray(
          "UPDATE internal.observation_history_rollout SET video_source_reservation_enabled=true",
        );
        const receipt = await reserve(db, owner, request);
        assertEquals(receipt, {
          ...identity,
          owner_id: owner,
          state: "reserved",
        });
        await decodeVideoSourceReservationReceipt(
          new TextEncoder().encode(JSON.stringify(receipt)),
          request,
          owner,
        );
        assertEquals(await reserve(db, owner, request), receipt);
        assertEquals(await recover(db, owner, identity), receipt);
        await db.queryArray(
          "UPDATE internal.observation_history_rollout SET video_source_reservation_enabled=false,source_reservation_enabled=false",
        );
        assertEquals(await reserve(db, owner, request), receipt); // lost reply replay before fresh gates
        await db.queryArray(
          "UPDATE internal.observation_history_rollout SET video_source_recovery_enabled=false",
        );
        assertEquals(await recover(db, owner, identity), unavailable);
        await db.queryArray(
          "UPDATE internal.observation_history_rollout SET video_source_recovery_enabled=true,source_reservation_enabled=true,video_source_reservation_enabled=true",
        );
        const next = await candidate(parent, source, other, i),
          nextIdentity = await buildVideoSourceRecoveryRequest(next);
        assertEquals(await reserve(db, owner, next), {
          ...nextIdentity,
          owner_id: owner,
          state: "held",
          reason: "source_occupied",
        });
        assertEquals(await recover(db, other, identity), {
          ...identity,
          owner_id: other,
          state: "unavailable",
        });
        assertEquals(
          await recover(db, owner, {
            ...identity,
            fingerprint: "0".repeat(64),
          }),
          {
            ...identity,
            fingerprint: "0".repeat(64),
            owner_id: owner,
            state: "unavailable",
          },
        );
        await denied(db, () => reserve(db, owner, request, 11));
        await denied(db, () => recover(db, owner, identity, 11));
        await denied(
          db,
          () => reserve(db, owner, { ...request, fingerprint: "0".repeat(64) }),
        );
        await denied(
          db,
          () => recover(db, owner, { ...identity, operation_id: other }),
        );
        await denied(
          db,
          () =>
            call(db, "reserve_owned_observation_analysis_source", owner, {
              ...request,
              schema_version: 1,
            }, 11),
        );
        const changed = { ...request.input, request_digest: "c".repeat(64) };
        await denied(db, async () =>
          reserve(db, owner, {
            ...request,
            input: changed,
            fingerprint: await videoSourceFingerprint(changed),
          }));
        for (const role of ["anon", "authenticated"]) {
          await denied(db, async () => {
            await db.queryArray(`SET LOCAL ROLE ${role}`);
            await reserve(db, owner, request);
          });
          await denied(db, async () => {
            await db.queryArray(`SET LOCAL ROLE ${role}`);
            await recover(db, owner, identity);
          });
        }
        await db.queryArray("SET LOCAL ROLE service_role");
        assertEquals(await reserve(db, owner, request), receipt);
        assertEquals(await recover(db, owner, identity), receipt);
        await db.queryArray("RESET ROLE");
        for (const field of ["analysis_id", "request_digest"]) {
          const changedIdentity = {
            ...identity,
            [field]: field === "analysis_id" ? other : "d".repeat(64),
          };
          assertEquals(await recover(db, owner, changedIdentity), {
            ...changedIdentity,
            owner_id: owner,
            state: "unavailable",
          });
        }
        // A nonexistent source cannot be used as an owned saved analysis.
        await denied(
          db,
          () => recover(db, owner, { ...identity, source_analysis_id: other }),
        );
        for (
          const patch of [
            { observation_id: "not-a-uuid" },
            { analysis_id: 7 },
            { fingerprint: "bad" },
            { request_digest: "A".repeat(64) },
          ]
        ) {
          await denied(db, () => recover(db, owner, { ...identity, ...patch }));
        }
        // Privileged corruption fixture only; production cannot remove live occupancy.
        await db.queryArray(
          "ALTER TABLE internal.observation_analysis_source_occupancy DISABLE TRIGGER guard_observation_source_occupancy",
        );
        // Missing occupancy cannot turn retained V4 metadata into vacancy proof.
        await db.queryArray(
          "DELETE FROM internal.observation_analysis_source_occupancy WHERE analysis_id=$1",
          [child],
        );
        await db.queryArray(
          "ALTER TABLE internal.observation_analysis_source_occupancy ENABLE TRIGGER guard_observation_source_occupancy",
        );
        const held = {
          ...identity,
          owner_id: owner,
          state: "held",
          reason: "terminal_unproven",
        };
        assertEquals(await reserve(db, owner, request), held);
        assertEquals(await recover(db, owner, identity), held);
        assertEquals(
          (await reserve(db, owner, next)).reason,
          "terminal_unproven",
        );
        await db.queryArray("SELECT public.apply_user_tombstone($1)", [owner]);
        assertEquals(await reserve(db, owner, request), unavailable);
        assertEquals(await recover(db, owner, identity), unavailable);
      }
    } finally {
      await db.queryArray("ROLLBACK");
      await db.end();
    }
  },
});

for (
  const scenario of [
    "duplicate",
    "competing",
    "recovery",
    "delete-first",
    "reserve-first",
  ]
) {
  Deno.test({
    name: `video reservation concurrency - ${scenario}`,
    ignore: !url,
    async fn() {
      const first = await connect(), second = await connect();
      const [owner, parent, source, child, next] = Array.from(
        { length: 5 },
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
        const request = await candidate(parent, source, child),
          other = await candidate(parent, source, next);
        const identity = await buildVideoSourceRecoveryRequest(request);
        await first.queryArray("BEGIN");
        await second.queryArray("BEGIN");
        if (scenario === "delete-first") {
          await first.queryArray("SELECT public.apply_user_tombstone($1)", [
            owner,
          ]);
        } else await reserve(first, owner, request);
        const pid = (await second.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() pid",
        )).rows[0].pid;
        const pending = (scenario === "reserve-first"
          ? second.queryArray("SELECT public.apply_user_tombstone($1)", [owner])
          : scenario === "recovery"
          ? recover(second, owner, identity)
          : reserve(second, owner, scenario === "competing" ? other : request))
          .then(
            (value) => ({ value, error: undefined }),
            (error) => ({ value: undefined, error }),
          );
        let blocked = false;
        for (let n = 0; n < 100 && !blocked; n++) {
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
        assert(blocked, "actual canonical-lock blocking required");
        await first.queryArray("COMMIT");
        const settled = await pending;
        if (settled.error) {
          throw settled.error;
        }
        const result = settled.value;
        await second.queryArray("COMMIT");
        if (scenario !== "reserve-first") {
          assertEquals(
            (result as Record<string, unknown>).state,
            scenario === "delete-first"
              ? "unavailable"
              : scenario === "competing"
              ? "held"
              : "reserved",
          );
        }
        if (scenario === "reserve-first") {
          assertEquals(
            (await recover(first, owner, identity)).state,
            "unavailable",
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
  name: "video reservation bounds retained binding coverage at 64 versus 65",
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
      const request = await candidate(parent, source, child);
      for (let i = 0; i < 65; i++) {
        const predecessor = await candidate(
          parent,
          source,
          crypto.randomUUID(),
        );
        await db.queryArray(
          "INSERT INTO internal.observation_analysis_source_bindings(analysis_id,owner_id,observation_id,source_analysis_id,input_snapshot,fingerprint_version,fingerprint) VALUES($1,$2,$3,$4,$5::jsonb,1,$6)",
          [
            predecessor.input.analysis_id,
            owner,
            parent,
            source,
            JSON.stringify(predecessor.input),
            predecessor.fingerprint,
          ],
        );
        if (i === 63) {
          assertEquals(
            (await reserve(db, owner, request)).reason,
            "terminal_unproven",
          );
        }
      }
      assertEquals(
        (await reserve(db, owner, request)).reason,
        "coverage_incomplete",
      );
      // Prove the independent video-cohort cap, using another saved source so
      // the same-source binding sentinel cannot mask the cohort boundary.
      const alternateSource = crypto.randomUUID();
      await db.queryArray(
        "SELECT internal.append_observation_analysis($1,pg_temp.history_append_request($2,$3))",
        [owner, parent, alternateSource],
      );
      const alternate = await candidate(
        parent,
        alternateSource,
        crypto.randomUUID(),
      );
      const bindings = (await db.queryObject<{ analysis_id: string }>(
        "SELECT analysis_id FROM internal.observation_analysis_source_bindings WHERE observation_id=$1 ORDER BY analysis_id",
        [parent],
      )).rows;
      // Privileged fixture constructs retained cohorts without a live uploader.
      await db.queryArray(
        "ALTER TABLE internal.observation_video_evidence_upload_cohorts DISABLE TRIGGER guard_observation_video_cohort",
      );
      for (let i = 0; i < 65; i++) {
        await db.queryArray(
          "INSERT INTO internal.observation_video_evidence_upload_cohorts(analysis_id,owner_id,observation_id,source_analysis_id,items) SELECT analysis_id,owner_id,observation_id,source_analysis_id,internal.observation_video_source_cohort_items(input_snapshot) FROM internal.observation_analysis_source_bindings WHERE analysis_id=$1",
          [bindings[i].analysis_id],
        );
        if (i === 63) {
          await db.queryArray("SAVEPOINT boundary");
          assertEquals((await reserve(db, owner, alternate)).state, "reserved");
          await db.queryArray("ROLLBACK TO SAVEPOINT boundary");
        }
      }
      await db.queryArray(
        "ALTER TABLE internal.observation_video_evidence_upload_cohorts ENABLE TRIGGER guard_observation_video_cohort",
      );
      assertEquals(
        (await reserve(db, owner, alternate)).reason,
        "coverage_incomplete",
      );
    } finally {
      await db.queryArray("ROLLBACK");
      await db.end();
    }
  },
});
