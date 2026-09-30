import { assert, assertEquals, assertRejects } from "@std/assert";
import { PostgresError } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import { effectiveIdentification } from "../_shared/identify/effectiveIdentity.ts";
import {
  primaryProvenanceFixture,
  savedIdentityFixture,
} from "./primaryIdentityTestHelpers.ts";
import {
  insertExplorePost,
  insertSpecies,
  insertUser,
  withExploreDbTest,
} from "./exploreDbTestHelpers.ts";

Deno.test("SQL and Edge identity agree for explicit, pending, malformed and legacy rows", async () => {
  await withExploreDbTest("primary-identity-policy", async (db) => {
    await db.queryArray("SET LOCAL ROLE service_role");
    const rows = [
      savedIdentityFixture(),
      savedIdentityFixture("species"),
      savedIdentityFixture("family"),
      savedIdentityFixture("unresolved_biological"),
      savedIdentityFixture("non_biological"),
      { ...savedIdentityFixture(), primary_identification: null },
      { ...savedIdentityFixture(), confirmed_species_identity: {} },
      {
        ...savedIdentityFixture(),
        user_review_state: "ai_confirmed",
        user_confirmed_identification: true,
      },
      {
        ...savedIdentityFixture("species"),
        user_review_state: "user_overridden",
        user_identification_override: "Pending",
      },
      { species_id: "00000000-0000-0000-0000-00000000ef01" },
    ];
    for (const row of rows) {
      const result = await db.queryObject<{ value: unknown }>(
        "SELECT internal.scan_effective_identification(jsonb_populate_record(NULL::public.scans,$1::jsonb)) AS value",
        [JSON.stringify(row)],
      );
      assertEquals(result.rows[0].value, effectiveIdentification(row));
    }
  });
});

