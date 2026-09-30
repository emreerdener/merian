import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";

const databaseUrl = Deno.env.get("SUPABASE_DB_TEST_URL");
for (const conflict of [false, true]) {
  Deno.test({
    name: `concurrent verified review ${
      conflict ? "rejects a different selection" : "collapses an exact retry"
    }`,
    ignore: !databaseUrl,
    async fn() {
      assert(databaseUrl);
      assert(
        ["127.0.0.1", "localhost", "[::1]"].includes(
          new URL(databaseUrl).hostname,
        ),
        "Requires disposable loopback database",
      );
      const clients = [
        new Client(databaseUrl),
        new Client(databaseUrl),
        new Client(databaseUrl),
      ];
      const [first, second, observer] = clients;
      await Promise.all(clients.map((client) => client.connect()));
      const owner = crypto.randomUUID(), scan = crypto.randomUUID();
      const name = `Reviewrace fixture${scan.replaceAll("-", "")}`;
      const proof = {
        scientific_name: name,
        gbif_taxon_key: 987600010,
        rank: "SPECIES",
        status: "ACCEPTED",
        kingdom: "Plantae",
      };
      const provenance = {
        version: 2,
        provider: "openai",
        binding: "openai_photo_v1",
        model: "gpt-6-sol",
        variant: "multimodal",
        operation: "scan_identification",
        policy_version: 2,
        prompt: "synthetic_primary_fixture_v1",
        schema: "merian_identify_primary_v1",
        confidence: "openai_unqualified_v1",
        diagnostic_trigger: null,
        prompt_diagnostic_trigger: null,
        safety: "openai_photo_moderation_v1",
        timeout_ms: 90000,
        generation: {
          max_output_tokens: 8192,
          reasoning_effort: "low",
          image_detail: "high",
        },
      };
      let pending: Promise<unknown> | undefined;
      try {
        await observer.queryArray(
          "INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES($1,'authenticated','authenticated',$2,'{}','{}',NOW(),NOW())",
          [owner, `${owner}@example.invalid`],
        );
        await observer.queryArray(
          "INSERT INTO public.scan_ingestion_jobs(scan_id,user_id) VALUES($1,$2)",
          [scan, owner],
        );
        await observer.queryArray(
          `INSERT INTO public.scans(id,user_id,image_storage_urls,ai_confidence_score,is_biological_subject,inference_tier,geoprivacy,identification_provenance,primary_identification)
        VALUES($1,$2,'{}',0.75,TRUE,'flash','private',$3::jsonb,$4::jsonb)`,
          [
            scan,
            owner,
            JSON.stringify(provenance),
            JSON.stringify({
              version: 1,
              resolution: "genus",
              scientific_name: "Reviewrace",
              common_name: null,
            }),
          ],
        );
        for (const client of [first, second]) {
          await client.queryArray(
            "BEGIN; SET LOCAL statement_timeout='15s'; SET LOCAL lock_timeout='10s'; SET LOCAL ROLE service_role",
          );
        }
        const firstPID =
          (await first.queryArray<number[]>("SELECT pg_backend_pid()"))
            .rows[0][0];
        const secondPID =
          (await second.queryArray<number[]>("SELECT pg_backend_pid()"))
            .rows[0][0];
        const call =
          "SELECT public.apply_verified_scan_species_review($1::uuid,$2::uuid,0,'confirm_name',$3,$4::jsonb)";
        const initial = await first.queryArray(call, [
          owner,
          scan,
          name,
          JSON.stringify(proof),
        ]);
        const competingProof = conflict
          ? {
            ...proof,
            scientific_name: `${name}other`,
            gbif_taxon_key: 987600011,
          }
          : proof;
        const concurrent = second.queryArray(call, [
          owner,
          scan,
          competingProof.scientific_name,
          JSON.stringify(competingProof),
        ]).then(
          (result) => ({ result, error: null }),
          (error) => ({ result: null, error }),
        );
        pending = concurrent;
        let blocked = false;
        for (let attempt = 0; attempt < 100; attempt++) {
          blocked = (await observer.queryArray<boolean[]>(
            "SELECT $1::integer=ANY(pg_blocking_pids($2::integer))",
            [firstPID, secondPID],
          )).rows[0][0];
          if (blocked) break;
          await new Promise((resolve) => setTimeout(resolve, 25));
        }
        assert(blocked, "Second review must wait on the scan generation lock");
        await first.queryArray("COMMIT");
        const other = await concurrent;
        if (conflict) {
          assert(other.error instanceof Error);
          assertEquals(other.error.message, "species_review_revision_conflict");
          await second.queryArray("ROLLBACK");
          assertEquals(
            (await observer.queryArray(
              "SELECT id FROM public.species_dictionary WHERE gbif_taxon_key=987600011",
            )).rows,
            [],
          );
        } else {
          assertEquals(other.error, null);
          assertEquals(other.result?.rows, initial.rows);
          await second.queryArray("COMMIT");
        }
        assertEquals(
          (await observer.queryArray(
            `SELECT s.confirmed_species_identity_revision, s.confirmed_species_identity->>'scientific_name',
        internal.scan_species_review_snapshot(s)=j.confirmed_species_review
        FROM public.scans s JOIN public.scan_ingestion_jobs j ON j.scan_id=s.id::text AND j.user_id=s.user_id WHERE s.id=$1`,
            [scan],
          )).rows,
          [[1, name, true]],
        );
      } finally {
        await first.queryArray("ROLLBACK");
        await pending;
        await second.queryArray("ROLLBACK");
        await observer.queryArray("DELETE FROM public.scans WHERE id=$1", [
          scan,
        ]);
        await observer.queryArray("DELETE FROM public.users WHERE id=$1", [
          owner,
        ]);
        await observer.queryArray("DELETE FROM auth.users WHERE id=$1", [
          owner,
        ]);
        await observer.queryArray(
          "DELETE FROM internal.scan_deletion_tombstones WHERE scan_id=$1",
          [scan],
        );
        await observer.queryArray(
          "DELETE FROM public.species_dictionary WHERE scientific_name=ANY($1::text[])",
          [[name, `${name}other`]],
        );
        await Promise.all(clients.map((client) => client.end()));
      }
    },
  });
}
