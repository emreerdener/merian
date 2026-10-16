import { assert, assertEquals, assertRejects } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import vectors from "../_shared/analysisHistory/fixtures/video-source-fingerprint-v1.json" with {
  type: "json",
};
import { preparedVideoCohortItems } from "../_shared/analysisHistory/videoCohort.ts";
const url = Deno.env.get("SUPABASE_DB_TEST_URL");
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
function input(parent: string, source: string, child: string, i = 0) {
  return {
    ...structuredClone(vectors[i].input),
    observation_id: parent,
    source_analysis_id: source,
    analysis_id: child,
  };
}
async function bind(
  db: Client,
  owner: string,
  value: ReturnType<typeof input>,
  occupy = true,
) {
  await db.queryArray(
    "INSERT INTO internal.observation_analysis_source_bindings VALUES($1,$2,$3,$4,$5::jsonb,1,internal.observation_video_source_fingerprint($5::jsonb))",
    [
      value.analysis_id,
      owner,
      value.observation_id,
      value.source_analysis_id,
      JSON.stringify(value),
    ],
  );
  if (occupy) {
    await db.queryArray(
      "INSERT INTO internal.observation_analysis_source_occupancy VALUES($1,$2,$3,$4)",
      [
        owner,
        value.observation_id,
        value.source_analysis_id,
        value.analysis_id,
      ],
    );
  }
}
const insert = (
  db: Client,
  owner: string,
  value: ReturnType<typeof input>,
  items: unknown = preparedVideoCohortItems(value),
) =>
  db.queryArray(
    "INSERT INTO internal.observation_video_evidence_upload_cohorts VALUES($1,$2,$3,$4,$5::jsonb)",
    [
      value.analysis_id,
      owner,
      value.observation_id,
      value.source_analysis_id,
      JSON.stringify(items),
    ],
  );
