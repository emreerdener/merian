import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { fetchSimilarSpecies } from "../_shared/biology.ts";
import { requireParams } from "../_shared/http.ts";
import { fetchStaticEncyclopedicData, EncyclopedicData } from "../_shared/biology.ts";
import { trackPostHogEvent } from "../_shared/posthog.ts";
import {
  getCachedSpecies,
  updateSpeciesEnrichment,
  fetchLookalikesFromJoinTable,
  resolveLookalikesToJoinTable,
} from "./db.ts";
import { CachedSpeciesData, LookalikeSummary } from "./types.ts";

function formatEnrichmentPayload(
  cachedSpecies: CachedSpeciesData | null,
  enrichmentResult: EncyclopedicData | null,
  lookalikes: LookalikeSummary[],
) {
  // Prefer rich join-table entries. Fall back to TEXT[] scientific names when rich
  // resolution failed (lookalike species not yet in species_dictionary). This ensures
  // clients always receive at least species names rather than null, which prevents
  // the UI from going blank when the join table is sparsely populated.
  const resolvedLookalikes: LookalikeSummary[] =
    lookalikes.length > 0
      ? lookalikes
      : (cachedSpecies?.similar_species ?? []).map((name) => ({
          scientific_name: name,
          common_name: null,
          reference_image_url: null,
          iucn_red_list_status: null,
        }));

  return {
    habitat_description:
      enrichmentResult?.habitat_description ??
      cachedSpecies?.habitat_description ??
      "No habitat data available.",
    gbif_taxon_key: cachedSpecies?.gbif_taxon_key,
    similar_species: resolvedLookalikes.length > 0 ? resolvedLookalikes : null,
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

    const paramErr = requireParams(body, ["scientific_name"]);
    if (paramErr) return paramErr;

    const { scientific_name } = body;

    const cachedSpecies = await getCachedSpecies(scientific_name, supabaseAdmin);

    const hasEnrichment =
      cachedSpecies?.habitat_description !== null &&
      cachedSpecies?.habitat_description !== undefined;

    // Fetch existing rich lookalike entries from the join table
    const speciesId = cachedSpecies?.id ?? null;
    let lookalikes: LookalikeSummary[] = [];

    if (speciesId) {
      lookalikes = await fetchLookalikesFromJoinTable(speciesId, supabaseAdmin);

      // Migration path: join table is empty but TEXT[] has names from the old pipeline —
      // resolve them into the join table once at zero Gemini token cost.
      // Legacy TEXT[] entries carry no common_name; the back-fill in resolveLookalikesToJoinTable
      // will populate common_names for any matched dictionary rows that have a null column.
      if (
        lookalikes.length === 0 &&
        cachedSpecies?.similar_species &&
        cachedSpecies.similar_species.length > 0
      ) {
        // resolveLookalikesToJoinTable returns the hydrated summaries directly —
        // no redundant fetchLookalikesFromJoinTable call needed.
        lookalikes = await resolveLookalikesToJoinTable(
          speciesId,
          cachedSpecies.similar_species.map((name) => ({ scientific_name: name, common_name: null })),
          supabaseAdmin,
        );
      }
    }

    // Require at least one resolved common_name OR a prior Flash attempt flag.
    // - lookalikes.some(...): enriched species with at least one known common name.
    // - lookalikes_flash_attempted: Flash has already run for this species and returned
    //   all-null common names (legitimately obscure lookalikes). Without this flag,
    //   the .some() check would never become true and Flash would re-run on every call.
    const hasLookalikes =
      lookalikes.some((l) => l.common_name !== null) ||
      cachedSpecies?.lookalikes_flash_attempted === true;

    if (hasEnrichment && hasLookalikes) {
      console.log(`[enrich-scan] CACHE HIT for ${scientific_name}`);
      return jsonResponse(
        {
          success: true,
          data: formatEnrichmentPayload(cachedSpecies, null, lookalikes),
        },
        200,
      );
    }

    const enrichmentPromise = hasEnrichment
      ? Promise.resolve(null)
      : fetchStaticEncyclopedicData(_user, scientific_name);

    // Skip Gemini if the join table (or migrated TEXT[]) already has entries
    const similarSpeciesPromise = hasLookalikes
      ? Promise.resolve(null)
      : fetchSimilarSpecies(_user, scientific_name);

    try {
      const [enrichmentResult, similarResult] = await Promise.all([
        enrichmentPromise,
        similarSpeciesPromise,
      ]);

      // Resolve newly-generated lookalike names into the join table.
      // resolveLookalikesToJoinTable returns the hydrated summaries directly —
      // no redundant fetchLookalikesFromJoinTable call needed.
      if (similarResult?.similar_species && speciesId) {
        lookalikes = await resolveLookalikesToJoinTable(
          speciesId,
          similarResult.similar_species,
          supabaseAdmin,
        );
        // Mark lookalikes_flash_attempted so future cold-path calls skip Flash even when all
        // common names are legitimately null (genuinely obscure lookalike species).
        // Deferred via waitUntil — this flag is not needed before the response is flushed,
        // and awaiting it sequentially added a gratuitous ~20 ms Postgres round-trip.
        if (speciesId) {
          EdgeRuntime.waitUntil(
            supabaseAdmin
              .from("species_dictionary")
              .update({ lookalikes_flash_attempted: true })
              .eq("id", speciesId)
              .then(() => {}),
          );
        }
      }

      const totalTokens =
        (enrichmentResult?.usage?.totalTokenCount ?? 0) +
        (similarResult?.usage?.totalTokenCount ?? 0);

      if (totalTokens > 0) {
        trackPostHogEvent(_user, "EnrichmentCostAnalyzed", {
          scientific_name,
          encyclopedic_tokens: enrichmentResult?.usage?.totalTokenCount ?? 0,
          similar_species_tokens: similarResult?.usage?.totalTokenCount ?? 0,
          cumulative_scan_tokens: totalTokens,
        }).catch((e) => console.error("PostHog EnrichmentCostAnalyzed failed:", e));
      }

      // Persist enrichment + write similar_species TEXT[] for backwards compatibility.
      // Deferred via waitUntil — the response payload is fully formed at this point
      // and the client does not need to wait for this write before consuming the response.
      // Previously awaited sequentially, adding another ~20-30 ms to cold-path latency.
      EdgeRuntime.waitUntil(
        updateSpeciesEnrichment(
          scientific_name,
          enrichmentResult,
          similarResult,
          supabaseAdmin,
        ),
      );

      console.log(`[enrich-scan] CACHE MISS: Generated enrichment for ${scientific_name}`);

      return jsonResponse(
        {
          success: true,
          data: formatEnrichmentPayload(cachedSpecies, enrichmentResult, lookalikes),
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
