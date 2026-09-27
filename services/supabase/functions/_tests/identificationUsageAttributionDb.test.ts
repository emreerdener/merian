import { assert, assertEquals } from "@std/assert";
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

Deno.test("scan usage uses saved execution, preserves legacy attribution and never prices a provider by model-name collision", async () => {
  await withExploreDbTest("identificationUsageAttribution", async (client) => {
    const user = crypto.randomUUID(), species = crypto.randomUUID();
    await insertUser(client, user, "Synthetic Usage Attribution");
    await insertSpecies(client, species, "Rosa attributionis");
    const known = geminiMetricProvenance();
    const cases = [
      {
        provenance: undefined,
        model: "gemini-2.5-flash",
        provider: "gemini",
        priced: true,
      },
      {
        provenance: { ...known, model: "gemini-2.5-pro" },
        model: "gemini-2.5-pro",
        provider: "gemini",
        priced: true,
      },
      {
        provenance: unqualifiedMetricProvenance(),
        model: "future-model",
        provider: "future-provider",
        priced: false,
      },
      {
        provenance: {
          ...unqualifiedMetricProvenance(),
          model: "gemini-2.5-flash",
        },
        model: "gemini-2.5-flash",
        provider: "future-provider",
        priced: false,
      },
    ];
    for (const fixture of cases) {
      const scan = crypto.randomUUID();
      await insertScan(client, {
        id: scan,
        userId: user,
        speciesId: species,
        latitude: 0,
        longitude: 0,
        geoprivacy: "private",
        inferenceTier: "flash",
        identificationProvenance: fixture.provenance,
      });
      await client.queryArray(
        `UPDATE public.scans SET llm_prompt_tokens=100, llm_cached_tokens=20,
        llm_candidate_tokens=30, llm_thinking_tokens=10, llm_total_tokens=140 WHERE id=$1`,
        [scan],
      );
      const read = () =>
        client.queryObject<
          {
            event: {
              id: string;
              model: string;
              operation: string;
              estimated_cost_microusd: number | null;
              pricing_version: string | null;
              metadata: Record<string, unknown>;
            };
          }
        >(
          "SELECT to_jsonb(event) AS event FROM public.ai_usage_events event WHERE scan_id=$1",
          [scan],
        );
      const before = (await read()).rows;
      assertEquals(before.length, 1);
      const event = before[0].event;
      assertEquals(event.model, fixture.model);
      assertEquals(event.operation, "scan_identification");
      assertEquals(event.metadata.ai_provider, fixture.provider);
      assertEquals(
        event.metadata.ai_attribution,
        fixture.provenance ? "recorded_provenance" : "legacy_tier",
      );
      assertEquals(event.estimated_cost_microusd !== null, fixture.priced);
      assertEquals(event.pricing_version !== null, fixture.priced);
      if (fixture.provenance) {
        assertEquals(event.metadata.ai_binding, fixture.provenance.binding);
        assertEquals(
          event.metadata.ai_policy_version,
          fixture.provenance.policy_version,
        );
        assertEquals(event.metadata.ai_prompt, fixture.provenance.prompt);
        assertEquals(event.metadata.ai_schema, fixture.provenance.schema);
        assertEquals(event.metadata.ai_operation, fixture.provenance.operation);
      }
      // The source can receive a retry; the original accounting event stays immutable.
      await client.queryArray(
        "UPDATE public.scans SET llm_total_tokens=999 WHERE id=$1",
        [scan],
      );
      assertEquals((await read()).rows, before);
    }
    const original = await client.queryObject<
      {
        id: string;
        model: string;
        metadata: unknown;
        estimated_cost_microusd: number | null;
      }
    >(
      "SELECT id,model,metadata,estimated_cost_microusd FROM public.ai_usage_events WHERE user_id=$1 ORDER BY id",
      [user],
    );
    await client.queryArray("DELETE FROM public.users WHERE id=$1", [user]);
    const retained = await client.queryObject<
      {
        id: string;
        model: string;
        metadata: unknown;
        estimated_cost_microusd: number | null;
        anonymous: boolean;
      }
    >(
      `SELECT id,model,metadata,estimated_cost_microusd,
        user_id IS NULL AND scan_id IS NULL AND source_id IS NULL AND conversation_id IS NULL AND message_id IS NULL AS anonymous
        FROM public.ai_usage_events WHERE id = ANY($1::UUID[]) ORDER BY id`,
      [original.rows.map((row) => row.id)],
    );
    assertEquals(retained.rows.length, cases.length);
    assert(retained.rows.every((row) => row.anonymous));
    assertEquals(
      retained.rows.map(({ anonymous: _anonymous, ...row }) => row),
      original.rows,
    );
  });
});