Deno.test("broader public observations keep labels; selection and clear update all species consumers", async () => {
  await withExploreDbTest("primary-public-consumers", async (db) => {
    const owner = crypto.randomUUID(),
      scan = crypto.randomUUID(),
      post = crypto.randomUUID();
    await insertUser(db, owner, "Primary fixture");
    await db.queryArray(
      `SELECT set_config('request.headers','{"x-merian-identification-protocol":"5"}',TRUE)`,
    );
    await db.queryArray(
      `INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,terminal_reason_code)
      VALUES ($1,$2,'failed_terminal','server_replay_limit_reached','replay_exhausted')`,
      [scan, owner],
    );
    await db.queryArray(
      `INSERT INTO public.scan_ingestion_intents(scan_id,user_id,endpoint,request_payload)
       VALUES ($1,$2,'identify-multimodal','{}'::jsonb)`,
      [scan, owner],
    );
    await db.queryArray(
      `INSERT INTO public.scans(id,user_id,image_storage_urls,ai_confidence_score,is_biological_subject,
      inference_tier,geoprivacy,identification_provenance,primary_identification)
      VALUES ($1,$2,ARRAY['https://images.example.invalid/fixture.webp'],0.75,TRUE,'flash','private',$3::jsonb,$4::jsonb)`,
      [
        scan,
        owner,
        JSON.stringify(primaryProvenanceFixture),
        JSON.stringify(savedIdentityFixture().primary_identification),
      ],
    );
    await insertExplorePost(db, {
      id: post,
      userId: owner,
      scanId: scan,
      locationSharing: "private",
    });
    await db.queryArray("SET LOCAL ROLE service_role");
    const card = async () => {
      const query = () =>
        db.queryObject<{
          species_scientific_name: string;
          identification: {
            rank: string;
            label_source: string;
            original_rank: string;
          };
        }>(
          "SELECT species_scientific_name,identification FROM public.get_explore_post($1,$2)",
          [owner, post],
        );
      const service = (await query()).rows[0];
      await db.queryArray("RESET ROLE");
      await db.queryArray("SELECT set_config('request.jwt.claims',$1,TRUE)", [
        JSON.stringify({ sub: owner, role: "authenticated" }),
      ]);
      await db.queryArray("SET LOCAL ROLE authenticated");
      assertEquals((await query()).rows[0], service);
      await db.queryArray("RESET ROLE");
      await db.queryArray("SELECT set_config('request.jwt.claims','{}',TRUE)");
      await db.queryArray("SET LOCAL ROLE service_role");
      return service;
    };
    let result = await card();
    assertEquals([
      result.species_scientific_name,
      result.identification.rank,
      result.identification.label_source,
    ], ["Fixtureus", "genus", "ai_primary"]);
    const detail = async () =>
      (await db.queryObject<
        {
          species_dictionary_id: string | null;
          reference_image_url: string | null;
        }
      >(
        "SELECT species_dictionary_id,reference_image_url FROM public.get_explore_post_detail($1,$2)",
        [owner, post],
      )).rows[0];
    assertEquals((await detail()).species_dictionary_id, null);
    const page = await db.queryObject<
      { post_payload: { identification: { rank: string } } }
    >("SELECT post_payload FROM public.get_public_web_explore_post_page($1)", [
      post,
    ]);
    assertEquals(page.rows[0].post_payload.identification.rank, "genus");
    const proof = {
      scientific_name: "Fixtureus accepted",
      gbif_taxon_key: 987600121,
      rank: "SPECIES",
      status: "ACCEPTED",
      kingdom: "Plantae",
    };
    const confirm = await db.queryObject<
      { result: { review: { identity: { species_id: string } } } }
    >(
      "SELECT public.apply_verified_scan_species_review($1,$2,0,'confirm_name','Fixtureus accepted',$3::jsonb) AS result",
      [owner, scan, JSON.stringify(proof)],
    );
    const selectedID = confirm.rows[0].result.review.identity.species_id;
    result = await card();
    assertEquals([
      result.species_scientific_name,
      result.identification.rank,
      result.identification.label_source,
      result.identification.original_rank,
    ], ["Fixtureus accepted", "species", "verified_selection", "genus"]);
    assertEquals((await detail()).species_dictionary_id, selectedID);
    await db.queryArray("RESET ROLE");
    const evidence = await db.queryObject<
      { eligible: boolean; revision: string }
    >(
      `SELECT public.field_trip_scan_evidence_is_eligible(scans) AS eligible,
      receipt.scan_revision ->> 'confirmed_species_identity_revision' AS revision FROM public.scans scans
      JOIN public.field_trip_scan_progress_receipts receipt ON receipt.scan_id=scans.id WHERE scans.id=$1`,
      [scan],
    );
    assert(evidence.rows[0].eligible);
    assertEquals(evidence.rows[0].revision, "1");
    await db.queryArray("SET LOCAL ROLE service_role");
    await db.queryArray(
      "SELECT public.apply_verified_scan_species_review($1,$2,1,'clear',NULL,NULL)",
      [owner, scan],
    );
    result = await card();
    assertEquals([
      result.identification.rank,
      result.identification.label_source,
    ], ["genus", "ai_primary"]);
    assertEquals((await detail()).species_dictionary_id, null);
    await db.queryArray("RESET ROLE");
    const snapshot = await db.queryObject<
      {
        payload: {
          effective_species_id: string | null;
          identification: { rank: string };
        };
      }
    >(
      "SELECT occurrence_payload AS payload FROM internal.dwca_export_snapshot_source WHERE scan_id=$1",
      [scan],
    );
    assertEquals(snapshot.rows[0].payload.effective_species_id, null);
    assertEquals(snapshot.rows[0].payload.identification.rank, "genus");
    const cleared = await db.queryObject<
      { eligible: boolean; revision: string }
    >(
      `SELECT public.field_trip_scan_evidence_is_eligible(scans) AS eligible,
      receipt.scan_revision ->> 'confirmed_species_identity_revision' AS revision FROM public.scans scans
      JOIN public.field_trip_scan_progress_receipts receipt ON receipt.scan_id=scans.id WHERE scans.id=$1`,
      [scan],
    );
    assertEquals(cleared.rows[0], { eligible: false, revision: "2" });
  });
});

