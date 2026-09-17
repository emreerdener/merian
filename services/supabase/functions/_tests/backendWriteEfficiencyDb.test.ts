import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";

const databaseUrl = Deno.env.get("SUPABASE_DB_TEST_URL");

function disposableClient(): Client {
  assert(databaseUrl, "A disposable database is required");
  const target = new URL(databaseUrl);
  assert(
    ["127.0.0.1", "localhost", "[::1]"].includes(target.hostname),
    "Write benchmarks and concurrency fixtures require a loopback database",
  );
  return new Client(databaseUrl);
}

Deno.test({
  name:
    "lookalike write benchmark - historical and installed RPC preserve results with fewer updates",
  ignore: !databaseUrl,
  async fn() {
    const client = disposableClient();
    await client.connect();
    try {
      const historical = await Deno.readTextFile(
        new URL(
          "../../migrations/20260903163744_recover_species_lookalike_enrichment.sql",
          import.meta.url,
        ),
      );
      const start = historical.indexOf(
        "CREATE FUNCTION public.persist_species_model_lookalikes(",
      );
      const end = historical.indexOf("\n$$;", start);
      assert(start >= 0 && end > start);
      const baseline = historical.slice(start, end + 4).replace(
        "CREATE FUNCTION public.persist_species_model_lookalikes(",
        "CREATE FUNCTION pg_temp.baseline_lookalikes(",
      );
      const fixtureSource = await Deno.readTextFile(
        new URL("../../tests/lookalike_write_efficiency.sql", import.meta.url),
      );
      const fixture = fixtureSource.split("-- BEGIN SYNTHETIC FIXTURE\n")[1]
        ?.split("-- END SYNTHETIC FIXTURE")[0];
      assert(fixture, "Shared synthetic fixture must be present");
      for (const version of ["historical", "installed"] as const) {
        await client.queryArray("BEGIN");
        try {
          await client.queryArray("SET LOCAL statement_timeout = '30s'");
          await client.queryArray(fixture);
          await client.queryArray(baseline);
          const routine = version === "historical"
            ? "pg_temp.baseline_lookalikes"
            : "public.persist_species_model_lookalikes";
          const call =
            `SELECT * FROM ${routine}(pg_temp.io_species_id(1), jsonb_build_array(pg_temp.io_candidate(2)), TRUE)`;
          assertEquals((await client.queryArray(call)).rows, [[1, 0, 0]]);
          await client.queryArray("TRUNCATE pg_temp.io_row_updates");
          const started = performance.now();
          for (let replay = 0; replay < 50; replay++) {
            assertEquals((await client.queryArray(call)).rows, [[1, 0, 0]]);
          }
          const counts = (await client.queryArray<number[]>(`
            SELECT count(*) FILTER (WHERE relation_name = 'species_dictionary')::integer,
                   count(*) FILTER (WHERE relation_name = 'species_lookalikes')::integer,
                   count(*) FILTER (WHERE relation_name = 'species_content_provenance')::integer
            FROM pg_temp.io_row_updates
          `)).rows[0];
          assertEquals(
            counts,
            version === "historical" ? [100, 50, 50] : [0, 0, 50],
          );
          assertEquals(
            (await client.queryArray(`
            SELECT similar_species = ARRAY['Iofixture species2'], lookalikes_flash_attempted
            FROM public.species_dictionary WHERE id = pg_temp.io_species_id(1)
          `)).rows,
            [[true, true]],
          );
          // Synthetic counts only. Instrumentation and round trips are included;
          // elapsed time is diagnostic, not a production I/O savings estimate.
          console.info(JSON.stringify({
            benchmark: "lookalike-replay",
            version,
            replays: 50,
            dictionaryUpdates: counts[0],
            relationshipUpdates: counts[1],
            provenanceUpdates: counts[2],
            elapsedMs: Math.round(performance.now() - started),
          }));
        } finally {
          await client.queryArray("ROLLBACK");
        }
      }
    } finally {
      await client.end();
    }
  },
});

