import { assert, assertEquals } from "@std/assert";
import type { AIRequest } from "../_shared/ai/contracts.ts";
import {
  insertExplorePost,
  insertScan,
  insertSpecies,
  insertUser,
  withExploreDbTest,
} from "./exploreDbTestHelpers.ts";
import {
  geminiMetricProvenance,
  metricAudio,
  metricCapture,
  metricImage,
  recordedMetricProvenance,
  unqualifiedMetricProvenance,
} from "./identificationMetricsTestFixtures.ts";

Deno.test("metric interpretation accepts actual registered executions and rejects altered or malformed profiles", async () => {
  await withExploreDbTest("identificationMetricsProfiles", async (client) => {
    const multi = (
      evidence: Extract<AIRequest, { variant: "multimodal" }>["evidence"],
      video = false,
    ): AIRequest => ({
      task: "identify",
      variant: "multimodal",
      evidence,
      capture: video
        ? {
          hasVideo: true,
          videoClipCount: 1,
          declaredVideoFrameCount: 5,
          videoInferenceFrameCount: 5,
        }
        : metricCapture,
    });
    const requests: AIRequest[] = [
      {
        task: "identify",
        variant: "description_compat",
        evidence: [{
          kind: "text",
          source: "description",
          text: "Synthetic observation",
          order: 0,
        }],
      },
      { task: "identify", variant: "vision_compat", evidence: [metricImage] },
      { task: "identify", variant: "audio_compat", evidence: [metricAudio] },
      multi([{
        kind: "text",
        source: "observation_context",
        text: "Synthetic observation",
        order: 0,
      }]),
      multi([metricImage]),
      multi([metricAudio]),
      multi([metricImage, { ...metricAudio, order: 1 }]),
      multi([metricImage], true),
      multi([metricImage, { ...metricAudio, order: 1 }], true),
    ];
    await client.queryArray("SET LOCAL ROLE service_role");
    async function compatible(
      value: unknown,
      tier: string | null,
      sqlNull = false,
    ) {
      const result = await client.queryObject<{ compatible: boolean }>(
        "SELECT internal.identification_metrics_are_gemini_compatible($1::JSONB, $2) AS compatible",
        [sqlNull ? null : JSON.stringify(value), tier],
      );
      return result.rows[0].compatible;
    }
    for (const pro of [false, true]) {
      for (const request of requests) {
        assertEquals(
          await compatible(
            recordedMetricProvenance(request, pro),
            pro ? "pro" : "flash",
          ),
          true,
        );
      }
    }
    const audioB = recordedMetricProvenance(
      multi([metricAudio, {
        kind: "text",
        source: "capture_context",
        text: "Synthetic capture context",
        order: 1,
      }]),
      true,
      "B",
    );
    assertEquals(await compatible(audioB, "pro"), true);
    assertEquals(await compatible(audioB, "flash"), false);
    for (const tier of ["flash", "pro", "future-tier", null]) {
      assertEquals(await compatible(null, tier, true), true);
    }
    const original = geminiMetricProvenance();
    const bad: unknown[] = [
      null,
      [],
      {},
      "malformed",
      unqualifiedMetricProvenance(),
      { ...original, unexpected: true },
    ];
    for (const [key, value] of Object.entries(original)) {
      const changed = {
        ...original,
        [key]: typeof value === "string"
          ? "unknown_profile"
          : value === null
          ? 0
          : null,
      };
      bad.push(changed);
      const missing: Record<string, unknown> = { ...original };
      delete missing[key];
      bad.push(missing);
    }
    for (const key of Object.keys(original.generation)) {
      bad.push({
        ...original,
        generation: { ...original.generation, [key]: -1 },
      });
    }
    bad.push({ ...original, policy_version: 2 }, { ...original, version: 2 }, {
      ...original,
      generation: { ...original.generation, extra: 1 },
    });
    for (const value of bad) {
      assertEquals(await compatible(value, "flash"), false);
    }
    assertEquals(await compatible(original, "pro"), false);
    assertEquals(await compatible(original, null), false);
    assertEquals(await compatible(original, "future-tier"), false);
    await client.queryArray("RESET ROLE");
  });
});

