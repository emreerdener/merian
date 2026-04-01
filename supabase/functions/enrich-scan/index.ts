import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler, runBackground } from "../_shared/edgeHandler.ts";
import { fetchSimilarSpecies, fetchStaticEncyclopedicData, EncyclopedicData } from "../_shared/biology.ts";
import { requireParams } from "../_shared/http.ts";
import { trackPostHogEvent } from "../_shared/posthog.ts";
import {
  getCachedSpecies,
  updateSpeciesEnrichment,
  fetchLookalikesFromJoinTable,
  resolveLookalikesToJoinTable,
} from "./db.ts";
import { CachedSpeciesData, LookalikeSummary } from "./types.ts";

// Scoped response payload helpers — each scope returns only its own fields so the
// iOS client can apply them to the UI as they arrive in parallel.

function formatEnrichmentOnlyPayload(
  cachedSpecies: CachedSpeciesData | null,
  enrichmentResult: EncyclopedicData | null,
) {
  return {
    scope: "enrichment" as const,
    habitat_description:
      enrichmentResult?.habitat_description ??
      cachedSpecies?.habitat_description ??
      "No habitat data available.",
    gbif_taxon_key: cachedSpecies?.gbif_taxon_key,
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

function formatLookalikesOnlyPayload(
  cachedSpecies: CachedSpeciesData | null,
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
    scope: "lookalikes" as const,
    similar_species: resolvedLookalikes.length > 0 ? resolvedLookalikes : null,
  };
}

// TODO(rate-limiting): _user is authenticated but there is no per-user server-side throttle on
// LLM-triggering enrichment calls. Any authenticated user can invoke this endpoint an unbounded
// number of times, each triggering a Gemini generation round-trip. Add a per-user daily quota
// check against `usage_limits` (or a dedicated `enrichment_calls_today` counter) that returns
// HTTP 429 before reaching `fetchStaticEncyclopedicData` / `fetchSimilarSpecies`. The client-side
// `InferenceEngine` already gates via `enrichedSpeciesNames`, but the server must not trust it.

serve((req: Request) =>
  withEdgeHandler(req, async (_user, supabaseAdmin) => {
    let body;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    const paramErr = requireParams(body, ["scientific_name", "scope"]);
    if (paramErr) return paramErr;

    const { scientific_name, scope } = body as {
      scientific_name: string;
      scope: "enrichment" | "lookalikes";
    };

    if (scope !== "enrichment" && scope !== "lookalikes") {
      return jsonResponse({ error: "scope must be \"enrichment\" or \"lookalikes\"" }, 400);
    }

    const cachedSpecies = await getCachedSpecies(scientific_name, supabaseAdmin);
    const speciesId = cachedSpecies?.id ?? null;

    // ── ENRICHMENT SCOPE ──────────────────────────────────────────────────────
    if (scope === "enrichment") {
      const hasEnrichment =
        cachedSpecies?.habitat_description !== null &&
        cachedSpecies?.habitat_description !== undefined;

      if (hasEnrichment) {
        console.log(`[enrich-scan:enrichment] CACHE HIT for ${scientific_name}`);
        return jsonResponse(
          { success: true, data: formatEnrichmentOnlyPayload(cachedSpecies, null) },
          200,
        );
      }

      try {
        const enrichmentResult = await fetchStaticEncyclopedicData(_user, scientific_name);

        if (enrichmentResult?.usage?.totalTokenCount) {
          trackPostHogEvent(_user, "EnrichmentCostAnalyzed", {
            scientific_name,
            scope: "enrichment",
            encyclopedic_tokens: enrichmentResult.usage.totalTokenCount,
            cumulative_scan_tokens: enrichmentResult.usage.totalTokenCount,
          }).catch((e) => console.error("PostHog EnrichmentCostAnalyzed failed:", e));
        }

        runBackground(
          updateSpeciesEnrichment(scientific_name, enrichmentResult, null, supabaseAdmin),
        );

        console.log(`[enrich-scan:enrichment] CACHE MISS for ${scientific_name}`);
        return jsonResponse(
          { success: true, data: formatEnrichmentOnlyPayload(cachedSpecies, enrichmentResult) },
          200,
        );
      } catch (e: unknown) {
        console.error("[enrich-scan:enrichment] LLM error:", e);
        const message = e instanceof Error ? e.message : "Failed to process enrichment.";
        return jsonResponse({ success: false, error: message }, 500);
      }
    }

    // ── LOOKALIKES SCOPE ──────────────────────────────────────────────────────
    let lookalikes: LookalikeSummary[] = [];

    if (speciesId) {
      lookalikes = await fetchLookalikesFromJoinTable(speciesId, supabaseAdmin);

      // Migration path: join table is empty but TEXT[] has names from the old pipeline —
      // resolve them into the join table once at zero Gemini token cost.
      if (
        lookalikes.length === 0 &&
        cachedSpecies?.similar_species &&
        cachedSpecies.similar_species.length > 0
      ) {
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

    if (hasLookalikes) {
      console.log(`[enrich-scan:lookalikes] CACHE HIT for ${scientific_name}`);
      return jsonResponse(
        { success: true, data: formatLookalikesOnlyPayload(cachedSpecies, lookalikes) },
        200,
      );
    }

    try {
      const similarResult = await fetchSimilarSpecies(_user, scientific_name);

      if (similarResult?.similar_species && speciesId) {
        lookalikes = await resolveLookalikesToJoinTable(
          speciesId,
          similarResult.similar_species,
          supabaseAdmin,
        );
        // Guard: only set the flag when lookalikes were actually resolved. Flash can return
        // similar_species: [] (empty array) for species it doesn't recognise; [] is truthy
        // in JS so the outer `if` fires, but we must not permanently lock out future Flash
        // retries when no lookalike data was produced.
        if (lookalikes.length > 0) {
          runBackground(
            Promise.resolve(
              supabaseAdmin
                .from("species_dictionary")
                .update({ lookalikes_flash_attempted: true })
                .eq("id", speciesId),
            ).then(() => {}),
          );
        }
      }

      if (similarResult?.usage?.totalTokenCount) {
        trackPostHogEvent(_user, "EnrichmentCostAnalyzed", {
          scientific_name,
          scope: "lookalikes",
          similar_species_tokens: similarResult.usage.totalTokenCount,
          cumulative_scan_tokens: similarResult.usage.totalTokenCount,
        }).catch((e) => console.error("PostHog EnrichmentCostAnalyzed failed:", e));
      }

      runBackground(
        updateSpeciesEnrichment(scientific_name, null, similarResult, supabaseAdmin),
      );

      console.log(`[enrich-scan:lookalikes] CACHE MISS for ${scientific_name}`);
      return jsonResponse(
        { success: true, data: formatLookalikesOnlyPayload(cachedSpecies, lookalikes) },
        200,
      );
    } catch (e: unknown) {
      console.error("[enrich-scan:lookalikes] LLM error:", e);
      const message = e instanceof Error ? e.message : "Failed to process lookalikes.";
      return jsonResponse({ success: false, error: message }, 500);
    }
  }),
);
