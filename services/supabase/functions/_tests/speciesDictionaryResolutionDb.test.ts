import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";

const databaseUrl = Deno.env.get("SUPABASE_DB_TEST_URL");
for (const reuseLegacy of [false, true]) {
  Deno.test({
    name: `concurrent dictionary resolution reuses one ${
      reuseLegacy ? "legacy" : "new"
    } canonical identity`,
    ignore: !databaseUrl,
    async fn() {
      assert(databaseUrl);
      assert(
        ["127.0.0.1", "localhost", "[::1]"].includes(
          new URL(databaseUrl).hostname,
        ),
        "Requires a disposable loopback database",
      );
      const clients = [
        new Client(databaseUrl),
        new Client(databaseUrl),
        new Client(databaseUrl),
      ];
      const [first, second, observer] = clients;
      await Promise.all(clients.map((client) => client.connect()));
      const name = `Resolutionrace fixture${
        crypto.randomUUID().replaceAll("-", "")
      }`;
      const proof = JSON.stringify({
        scientific_name: name,
        gbif_taxon_key: 987000009,
        rank: "SPECIES",
        status: "ACCEPTED",
        kingdom: "Plantae",
      });
      let pending: Promise<unknown> | undefined;
      try {
        let legacyID: string | undefined;
        if (reuseLegacy) {
          await observer.queryArray(
            "BEGIN; SET LOCAL merian.lookalike_candidate_materialization = 'on'",
          );
          legacyID = (await observer.queryArray<string[]>(
            `INSERT INTO public.species_dictionary
           (scientific_name, common_names, kingdom, phylum, class, "order", family, genus, native_region)
           VALUES ($1, '{}'::jsonb, 'Plantae', 'Tracheophyta', 'Magnoliopsida', 'Rosales', 'Rosaceae', 'Resolutionrace', 'Unknown') RETURNING id`,
            [name],
          )).rows[0][0];
          await observer.queryArray("COMMIT");
        }
        for (const client of [first, second]) {
          await client.queryArray(
            "BEGIN; SET LOCAL statement_timeout = '15s'; SET LOCAL lock_timeout = '10s'; SET LOCAL ROLE service_role",
          );
        }
        const firstPID =
          (await first.queryArray<number[]>("SELECT pg_backend_pid()"))
            .rows[0][0];
        const secondPID =
          (await second.queryArray<number[]>("SELECT pg_backend_pid()"))
            .rows[0][0];
        const call =
          "SELECT public.resolve_verified_dictionary_species($1::jsonb)";
        const initial = await first.queryArray<string[]>(call, [proof]);
        if (legacyID) assertEquals(initial.rows, [[legacyID]]);
        const concurrent = second.queryArray<string[]>(call, [
          JSON.stringify({
            ...JSON.parse(proof),
            scientific_name: `${name}accepted`,
          }),
        ]);
        pending = concurrent.then(() => undefined, () => undefined);
        let blocked = false;
        for (let attempt = 0; attempt < 100; attempt++) {
          blocked = (await observer.queryArray<boolean[]>(
            "SELECT $1::integer = ANY(pg_blocking_pids($2::integer))",
            [firstPID, secondPID],
          )).rows[0][0];
          if (blocked) break;
          await new Promise((resolve) => setTimeout(resolve, 25));
        }
        assert(
          blocked,
          "The duplicate insert must await the first transaction",
        );
        await first.queryArray("COMMIT");
        assertEquals((await concurrent).rows, initial.rows);
        await second.queryArray("COMMIT");
        assertEquals(
          (await observer.queryArray<number[]>(
            "SELECT count(*)::integer FROM public.species_dictionary WHERE gbif_taxon_key = 987000009",
          )).rows,
          [[1]],
        );
      } finally {
        await first.queryArray("ROLLBACK");
        await pending;
        await second.queryArray("ROLLBACK");
        await observer.queryArray("ROLLBACK");
        await observer.queryArray(
          "DELETE FROM public.species_dictionary WHERE scientific_name = ANY($1::text[])",
          [[name, `${name}accepted`]],
        );
        await Promise.all(clients.map((client) => client.end()));
      }
    },
  });
}