Deno.test("community projection removes unsupported scores, retains candidate order and rejects direct client callers", async () => {
  await withExploreDbTest("identificationMetricsCommunity", async (client) => {
    const owner = crypto.randomUUID(), viewer = crypto.randomUUID();
    await insertUser(client, owner, "Metric Owner");
    await insertUser(client, viewer, "Metric Viewer");
    const species = [
      crypto.randomUUID(),
      crypto.randomUUID(),
      crypto.randomUUID(),
    ];
    const names = [
      "Rosa metricinitialis",
      "Rosa metricprima",
      "Rosa metricsecunda",
    ];
    for (let i = 0; i < species.length; i++) {
      await insertSpecies(client, species[i], names[i]);
    }
    const taxonomy = await client.queryObject<{ id: string }>(
      "SELECT id FROM public.refresh_taxonomy_nodes_from_species_dictionary('synthetic-metric-profile', TRUE)",
    );
    const version = taxonomy.rows[0].id;
    const initial = await client.queryObject<{ id: string }>(
      "SELECT id FROM public.taxon_nodes WHERE taxonomy_version_id = $1 AND species_id = $2",
      [version, species[0]],
    );
    for (const known of [true, false]) {
      const scan = crypto.randomUUID(),
        post = crypto.randomUUID(),
        request = crypto.randomUUID();
      await insertScan(client, {
        id: scan,
        userId: owner,
        speciesId: species[0],
        latitude: 0,
        longitude: 0,
        geoprivacy: "private",
        aiConfidenceScore: 0.999,
        identificationProvenance: known
          ? geminiMetricProvenance()
          : unqualifiedMetricProvenance(),
        candidates: [{ scientific_name: names[1], confidence_score: 0.10 }, {
          scientific_name: names[2],
          confidence_score: 0.98,
        }],
      });
      await insertExplorePost(client, {
        id: post,
        userId: owner,
        scanId: scan,
      });
      await client.queryArray(
        "INSERT INTO public.explore_community_requests (id, post_id, scan_id, requested_by, taxonomy_version_id, initial_taxon_node_id) VALUES ($1,$2,$3,$4,$5,$6)",
        [request, post, scan, owner, version, initial.rows[0].id],
      );
      await client.queryArray("SET LOCAL ROLE service_role");
      const detail = await client.queryObject<
        {
          ai_confidence_qualified: boolean;
          suggested_taxa: {
            scientific_name: string;
            confidence_score: number | null;
          }[];
        }
      >("SELECT * FROM public.get_community_identification_detail($1,$2)", [
        viewer,
        request,
      ]);
      assertEquals(detail.rows.length, 1);
      assertEquals(detail.rows[0].ai_confidence_qualified, known);
      assertEquals(
        detail.rows[0].suggested_taxa.map((v) => v.scientific_name),
        known ? [names[0], names[2], names[1]] : names,
      );
      assertEquals(
        detail.rows[0].suggested_taxa.map((v) => v.confidence_score),
        known ? [0.999, 0.98, 0.10] : [null, null, null],
      );
      assert(!("identification_provenance" in detail.rows[0]));
      await client.queryArray("RESET ROLE");
      await client.queryArray(
        "UPDATE public.explore_posts SET moderated_at = NOW() WHERE id = $1",
        [post],
      );
      const hidden = await client.queryObject(
        "SELECT * FROM public.get_community_identification_detail($1,$2)",
        [viewer, request],
      );
      assertEquals(hidden.rows.length, 0);
      for (const role of ["anon", "authenticated"]) {
        const denied = await client.queryObject<{ allowed: boolean }>(
          "SELECT pg_catalog.has_function_privilege($1, 'public.get_community_identification_detail(uuid,uuid)', 'EXECUTE') AS allowed",
          [role],
        );
        assertEquals(denied.rows[0].allowed, false);
      }
    }
  });
});

Deno.test("reference promotion and public Perfect Lens reject unfamiliar metrics even with confirmed species", async () => {
  await withExploreDbTest(
    "identificationMetricsPublicConsumers",
    async (client) => {
      const owner = crypto.randomUUID();
      await insertUser(client, owner, "Metric Public Owner");
      const ids: string[] = [];
      const cases = ["legacy", "known", "unknown", "unknown_confirmed"];
      for (const [i, kind] of cases.entries()) {
        const species = crypto.randomUUID(), scan = crypto.randomUUID();
        ids.push(scan);
        await insertSpecies(client, species, `Rosa metricpublic${i}`);
        await insertScan(client, {
          id: scan,
          userId: owner,
          speciesId: species,
          confirmedSpeciesId: kind === "unknown_confirmed" ? species : null,
          latitude: 0,
          longitude: 0,
          geoprivacy: "open",
          imageQualityScore: 100,
          aiConfidenceScore: 0.999,
          imageUrl: `https://example.invalid/metric-${i}.webp`,
          identificationProvenance: kind === "legacy"
            ? undefined
            : kind === "known"
            ? geminiMetricProvenance()
            : unqualifiedMetricProvenance(),
        });
        await client.queryArray(
          "UPDATE public.scans SET is_biological_subject = TRUE WHERE id = $1",
          [scan],
        );
        await insertExplorePost(client, {
          id: crypto.randomUUID(),
          userId: owner,
          scanId: scan,
        });
      }
      await client.queryArray("SET LOCAL ROLE service_role");
      for (const dryRun of [true, false]) {
        const result = await client.queryObject<
          { candidate_count: number; promoted_count: number }
        >(
          "SELECT * FROM public.refresh_merian_reference_images(80,8,$1,0.95)",
          [dryRun],
        );
        assertEquals(result.rows[0].candidate_count, 2);
        assertEquals(result.rows[0].promoted_count, 2);
      }
      const profile = await client.queryObject<
        { awards: { type: string; current_count: number }[] }
      >("SELECT * FROM public.get_explore_author_profile($1,$1,9)", [owner]);
      assertEquals(
        profile.rows[0].awards.find((a) => a.type === "perfect_lens")
          ?.current_count,
        2,
      );
      await client.queryArray("RESET ROLE");
      const promoted = await client.queryObject<{ scan_id: string }>(
        "SELECT scan_id FROM public.species_reference_image_merian_sources WHERE is_promoted ORDER BY scan_id",
      );
      assertEquals(
        promoted.rows.map((r) => r.scan_id).sort(),
        ids.slice(0, 2).sort(),
      );
    },
  );
});
