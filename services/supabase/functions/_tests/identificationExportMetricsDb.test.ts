import { assertEquals } from "@std/assert";
import {
  insertScan,
  insertSpecies,
  insertUser,
  withExploreDbTest,
} from "./exploreDbTestHelpers.ts";
import {
  geminiMetricProvenance,
  unqualifiedMetricProvenance,
} from "./identificationMetricsTestFixtures.ts";

Deno.test("export creation freezes metric qualification and later score edits cannot rewrite it", async () => {
  await withExploreDbTest("identificationExportMetrics", async (client) => {
    // Suppress only the outbound worker wakeup. The real source-snapshot creation
    // trigger and all privacy/lease fences remain active in this rollback fixture.
    await client.queryArray(
      "ALTER TABLE public.export_jobs DISABLE TRIGGER on_export_job_created",
    );
    await client.queryArray(
      "UPDATE internal.dwca_export_release_control SET enabled = TRUE WHERE singleton",
    );
    const user = crypto.randomUUID(),
      species = crypto.randomUUID(),
      job = crypto.randomUUID(),
      claim = crypto.randomUUID();
    await insertUser(client, user, "Synthetic Export Metrics");
    await insertSpecies(client, species, "Rosa exportmetrics");
    const scans = [
      crypto.randomUUID(),
      crypto.randomUUID(),
      crypto.randomUUID(),
    ];
    const values = [
      undefined,
      geminiMetricProvenance(),
      unqualifiedMetricProvenance(),
    ];
    for (let i = 0; i < scans.length; i++) {
      await insertScan(client, {
        id: scans[i],
        userId: user,
        speciesId: species,
        latitude: 0,
        longitude: 0,
        geoprivacy: "private",
        aiConfidenceScore: 0.987,
        identificationProvenance: values[i],
        inferenceTier: "flash",
      });
    }
    await client.queryArray(
      "INSERT INTO public.export_jobs (id,user_id,export_scope,include_precise_coordinates) VALUES ($1,$2,'personal',FALSE)",
      [job, user],
    );
    const before = await client.queryObject<
      { scan_id: string; occurrence_payload: Record<string, unknown> }
    >(
      "SELECT scan_id, occurrence_payload FROM internal.export_job_source_rows WHERE job_id = $1 ORDER BY scan_id",
      [job],
    );
    assertEquals(before.rows.length, 3);
    for (const row of before.rows) {
      assertEquals(
        row.occurrence_payload.ai_confidence_qualified,
        row.scan_id !== scans[2],
      );
      assertEquals(row.occurrence_payload.ai_confidence_score, 0.987);
      assertEquals(
        "identification_provenance" in row.occurrence_payload,
        false,
      );
      assertEquals("gps_lat_exact" in row.occurrence_payload, false);
    }
    await client.queryArray(
      "UPDATE public.scans SET ai_confidence_score = 0.1 WHERE user_id = $1",
      [user],
    );
    await client.queryArray("SET LOCAL ROLE service_role");
    const claimed = await client.queryObject(
      "SELECT * FROM public.claim_export_job_step($1,$2)",
      [job, claim],
    );
    assertEquals(claimed.rows.length, 1);
    const batch = await client.queryObject<
      { scan_id: string; scan_payload: Record<string, unknown> }
    >(
      "SELECT scan_id,scan_payload FROM public.get_dwca_export_scan_batch($1,$2,'occurrence',NULL,100,262144) WHERE scan_payload IS NOT NULL ORDER BY scan_id",
      [job, claim],
    );
    assertEquals(
      batch.rows.map((row) => row.scan_payload),
      before.rows.map((row) => row.occurrence_payload),
    );
    await client.queryArray("RESET ROLE");
  });
});
