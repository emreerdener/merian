import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { fetchSimilarSpecies } from "../_shared/similar-species.ts";
import { requireParams } from "../_shared/validation.ts";
import { fetchStaticEncyclopedicData, EncyclopedicData } from "../_shared/encyclopedic.ts";
import { trackPostHogEvent } from "../_shared/posthog.ts";
import { getCachedSpecies, updateSpeciesEnrichment } from "./db.ts";
import { CachedSpeciesData } from "./types.ts";

function formatEnrichmentPayload(
  cachedSpecies: CachedSpeciesData | null,
  enrichmentResult: EncyclopedicData | null,
  similarResult: { similar_species: string[] } | null,
  needsSimilarSpecies: boolean,
  hasSimilarSpecies: boolean,
) {
  return {
    habitat_description:
      enrichmentResult?.habitat_description ??
      cachedSpecies?.habitat_description ??
      "No habitat data available.",
    gbif_taxon_key: cachedSpecies?.gbif_taxon_key,
    similar_species: needsSimilarSpecies
      ? similarResult ||
        (hasSimilarSpecies
          ? {
              lookalike_species: cachedSpecies!.similar_species ?? [],
            }
          : null)
      : null,
    taxonomy: {
      kingdom: enrichmentResult?.taxonomy?.kingdom ?? cachedSpecies?.kingdom ?? "Unknown",
      phylum: enrichmentResult?.taxonomy?.phylum ?? cachedSpecies?.phylum ?? "Unknown",
      class: enrichmentResult?.taxonomy?.class ?? cachedSpecies?.class ?? "Unknown",
      order: enrichmentResult?.taxonomy?.order ?? cachedSpecies?.order ?? "Unknown",
      family: enrichmentResult?.taxonomy?.family ?? cachedSpecies?.family ?? "Unknown",
      genus: enrichmentResult?.taxonomy?.genus ?? cachedSpecies?.genus ?? "Unknown",
    },
  };
}

serve((req: Request) =>
  withEdgeHandler(req, async (_user, supabaseAdmin) => {
    let body;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    const paramErr = requireParams(body, ["scientific_name", "confidence_score"]);
    if (paramErr) return paramErr;

    const { scientific_name, confidence_score } = body;

    const cachedSpecies = await getCachedSpecies(scientific_name, supabaseAdmin);

    const hasEnrichment =
      cachedSpecies?.habitat_description !== null &&
      cachedSpecies?.habitat_description !== undefined;

    const needsSimilarSpecies = confidence_score < 0.88;
    const hasSimilarSpecies =
      cachedSpecies?.similar_species !== null &&
      cachedSpecies?.similar_species !== undefined;

    if (hasEnrichment && (!needsSimilarSpecies || hasSimilarSpecies)) {
      console.log(`[enrich-scan] CACHE HIT for ${scientific_name}`);
      return jsonResponse(
        {
          success: true,
          data: formatEnrichmentPayload(
            cachedSpecies,
            null,
            null,
            needsSimilarSpecies,
            hasSimilarSpecies,
          ),
        },
        200,
      );
    }

    const enrichmentPromise = hasEnrichment
      ? Promise.resolve(null)
      : fetchStaticEncyclopedicData(_user, scientific_name);

    const similarSpeciesPromise =
      !needsSimilarSpecies || hasSimilarSpecies
        ? Promise.resolve(null)
        : fetchSimilarSpecies(_user, scientific_name);

    try {
      const [enrichmentResult, similarResult] = await Promise.all([
        enrichmentPromise,
        similarSpeciesPromise,
      ]);

      const totalTokens =
        (enrichmentResult?.usage?.totalTokenCount ?? 0) +
        (similarResult?.usage?.totalTokenCount ?? 0);

      if (totalTokens > 0) {
        await trackPostHogEvent(_user, "EnrichmentCostAnalyzed", {
          scientific_name,
          encyclopedic_tokens: enrichmentResult?.usage?.totalTokenCount ?? 0,
          similar_species_tokens: similarResult?.usage?.totalTokenCount ?? 0,
          cumulative_scan_tokens: totalTokens,
        });
      }

      await updateSpeciesEnrichment(
        scientific_name,
        enrichmentResult,
        similarResult,
        supabaseAdmin,
      );

      console.log(`[enrich-scan] CACHE MISS: Generated enrichment for ${scientific_name}`);

      return jsonResponse(
        {
          success: true,
          data: formatEnrichmentPayload(
            cachedSpecies,
            enrichmentResult,
            similarResult,
            needsSimilarSpecies,
            hasSimilarSpecies,
          ),
        },
        200,
      );
    } catch (e: unknown) {
      console.error("[enrich-scan] LLM error:", e);
      const message =
        e instanceof Error ? e.message : "Failed to process scan data.";
      return jsonResponse({ success: false, error: message }, 500);
    }
  }),
);