async function seed(db: Client, owner: string, parent: string, source: string) {
  await db.queryArray("SELECT pg_temp.seed_history_append($1,$2)", [
    owner,
    parent,
  ]);
  await db.queryArray(
    "UPDATE internal.observation_history_rollout SET append_enabled=true,source_discovery_enabled=true,source_reservation_enabled=true,source_unfunded_retirement_enabled=true",
  );
  await db.queryArray(
    "SELECT internal.append_observation_analysis($1,pg_temp.history_append_request($2,$3))",
    [owner, parent, source],
  );
}
Deno.test({
  name:
    "held video storage validates complete binding, inventory, coverage and deletion",
  ignore: !url,
  async fn() {
    assert(
      url &&
        ["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname),
    );
    const db = new Client(url);
    await db.connect();
    await db.queryArray("BEGIN");
    try {
      await fixture(db);
      const [owner, parent, source, child, other] = Array.from(
        { length: 5 },
        () => crypto.randomUUID(),
      );
      await seed(db, owner, parent, source);
      const value = input(parent, source, child);
      await bind(db, owner, value);
      const reject = async (action: () => Promise<unknown>) => {
        await db.queryArray("SAVEPOINT denied");
        await assertRejects(action);
        await db.queryArray("ROLLBACK TO SAVEPOINT denied");
      };
      const items = preparedVideoCohortItems(value);
      for (
        const bad of [[], items.slice(1), [...items].reverse(), [
          ...items,
          items[0],
        ], items.map((x, i) => i === 0 ? { ...x, sha256: "0".repeat(64) } : x)]
      ) await reject(() => insert(db, owner, value, bad));
      await reject(() => insert(db, other, value));
      await reject(() =>
        insert(db, owner, { ...value, source_analysis_id: other })
      );
      await reject(() => insert(db, owner, { ...value, analysis_id: other }));
      await reject(() =>
        db.queryArray(
          "SELECT internal.lock_owned_observation_source_binding($1,$2,$3,$4::jsonb)",
          [owner, parent, child, JSON.stringify(value)],
        )
      );
      await reject(() =>
        db.queryArray(
          "SELECT internal.assert_observation_source_input_chain($1,$2,$3,$4::jsonb)",
          [owner, parent, child, JSON.stringify(value)],
        )
      );
      const unoccupied = input(parent, source, crypto.randomUUID());
      await bind(db, owner, unoccupied, false);
      await reject(() => insert(db, owner, unoccupied));
      const forged = input(parent, source, crypto.randomUUID());
      await reject(() =>
        db.queryArray(
          "INSERT INTO internal.observation_analysis_source_bindings VALUES($1,$2,$3,$4,$5::jsonb,1,$6)",
          [
            forged.analysis_id,
            owner,
            parent,
            source,
            JSON.stringify(forged),
            "0".repeat(64),
          ],
        )
      );
      await reject(() =>
        insert(db, owner, { ...value, observation_id: other })
      );
      await insert(db, owner, value);
      assertEquals(
        (await db.queryObject<{ unused: boolean }>(
          "SELECT internal.observation_source_child_is_unused($1) unused",
          [child],
        )).rows[0].unused,
        false,
      );
      const discovery =
        (await db.queryObject<{ value: { state: string; reason: string } }>(
          "SELECT public.get_owned_observation_analysis_source($1,$2::jsonb,10) value",
          [
            owner,
            JSON.stringify({
              schema_version: 1,
              observation_id: parent,
              source_analysis_id: source,
            }),
          ],
        )).rows[0].value;
      assertEquals(discovery.state, "held");
      assertEquals(discovery.reason, "coverage_incomplete");
      await reject(() =>
        db.queryArray(
          "UPDATE internal.observation_video_evidence_upload_cohorts SET items=items WHERE analysis_id=$1",
          [child],
        )
      );
      await reject(() =>
        db.queryArray(
          "DELETE FROM internal.observation_video_evidence_upload_cohorts WHERE analysis_id=$1",
          [child],
        )
      );
      await reject(() =>
        db.queryArray(
          "DELETE FROM internal.observation_analysis_source_occupancy WHERE analysis_id=$1",
          [child],
        )
      );
      await reject(() =>
        db.queryArray(
          "INSERT INTO internal.observation_evidence_upload_cohorts(analysis_id,observation_id,owner_id,items) VALUES($1,$2,$3,$4::jsonb)",
          [
            child,
            parent,
            owner,
            JSON.stringify([{
              media_id: crypto.randomUUID(),
              content_type: "image/jpeg",
              byte_count: 46,
              sha256: "b".repeat(64),
            }]),
          ],
        )
      );
      await reject(() =>
        db.queryArray(
          "SELECT public.reserve_owned_observation_analysis_source($1,jsonb_build_object('schema_version',1,'input',$2::jsonb,'fingerprint_version',1,'fingerprint',internal.observation_video_source_fingerprint($2::jsonb)),11)",
          [owner, JSON.stringify(value)],
        )
      );
      await reject(() =>
        db.queryArray(
          "INSERT INTO internal.observation_audio_evidence_upload_cohorts(analysis_id,observation_id,owner_id,media_id,content_type,byte_count,sha256) VALUES($1,$2,$3,$4,'audio/wav',46,$5)",
          [child, parent, owner, crypto.randomUUID(), "b".repeat(64)],
        )
      );
      for (const role of ["anon", "authenticated", "service_role"]) {
        await reject(async () => {
          await db.queryArray(`SET LOCAL ROLE ${role}`);
          await db.queryArray(
            "SELECT * FROM internal.observation_video_evidence_upload_cohorts",
          );
        });
      }
      // Complete silent and Unicode vectors use the same guarded persistence path.
      for (const i of [1, 2]) {
        const s = crypto.randomUUID(), c = crypto.randomUUID();
        await db.queryArray(
          "SELECT internal.append_observation_analysis($1,pg_temp.history_append_request($2,$3))",
          [owner, parent, s],
        );
        const v = input(parent, s, c, i);
        await bind(db, owner, v);
        await insert(db, owner, v);
      }
      assertEquals(
        (await db.queryObject<{ n: string }>(
          "SELECT count(*)::text n FROM internal.observation_evidence_objects WHERE observation_id=$1",
          [parent],
        )).rows[0].n,
        "0",
      );
      // Each independently growing namespace needs its own 65th-row sentinel.
      for (let i = 3; i < 65; i++) {
        const s = crypto.randomUUID(), c = crypto.randomUUID();
        await db.queryArray(
          "SELECT internal.append_observation_analysis($1,pg_temp.history_append_request($2,$3))",
          [owner, parent, s],
        );
        const v = input(parent, s, c);
        await bind(db, owner, v);
        await insert(db, owner, v);
      }
      const coverage =
        (await db.queryObject<{ value: { state: string; reason: string } }>(
          "SELECT public.reserve_owned_observation_analysis_source($1,jsonb_build_object('schema_version',1,'input',p,'fingerprint_version',1,'fingerprint',internal.observation_source_fingerprint(p)),11) value FROM (SELECT pg_temp.admission_input($2,$3,$4,$5,2) p) q",
          [owner, parent, source, crypto.randomUUID(), crypto.randomUUID()],
        )).rows[0].value;
      assertEquals(coverage.state, "held");
      assertEquals(coverage.reason, "coverage_incomplete");
      const capped =
        (await db.queryObject<{ value: { state: string; reason: string } }>(
          "SELECT public.get_owned_observation_analysis_source($1,$2::jsonb,10) value",
          [
            owner,
            JSON.stringify({
              schema_version: 1,
              observation_id: parent,
              source_analysis_id: source,
            }),
          ],
        )).rows[0].value;
      assertEquals(capped.state, "held");
      assertEquals(capped.reason, "coverage_incomplete");
      await db.queryArray(
        "INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES($1,$2)",
        [parent, owner],
      );
      assertEquals(
        (await db.queryObject<{ n: string }>(
          "SELECT count(*)::text n FROM internal.observation_video_evidence_upload_cohorts WHERE observation_id=$1",
          [parent],
        )).rows[0].n,
        "0",
      );
    } finally {
      await db.queryArray("ROLLBACK");
      await db.end();
    }
  },
});
for (
  const scenario of [
    "video-delete",
    "delete-video",
    "video-legacy",
    "video-retire",
  ]
) {
  Deno.test({
    name: `held video storage locks ${scenario}`,
    ignore: !url,
    async fn() {
      assert(
        url &&
          ["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname),
      );
      const first = new Client(url), second = new Client(url);
      const [owner, parent, source, child] = Array.from(
        { length: 4 },
        () => crypto.randomUUID(),
      );
      let rollout: Record<string, boolean> | undefined;
      try {
        await first.connect();
        await second.connect();
        await fixture(first);
        await fixture(second);
        const columns = [
          "append_enabled",
          "source_discovery_enabled",
          "source_reservation_enabled",
          "source_unfunded_retirement_enabled",
        ];
        rollout = (await first.queryObject<Record<string, boolean>>(
          `SELECT ${
            columns.join(",")
          } FROM internal.observation_history_rollout WHERE singleton`,
        )).rows[0];
        await seed(first, owner, parent, source);
        const value = input(parent, source, child);
        await bind(first, owner, value);
        const erase = (c: Client) =>
          c.queryArray(
            "INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES($1,$2)",
            [parent, owner],
          );
        const pid = (await second.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() pid",
        )).rows[0].pid;
        await first.queryArray("BEGIN");
        await second.queryArray("BEGIN");
        await second.queryArray("SET LOCAL statement_timeout='10s'");
        if (scenario === "delete-video") await erase(first);
        else await insert(first, owner, value);
        const pending = (scenario === "video-delete"
          ? erase(second)
          : scenario === "delete-video"
          ? insert(second, owner, value)
          : scenario === "video-legacy"
          ? second.queryArray(
            "SELECT public.reserve_owned_observation_evidence_cohort($1,$2,$3,$4::jsonb)",
            [
              owner,
              parent,
              child,
              JSON.stringify([{
                media_id: crypto.randomUUID(),
                content_type: "image/jpeg",
                byte_count: 46,
                sha256: "b".repeat(64),
              }]),
            ],
          )
          : second.queryArray(
            "SELECT public.retire_owned_observation_analysis_source($1,internal.observation_source_identity(b)||jsonb_build_object('operation_id',$2::uuid),11) FROM internal.observation_analysis_source_bindings b WHERE analysis_id=$3",
            [owner, crypto.randomUUID(), child],
          )).then(() =>
            false, () => true);
        let blocked = false;
        for (let n = 0; n < 100 && !blocked; n++) {
          blocked = (await first.queryObject<{ blocked: boolean }>(
            "SELECT cardinality(pg_blocking_pids($1))>0 blocked",
            [pid],
          )).rows[0].blocked;
          if (!blocked) await new Promise((r) => setTimeout(r, 5));
        }
        assert(blocked, "second writer must actually wait on canonical locks");
        await first.queryArray("COMMIT");
        const denied = await pending;
        assertEquals(denied, scenario !== "video-delete");
        await second.queryArray(denied ? "ROLLBACK" : "COMMIT");
        if (scenario === "video-legacy" || scenario === "video-retire") {
          assertEquals(
            (await first.queryObject<{ n: string }>(
              "SELECT count(*)::text n FROM internal.observation_analysis_source_occupancy WHERE analysis_id=$1",
              [child],
            )).rows[0].n,
            "1",
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
        if (rollout) {
          const entries = Object.entries(rollout);
          await first.queryArray(
            `UPDATE internal.observation_history_rollout SET ${
              entries.map(([k], i) => `${k}=$${i + 1}`).join(",")
            }`,
            entries.map(([, v]) => v),
          );
        }
        await first.end();
        await second.end();
      }
    },
  });
}
