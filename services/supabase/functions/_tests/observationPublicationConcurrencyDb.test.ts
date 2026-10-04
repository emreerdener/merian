import { assert, assertEquals, assertRejects } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";

const databaseUrl = Deno.env.get("SUPABASE_DB_TEST_URL");
for (
  const scenario of [
    "consensus owns public row before owner review",
    "owner review owns public row before consensus",
    "withdrawal before worker",
    "account deletion during consensus",
    "reference refresh blocks publication",
    "duplicate publication and deletion replay",
  ]
) {
  Deno.test({
    name: `Publication DB concurrency - ${scenario}`,
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
      const owner = crypto.randomUUID(),
        observation = crypto.randomUUID(),
        request = crypto.randomUUID(),
        post = crypto.randomUUID(),
        publication = crypto.randomUUID();
      const flags = [
        "reader_enabled",
        "enrollment_enabled",
        "saved_import_enabled",
        "state_reader_enabled",
        "selection_enabled",
        "selection_api_enabled",
        "community_authority_enabled",
        "publication_snapshot_enabled",
      ];
      let previous: Record<string, boolean> | undefined;
      let taxon: string | undefined;
      try {
        for (const client of clients) {
          await client.connect();
          await client.queryArray("SET statement_timeout='3s'");
          await client.queryArray(
            "SELECT set_config('request.jwt.claims','{\"role\":\"service_role\"}',false)",
          );
        }
        const fixture = await Deno.readTextFile(
          new URL(
            "../../tests/observation_publication_snapshots.sql",
            import.meta.url,
          ),
        );
        await observer.queryArray(
          fixture.split("-- BEGIN PUBLICATION HELPERS\n")[1].split(
            "-- END PUBLICATION HELPERS",
          )[0],
        );
        previous = (await observer.queryObject<Record<string, boolean>>(
          `SELECT ${
            flags.join(",")
          } FROM internal.observation_history_rollout WHERE singleton`,
        )).rows[0];
        await observer.queryArray(
          `UPDATE internal.observation_history_rollout SET ${
            flags.map((flag) => `${flag}=true`).join(",")
          }`,
        );
        const analysis = (await observer.queryObject<{ analysis: string }>(
          "SELECT pg_temp.seed_publication($1,$2,$3,$4,$5) AS analysis",
          [owner, observation, request, post, publication],
        )).rows[0].analysis;
        taxon = (await observer.queryObject<{ taxon: string }>(
          "SELECT resolved_taxon_node_id AS taxon FROM public.explore_community_requests WHERE id=$1",
          [request],
        )).rows[0].taxon;
        const withdraw = (client: Client) =>
          client.queryArray(
            "UPDATE public.explore_community_requests SET status='needs_id',resolved_at=NULL,resolved_taxon_node_id=NULL WHERE id=$1",
            [request],
          );
        // Clearing community authority represents a newer owner review generation;
        // no pending worker may republish the superseded community result.
        const review = (client: Client) =>
          client.queryArray(
            "UPDATE internal.observation_analysis_authorities SET review_revision=review_revision+1,review_snapshot=jsonb_set(jsonb_set(review_snapshot,'{ai_identification_review,community}','null'::jsonb),'{ai_identification_review,revision}',to_jsonb((review_snapshot#>>'{ai_identification_review,revision}')::int+1)) WHERE analysis_id=$1",
            [analysis],
          );
        const reconcile = (client: Client) =>
          client.queryObject<{ outcome: string }>(
            "SELECT internal.reconcile_observation_community_authority($1,$2) AS outcome",
            [owner, request],
          );
        const current = async () =>
          (await observer.queryObject<{ current: boolean }>(
            "SELECT identification IS NOT NULL AS current FROM public.explore_analysis_public_projection WHERE post_id=$1",
            [post],
          )).rows[0].current;
        await first.queryArray("BEGIN");
        await second.queryArray("BEGIN");
        if (scenario === "account deletion during consensus") {
          await withdraw(first);
          await assertRejects(
            () =>
              second.queryArray("SELECT public.apply_user_tombstone($1)", [
                owner,
              ]),
            Error,
            "analysis_history_unavailable",
          );
          await second.queryArray("ROLLBACK");
          await first.queryArray("COMMIT");
          await observer.queryArray("SELECT public.apply_user_tombstone($1)", [
            owner,
          ]);
          assertEquals(
            (await observer.queryObject<{ count: number }>(
              "SELECT count(*)::int AS count FROM public.explore_analysis_public_projection WHERE post_id=$1",
              [post],
            )).rows[0].count,
            0,
          );
        } else if (scenario === "reference refresh blocks publication") {
          // The lock must be acquired before registration creates its receipt,
          // without waiting while that operation owns history and post locks.
          await first.queryArray(
            "SELECT pg_advisory_xact_lock(hashtextextended('merian-analysis-publication-references',0::bigint))",
          );
          const secondOwner = crypto.randomUUID(),
            secondObservation = crypto.randomUUID(),
            secondRequest = crypto.randomUUID(),
            secondPost = crypto.randomUUID(),
            secondPublication = crypto.randomUUID();
          await second.queryArray(
            fixture.split("-- BEGIN PUBLICATION HELPERS\n")[1].split(
              "-- END PUBLICATION HELPERS",
            )[0],
          );
          await assertRejects(
            () =>
              second.queryArray(
                "SELECT pg_temp.seed_publication($1,$2,$3,$4,$5)",
                [
                  secondOwner,
                  secondObservation,
                  secondRequest,
                  secondPost,
                  secondPublication,
                ],
              ),
            Error,
            "analysis_history_unavailable",
          );
          await second.queryArray("ROLLBACK");
          await first.queryArray("COMMIT");
          assertEquals(
            (await observer.queryObject<{ count: number }>(
              "SELECT count(*)::int AS count FROM internal.observation_analysis_publications WHERE publication_id=$1",
              [secondPublication],
            )).rows[0].count,
            0,
          );
        } else if (
          scenario === "consensus owns public row before owner review"
        ) {
          await withdraw(first);
          await assertRejects(
            () => review(second),
            Error,
            "analysis_history_unavailable",
          );
          await second.queryArray("ROLLBACK");
          await first.queryArray("COMMIT");
          assertEquals(await current(), false);
          await review(observer);
          assertEquals(
            (await reconcile(observer)).rows[0].outcome,
            "superseded",
          );
        } else if (
          scenario === "owner review owns public row before consensus"
        ) {
          await review(first);
          await assertRejects(
            () => withdraw(second),
            Error,
            "analysis_history_unavailable",
          );
          await second.queryArray("ROLLBACK");
          await first.queryArray("COMMIT");
          await withdraw(observer);
          assertEquals(
            (await reconcile(observer)).rows[0].outcome,
            "superseded",
          );
          assertEquals(await current(), false);
        } else if (scenario === "withdrawal before worker") {
          await withdraw(first);
          assertEquals((await reconcile(second)).rows[0].outcome, "pending");
          await second.queryArray("COMMIT");
          await first.queryArray("COMMIT");
          assertEquals(await current(), false);
          assertEquals((await reconcile(observer)).rows[0].outcome, "applied");
          assertEquals((await reconcile(observer)).rows[0].outcome, "current");
          assertEquals(await current(), false);
        } else {
          const retry = (client: Client) =>
            client.queryArray(
              "SELECT internal.register_observation_publication(owner_id,request_id,publication_id,observation_revision,review_revision,media_manifest) FROM internal.observation_analysis_publications WHERE publication_id=$1",
              [publication],
            );
          await retry(first);
          const pending = retry(second);
          await first.queryArray("COMMIT");
          await pending;
          await second.queryArray("COMMIT");
          assertEquals(
            (await observer.queryObject<{ count: number }>(
              "SELECT count(*)::int AS count FROM internal.observation_analysis_publications WHERE post_id=$1",
              [post],
            )).rows[0].count,
            1,
          );
          const saved = (await observer.queryObject<
            { revision: number; review: number; media: unknown }
          >(
            "SELECT observation_revision AS revision,review_revision AS review,media_manifest AS media FROM internal.observation_analysis_publications WHERE publication_id=$1",
            [publication],
          )).rows[0];
          await observer.queryArray("SELECT public.apply_user_tombstone($1)", [
            owner,
          ]);
          await assertRejects(
            () =>
              observer.queryArray(
                "SELECT internal.register_observation_publication($1,$2,$3,$4,$5,$6::jsonb)",
                [
                  owner,
                  request,
                  publication,
                  saved.revision,
                  saved.review,
                  JSON.stringify(saved.media),
                ],
              ),
            Error,
            "analysis_history_not_found",
          );
        }
      } finally {
        for (const client of [first, second]) {
          await client.queryArray("ROLLBACK").catch(() => {});
        }
        if (previous) {
          await observer.queryArray(
            `UPDATE internal.observation_history_rollout SET ${
              flags.map((flag, i) => `${flag}=$${i + 1}`).join(",")
            }`,
            flags.map((flag) => previous![flag]),
          );
        }
        await observer.queryArray("SELECT public.apply_user_tombstone($1)", [
          owner,
        ]).catch(() => {});
        await observer.queryArray("DELETE FROM auth.users WHERE id=$1", [owner])
          .catch(() => {});
        if (taxon) {
          await observer.queryArray(
            "DELETE FROM public.taxon_nodes WHERE id=$1",
            [taxon],
          ).catch(() => {});
        }
        for (const client of clients) await client.end().catch(() => {});
      }
    },
  });
}
