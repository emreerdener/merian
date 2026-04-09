import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler, runBackground } from "../_shared/edgeHandler.ts";
import { fetchSimilarSpecies, fetchStaticEncyclopedicData, EncyclopedicData } from "../_shared/biology.ts";
import { fetchGBIFVernacularNames } from "../_shared/external.ts";
import { requireParams } from "../_shared/http.ts";
import { trackPostHogEvent } from "../_shared/posthog.ts";
import {
  getCachedSpecies,
  updateSpeciesEnrichment,
  fetchLookalikesFromJoinTable,
  resolveLookalikesToJoinTable,
  clearLookalikesForSpecies,
} from "./db.ts";
import { CachedSpeciesData, LookalikeSummary } from "./types.ts";

// Scoped response payload helpers — each scope returns only its own fields so the
// iOS client can apply them to the UI as they arrive in parallel.

function formatEnrichmentOnlyPayload(
  cachedSpecies: CachedSpeciesData | null,
  enrichmentResult: EncyclopedicData | null,
  altNames: string[] | null,
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
    // Caller resolves altNames from DB cache or live GBIF fetch so this is always
    // the freshest available value. Null when GBIF has no English entries.
    alternative_common_names: altNames,
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

// In-flight deduplication (singleflight pattern) — prevents concurrent requests on the
// same warm Deno isolate from each firing a Gemini call for the same species on a cache
// miss (thundering herd on popular species at launch). Late arrivals await the in-flight
// Promise, then re-read the species_dictionary, which will be a cache hit by then.
const _enrichmentInFlight = new Map<string, Promise<void>>();
const _lookalikesInFlight = new Map<string, Promise<void>>();

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

    if (typeof scientific_name !== "string" || scientific_name.length === 0 || scientific_name.length > 500) {
      return jsonResponse({ error: "scientific_name must be a non-empty string under 500 characters." }, 400);
    }

    if (scope !== "enrichment" && scope !== "lookalikes") {
      return jsonResponse({ error: "scope must be \"enrichment\" or \"lookalikes\"" }, 400);
    }

    const cachedSpecies = await getCachedSpecies(scientific_name, supabaseAdmin);
    const speciesId = cachedSpecies?.id ?? null;

    // ── ENRICHMENT SCOPE ──────────────────────────────────────────────────────
    if (scope === "enrichment") {
      // Resolve alternative common names before branching on hasEnrichment so both
      // the cache-hit and cache-miss paths serve the freshest available value.
      //
      // Priority order:
      //   1. Already stored in species_dictionary.alternative_common_names — fastest, no I/O.
      //   2. Live fetch from GBIF vernacular names endpoint using the cached gbif_taxon_key.
      //      Covers two gaps: (a) old species rows that existed before V34 added the column,
      //      (b) new species where identify's background GBIF fetch raced ahead of this call
      //      and hadn't written to DB yet when getCachedSpecies ran above.
      //
      // The result is persisted via updateSpeciesEnrichment so subsequent requests are served
      // from the DB (path 1) without another GBIF round-trip.
      let altNames: string[] | null = cachedSpecies?.alternative_common_names ?? null;
      let altNamesFetched = false;
      if (altNames === null && cachedSpecies?.gbif_taxon_key != null) {
        const fetched = await fetchGBIFVernacularNames(cachedSpecies.gbif_taxon_key);
        if (fetched.length > 0) {
          const primaryEn = (cachedSpecies.common_names?.en ?? "").toLowerCase();
          altNames = fetched.filter((n) => n.toLowerCase() !== primaryEn);
          if (altNames.length === 0) altNames = null;
        }
        // Mark as freshly fetched even when empty so we persist the result below —
        // an empty fetch means GBIF has no English entries, not that we skipped the call.
        altNamesFetched = true;
      }

      const hasEnrichment =
        cachedSpecies?.habitat_description !== null &&
        cachedSpecies?.habitat_description !== undefined;

      if (hasEnrichment) {
        console.log(`[enrich-scan:enrichment] CACHE HIT for ${scientific_name}`);
        // Persist freshly fetched alt names so future requests hit DB path 1.
        if (altNamesFetched) {
          runBackground(
            updateSpeciesEnrichment(scientific_name, null, null, supabaseAdmin, altNames),
          );
        }
        return jsonResponse(
          { success: true, data: formatEnrichmentOnlyPayload(cachedSpecies, null, altNames) },
          200,
        );
      }

      // Singleflight guard — if another request is already enriching this species on this
      // isolate, wait for it to finish and return the now-cached result without a second call.
      const inFlightEnrichment = _enrichmentInFlight.get(scientific_name);
      if (inFlightEnrichment) {
        try {
          await inFlightEnrichment;
          const refreshed = await getCachedSpecies(scientific_name, supabaseAdmin);
          // Re-resolve altNames from the refreshed row (background write may have landed).
          const refreshedAltNames = refreshed?.alternative_common_names ?? altNames;
          return jsonResponse(
            { success: true, data: formatEnrichmentOnlyPayload(refreshed, null, refreshedAltNames) },
            200,
          );
        } catch {
          // Failed! Fall through to allow this request to retry the LLM call.
        }
      }

      let resolveEnrichmentInFlight!: () => void;
      let rejectEnrichmentInFlight!: (e: Error) => void;
      _enrichmentInFlight.set(
        scientific_name,
        new Promise<void>((resolve, reject) => { 
          resolveEnrichmentInFlight = resolve; 
          rejectEnrichmentInFlight = reject; 
        }),
      );

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
          updateSpeciesEnrichment(scientific_name, enrichmentResult, null, supabaseAdmin, altNames),
        );

        console.log(`[enrich-scan:enrichment] CACHE MISS for ${scientific_name}`);
        resolveEnrichmentInFlight();
        return jsonResponse(
          { success: true, data: formatEnrichmentOnlyPayload(cachedSpecies, enrichmentResult, altNames) },
          200,
        );
      } catch (e: unknown) {
        console.error("[enrich-scan:enrichment] LLM error:", e);
        rejectEnrichmentInFlight(e instanceof Error ? e : new Error(String(e)));
        const message = e instanceof Error ? e.message : "Failed to process enrichment.";
        return jsonResponse({ success: false, error: message }, 500);
      } finally {
        _enrichmentInFlight.delete(scientific_name);
      }
    }

    // ── LOOKALIKES SCOPE ──────────────────────────────────────────────────────
    let lookalikes: LookalikeSummary[] = [];

    if (speciesId) {
      const rawLookalikes = await fetchLookalikesFromJoinTable(speciesId, supabaseAdmin);

      // Stale contamination detection: if the primary species' order is known and EVERY
      // join-table entry has a different known order, the entire cached set was written
      // without taxonomy context (common when the lookalikes Flash call raced ahead of the
      // enrichment scope that populates species_dictionary taxonomy). Clear the stale rows,
      // reset the flash-attempted flag, and fall through to a fresh Flash call.
      const primaryOrder = cachedSpecies?.order?.toLowerCase() ?? null;
      if (primaryOrder && rawLookalikes.length > 0) {
        const stale = rawLookalikes.filter(
          (l) => l._order != null && l._order.toLowerCase() !== primaryOrder,
        );
        if (stale.length === rawLookalikes.length) {
          console.warn(
            `[enrich-scan:lookalikes] Stale cross-order contamination for ${scientific_name} ` +
            `(primary order: ${primaryOrder}). Clearing ${rawLookalikes.length} entries and re-running Flash.`,
          );
          await clearLookalikesForSpecies(speciesId, supabaseAdmin);
          await supabaseAdmin
            .from("species_dictionary")
            .update({ lookalikes_flash_attempted: false, similar_species: null })
            .eq("id", speciesId);
          lookalikes = [];
        } else {
          // Strip the internal _order field before serving to client.
          lookalikes = rawLookalikes.map(({ _order: _o, ...rest }) => rest);
        }
      } else {
        lookalikes = rawLookalikes.map(({ _order: _o, ...rest }) => rest);
      }

      // Migration path: join table is empty but TEXT[] has names from the old pipeline —
      // resolve them into the join table once at zero Gemini token cost.
      if (
        lookalikes.length === 0 &&
        cachedSpecies?.similar_species &&
        cachedSpecies.similar_species.length > 0
      ) {
        const migrationResult = await resolveLookalikesToJoinTable(
          speciesId,
          cachedSpecies.similar_species.map((name) => ({ scientific_name: name, common_name: null })),
          supabaseAdmin,
          cachedSpecies?.kingdom,
          cachedSpecies?.order,
        );
        lookalikes = migrationResult.lookalikes;
        // migrationResult.persisted is intentionally not used here: the migration path
        // runs against TEXT[] names stored by a prior Flash call, not a new Flash call.
        // lookalikes_flash_attempted was already set during the original Flash run.
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

    // Singleflight guard — wait for any in-flight lookalikes Flash call on this isolate
    // and return the persisted result rather than firing a duplicate Gemini call.
    const inFlightLookalikes = _lookalikesInFlight.get(scientific_name);
    if (inFlightLookalikes) {
      try {
        await inFlightLookalikes;
        const refreshedSpecies = await getCachedSpecies(scientific_name, supabaseAdmin);
        const refreshedId = refreshedSpecies?.id ?? speciesId;
        const refreshedLookalikes = refreshedId
          ? await fetchLookalikesFromJoinTable(refreshedId, supabaseAdmin)
          : [];
        return jsonResponse(
          { success: true, data: formatLookalikesOnlyPayload(refreshedSpecies, refreshedLookalikes) },
          200,
        );
      } catch {
        // Failed! Fall through.
      }
    }

    let resolveLookalikesInFlight!: () => void;
    let rejectLookalikesInFlight!: (e: Error) => void;
    _lookalikesInFlight.set(
      scientific_name,
      new Promise<void>((resolve, reject) => { 
        resolveLookalikesInFlight = resolve; 
        rejectLookalikesInFlight = reject;
      }),
    );

    try {
      const similarResult = await fetchSimilarSpecies(_user, scientific_name, {
        kingdom: cachedSpecies?.kingdom,
        class: cachedSpecies?.class,
        order: cachedSpecies?.order,
        family: cachedSpecies?.family,
      });

      if (similarResult?.similar_species) {
        if (speciesId) {
          const resolveResult = await resolveLookalikesToJoinTable(
            speciesId,
            similarResult.similar_species,
            supabaseAdmin,
            cachedSpecies?.kingdom,
            cachedSpecies?.order,
          );
          lookalikes = resolveResult.lookalikes;
          // Only set lookalikes_flash_attempted when the join table was actually written
          // (resolveResult.persisted = true). If primaryKingdom was null, the function
          // returned early without touching the join table — locking the flag in that
          // state would permanently prevent a future validated write once kingdom is known.
          if (resolveResult.persisted && lookalikes.length > 0) {
            runBackground(
              Promise.resolve(
                supabaseAdmin
                  .from("species_dictionary")
                  .update({ lookalikes_flash_attempted: true })
                  .eq("id", speciesId),
              ).then(() => {}),
            );
          }
        } else {
          // Species row not yet visible on the read replica (replication lag on first scan).
          // Return the raw Flash names so the client is not left with null. Image URLs and
          // IUCN status are unavailable without a DB lookup, but scientific + common names
          // are enough for the SimilarSpeciesGallery to render. The join table will be
          // populated on the next enrich-scan call once the row is visible.
          lookalikes = similarResult.similar_species.map((e) => ({
            scientific_name: e.scientific_name,
            common_name: e.common_name,
            reference_image_url: null,
            iucn_red_list_status: null,
          }));
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
      resolveLookalikesInFlight();
      return jsonResponse(
        { success: true, data: formatLookalikesOnlyPayload(cachedSpecies, lookalikes) },
        200,
      );
    } catch (e: unknown) {
      console.error("[enrich-scan:lookalikes] LLM error:", e);
      rejectLookalikesInFlight(e instanceof Error ? e : new Error(String(e)));
      const message = e instanceof Error ? e.message : "Failed to process lookalikes.";
      return jsonResponse({ success: false, error: message }, 500);
    } finally {
      _lookalikesInFlight.delete(scientific_name);
    }
  }),
);
