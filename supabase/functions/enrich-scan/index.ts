import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { fetchSimilarSpecies } from "../_shared/similar-species.ts";
import { requireParams } from "../_shared/validation.ts";
import { fetchStaticEncyclopedicData } from "../_shared/encyclopedic.ts";
import { trackPostHogEvent } from "../_shared/posthog.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (_user, supabaseAdmin) => {
    let body;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    const paramErr = requireParams(body, [
      "scientific_name",
      "confidence_score",
    ]);
    if (paramErr) return paramErr;

    const { scientific_name, confidence_score } = body;

    // Check what we already have for this species in PG
    const { data: cachedSpecies, error } = await supabaseAdmin
      .from("species_dictionary")
      .select(
        "gbif_taxon_key, habitat_description, kingdom, phylum, class, order, family, genus, similar_species",
      )
      .eq("scientific_name", scientific_name)
      .maybeSingle();

    if (error && error.code !== "PGRST116") throw error;

    const hasEnrichment =
      cachedSpecies?.habitat_description !== null &&
      cachedSpecies?.habitat_description !== undefined;

    // We only perform the expensive Gemini lookalikes lookup on 'possible' or 'speculative' matches
    const needsSimilarSpecies = confidence_score < 0.88;
    const hasSimilarSpecies =
      cachedSpecies?.similar_species !== null &&
      cachedSpecies?.similar_species !== undefined;

    // Fast-path: we already have everything required
    if (hasEnrichment && (!needsSimilarSpecies || hasSimilarSpecies)) {
      console.log(`[enrich-scan] CACHE HIT for ${scientific_name}`);

      return jsonResponse(
        {
          success: true,
          data: {
            habitat_description: cachedSpecies!.habitat_description,
            gbif_taxon_key: cachedSpecies!.gbif_taxon_key,
            similar_species:
              needsSimilarSpecies && hasSimilarSpecies
                ? {
                    lookalike_species: cachedSpecies!.similar_species ?? [],
                  }
                : null,
            taxonomy: {
              kingdom: cachedSpecies!.kingdom ?? "Unknown",
              phylum: cachedSpecies!.phylum ?? "Unknown",
              class: cachedSpecies!.class ?? "Unknown",
              order: cachedSpecies!.order ?? "Unknown",
              family: cachedSpecies!.family ?? "Unknown",
              genus: cachedSpecies!.genus ?? "Unknown",
            },
          },
        },
        200,
      );
    }

    // Fire enrichment and similar species Flash calls in parallel for whatever is missing.
    const enrichmentPromise = hasEnrichment
      ? Promise.resolve(cachedSpecies)
      : (async () => {
          const result = await fetchStaticEncyclopedicData(
            _user,
            scientific_name,
          );

          await trackPostHogEvent(_user, "EnrichmentCompleted", {
            scientific_name,
          });

          return {
            habitat_description: result.habitat_description,
            kingdom: result.taxonomy.kingdom,
            phylum: result.taxonomy.phylum,
            class: result.taxonomy.class,
            order: result.taxonomy.order,
            family: result.taxonomy.family,
            genus: result.taxonomy.genus,
          };
        })();

    const similarSpeciesPromise =
      !needsSimilarSpecies || hasSimilarSpecies
        ? Promise.resolve(null)
        : fetchSimilarSpecies(_user, scientific_name);

    try {
      const [enrichmentResult, similarResult] = await Promise.all([
        enrichmentPromise,
        similarSpeciesPromise,
      ]);

      // Persist whatever was freshly generated.
      const persistOps: PromiseLike<unknown>[] = [];
      if (!hasEnrichment && enrichmentResult) {
        persistOps.push(
          supabaseAdmin
            .from("species_dictionary")
            .update({
              habitat_description: (
                enrichmentResult as { habitat_description: string }
              ).habitat_description,
            })
            .eq("scientific_name", scientific_name),
        );
      }
      if (!hasSimilarSpecies && similarResult) {
        persistOps.push(
          supabaseAdmin
            .from("species_dictionary")
            .update({
              similar_species: similarResult.similar_species,
            })
            .eq("scientific_name", scientific_name),
        );
      }
      await Promise.allSettled(persistOps);

      console.log(
        `[enrich-scan] CACHE MISS: Generated enrichment for ${scientific_name}`,
      );

      return jsonResponse(
        {
          success: true,
          data: {
            habitat_description:
              (enrichmentResult as Record<string, string>)
                ?.habitat_description ??
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
              kingdom:
                (enrichmentResult as Record<string, string>)?.kingdom ??
                cachedSpecies?.kingdom ??
                "Unknown",
              phylum:
                (enrichmentResult as Record<string, string>)?.phylum ??
                cachedSpecies?.phylum ??
                "Unknown",
              class:
                (enrichmentResult as Record<string, string>)?.class ??
                cachedSpecies?.class ??
                "Unknown",
              order:
                (enrichmentResult as Record<string, string>)?.order ??
                cachedSpecies?.order ??
                "Unknown",
              family:
                (enrichmentResult as Record<string, string>)?.family ??
                cachedSpecies?.family ??
                "Unknown",
              genus:
                (enrichmentResult as Record<string, string>)?.genus ??
                cachedSpecies?.genus ??
                "Unknown",
            },
          },
        },
        200,
      );
    } catch (e: unknown) {
      console.error("[enrich-scan] LLM error:", e);
      const message = e instanceof Error ? e.message : "Failed to process scan data.";
      return jsonResponse(
        { success: false, error: message },
        500,
      );
    }
  }),
);