Deno.test("public identity cards preserve caller access, exclusions and community identity boundaries", async () => {
  await withExploreDbTest("primary-public-roles", async (db) => {
    const owner = crypto.randomUUID(), viewer = crypto.randomUUID();
    const species = crypto.randomUUID(),
      confirmed = crypto.randomUUID(),
      unknown = crypto.randomUUID();
    await insertUser(db, owner, "Primary role owner");
    await insertUser(db, viewer, "Primary role viewer");
    await db.queryArray(
      `SELECT set_config('request.headers','{"x-merian-identification-protocol":"5"}',TRUE)`,
    );
    await insertSpecies(db, species, "Fixtureus original");
    await insertSpecies(db, confirmed, "Fixtureus reviewed");
    await insertSpecies(db, unknown, "Unknown Subject");
    const fixtures: {
      post: string;
      scan: string;
      expectedRank: string | null;
      expectedName: string;
      visible: boolean;
    }[] = [];
    for (
      const kind of [
        "species",
        "genus",
        "family",
        "unresolved_biological",
        "legacy",
        "private",
        "human",
        "sentinel",
      ]
    ) {
      const scan = crypto.randomUUID(), post = crypto.randomUUID();
      const legacy = kind === "legacy" || kind === "sentinel";
      const primary = legacy ? null : kind === "human"
        ? {
          version: 1,
          resolution: "species",
          scientific_name: "Homo sapiens",
          common_name: null,
        }
        : savedIdentityFixture(kind === "private" ? "genus" : kind)
          .primary_identification;
      if (primary !== null) {
        await db.queryArray(
          `INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,terminal_reason_code)
          VALUES($1,$2,'failed_terminal','server_replay_limit_reached','replay_exhausted')`,
          [scan, owner],
        );
        await db.queryArray(
          `INSERT INTO public.scan_ingestion_intents(scan_id,user_id,endpoint,request_payload)
          VALUES($1,$2,'identify-multimodal','{}'::jsonb)`,
          [scan, owner],
        );
      }
      await db.queryArray(
        `INSERT INTO public.scans(id,user_id,species_id,confirmed_species_id,image_storage_urls,
        ai_confidence_score,is_biological_subject,inference_tier,geoprivacy,identification_provenance,primary_identification)
        VALUES($1,$2,$3,$4,ARRAY['https://images.example.invalid/role-fixture.webp'],0.75,TRUE,'flash',$5,$6::jsonb,$7::jsonb)`,
        [
          scan,
          owner,
          kind === "sentinel"
            ? unknown
            : kind === "legacy" || kind === "species"
            ? species
            : null,
          kind === "legacy" ? confirmed : null,
          kind === "private" ? "private" : "open",
          primary === null ? null : JSON.stringify(primaryProvenanceFixture),
          primary === null ? null : JSON.stringify(primary),
        ],
      );
      await insertExplorePost(db, { id: post, userId: owner, scanId: scan });
      fixtures.push({
        post,
        scan,
        expectedRank: legacy ? null : kind === "private" ? "genus" : kind,
        expectedName: kind === "legacy"
          ? "Fixtureus reviewed"
          : kind === "unresolved_biological"
          ? ""
          : "Fixtureus",
        visible: kind !== "human" && kind !== "sentinel",
      });
    }
    const read = (post: string, identity: string | null) =>
      db.queryObject<{
        species_scientific_name: string;
        identification: { rank: string; label_source: string } | null;
      }>(
        "SELECT species_scientific_name,identification FROM public.get_explore_post($1,$2)",
        [identity, post],
      );
    // PUBLIC execute never granted anonymous table access. Public web uses the
    // existing service projection, and the public invoker must preserve this ACL.
    await db.queryArray("SAVEPOINT anonymous_projection");
    await db.queryArray("SELECT set_config('request.jwt.claims','{}',TRUE)");
    await db.queryArray("SET LOCAL ROLE anon");
    const denied = await assertRejects(
      () => read(fixtures[0].post, null),
      PostgresError,
      "permission denied for table explore_posts",
    );
    assertEquals(denied.fields.code, "42501");
    await db.queryArray("ROLLBACK TO SAVEPOINT anonymous_projection");
    for (const role of ["service_role", "authenticated"] as const) {
      await db.queryArray("SELECT set_config('request.jwt.claims',$1,TRUE)", [
        JSON.stringify(
          role === "authenticated" ? { sub: owner, role } : { role },
        ),
      ]);
      await db.queryArray(`SET LOCAL ROLE ${role}`);
      for (const fixture of fixtures) {
        const rows = (await read(fixture.post, owner)).rows;
        assertEquals(rows.length, fixture.visible ? 1 : 0);
        if (fixture.visible) {
          assertEquals(rows[0].species_scientific_name, fixture.expectedName);
          assertEquals(
            rows[0].identification?.rank ?? null,
            fixture.expectedRank,
          );
        }
      }
      await db.queryArray("RESET ROLE");
    }
    // Authenticated table policies remain owner-only, including public posts.
    await db.queryArray("SELECT set_config('request.jwt.claims',$1,TRUE)", [
      JSON.stringify({ sub: viewer, role: "authenticated" }),
    ]);
    await db.queryArray("SET LOCAL ROLE authenticated");
    for (const fixture of fixtures) {
      assertEquals((await read(fixture.post, viewer)).rows.length, 0);
    }
    await db.queryArray("RESET ROLE");
    await db.queryArray("SELECT set_config('request.jwt.claims','{}',TRUE)");
    const target = fixtures[0];
    const request = crypto.randomUUID();
    for (
      const [index, rank, linkedSpecies] of [[0, "species", species], [
        1,
        "species",
        confirmed,
      ], [2, "genus", null]] as const
    ) {
      const taxon = crypto.randomUUID();
      await db.queryArray(
        `INSERT INTO public.taxon_nodes(id,taxonomy_version_id,path,rank,scientific_name,common_name,species_id)
        VALUES($1,public.active_taxonomy_version_id(),$2::ltree,$3,'Fixtureus community','Community fixture',$4)`,
        [
          taxon,
          `primary_fixture_${taxon.replaceAll("-", "_")}`,
          rank,
          linkedSpecies,
        ],
      );
      if (index === 0) {
        await db.queryArray(
          `INSERT INTO public.explore_community_requests(id,post_id,scan_id,requested_by,status,
          resolved_taxon_node_id,resolved_observation_taxon_node_id,resolved_at,explore_published_at)
          VALUES($1,$2,$3,$4,'resolved',$5,$5,now(),now())`,
          [request, target.post, target.scan, owner, taxon],
        );
      } else {
        await db.queryArray(
          `UPDATE public.explore_community_requests SET resolved_taxon_node_id=$2,
          resolved_observation_taxon_node_id=$2 WHERE id=$1`,
          [request, taxon],
        );
      }
      await db.queryArray(
        `INSERT INTO public.explore_observation_projection(post_id,scan_id,projection_state,
        community_request_id,public_taxon_node_id,resolved_taxon_node_id)
        VALUES($1,$2,'community_resolved',$3,$4,$4) ON CONFLICT(post_id) DO UPDATE
        SET projection_state=EXCLUDED.projection_state,community_request_id=EXCLUDED.community_request_id,
          public_taxon_node_id=EXCLUDED.public_taxon_node_id,resolved_taxon_node_id=EXCLUDED.resolved_taxon_node_id`,
        [
          target.post,
          target.scan,
          request,
          taxon,
        ],
      );
      await db.queryArray("SET LOCAL ROLE service_role");
      const result = (await read(target.post, viewer)).rows[0];
      assertEquals(result.species_scientific_name, "Fixtureus community");
      assertEquals([
        result.identification?.rank,
        result.identification?.label_source,
      ], [rank, "community"]);
      const detail = await db.queryObject<
        { species_dictionary_id: string | null }
      >(
        "SELECT species_dictionary_id FROM public.get_explore_post_detail($1,$2)",
        [viewer, target.post],
      );
      assertEquals(
        detail.rows[0].species_dictionary_id,
        index === 0 ? species : null,
      );
      const policy = await db.queryObject<{ labels: unknown }>(
        "SELECT internal.explore_identification_labels(scans,$1) AS labels FROM public.scans scans WHERE id=$2",
        [target.post, target.scan],
      );
      assertEquals(result.identification, policy.rows[0].labels);
      await db.queryArray("RESET ROLE");
    }
    await db.queryArray(
      "INSERT INTO public.user_blocks(blocker_id,blocked_id) VALUES($1,$2)",
      [viewer, owner],
    );
    await db.queryArray("SET LOCAL ROLE service_role");
    assertEquals((await read(target.post, viewer)).rows.length, 0);
    await db.queryArray("RESET ROLE");
    await db.queryArray(
      "DELETE FROM public.user_blocks WHERE blocker_id=$1 AND blocked_id=$2",
      [viewer, owner],
    );
    await db.queryArray(
      "UPDATE public.explore_posts SET unshared_at=now() WHERE id=$1",
      [target.post],
    );
    await db.queryArray("SET LOCAL ROLE service_role");
    assertEquals((await read(target.post, viewer)).rows.length, 0);
  });
});
