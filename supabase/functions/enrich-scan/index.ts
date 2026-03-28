import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { fetchDiagnosticComparison } from "../_shared/diagnostic.ts";
import { requireParams } from "../_shared/validation.ts";
import { fetchStaticEncyclopedicData } from "../_shared/encyclopedic.ts";
import { trackPostHogEvent } from "../_shared/posthog.ts";

const DIAGNOSTIC_THRESHOLD = 0.85;

serve((req: Request) =>
  withEdgeHandler(req, async (_user, supabaseAdmin) => {
    const fnStart = Date.now();
    const body = await req.json();
    const { scan_id, scientific_name } = body;

    const paramErr = requireParams(body, ["scan_id", "scientific_name"]);
    if (paramErr) return paramErr;

    // Fetch confidence score for the diagnostic threshold check.
    // No ownership filter — enrichment returns only public species biology data (habitat,
    // GBIF key, diagnostic comparison), so there is nothing user-private to gate.
    // Historical scans opened from the library may have been created under a different ghost
    // session; enforcing user_id would permanently block enrichment for those records.
    const { data: scanData } = await supabaseAdmin
      .from("scans")
      .select("ai_confidence_score")
      .eq("id", scan_id)
      .maybeSingle();
    // If scan not found in Supabase (local-only or cross-session), default confidence to 1
    // so the diagnostic threshold is not met and no extra Gemini call is made.

    // Check species_dictionary for both enrichment data and cached diagnostic data.
    // identify's background task races this call on Cache Miss — poll briefly to let it land
    // before deciding a Flash call is needed, avoiding a duplicate token spend.
    let cachedSpecies: {
      habitat_description: string | null;
      diagnostic_primary_rationale: string | null;
      diagnostic_lookalike_name: string | null;
      diagnostic_differentiators_json: string | null;
      gbif_taxon_key: number | null;
      kingdom: string | null;
      phylum: string | null;
      class: string | null;
      order: string | null;
      family: string | null;
      genus: string | null;
    } | null = null;

    const POLL_ATTEMPTS = 3;
    const POLL_DELAY_MS = 2000;
    for (let attempt = 0; attempt < POLL_ATTEMPTS; attempt++) {
      const { data } = await supabaseAdmin
        .from("species_dictionary")
        .select("habitat_description, diagnostic_primary_rationale, diagnostic_lookalike_name, diagnostic_differentiators_json, gbif_taxon_key, kingdom, phylum, class, order, family, genus")
        .eq("scientific_name", scientific_name)
        .maybeSingle();
      cachedSpecies = data;

      const settled = !!cachedSpecies?.habitat_description;
      if (settled) break; // background task landed — no Flash call needed

      if (attempt < POLL_ATTEMPTS - 1) {
        await new Promise((resolve) => setTimeout(resolve, POLL_DELAY_MS));
      }
    }

    const hasEnrichment = !!cachedSpecies?.habitat_description;
    const needsDiagnostic = ((scanData?.ai_confidence_score ?? 1) as number) < DIAGNOSTIC_THRESHOLD;
    const hasDiagnostic = !!cachedSpecies?.diagnostic_primary_rationale;

    // If everything is already stored, return immediately.
    if (hasEnrichment && (!needsDiagnostic || hasDiagnostic)) {
      console.log(`[⏱ BENCH] enrich_scan full cache hit in ${Date.now() - fnStart}ms`);
      return jsonResponse({ success: true, data: {
        habitat_description: cachedSpecies!.habitat_description,
        gbif_taxon_key: cachedSpecies!.gbif_taxon_key ?? null,
        diagnostic_comparison: hasDiagnostic ? {
          primary_match_rationale: cachedSpecies!.diagnostic_primary_rationale,
          confusing_lookalike_name: cachedSpecies!.diagnostic_lookalike_name,
          key_differentiators: JSON.parse(cachedSpecies!.diagnostic_differentiators_json ?? "[]"),
        } : null,
        taxonomy: {
          kingdom: cachedSpecies!.kingdom ?? "Unknown",
          phylum: cachedSpecies!.phylum ?? "Unknown",
          class: cachedSpecies!.class ?? "Unknown",
          order: cachedSpecies!.order ?? "Unknown",
          family: cachedSpecies!.family ?? "Unknown",
          genus: cachedSpecies!.genus ?? "Unknown",
        }
      }}, 200);
    }

    // Fire enrichment and diagnostic Flash calls in parallel for whatever is missing.
    const enrichmentPromise = hasEnrichment
      ? Promise.resolve(cachedSpecies)
      : (async () => {
          const result = await fetchStaticEncyclopedicData(_user, scientific_name);
          
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
            genus: result.taxonomy.genus
          };
        })();

    const diagnosticPromise = (!needsDiagnostic || hasDiagnostic)
      ? Promise.resolve(null)
      : fetchDiagnosticComparison(_user, scientific_name);

    try {
      const [enrichmentResult, diagnosticResult] = await Promise.all([enrichmentPromise, diagnosticPromise]);

      // Persist whatever was freshly generated.
      const persistOps: PromiseLike<unknown>[] = [];
      if (!hasEnrichment && enrichmentResult) {
        persistOps.push(
          supabaseAdmin.from("species_dictionary").update({
            habitat_description: (enrichmentResult as { habitat_description: string }).habitat_description,
          }).eq("scientific_name", scientific_name)
        );
      }
      if (!hasDiagnostic && diagnosticResult) {
        persistOps.push(
          supabaseAdmin.from("species_dictionary").update({
            diagnostic_primary_rationale: diagnosticResult.primary_match_rationale,
            diagnostic_lookalike_name: diagnosticResult.confusing_lookalike_name,
            diagnostic_differentiators_json: JSON.stringify(diagnosticResult.key_differentiators),
          }).eq("scientific_name", scientific_name)
        );
      }
      await Promise.allSettled(persistOps);

      console.log(`[⏱ BENCH] enrich_scan completed in ${Date.now() - fnStart}ms`);
      return jsonResponse({ success: true, data: {
        habitat_description: (enrichmentResult as { habitat_description: string } | null)?.habitat_description ?? null,
        gbif_taxon_key: cachedSpecies?.gbif_taxon_key ?? null,
        diagnostic_comparison: diagnosticResult ?? (hasDiagnostic ? {
          primary_match_rationale: cachedSpecies!.diagnostic_primary_rationale,
          confusing_lookalike_name: cachedSpecies!.diagnostic_lookalike_name,
          key_differentiators: JSON.parse(cachedSpecies!.diagnostic_differentiators_json ?? "[]"),
        } : null),
        taxonomy: {
          kingdom: (enrichmentResult as Record<string, string>)?.kingdom ?? cachedSpecies?.kingdom ?? "Unknown",
          phylum: (enrichmentResult as Record<string, string>)?.phylum ?? cachedSpecies?.phylum ?? "Unknown",
          class: (enrichmentResult as Record<string, string>)?.class ?? cachedSpecies?.class ?? "Unknown",
          order: (enrichmentResult as Record<string, string>)?.order ?? cachedSpecies?.order ?? "Unknown",
          family: (enrichmentResult as Record<string, string>)?.family ?? cachedSpecies?.family ?? "Unknown",
          genus: (enrichmentResult as Record<string, string>)?.genus ?? cachedSpecies?.genus ?? "Unknown",
        }
      }}, 200);

    } catch (genError) {
      console.error("AI generation failed for enrichment:", genError);
      return jsonResponse({ error: "AI processing error during enrichment. Please try again." }, 400);
    }
  })
);
