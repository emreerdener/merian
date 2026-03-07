import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import {
  GoogleGenerativeAI,
  SchemaType,
} from "https://esm.sh/@google/generative-ai@0.24.1";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req: Request) => {
  // Handle CORS preflight requests
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    console.log("[1] Request received");
    const {
      geminiFileUri,
      gpsLatitude,
      gpsLongitude,
      depthScaleText,
      weatherCondition,
    } = await req.json();

    if (!geminiFileUri) {
      throw new Error("Missing geminiFileUri.");
    }

    const genAI = new GoogleGenerativeAI(Deno.env.get("GEMINI_API_KEY")!);

    const systemInstruction = `You are Merian, the world's leading biological identification engine.
Your task is to accurately identify biological subjects. 
Crucial instructions:
1. Always check for liveness. If the subject is on a screen, in a book, or otherwise artificial, it is not a live capture.
2. Evaluate the 'is_invasive' flag strictly based on the provided GPS coordinates and ecological literature.
3. If your confidence_score is below 0.85 (85%), you MUST fill out the 'diagnostic_comparison' object.`;

    const model = genAI.getGenerativeModel({
      model: "gemini-2.5-flash",
      systemInstruction: systemInstruction,
    });

    const dynamicContext = `
      Environmental Context:
      - GPS Coordinates: Lat ${gpsLatitude ?? "Unknown"}, Long ${gpsLongitude ?? "Unknown"}
      - Depth Scale (Lidar): ${depthScaleText ?? "Unknown"}
      - Weather Condition: ${weatherCondition ?? "Unknown"}
    `;

    const merianResponseSchema = {
      type: SchemaType.OBJECT,
      properties: {
        is_biological_subject: { type: SchemaType.BOOLEAN },
        is_live_capture: { type: SchemaType.BOOLEAN },
        ecology_type: {
          type: SchemaType.STRING,
          enum: ["wild", "urban", "domesticated", "unknown"],
          description: "Identify the ecological origin of the subject.",
        },
        scientific_name: { type: SchemaType.STRING },
        common_name: { type: SchemaType.STRING },
        confidence_score: {
          type: SchemaType.NUMBER,
          description: "Float between 0.0 and 1.0",
        },
        is_invasive: { type: SchemaType.BOOLEAN },
        taxonomy: {
          type: SchemaType.OBJECT,
          properties: {
            kingdom: { type: SchemaType.STRING },
            phylum: { type: SchemaType.STRING },
            class: { type: SchemaType.STRING },
            order: { type: SchemaType.STRING },
            family: { type: SchemaType.STRING },
            genus: { type: SchemaType.STRING },
          },
          required: ["kingdom", "phylum", "class", "order", "family", "genus"],
        },
        insight_data: {
          type: SchemaType.OBJECT,
          properties: {
            description: { type: SchemaType.STRING },
            regional_status_rationale: { type: SchemaType.STRING },
          },
          required: ["description", "regional_status_rationale"],
        },
        diagnostic_comparison: {
          type: SchemaType.OBJECT,
          nullable: true,
          properties: {
            similar_species: { type: SchemaType.STRING },
            distinguishing_features: { type: SchemaType.STRING },
          },
          required: ["similar_species", "distinguishing_features"],
        },
      },
      required: [
        "is_biological_subject",
        "is_live_capture",
        "ecology_type",
        "scientific_name",
        "common_name",
        "confidence_score",
        "is_invasive",
        "taxonomy",
        "insight_data",
      ],
    };

    const parts = [
      { fileData: { mimeType: "image/jpeg", fileUri: geminiFileUri } },
      { text: dynamicContext },
      { text: "Perform the biological identification." },
    ];

    console.log(
      "[2] Extracted body, calling Gemini. ServiceKey length:",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.length,
    );

    const result = await model.generateContent({
      contents: [{ role: "user", parts }],
      generationConfig: {
        responseMimeType: "application/json",
        responseSchema: merianResponseSchema as any,
      },
    });

    console.log("[3] Gemini Finished, Parsing JSON");
    const responseText = result.response.text();

    // Parse Gemini response to persist securely into the physical DB
    const parsedData = JSON.parse(responseText);

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const authHeader = req.headers.get("Authorization");

    const supabaseClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader || "" } },
    });

    // Admin client strictly explicitly to push securely into the global read-only species dictionary natively
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey);

    const token = authHeader?.replace("Bearer ", "") ?? "";
    const { data: userData, error: _ } =
      await supabaseClient.auth.getUser(token);
    console.log("[4] Checking User Identity:", {
      id: userData?.user?.id,
      err: _,
    });

    if (userData && userData.user) {
      const userId = userData.user.id;
      let speciesId = null;

      // Upsert physical taxonomy object dictionary lookup cleanly
      if (parsedData.scientific_name) {
        console.log(
          "[5] Upserting Dictionary with: ",
          parsedData.scientific_name,
        );
        const { data: existingSpecies, error: selectError } =
          await supabaseAdmin
            .from("species_dictionary")
            .select("id, wikipedia_url, reference_image_url")
            .eq("scientific_name", parsedData.scientific_name)
            .single();

        if (existingSpecies) {
          speciesId = existingSpecies.id;
          parsedData.wikipedia_url = existingSpecies.wikipedia_url;
          parsedData.reference_image_url = existingSpecies.reference_image_url;
        } else {
          console.log("[5.1] Enriching data for:", parsedData.scientific_name);
          let wikiUrl: string | null = null;
          let gbifKey: number | null = null;
          let combinedImageUrls: string | null = null;

          try {
            let fetchedUrls: string[] = [];
            // Unauthenticated taxonomy fetch to global GBIF registry
            const gbifRes = await fetch(
              `https://api.gbif.org/v1/species/match?name=${encodeURIComponent(parsedData.scientific_name)}`,
            );
            if (gbifRes.ok) {
              const gbifJson = await gbifRes.json();
              gbifKey = gbifJson.usageKey || null;
              if (gbifKey) {
                const mediaRes = await fetch(
                  `https://api.gbif.org/v1/species/${gbifKey}/media`,
                );
                if (mediaRes.ok) {
                  const mediaJson = await mediaRes.json();
                  if (mediaJson.results && mediaJson.results.length > 0) {
                    fetchedUrls = mediaJson.results
                      .filter(
                        (m: any) => m.type === "StillImage" && m.identifier,
                      )
                      .map((m: any) => m.identifier)
                      .slice(0, 5);
                  }
                }
              }
            }

            // Unauthenticated lookup against Wikipedia's Desktop Page REST framework
            const wikiRes = await fetch(
              `https://en.wikipedia.org/api/rest_v1/page/summary/${encodeURIComponent(parsedData.scientific_name.replace(/ /g, "_"))}`,
            );
            if (wikiRes.ok) {
              const wikiJson = await wikiRes.json();
              wikiUrl = wikiJson.content_urls?.desktop?.page || null;
              let wikiImg =
                wikiJson.originalimage?.source ||
                wikiJson.thumbnail?.source ||
                null;
              if (wikiImg) {
                fetchedUrls.unshift(wikiImg);
              }
            }
            if (fetchedUrls.length > 0) {
              // Deduplicate explicitly and serialize
              combinedImageUrls = Array.from(new Set(fetchedUrls)).join(",");
            }
          } catch (e) {
            console.log("Data enrichment failed silently: ", e);
          }

          const { data: newSpecies, error: insertError } = await supabaseAdmin
            .from("species_dictionary")
            .insert({
              scientific_name: parsedData.scientific_name,
              common_names: { default: parsedData.common_name },
              kingdom: parsedData.taxonomy.kingdom,
              phylum: parsedData.taxonomy.phylum,
              class: parsedData.taxonomy.class,
              order: parsedData.taxonomy.order,
              family: parsedData.taxonomy.family,
              genus: parsedData.taxonomy.genus,
              descriptions: { insight: parsedData.insight_data.description },
              wikipedia_url: wikiUrl,
              gbif_taxon_key: gbifKey,
              reference_image_url: combinedImageUrls,
              native_region: "Unknown",
            })
            .select("id")
            .single();
          if (newSpecies) {
            speciesId = newSpecies.id;
          }
          parsedData.wikipedia_url = wikiUrl;
          parsedData.reference_image_url = combinedImageUrls;
        }
      }

      console.log("[6] Inserting Scan");
      // Finally natively bind the architectural map directly down to the Ghost User UUID
      await supabaseClient.from("scans").insert({
        user_id: userId,
        species_id: speciesId,
        gps_lat_exact: gpsLatitude,
        gps_long_exact: gpsLongitude,
        ai_confidence_score: parsedData.confidence_score,
        ecology_type: parsedData.ecology_type,
        is_invasive: parsedData.is_invasive,
        regional_status_rationale:
          parsedData.insight_data.regional_status_rationale,
        is_live_capture: parsedData.is_live_capture,
        weather_condition: weatherCondition,
      });
    } else {
      throw new Error(
        "Unauthorized: Invalid or missing User JWT. Scans cannot be saved without a Ghost Session.",
      );
    }

    // Wrap the resulting taxonomy cleanly up in the JSON shell required strictly by the Native Swift Codable mappings
    const finalResponseText = JSON.stringify(parsedData);
    return new Response(JSON.stringify({ result: finalResponseText }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });
  } catch (error) {
    console.error("FATAL ERROR IN EDGE LAYER:", error);
    return new Response(JSON.stringify({ error: (error as Error).message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    });
  }
});
