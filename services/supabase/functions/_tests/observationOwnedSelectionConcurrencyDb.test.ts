import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
const databaseUrl = Deno.env.get("SUPABASE_DB_TEST_URL");
async function blocked(observer: Client, waiter: number, blocker: number) {
  for (let n = 0; n < 100; n++) {
    if (
      (await observer.queryObject<{ blocked: boolean }>(
        "SELECT $1::int=ANY(pg_blocking_pids($2::int)) AS blocked",
        [blocker, waiter],
      )).rows[0].blocked
    ) return;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error("Expected selection owner lock not observed");
}
const settled = <T>(promise: Promise<T>) =>
  promise.then(
    (value) => ({ ok: true as const, value }),
    () => ({ ok: false as const }),
  );
for (
  const scenario of [
    "duplicate",
    "competing choices",
    "review first",
    "selection first",
    "deletion first",
    "account deletion first",
  ]
) {
  Deno.test({
    name: `Owned selection DB concurrency - ${scenario}`,
    ignore: !databaseUrl,
    async fn() {
      assert(databaseUrl);
      assert(
        ["localhost", "127.0.0.1", "[::1]"].includes(
          new URL(databaseUrl).hostname,
        ),
      );
      const clients = [
        new Client(databaseUrl),
        new Client(databaseUrl),
        new Client(databaseUrl),
      ];
      const [observer, first, second] = clients;
      const owner = crypto.randomUUID(), observation = crypto.randomUUID();
      const flags = [
        "reader_enabled",
        "enrollment_enabled",
        "saved_import_enabled",
        "state_reader_enabled",
        "selection_enabled",
        "selection_api_enabled",
      ];
      let previous: Record<string, boolean> | undefined;
      try {
        for (const client of clients) await client.connect();
        const source = await Deno.readTextFile(
          new URL(
            "../../tests/observation_saved_enrollment.sql",
            import.meta.url,
          ),
        );
        await observer.queryArray(
          source.split("-- BEGIN SAVED ENROLLMENT HELPERS\n")[1].split(
            "-- END SAVED ENROLLMENT HELPERS",
          )[0],
        );
        await observer.queryArray(
          "SELECT pg_temp.seed_saved_observation($1,$2)",
          [owner, observation],
        );
        previous = (await observer.queryObject<Record<string, boolean>>(
          `SELECT ${
            flags.join(",")
          } FROM internal.observation_history_rollout WHERE singleton`,
        )).rows[0];
        await observer.queryArray(
          `UPDATE internal.observation_history_rollout SET ${
            flags.map((flag) => `${flag}=TRUE`).join(",")
          }`,
        );
        await observer.queryArray(
          "SELECT set_config('request.jwt.claims',$1,FALSE)",
          [JSON.stringify({ sub: owner, role: "authenticated" })],
        );
        await observer.queryArray(
          "SELECT public.enroll_owned_observation_history($1,9)",
          [observation],
        );
        const analysis = (await observer.queryObject<{ id: string }>(
          "SELECT selected_analysis_id AS id FROM internal.observation_histories WHERE observation_id=$1",
          [observation],
        )).rows[0].id;
        const targets = scenario === "competing choices"
          ? [crypto.randomUUID(), crypto.randomUUID()]
          : [analysis, analysis];
        if (scenario === "competing choices") {
          for (const [index, target] of targets.entries()) {
            await observer.queryArray(
              "INSERT INTO internal.observation_analysis_results(analysis_id,observation_id,ordinal,request_digest,completed_at,result_snapshot,evidence_manifest) VALUES($1,$2,$3,repeat('a',64),now(),$4::jsonb,$5::jsonb)",
              [
                target,
                observation,
                index + 2,
                JSON.stringify({
                  scan_id: observation,
                  scientific_name: `Fixture species${index}`,
                  common_name: `Fixture ${index}`,
                  confidence_score: 0.87,
                  is_biological_subject: true,
                  inference_tier: "flash",
                  ai_reasoning: "Synthetic identification fixture.",
                  colors: [],
                  extracted_visual_traits: [],
                  candidates: null,
                  pet_identification: null,
                  estimated_size_cm: null,
                  blur_score: 0.2,
                  is_live_capture: true,
                  image_quality: {
                    diagnostic_utility: 9,
                    framing: 7,
                    overall_score: 82,
                    sharpness: 8,
                  },
                }),
                JSON.stringify({
                  schema_version: 1,
                  captured_media: [{
                    description: {
                      _0: { freeText: "Synthetic observation fixture." },
                    },
                  }],
                }),
              ],
            );
            await observer.queryArray(
              "INSERT INTO internal.observation_analysis_authorities(observation_id,analysis_id,review_snapshot) SELECT observation_id,$1,review_snapshot FROM internal.observation_analysis_authorities WHERE analysis_id=$2",
              [target, analysis],
            );
          }
        }
        const request = {
          schema_version: 1,
          observation_id: observation,
          analysis_id: targets[0],
          operation_id: crypto.randomUUID(),
          expected_observation_revision: 1,
          expected_review_revision: 0,
        };
        for (const client of [first, second]) {
          await client.queryArray("BEGIN");
          await client.queryArray("SET LOCAL statement_timeout='10s'");
          await client.queryArray(
            "SELECT set_config('request.jwt.claims',$1,TRUE)",
            [JSON.stringify({ sub: owner, role: "authenticated" })],
          );
        }
        const blocker = (await first.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() AS pid",
        )).rows[0].pid;
        const waiter = (await second.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() AS pid",
        )).rows[0].pid;
        const select = (
          client: Client,
          operation = request.operation_id,
          target = targets[0],
        ) =>
          client.queryObject<{ receipt: Record<string, unknown> }>(
            "SELECT public.select_owned_observation_analysis($1::jsonb,9) AS receipt",
            [JSON.stringify({
              ...request,
              operation_id: operation,
              analysis_id: target,
            })],
          );
        const review = (client: Client) =>
          client.queryArray(
            'UPDATE internal.observation_analysis_authorities SET review_revision=1,review_snapshot=review_snapshot||\'{"user_identification_override":"Changed fixture","user_review_state":"user_overridden"}\' WHERE observation_id=$1',
            [observation],
          );
        if (
          scenario === "duplicate" || scenario === "competing choices" ||
          scenario === "selection first"
        ) {
          const before = (await select(first)).rows[0].receipt;
          const pending = settled(
            scenario === "selection first"
              ? review(second).then(() => ({
                rows: [{ receipt: {} as Record<string, unknown> }],
              }))
              : select(
                second,
                scenario === "duplicate"
                  ? request.operation_id
                  : crypto.randomUUID(),
                scenario === "duplicate" ? targets[0] : targets[1],
              ),
          );
          await blocked(observer, waiter, blocker);
          await first.queryArray("COMMIT");
          const after = await pending;
          assert(after.ok);
          await second.queryArray("COMMIT");
          if (scenario !== "selection first") {
            const receipt =
              (after.value.rows[0] as { receipt: Record<string, unknown> })
                .receipt;
            if (scenario === "duplicate") assertEquals(receipt, before);
            else assertEquals(receipt.outcome, "revision_conflict");
          }
          const current =
            (await observer.queryObject<{ selected: string; revision: number }>(
              "SELECT selected_analysis_id AS selected,state_revision AS revision FROM internal.observation_histories WHERE observation_id=$1",
              [observation],
            )).rows[0];
          assertEquals(current.selected, targets[0]);
          assertEquals(
            current.revision,
            scenario === "selection first" ? 3 : 2,
          );
          assertEquals(before.previous_analysis_id, analysis);
          assertEquals(
            (await observer.queryObject<{ count: number }>(
              "SELECT count(*)::int AS count FROM internal.observation_selection_receipts WHERE observation_id=$1",
              [observation],
            )).rows[0].count,
            scenario === "competing choices" ? 2 : 1,
          );
        } else {
          if (scenario === "review first") await review(first);
          else if (scenario === "account deletion first") {
            await first.queryArray("SELECT public.apply_user_tombstone($1)", [
              owner,
            ]);
          } else {
            await first.queryArray(
              "SELECT id FROM public.users WHERE id=$1 FOR UPDATE",
              [owner],
            );
            await first.queryArray(
              "INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES($1,$2)",
              [observation, owner],
            );
          }
          const pending = settled(select(second));
          await blocked(observer, waiter, blocker);
          await first.queryArray("COMMIT");
          const after = await pending;
          if (scenario === "review first") {
            assert(after.ok);
            assertEquals(
              after.value.rows[0].receipt.outcome,
              "revision_conflict",
            );
            await second.queryArray("COMMIT");
          } else {
            assertEquals(after.ok, false);
            await second.queryArray("ROLLBACK");
            assertEquals(
              (await observer.queryObject<{ count: number }>(
                "SELECT count(*)::int AS count FROM internal.observation_selection_receipts WHERE observation_id=$1",
                [observation],
              )).rows[0].count,
              0,
            );
          }
        }
      } finally {
        for (const client of [first, second]) {
          await client.queryArray("ROLLBACK").catch(() => {});
        }
        if (previous) {
          await observer.queryArray(
            `UPDATE internal.observation_history_rollout SET ${
              flags.map((flag, index) => `${flag}=$${index + 1}`).join(",")
            }`,
            flags.map((flag) => previous![flag]),
          );
        }
        await observer.queryArray("SELECT public.apply_user_tombstone($1)", [
          owner,
        ]).catch(() => {});
        await observer.queryArray("DELETE FROM auth.users WHERE id=$1", [owner])
          .catch(() => {});
        for (const client of clients) await client.end().catch(() => {});
      }
    },
  });
}
