import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { SchemaType, ResponseSchema } from "https://esm.sh/@google/generative-ai@0.24.1";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { fetchDiagnosticComparison } from "../_shared/diagnostic.ts";
import { createFlashModel, extractJson } from "../_shared/gemini.ts";
import { requireParams } from "../_shared/validation.ts";

const DIAGNOSTIC_THRESHOLD = 0.85;

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const fnStart = Date.now();
    const body = await req.json();
    const { scan_id, scientific_name } = body;

    const paramErr = requireParams(body, ["scan_id", "scientific_name"]);
    if (paramErr) return paramErr;

    // Verify ownership and fetch confidence score.
    const { data: scanData, error: scanError } = await supabaseAdmin
      .from("scans")
      .select("id, user_id, ai_confidence_score")
      .eq("id", scan_id)
      .eq("user_id", user.id)
      .maybeSingle();

    if (scanError || !scanData) {
      return jsonResponse({ error: "Forbidden: Scan not found or does not belong to the user." }, 403);
    }

    // Check species_dictionary for both enrichment data and cached diagnostic data.
    // identify's background task races this call on Cache Miss — poll briefly to let it land
    // before deciding a Flash call is needed, avoiding a duplicate token spend.
    let cachedSpecies: {
      habitat_description: string | null;
      global_distribution_regions: string[] | null;
      diagnostic_primary_rationale: string | null;
      diagnostic_lookalike_name: string | null;
      diagnostic_differentiators_json: string | null;
      gbif_taxon_key: number | null;
    } | null = null;

    const POLL_ATTEMPTS = 3;
    const POLL_DELAY_MS = 2000;
    for (let attempt = 0; attempt < POLL_ATTEMPTS; attempt++) {
      const { data } = await supabaseAdmin
        .from("species_dictionary")
        .select("habitat_description, global_distribution_regions, diagnostic_primary_rationale, diagnostic_lookalike_name, diagnostic_differentiators_json, gbif_taxon_key")
        .eq("scientific_name", scientific_name)
        .maybeSingle();
      cachedSpecies = data;

      const settled = !!(cachedSpecies?.habitat_description && (cachedSpecies?.global_distribution_regions?.length ?? 0) > 0);
      if (settled) break; // background task landed — no Flash call needed

      if (attempt < POLL_ATTEMPTS - 1) {
        await new Promise((resolve) => setTimeout(resolve, POLL_DELAY_MS));
      }
    }

    const hasEnrichment = !!(cachedSpecies?.habitat_description && (cachedSpecies?.global_distribution_regions?.length ?? 0) > 0);
    const needsDiagnostic = (scanData.ai_confidence_score ?? 1) < DIAGNOSTIC_THRESHOLD;
    const hasDiagnostic = !!cachedSpecies?.diagnostic_primary_rationale;

    // If everything is already stored, return immediately.
    if (hasEnrichment && (!needsDiagnostic || hasDiagnostic)) {
      console.log(`[⏱ BENCH] enrich_scan full cache hit in ${Date.now() - fnStart}ms`);
      return jsonResponse({ success: true, data: {
        habitat_description: cachedSpecies!.habitat_description,
        global_distribution_regions: cachedSpecies!.global_distribution_regions,
        gbif_taxon_key: cachedSpecies!.gbif_taxon_key ?? null,
        diagnostic_comparison: hasDiagnostic ? {
          primary_match_rationale: cachedSpecies!.diagnostic_primary_rationale,
          confusing_lookalike_name: cachedSpecies!.diagnostic_lookalike_name,
          key_differentiators: JSON.parse(cachedSpecies!.diagnostic_differentiators_json ?? "[]"),
        } : null,
      }}, 200);
    }

    const model = createFlashModel(
      "You are a world-class biologist. Provide encyclopedic habitat and global distribution for the provided scientific name. Keep descriptions concise and accessible.",
      600,
    );

    // Fire enrichment and diagnostic Flash calls in parallel for whatever is missing.
    const enrichmentPromise = hasEnrichment
      ? Promise.resolve(cachedSpecies)
      : (async () => {
          const enrichSchema: Record<string, unknown> = {
            type: SchemaType.OBJECT,
            properties: {
              habitat_description: { type: SchemaType.STRING },
              global_distribution_regions: {
                type: SchemaType.ARRAY,
                items: { type: SchemaType.STRING },
                description: "ISO-3166-2 region codes (e.g. 'US-TX', 'GB'). Lightweight strings only — no GeoJSON.",
              },
            },
            required: ["habitat_description", "global_distribution_regions"],
          };
          const result = await model.generateContent({
            contents: [{ role: "user", parts: [{ text: `Species enrichment for: ${scientific_name}` }] }],
            generationConfig: { responseMimeType: "application/json", responseSchema: enrichSchema as unknown as ResponseSchema },
          });
          return extractJson<{ habitat_description: string; global_distribution_regions: string[] }>(
            result.response.text(),
          );
        })();

    const diagnosticPromise = (!needsDiagnostic || hasDiagnostic)
      ? Promise.resolve(null)
      : fetchDiagnosticComparison(scientific_name);

    try {
      const [enrichmentResult, diagnosticResult] = await Promise.all([enrichmentPromise, diagnosticPromise]);

      // Persist whatever was freshly generated.
      const persistOps: PromiseLike<unknown>[] = [];
      if (!hasEnrichment && enrichmentResult) {
        persistOps.push(
          supabaseAdmin.from("species_dictionary").update({
            habitat_description: (enrichmentResult as { habitat_description: string }).habitat_description,
            global_distribution_regions: (enrichmentResult as { global_distribution_regions: string[] }).global_distribution_regions ?? [],
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
        global_distribution_regions: (enrichmentResult as { global_distribution_regions: string[] } | null)?.global_distribution_regions ?? null,
        gbif_taxon_key: cachedSpecies?.gbif_taxon_key ?? null,
        diagnostic_comparison: diagnosticResult ?? (hasDiagnostic ? {
          primary_match_rationale: cachedSpecies!.diagnostic_primary_rationale,
          confusing_lookalike_name: cachedSpecies!.diagnostic_lookalike_name,
          key_differentiators: JSON.parse(cachedSpecies!.diagnostic_differentiators_json ?? "[]"),
        } : null),
      }}, 200);

    } catch (genError) {
      console.error("AI generation failed for enrichment:", genError);
      return jsonResponse({ error: "AI processing error during enrichment. Please try again." }, 400);
    }
  })
);
