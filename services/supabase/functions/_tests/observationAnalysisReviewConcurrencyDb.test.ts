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
    (error: unknown) => ({
      ok: false as const,
      error: error instanceof Error ? error.message : "unknown",
    }),
  );
for (
  const scenario of [
    "community first",
    "enrollment before community",
    "duplicate",
    "competing rejection",
    "selection first",
    "rejection first",
    "deletion first",
    "account deletion first",
    "enrollment before legacy commit",
  ]
) {
  Deno.test({
    name: `Analysis rejection DB concurrency - ${scenario}`,
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
        "rejection_api_enabled",
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
        if (
          scenario !== "enrollment before legacy commit" &&
          !scenario.includes("community")
        ) {
          await observer.queryArray(
            "SELECT public.enroll_owned_observation_history($1,9)",
            [observation],
          );
        }
        const analysis = (await observer.queryObject<{ id: string }>(
          "SELECT selected_analysis_id AS id FROM internal.observation_histories WHERE observation_id=$1",
          [observation],
        )).rows[0]?.id ?? crypto.randomUUID();
        const species = crypto.randomUUID(), node = crypto.randomUUID();
        const mediaURL =
          `https://media.merian.app/public_uploads/free/${owner}/${observation}.webp`;
        if (scenario.includes("community")) {
          await observer.queryArray(
            "INSERT INTO public.species_dictionary(id,scientific_name,common_names) VALUES($1,$2,'{}')",
            [species, `Fixture ${species}`],
          );
          await observer.queryArray(
            "UPDATE public.scans SET species_id=$1,image_storage_urls=ARRAY[$2::text] WHERE id=$3",
            [species, mediaURL, observation],
          );
          await observer.queryArray(
            "INSERT INTO public.taxon_nodes(id,path,rank,scientific_name,species_id,taxonomy_version_id) VALUES($1,$2::public.ltree,'species',$3,$4,public.active_taxonomy_version_id())",
            [
              node,
              `fixture_${node.replaceAll("-", "")}`,
              `Fixture ${species}`,
              species,
            ],
          );
        }
        const request = {
          schema_version: 1,
          observation_id: observation,
          analysis_id: analysis,
          operation_id: crypto.randomUUID(),
          expected_observation_revision: 1,
          expected_review_revision: 0,
          action: "reject",
          undo_operation_id: null,
        };
        for (const client of [first, second]) {
          await client.queryArray("BEGIN");
          await client.queryArray("SET LOCAL statement_timeout='10s'");
          await client.queryArray(
            "SELECT set_config('request.jwt.claims',$1,TRUE)",
            [JSON.stringify({
              sub: owner,
              role: (scenario === "enrollment before legacy commit" ||
                  scenario.includes("community"))
                ? "service_role"
                : "authenticated",
            })],
          );
        }
        const blocker = (await first.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() AS pid",
        )).rows[0].pid;
        const waiter = (await second.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() AS pid",
        )).rows[0].pid;
        const reject = (client: Client, operation = request.operation_id) =>
          client.queryObject<{ receipt: Record<string, unknown> }>(
            "SELECT public.review_owned_observation_analysis($1::jsonb,9) AS receipt",
            [JSON.stringify({ ...request, operation_id: operation })],
          );
        const select = (client: Client) =>
          client.queryObject<{ receipt: Record<string, unknown> }>(
            "SELECT public.select_owned_observation_analysis($1::jsonb,9) AS receipt",
            [JSON.stringify({
              schema_version: 1,
              observation_id: observation,
              analysis_id: analysis,
              operation_id: crypto.randomUUID(),
              expected_observation_revision: 1,
              expected_review_revision: 0,
            })],
          );
        if (scenario.includes("community")) {
          const create = (client: Client) =>
            client.queryArray(
              "SELECT public.request_community_identification_atomically($1,$2,NULL,NULL,NULL,$3::jsonb,$4,public.active_taxonomy_version_id())",
              [
                observation,
                owner,
                JSON.stringify([{
                  kind: "image",
                  url: mediaURL,
                  thumbnail_url: mediaURL,
                  order_index: 0,
                  duration_seconds: null,
                  has_audio: false,
                }]),
                node,
              ],
            );
          const enroll = (client: Client) =>
            client.queryArray(
              "SELECT public.enroll_owned_observation_history($1,9)",
              [observation],
            );
          if (scenario === "community first") {
            await create(first);
            const pending = settled(enroll(second));
            await blocked(observer, waiter, blocker);
            await first.queryArray("COMMIT");
            assert((await pending).ok);
            await second.queryArray("COMMIT");
          } else {
            await enroll(first);
            const pending = settled(create(second));
            await blocked(observer, waiter, blocker);
            await first.queryArray("COMMIT");
            const refused = await pending;
            assert(!refused.ok);
            assertEquals(refused.error, "analysis_bound_review_required");
            await second.queryArray("ROLLBACK");
          }
          assertEquals(
            (await observer.queryObject<{ count: number }>(
              "SELECT count(*)::int AS count FROM public.explore_community_requests WHERE scan_id=$1",
              [observation],
            )).rows[0].count,
            scenario === "community first" ? 1 : 0,
          );
        } else if (
          [
            "duplicate",
            "competing rejection",
            "selection first",
            "rejection first",
          ].includes(scenario)
        ) {
          const before = (await (scenario === "selection first"
            ? select(first)
            : reject(first))).rows[0].receipt;
          const pending = settled(
            scenario === "rejection first" ? select(second) : reject(
              second,
              scenario === "duplicate"
                ? request.operation_id
                : crypto.randomUUID(),
            ),
          );
          await blocked(observer, waiter, blocker);
          await first.queryArray("COMMIT");
          const after = await pending;
          assert(after.ok);
          await second.queryArray("COMMIT");
          if (scenario === "duplicate") {
            assertEquals(after.value.rows[0].receipt, before);
          } else {assertEquals(
              after.value.rows[0].receipt.outcome,
              "revision_conflict",
            );}
          assertEquals(
            (await observer.queryObject<{ revision: number }>(
              "SELECT state_revision AS revision FROM internal.observation_histories WHERE observation_id=$1",
              [observation],
            )).rows[0].revision,
            2,
          );
          assertEquals(
            (await observer.queryObject<{ count: number }>(
              "SELECT count(*)::int AS count FROM internal.observation_history_reconciliation WHERE observation_id=$1",
              [observation],
            )).rows[0].count,
            1,
          );
        } else {
          if (scenario === "account deletion first") {
            await first.queryArray("SELECT public.apply_user_tombstone($1)", [
              owner,
            ]);
          } else if (scenario === "enrollment before legacy commit") {
            await first.queryArray(
              "SELECT public.enroll_owned_observation_history($1,9)",
              [observation],
            );
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
          const pending = settled(
            scenario === "enrollment before legacy commit"
              ? second.queryObject<{ receipt: Record<string, unknown> }>(
                "SELECT public.apply_verified_scan_species_review($1,$2,0,'clear',NULL,NULL) AS receipt",
                [owner, observation],
              )
              : reject(second),
          );
          await blocked(observer, waiter, blocker);
          await first.queryArray("COMMIT");
          const refused = await pending;
          assert(!refused.ok);
          assertEquals(
            refused.error,
            scenario === "enrollment before legacy commit"
              ? "analysis_bound_review_required"
              : "analysis_history_not_found",
          );
          await second.queryArray("ROLLBACK");
          assertEquals(
            (await observer.queryObject<{ count: number }>(
              "SELECT count(*)::int AS count FROM internal.observation_review_receipts WHERE observation_id=$1",
              [observation],
            )).rows[0].count,
            0,
          );
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
