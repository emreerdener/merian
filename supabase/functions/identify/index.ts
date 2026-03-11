import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

import { AwsClient } from "https://esm.sh/aws4fetch@1.0.17";
import {
  GoogleGenerativeAI,
  SchemaType,
} from "https://esm.sh/@google/generative-ai@0.24.1";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
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

    const {
      r2ObjectKey,
      user_id,
      gpsLatitude,
      gpsLongitude,
      gpsElevation,
      depthScaleText,
      weatherCondition,
      weatherTemperatureF,
    } = await req.json();

    if (!r2ObjectKey) {
      throw new Error("Missing r2ObjectKey.");
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing Authorization header" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 401 }
      );
    }

    // 1. Validate the JWT utilizing the Anon Key + Injected Auth Header natively
    const supabaseAuthClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { global: { headers: { Authorization: authHeader } } }
    );

    const {
      data: { user },
      error: authError,
    } = await supabaseAuthClient.auth.getUser();

    if (authError || !user) {
      console.error("Auth Rejection:", authError);
      return new Response(
        JSON.stringify({ error: "Invalid or expired Session" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 401 }
      );
    }

    if (!user_id) {
       return new Response(
           JSON.stringify({ error: "Missing user_id parameter in body" }), 
           { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
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

    // Server-side robust encoded stream to prevent OOM
    const geminiApiKey = Deno.env.get("GEMINI_API_KEY")!;
    const uploadRes = await fetch(
      `https://generativelanguage.googleapis.com/upload/v1beta/files?key=${geminiApiKey}`,
      {
        method: "POST",
        headers: {
          "X-Goog-Upload-Command": "start, upload, finalize",
          "X-Goog-Upload-Header-Content-Type": "image/jpeg",
          "X-Goog-Upload-Header-Content-Length":
            r2Response.headers.get("content-length") || "",
          "Content-Type": "image/jpeg",
        },
        body: r2Response.body,
        duplex: "half",
      },
    );

    if (!uploadRes.ok) {
      throw new Error(`Gemini File Upload Failed: ${uploadRes.statusText}`);
    }

    const uploadData = await uploadRes.json();
    const googleFileUri = uploadData.file.uri;

    const genAI = new GoogleGenerativeAI(geminiApiKey);

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
      - Elevation: ${gpsElevation != null ? `${gpsElevation} meters` : "Unknown"}
      - Depth Scale (Lidar): ${depthScaleText ?? "Unknown"}
      - Weather Condition: ${weatherCondition ?? "Unknown"}
      - Temperature: ${weatherTemperatureF != null ? `${weatherTemperatureF}°F` : "Unknown"}
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
        "is_invasive",
        "taxonomy",
        "insight_data",
      ],
    };

    const parts = [
      {
        fileData: {
          mimeType: "image/jpeg",
          fileUri: googleFileUri,
        },
      },
      { text: dynamicContext },
      { text: "Perform the biological identification." },
    ];

    console.log(
      "[2] Extracted body, calling Gemini. ServiceKey length:",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.length,
    );

    let result;
    try {
      result = await model.generateContent({
        contents: [{ role: "user", parts }],
        generationConfig: {
          responseMimeType: "application/json",
          // deno-lint-ignore no-explicit-any
          responseSchema: merianResponseSchema as any,
        },
      });
    } finally {
      try {
        const fileName = uploadData.file.name.replace("files/", "");
        await fetch(
          `https://generativelanguage.googleapis.com/v1beta/files/${fileName}?key=${geminiApiKey}`,
          { method: "DELETE" },
        );
      } catch (e) {
        console.error("Failed to delete temporary Google file", e);
      }
    }

    const candidate = result.response.candidates?.[0];
    const finishReason = candidate?.finishReason;
    const safetyRatings = candidate?.safetyRatings;

    // supabaseAdmin already instantiated above

    // Ensure the Ghost User exists before potentially issuing an abuse strike in moderation
    await supabaseAdmin
      .from("users")
      .upsert(
        { id: user_id, subscription_tier: "free" },
        { onConflict: "id", ignoreDuplicates: true },
      );

    const modResult = await evaluateAndProcessPayload(
      user_id,
      r2ObjectKey,
      finishReason,
      safetyRatings,
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

    const userId = user_id;
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
              const img =
                wikiJson.originalimage?.source ||
                wikiJson.thumbnail?.source ||
                null;
              return { url, img };
            })(),
          ]);

          if (gbifOutcome.status === "fulfilled") {
            gbifKey = gbifOutcome.value.key;
            fetchedUrls.push(...gbifOutcome.value.urls);
          }
          if (wikiOutcome.status === "fulfilled") {
            wikiUrl = wikiOutcome.value.url;
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
              descriptions: { insight: parsedData.insight_data.description },
              is_poisonous: parsedData.insight_data.is_poisonous,
              wikipedia_url: wikiUrl,
              gbif_taxon_key: gbifKey,
              reference_image_url: combinedImageUrls,
              native_region: "Unknown",
            },
            { onConflict: "scientific_name", ignoreDuplicates: true },
          )
          .select("id, wikipedia_url, reference_image_url")
          .single();

        if (upsertError) {
          console.error("Upsert failed: ", upsertError);
        }

        if (unifiedSpecies) {
          speciesId = unifiedSpecies.id;
          parsedData.wikipedia_url = unifiedSpecies.wikipedia_url;
          parsedData.reference_image_url = unifiedSpecies.reference_image_url;
        }
      }

      console.log("[6] Inserting Scan");
      // Finally natively bind the architectural map directly down to the Ghost User UUID
      await supabaseAdmin.from("scans").insert({
        user_id: userId,
        species_id: speciesId,
        gps_lat_exact: gpsLatitude,
        gps_long_exact: gpsLongitude,
        gps_elevation: gpsElevation,
        ai_confidence_score: parsedData.confidence_score,
        ecology_type: parsedData.ecology_type,
        is_invasive: parsedData.is_invasive,
        regional_status_rationale:
          parsedData.insight_data.regional_status_rationale,
        is_live_capture: parsedData.is_live_capture,
        weather_condition: weatherCondition,
        weather_temperature_f: weatherTemperatureF,
        image_storage_urls: modResult.publicUrl ? [modResult.publicUrl] : [],
      });
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
