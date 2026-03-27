import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { GoogleGenerativeAI, SchemaType, ResponseSchema } from "https://esm.sh/@google/generative-ai@0.24.1";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";

const DIAGNOSTIC_THRESHOLD = 0.85;

const _geminiApiKey = Deno.env.get("GEMINI_API_KEY")!;
const _genAI = new GoogleGenerativeAI(_geminiApiKey);

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const fnStart = Date.now();
    const body = await req.json();
    const { scan_id, scientific_name } = body;

    if (!scan_id || !scientific_name) {
      return jsonResponse({ error: "Missing required parameters: scan_id and scientific_name are required." }, 400);
    }

    // Gate on Pro tier — free users' data is stored but not surfaced until they upgrade.
    const { data: userData } = await supabaseAdmin
      .from("users")
      .select("subscription_tier")
      .eq("id", user.id)
      .maybeSingle();

    if (!userData || userData.subscription_tier !== "pro") {
      return jsonResponse({ error: "Forbidden: Premium insights require a Pro subscription." }, 403);
    }

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

    // Check species_dictionary for both premium insights and cached diagnostic data.
    // identify's background task usually stores this before the client's request arrives.
    const { data: cachedSpecies } = await supabaseAdmin
      .from("species_dictionary")
      .select("habitat_description, global_distribution_regions, diagnostic_primary_rationale, diagnostic_lookalike_name, diagnostic_differentiators_json")
      .eq("scientific_name", scientific_name)
      .maybeSingle();

    const hasPremium = !!(cachedSpecies?.habitat_description && (cachedSpecies?.global_distribution_regions?.length ?? 0) > 0);
    const needsDiagnostic = (scanData.ai_confidence_score ?? 1) < DIAGNOSTIC_THRESHOLD;
    const hasDiagnostic = !!cachedSpecies?.diagnostic_primary_rationale;

    // If everything is already stored, return immediately.
    if (hasPremium && (!needsDiagnostic || hasDiagnostic)) {
      console.log(`[⏱ BENCH] enrich_scan full cache hit in ${Date.now() - fnStart}ms`);
      return jsonResponse({ success: true, data: {
        habitat_description: cachedSpecies!.habitat_description,
        global_distribution_regions: cachedSpecies!.global_distribution_regions,
        diagnostic_comparison: hasDiagnostic ? {
          primary_match_rationale: cachedSpecies!.diagnostic_primary_rationale,
          confusing_lookalike_name: cachedSpecies!.diagnostic_lookalike_name,
          key_differentiators: JSON.parse(cachedSpecies!.diagnostic_differentiators_json ?? "[]"),
        } : null,
      }}, 200);
    }

    const model = _genAI.getGenerativeModel({
      model: "gemini-2.5-flash",
      systemInstruction: "You are a world-class biologist. Provide encyclopedic habitat and global distribution for the provided scientific name. Keep descriptions concise and accessible.",
      generationConfig: { temperature: 0.1, maxOutputTokens: 600 },
    });

    // Fire premium and diagnostic Flash calls in parallel for whatever is missing.
    const premiumPromise = hasPremium
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
            contents: [{ role: "user", parts: [{ text: `Premium insights for: ${scientific_name}` }] }],
            generationConfig: { responseMimeType: "application/json", responseSchema: enrichSchema as unknown as ResponseSchema },
          });
          const text = result.response.text();
          const s = text.indexOf("{"), e = text.lastIndexOf("}");
          if (s === -1 || e === -1) throw new Error("Malformed premium response");
          return JSON.parse(text.substring(s, e + 1)) as { habitat_description: string; global_distribution_regions: string[] };
        })();

    const diagnosticPromise = (!needsDiagnostic || hasDiagnostic)
      ? Promise.resolve(null)
      : (async () => {
          const diagModel = _genAI.getGenerativeModel({
            model: "gemini-2.5-flash",
            systemInstruction: "You are a world-class biologist. Given a species scientific name, return a brief diagnostic comparison: the primary identification rationale, the most commonly confused lookalike species, and key differentiating features.",
            generationConfig: { temperature: 0.1, maxOutputTokens: 400 },
          });
          const diagSchema: Record<string, unknown> = {
            type: SchemaType.OBJECT,
            properties: {
              primary_match_rationale: { type: SchemaType.STRING },
              confusing_lookalike_name: { type: SchemaType.STRING },
              key_differentiators: { type: SchemaType.ARRAY, items: { type: SchemaType.STRING } },
            },
            required: ["primary_match_rationale", "confusing_lookalike_name", "key_differentiators"],
          };
          const result = await diagModel.generateContent({
            contents: [{ role: "user", parts: [{ text: `Diagnostic comparison for: ${scientific_name}` }] }],
            generationConfig: { responseMimeType: "application/json", responseSchema: diagSchema as unknown as ResponseSchema },
          });
          const text = result.response.text();
          const s = text.indexOf("{"), e = text.lastIndexOf("}");
          if (s === -1 || e === -1) throw new Error("Malformed diagnostic response");
          return JSON.parse(text.substring(s, e + 1)) as { primary_match_rationale: string; confusing_lookalike_name: string; key_differentiators: string[] };
        })();

    try {
      const [premiumResult, diagnosticResult] = await Promise.all([premiumPromise, diagnosticPromise]);

      // Persist whatever was freshly generated.
      const persistOps: PromiseLike<unknown>[] = [];
      if (!hasPremium && premiumResult) {
        persistOps.push(
          supabaseAdmin.from("species_dictionary").update({
            habitat_description: (premiumResult as { habitat_description: string }).habitat_description,
            global_distribution_regions: (premiumResult as { global_distribution_regions: string[] }).global_distribution_regions ?? [],
          }).eq("scientific_name", scientific_name)
        );
      }
      if (!hasDiagnostic && diagnosticResult) {
        persistOps.push(
          supabaseAdmin.from("scans").update({
            diagnostic_primary_rationale: diagnosticResult.primary_match_rationale,
            diagnostic_lookalike_name: diagnosticResult.confusing_lookalike_name,
            diagnostic_differentiators_json: JSON.stringify(diagnosticResult.key_differentiators),
          }).eq("id", scan_id)
        );
      }
      await Promise.allSettled(persistOps);

      console.log(`[⏱ BENCH] enrich_scan completed in ${Date.now() - fnStart}ms`);
      return jsonResponse({ success: true, data: {
        habitat_description: (premiumResult as { habitat_description: string } | null)?.habitat_description ?? null,
        global_distribution_regions: (premiumResult as { global_distribution_regions: string[] } | null)?.global_distribution_regions ?? null,
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