Deno.test({
  name:
    "lookalike reciprocal concurrency - serialized requests persist both directions",
  ignore: !databaseUrl,
  async fn() {
    const observer = disposableClient();
    const first = disposableClient();
    const second = disposableClient();
    const ids = [
      "00000000-0000-4000-8000-00000000fe01",
      "00000000-0000-4000-8000-00000000fe02",
    ];
    let seeded = false;
    let pending: Promise<unknown> | undefined;
    await observer.connect();
    try {
      await first.connect();
      await second.connect();
      assertEquals(
        (await observer.queryArray(
          "SELECT count(*)::integer FROM public.species_dictionary WHERE id = ANY($1::uuid[]) OR scientific_name LIKE 'Concurrentio species%'",
          [ids],
        )).rows,
        [[0]],
      );
      await observer.queryArray(
        `
        INSERT INTO public.species_dictionary (id, scientific_name, common_names, gbif_taxon_key, kingdom, "order", family, genus)
        SELECT value::uuid, 'Concurrentio species' || ordinal, '{}'::jsonb,
               950000 + ordinal::integer, 'Plantae', 'Rosales', 'Rosaceae', 'Concurrentio' || ordinal
        FROM unnest($1::text[]) WITH ORDINALITY AS fixture(value, ordinal)
      `,
        [ids],
      );
      seeded = true;
      const payload = (candidate: number) =>
        JSON.stringify([{
          scientific_name: `Concurrentio species${candidate}`,
          reason: "Synthetic reciprocal relation",
          visual_traits: ["leaf shape"],
          confidence: 0.9,
          gbif: {
            scientific_name: `Concurrentio species${candidate}`,
            gbif_taxon_key: 950000 + candidate,
            rank: "SPECIES",
            status: "ACCEPTED",
            kingdom: "Plantae",
            order: "Rosales",
            family: "Rosaceae",
            genus: `Concurrentio${candidate}`,
          },
        }]);
      for (const client of [first, second]) {
        await client.queryArray(
          "BEGIN; SET LOCAL statement_timeout = '20s'; SET LOCAL lock_timeout = '15s'",
        );
      }
      const firstPid =
        (await first.queryArray<number[]>("SELECT pg_backend_pid()"))
          .rows[0][0];
      const secondPid =
        (await second.queryArray<number[]>("SELECT pg_backend_pid()"))
          .rows[0][0];
      const call =
        "SELECT * FROM public.persist_species_model_lookalikes($1::uuid, $2::jsonb, TRUE)";
      assertEquals((await first.queryArray(call, [ids[0], payload(2)])).rows, [[
        1,
        0,
        0,
      ]]);
      const reciprocal = second.queryArray(call, [ids[1], payload(1)]);
      // Attach a rejection handler immediately while observing the lock.
      pending = reciprocal.then(() => undefined, () => undefined);
      let blocked = false;
      for (let attempt = 0; attempt < 100; attempt++) {
        blocked = (await observer.queryArray<boolean[]>(
          "SELECT $1::integer = ANY(pg_blocking_pids($2::integer))",
          [firstPid, secondPid],
        )).rows[0][0];
        if (blocked) break;
        await new Promise((resolve) => setTimeout(resolve, 25));
      }
      assert(
        blocked,
        "Reciprocal request must wait for the existing transaction lock",
      );
      await first.queryArray("COMMIT");
      assertEquals((await reciprocal).rows, [[1, 0, 0]]);
      await second.queryArray("COMMIT");
      assertEquals(
        (await observer.queryArray(
          `
        SELECT count(*)::integer FROM public.species_lookalikes
        WHERE species_id = ANY($1::uuid[]) AND lookalike_id = ANY($1::uuid[])
          AND review_status = 'unreviewed' AND source = 'model_enrichment'
      `,
          [ids],
        )).rows,
        [[2]],
      );
    } finally {
      await first.queryArray("ROLLBACK").catch(() => {});
      await pending;
      await second.queryArray("ROLLBACK").catch(() => {});
      if (seeded) {
        await observer.queryArray(
          "DELETE FROM public.species_dictionary WHERE id = ANY($1::uuid[])",
          [ids],
        );
      }
      await Promise.all([first.end(), second.end(), observer.end()]);
    }
  },
});
