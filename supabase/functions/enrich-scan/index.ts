import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { GoogleGenerativeAI, SchemaType, ResponseSchema } from "https://esm.sh/@google/generative-ai@0.24.1";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";

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

    // Explicitly verify the user owns the scan they are trying to enrich
    const { data: scanData, error: scanError } = await supabaseAdmin
      .from("scans")
      .select("id, user_id")
      .eq("id", scan_id)
      .eq("user_id", user.id)
      .maybeSingle();

    if (scanError || !scanData) {
      return jsonResponse({ error: "Forbidden: Scan not found or does not belong to the user." }, 403);
    }

    // Check species_dictionary before calling AI — the identify function writes habitat and
    // distribution on every Cache Miss regardless of tier, so this data is usually already present.
    const { data: cachedSpecies } = await supabaseAdmin
      .from("species_dictionary")
      .select("habitat_description, global_distribution_regions")
      .eq("scientific_name", scientific_name)
      .maybeSingle();

    if (cachedSpecies?.habitat_description && (cachedSpecies?.global_distribution_regions?.length ?? 0) > 0) {
      console.log(`[⏱ BENCH] enrich_scan cache hit in ${Date.now() - fnStart}ms`);
      return jsonResponse({ success: true, data: {
        habitat_description: cachedSpecies.habitat_description,
        global_distribution_regions: cachedSpecies.global_distribution_regions,
      }}, 200);
    }

    const systemInstruction = `You are a world-class biologist. Provide encyclopedic identification traits, habitat, and global distribution for the provided scientific name. Keep descriptions concise and accessible.`;
    
    // Using gemini-2.5-flash for text-only rapid inference to keep cost at $0.000003 per scan
    const model = _genAI.getGenerativeModel({
      model: "gemini-2.5-flash",
      systemInstruction: systemInstruction,
      generationConfig: {
        temperature: 0.1,
        maxOutputTokens: 1500,
      },
    });

    const enrichSchema: Record<string, unknown> = {
      type: SchemaType.OBJECT,
      properties: {
        habitat_description: { type: SchemaType.STRING, description: "A description of the natural habitat where this species is typically found." },
        global_distribution_regions: { 
          type: SchemaType.ARRAY, 
          items: { type: SchemaType.STRING },
          description: "An array of standardized ISO-3166-2 region codes (e.g. 'US-TX', 'GB') where this species is natively found. Must be lightweight strings, do NOT generate GeoJSON coordinates."
        }
      },
      required: ["habitat_description", "global_distribution_regions"]
    };

    const prompt = `Generate premium insights for the species: ${scientific_name}`;

    try {
      const result = await model.generateContent({
        contents: [{ role: "user", parts: [{ text: prompt }] }],
        generationConfig: {
          responseMimeType: "application/json",
          responseSchema: enrichSchema as unknown as ResponseSchema,
        },
      });

      const responseText = result.response.text();
      
      const startIndex = responseText.indexOf('{');
      const endIndex = responseText.lastIndexOf('}');

      if (startIndex === -1 || endIndex === -1 || startIndex > endIndex) {
          throw new Error("Malformed AI response");
      }
      
      const cleanJsonString = responseText.substring(startIndex, endIndex + 1);
      const parsedData = JSON.parse(cleanJsonString);



      const { error: speciesUpdateError } = await supabaseAdmin
        .from("species_dictionary")
        .update({
          habitat_description: parsedData.habitat_description,
          global_distribution_regions: parsedData.global_distribution_regions || [],
        })
        .eq("scientific_name", scientific_name);
        
      if (speciesUpdateError) {
          console.error("Failed to update species dictionary with habitat info:", speciesUpdateError);
      }

      console.log(`[⏱ BENCH] enrich_scan completed in ${Date.now() - fnStart}ms`);
      return jsonResponse({ success: true, data: parsedData }, 200);

    } catch (genError) {
      console.error("AI generation failed for enrichment:", genError);
      return jsonResponse({ error: "AI processing error during enrichment. Please try again." }, 400);
    }
  })
);
