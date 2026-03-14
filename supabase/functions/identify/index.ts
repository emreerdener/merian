import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { encodeBase64 } from "jsr:@std/encoding@1/base64";

import { AwsClient } from "https://esm.sh/aws4fetch@1.0.20";
import {
  GoogleGenerativeAI,
  SchemaType,
} from "https://esm.sh/@google/generative-ai@0.24.1";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { evaluateAndProcessPayload } from "./moderation.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey);

serve(async (req: Request) => {
  // Handle CORS preflight requests
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    console.log("[1] Request received");

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing Authorization header" }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 401,
        },
      );
    }

    // Explicitly strip the 'Bearer ' prefix to prevent "Bearer Bearer <token>" extraction bugs
    const token = authHeader.replace(/^Bearer\s+/i, "").trim();

    // Validate the ES256 token directly against GoTrue natively bypassing the Edge Runtime
    const {
      data: { user },
      error: authError,
    } = await supabaseAdmin.auth.getUser(token);
    if (authError || !user) {
      console.error("Manual Auth Rejection:", authError);
      return new Response(
        JSON.stringify({ error: "Invalid or expired Session" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const body = await req.json();
    const {
      r2ObjectKey,
      user_id,
      gpsLatitude,
      gpsLongitude,
      gpsElevation,
      depthScaleText,
      weatherCondition,
      weatherTemperatureF,
      deviceLocale,
      currentMonth,
    } = body;

    if (!r2ObjectKey) {
      throw new Error("Missing r2ObjectKey.");
    }

    if (!user_id) {
      return new Response(
        JSON.stringify({ error: "Missing user_id parameter in body" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const R2_ACCOUNT_ID = Deno.env.get("R2_ACCOUNT_ID")!;
    const R2_BUCKET_NAME = Deno.env.get("R2_BUCKET_NAME")!;
    const R2_ACCESS_KEY_ID = Deno.env.get("R2_ACCESS_KEY_ID")!;
    const R2_SECRET_ACCESS_KEY = Deno.env.get("R2_SECRET_ACCESS_KEY")!;

    const aws = new AwsClient({
      accessKeyId: R2_ACCESS_KEY_ID,
      secretAccessKey: R2_SECRET_ACCESS_KEY,
      service: "s3",
      region: "auto",
    });

    const endpoint = `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`;
    const getUrl = `${endpoint}/${R2_BUCKET_NAME}/${r2ObjectKey}`;

    const r2Response = await aws.fetch(getUrl);
    if (!r2Response.ok) {
      throw new Error(
        `Failed to fetch image from R2: ${r2Response.statusText}`,
      );
    }

    const arrayBuffer = await r2Response.arrayBuffer();
    const base64Image = encodeBase64(new Uint8Array(arrayBuffer));

    let userTier = "free";
    const { data: existingUser } = await supabaseAdmin
      .from("users")
      .select("subscription_tier")
      .eq("id", user.id)
      .single();

    if (existingUser) {
      userTier = existingUser.subscription_tier;
    } else {
      // Ensure the Ghost User exists before proceeding
      await supabaseAdmin
        .from("users")
        .upsert(
          { id: user.id, subscription_tier: "free" },
          { onConflict: "id", ignoreDuplicates: true }
        );
    }

    const geminiApiKey = Deno.env.get("GEMINI_API_KEY")!;

    const genAI = new GoogleGenerativeAI(geminiApiKey);

    const systemInstruction = `You are Merian, the world's leading biological identification engine.
Your task is to accurately identify biological subjects. 
Crucial instructions:
1. Always check for liveness. If the subject is on a screen, in a book, or otherwise artificial, it is not a live capture.
2. Evaluate the 'is_invasive' flag strictly based on the provided GPS coordinates and ecological literature.
3. If your confidence_score is below 0.85 (85%), you MUST fill out the 'diagnostic_comparison' object.
4. You must write all 'insight_data' fields and the 'common_name' strictly in the target Locale provided in the context.
5. You must format the 'common_name' so that each word is capitalized in standard title case (e.g. "Bearded Iris" instead of "bearded iris").`;

    const targetModel = userTier === "pro" ? "gemini-2.5-pro" : "gemini-2.5-flash";
    console.log(`[2] Routing user ${user.id} (${userTier}) to ${targetModel}`);

    const model = genAI.getGenerativeModel({
      model: targetModel,
      systemInstruction: systemInstruction,
      generationConfig: {
        temperature: 0.1 // Strict logical routing, preventing biological hallucination
      }
    });

    const dynamicContext = `
      Environmental Context:
      - GPS Coordinates: Lat ${gpsLatitude ?? "Unknown"}, Long ${gpsLongitude ?? "Unknown"}
      - Elevation: ${gpsElevation != null ? `${gpsElevation} meters` : "Unknown"}
      - Depth Scale (Lidar): ${depthScaleText ?? "Unknown"}
      - Weather Condition: ${weatherCondition ?? "Unknown"}
      - Temperature: ${weatherTemperatureF != null ? `${weatherTemperatureF}°F` : "Unknown"}
      - Device Locale: ${deviceLocale ?? "en"}
      - Current Month: ${currentMonth ?? "Unknown"}
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
        blur_score: {
          type: SchemaType.NUMBER,
          description: "Float between 0.0 and 1.0 mapping the optical blur of the image, where 0.0 is perfectly sharp and 1.0 is extremely blurry/unusable.",
        },
        is_invasive: { type: SchemaType.BOOLEAN },
        iucn_red_list_status: {
          type: SchemaType.STRING,
          enum: ["not_evaluated", "data_deficient", "least_concern", "near_threatened", "vulnerable", "endangered", "critically_endangered", "extinct_in_the_wild", "extinct"],
          description: "Assess the IUCN Red List conservation status. Must exactly match one of the predefined enums.",
        },
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
            is_poisonous: { type: SchemaType.BOOLEAN },
          },
          required: [
            "description",
            "regional_status_rationale",
            "is_poisonous",
          ],
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
        "blur_score",
        "is_invasive",
        "iucn_red_list_status",
        "taxonomy",
        "insight_data",
      ],
    };

    const parts = [
      {
        inlineData: {
          mimeType: "image/jpeg",
          data: base64Image,
        },
      },
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
        // deno-lint-ignore no-explicit-any
        responseSchema: merianResponseSchema as any,
      },
    });

    const candidate = result.response.candidates?.[0];
    const finishReason = candidate?.finishReason;
    const safetyRatings = candidate?.safetyRatings;

    // supabaseAdmin already instantiated above

    const modResult = await evaluateAndProcessPayload(
      user.id,
      r2ObjectKey,
      finishReason,
      safetyRatings,
      userTier,
    );
    if (
      modResult.status === "SHADOWBANNED" ||
      modResult.status === "DELETED_WARNING"
    ) {
      throw new Error("Media flagged by safety moderation");
    }

    console.log("[3] Gemini Finished, Parsing JSON");
    const responseText = result.response.text();

    // Strip markdown formatting if Gemini hallucinates markdown blocks
    const cleanJsonString = responseText
      .replace(/```json/gi, "")
      .replace(/```/g, "")
      .trim();

    // Parse Gemini response to persist securely into the physical DB
    const parsedData = JSON.parse(cleanJsonString);

    const userId = user.id;
    if (userId) {
      let speciesId = null;

      // Upsert physical taxonomy object dictionary lookup cleanly
      if (
        parsedData.is_biological_subject &&
        parsedData.scientific_name &&
        parsedData.taxonomy
      ) {
        console.log(
          "[5] Upserting Dictionary with: ",
          parsedData.scientific_name,
        );
        console.log("[5.1] Enriching data for:", parsedData.scientific_name);
        let wikiUrl: string | null = null;
        let wikiExtract: string | null = null;
        let gbifKey: number | null = null;
        let combinedImageUrls: string | null = null;

        try {
          const fetchedUrls: string[] = [];

          const [gbifOutcome, wikiOutcome] = await Promise.allSettled([
            // Unauthenticated taxonomy fetch to global GBIF registry
            (async () => {
              let key: number | null = null;
              let urls: string[] = [];
              const gbifRes = await fetch(
                `https://api.gbif.org/v1/species/match?name=${encodeURIComponent(parsedData.scientific_name)}`,
                { signal: AbortSignal.timeout(2500) },
              );
              if (!gbifRes.ok) throw new Error("GBIF match lookup failed");
              const gbifJson = await gbifRes.json();
              key = gbifJson.usageKey || null;

              if (key) {
                const mediaRes = await fetch(
                  `https://api.gbif.org/v1/species/${key}/media`,
                  { signal: AbortSignal.timeout(2500) },
                );
                if (mediaRes.ok) {
                  const mediaJson = await mediaRes.json();
                  if (mediaJson.results && mediaJson.results.length > 0) {
                    urls = mediaJson.results
                      .filter(
                        (m: Record<string, string>) =>
                          m.type === "StillImage" && m.identifier,
                      )
                      .map((m: Record<string, string>) => m.identifier)
                      .slice(0, 5);
                  }
                }
              }
              return { key, urls };
            })(),

            // Unauthenticated lookup against Wikipedia's Desktop Page REST framework
            (async () => {
              const wikiRes = await fetch(
                `https://en.wikipedia.org/api/rest_v1/page/summary/${encodeURIComponent(parsedData.scientific_name.replace(/ /g, "_"))}`,
                { signal: AbortSignal.timeout(2500) },
              );
              if (!wikiRes.ok) throw new Error("Wikipedia lookup failed");
              const wikiJson = await wikiRes.json();
              const url = wikiJson.content_urls?.desktop?.page || null;
              const extract = wikiJson.extract || null;
              const img =
                wikiJson.originalimage?.source ||
                wikiJson.thumbnail?.source ||
                null;
              return { url, extract, img };
            })(),
          ]);

          if (gbifOutcome.status === "fulfilled") {
            gbifKey = gbifOutcome.value.key;
            fetchedUrls.push(...gbifOutcome.value.urls);
          }
          if (wikiOutcome.status === "fulfilled") {
            wikiUrl = wikiOutcome.value.url;
            wikiExtract = wikiOutcome.value.extract;
            if (wikiOutcome.value.img) {
              fetchedUrls.unshift(wikiOutcome.value.img);
            }
          }

          if (fetchedUrls.length > 0) {
            // Deduplicate explicitly and serialize
            combinedImageUrls = Array.from(new Set(fetchedUrls)).join(",");
          }
        } catch (e) {
          console.log("Data enrichment failed silently: ", e);
        }

        const { data: unifiedSpecies, error: upsertError } = await supabaseAdmin
          .from("species_dictionary")
          .upsert(
            {
              scientific_name: parsedData.scientific_name,
              common_names: { default: parsedData.common_name },
              kingdom: parsedData.taxonomy.kingdom,
              phylum: parsedData.taxonomy.phylum,
              class: parsedData.taxonomy.class,
              order: parsedData.taxonomy.order,
              family: parsedData.taxonomy.family,
              genus: parsedData.taxonomy.genus,
              descriptions: {
                  insight: parsedData.insight_data.description,
                  wikipedia: wikiExtract
              },
              is_poisonous: parsedData.insight_data.is_poisonous,
              wikipedia_url: wikiUrl,
              gbif_taxon_key: gbifKey,
              reference_image_url: combinedImageUrls,
              native_region: "Unknown",
              iucn_red_list_status: parsedData.iucn_red_list_status,
            },
            { onConflict: "scientific_name", ignoreDuplicates: true },
          )
          .select("id, wikipedia_url, reference_image_url, descriptions")
          .maybeSingle();

        if (upsertError) {
          console.error("Upsert failed: ", upsertError);
        }

        let resolvedSpecies = unifiedSpecies;

        // If 'ignoreDuplicates' kicks in during concurrent scans, Postgres returns NULL data.
        // We gracefully catch this here and execute a native read explicitly fetching the physical dictionary UUID.
        if (!resolvedSpecies && !upsertError) {
          console.log("[5.2] Duplicate Ignored. Fetching existing species natively...");
          const { data: existingSpecies, error: selectError } = await supabaseAdmin
            .from("species_dictionary")
            .select("id, wikipedia_url, reference_image_url, descriptions")
            .eq("scientific_name", parsedData.scientific_name)
            .single();

          if (selectError) {
             console.error("Failed to fetch existing species cleanly: ", selectError);
          } else {
             resolvedSpecies = existingSpecies;
          }
        }

        if (resolvedSpecies) {
          speciesId = resolvedSpecies.id;
          parsedData.wikipedia_url = resolvedSpecies.wikipedia_url;
          parsedData.wikipedia_extract = resolvedSpecies.descriptions?.wikipedia || wikiExtract;
          parsedData.reference_image_url = resolvedSpecies.reference_image_url;
        }
      }

      console.log("[6] Inserting Scan");
      // Finally natively bind the architectural map directly down to the Ghost User UUID
      const { data: scanData, error: scanInsertError } = await supabaseAdmin
        .from("scans")
        .insert({
          user_id: userId,
          species_id: speciesId,
          gps_lat_exact: gpsLatitude,
          gps_long_exact: gpsLongitude,
          gps_elevation: gpsElevation,
          ai_confidence_score: parsedData.confidence_score,
          blur_score: parsedData.blur_score,
          ecology_type: parsedData.ecology_type,
          is_invasive: parsedData.is_invasive,
          regional_status_rationale:
            parsedData.insight_data.regional_status_rationale,
          is_live_capture: parsedData.is_live_capture,
          weather_condition: weatherCondition,
          weather_temperature_f: weatherTemperatureF,
          image_storage_urls: modResult.publicUrl ? [modResult.publicUrl] : [],
        })
        .select("id")
        .single();

      if (scanInsertError) {
        console.error("Failed to insert scan:", scanInsertError);
      }

      if (scanData) {
        parsedData.scan_id = scanData.id;
      }
    } else {
      throw new Error(
        "Unauthorized: Invalid or missing User IDFV. Scans cannot be saved without a physical Device ID.",
      );
    }

    // Return standard nested JSON array to prevent iOS decoding double-escaped strings
    return new Response(JSON.stringify({ success: true, data: parsedData }), {
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
