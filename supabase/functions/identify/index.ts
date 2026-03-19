import { serve } from "@std/http/server.ts";
import { encodeBase64 } from "@std/encoding-base64";

import { AwsClient } from "aws4fetch";
import { GoogleGenerativeAI, SchemaType } from "@google/generative-ai";
import { createClient } from "@supabase/supabase-js";
import { evaluateAndProcessPayload } from "./moderation.ts";

import { corsHeaders } from "../_shared/cors.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey);

serve(async (req: Request) => {
  // Handle CORS preflight requests
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
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

    // Validate the session natively against GoTrue to handle ES256 tokens securely
    const { data: { user }, error: authError } = await supabaseAdmin.auth
      .getUser(authHeader.replace("Bearer ", ""));

    if (authError || !user) {
      console.error("Auth Rejection:", authError);
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
      imageBase64,
      user_id,
      gpsLatitude,
      gpsLongitude,
      gpsElevation,
      depthScaleText,
      weatherCondition,
      weatherTemperatureF,
      deviceLocale,
      currentMonth,
      semanticLocation,
      timeOfDay,
      isFlashFired,
      cameraPitchDegrees,
      compassHeading,
      relativeHumidity,
      uvIndex,
    } = body;

    if (!r2ObjectKey && !imageBase64) {
      throw new Error(
        "Missing structural boundary (neither r2ObjectKey nor imageBase64 provided).",
      );
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

    let base64Payload = "";

    if (imageBase64) {
      base64Payload = imageBase64;
    } else {
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

      // Phase 2: S3 Object Sizing Attack Protection - Limit to 5MB to prevent OOM
      const contentLengthStr = r2Response.headers.get("Content-Length");
      if (contentLengthStr) {
        const bytes = parseInt(contentLengthStr, 10);
        if (bytes > 5 * 1024 * 1024) {
          return new Response(
            JSON.stringify({
              error: "Payload Too Large: Exceeds 5MB boundary.",
            }),
            {
              status: 413,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            },
          );
        }
      }
      const arrayBuffer = await r2Response.arrayBuffer();
      base64Payload = encodeBase64(new Uint8Array(arrayBuffer));
    }

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
          { onConflict: "id", ignoreDuplicates: true },
        );
    }

    const geminiApiKey = Deno.env.get("GEMINI_API_KEY")!;

    const genAI = new GoogleGenerativeAI(geminiApiKey);

    const systemInstruction =
      `You are Merian, the world's leading biological identification engine.
Your task is to accurately identify biological subjects. 
Crucial instructions:
1. Always check for liveness. If the subject is on a screen, in a book, or otherwise artificial, it is not a live capture.
2. Evaluate the 'is_invasive' flag strictly based on the provided GPS coordinates and ecological literature.
3. If your confidence_score is below 0.85 (85%), you MUST fill out the 'diagnostic_comparison' object.
4. You must write all 'insight_data' fields and the 'common_name' strictly in the target Locale provided in the context.
5. You must format the 'common_name' so that each word is capitalized in standard title case (e.g. "Bearded Iris" instead of "bearded iris").`;

    const targetModel = userTier === "pro"
      ? "gemini-2.5-pro"
      : "gemini-2.5-flash";

    const model = genAI.getGenerativeModel({
      model: targetModel,
      systemInstruction: systemInstruction,
      generationConfig: {
        temperature: 0.1, // Strict logical routing, preventing biological hallucination
      },
    });

    const dynamicContext = `
      Environmental Context:
      - GPS Coordinates: Lat ${gpsLatitude ?? "Unknown"}, Long ${
      gpsLongitude ?? "Unknown"
    }
      - Elevation: ${
      gpsElevation != null ? `${gpsElevation} meters` : "Unknown"
    }
      - Depth Scale (Lidar): ${depthScaleText ?? "Unknown"}
      - Semantic Location: ${semanticLocation ?? "Unknown"}
      - Weather Condition: ${weatherCondition ?? "Unknown"}
      - Temperature: ${
      weatherTemperatureF != null ? `${weatherTemperatureF}°F` : "Unknown"
    }
      - Device Locale: ${deviceLocale ?? "en"}
      - Current Month: ${currentMonth ?? "Unknown"}
      - Time of Day: ${timeOfDay ?? "Unknown"}
      - Hardware Flash Fired: ${
      isFlashFired ? "Yes (Colors may be washed out or overexposed)" : "No"
    }
      - Camera Angle (Pitch): ${
      cameraPitchDegrees != null
        ? `${cameraPitchDegrees}° (Negative = looking down, Positive = looking up)`
        : "Unknown"
    }
      - Compass Heading: ${
      compassHeading != null ? `${compassHeading}°` : "Unknown"
    }
      - Relative Humidity: ${
      relativeHumidity != null
        ? (relativeHumidity * 100).toFixed(0) + "%"
        : "Unknown"
    }
      - UV Index: ${uvIndex ?? "Unknown"}
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
          description:
            "Float between 0.0 and 1.0 mapping the optical blur of the image, where 0.0 is perfectly sharp and 1.0 is extremely blurry/unusable.",
        },
        is_invasive: { type: SchemaType.BOOLEAN },
        iucn_red_list_status: {
          type: SchemaType.STRING,
          enum: [
            "not_evaluated",
            "data_deficient",
            "least_concern",
            "near_threatened",
            "vulnerable",
            "endangered",
            "critically_endangered",
            "extinct_in_the_wild",
            "extinct",
          ],
          description:
            "Assess the IUCN Red List conservation status. Must exactly match one of the predefined enums.",
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
            primary_match_rationale: { type: SchemaType.STRING },
            confusing_lookalike_name: { type: SchemaType.STRING },
            key_differentiators: {
              type: SchemaType.ARRAY,
              items: {
                type: SchemaType.OBJECT,
                properties: {
                  trait: { type: SchemaType.STRING },
                  subject_value: { type: SchemaType.STRING },
                  lookalike_value: { type: SchemaType.STRING },
                },
              },
            },
          },
          required: [
            "primary_match_rationale",
            "confusing_lookalike_name",
            "key_differentiators",
          ],
        },
        colors: {
          type: SchemaType.ARRAY,
          items: { type: SchemaType.STRING },
          description:
            "An array of 1-3 visually dominant colors present on the biological subject natively.",
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
        "colors",
      ],
    };

    const parts = [
      {
        inlineData: {
          mimeType: "image/jpeg",
          data: base64Payload,
        },
      },
      { text: dynamicContext },
      { text: "Perform the biological identification." },
    ];

    let finishReason: string | undefined;
    let safetyRatings: any[] | undefined;
    let responseText = "";
    try {
        const result = await model.generateContent({
            contents: [{ role: "user", parts }],
            generationConfig: {
                responseMimeType: "application/json",
                // deno-lint-ignore no-explicit-any
                responseSchema: merianResponseSchema as any,
            },
        });
        const candidate = result.response.candidates?.[0];
        finishReason = candidate?.finishReason;
        safetyRatings = candidate?.safetyRatings;
        responseText = result.response.text();
    } catch (genError) {
        console.error("Gemini Critical Extraction Failure:", genError);
        return new Response(JSON.stringify({ error: `Gemini Validation Error: ${(genError as Error).message}` }), { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 400 });
    }

    // Strip markdown formatting if Gemini hallucinates markdown blocks
    const cleanJsonString = responseText
      .replace(/```json/gi, "")
      .replace(/```/g, "")
      .trim();

    const parsedData = JSON.parse(cleanJsonString);

    const userId = user.id;
    if (!userId) {
      throw new Error(
        "Unauthorized: Invalid or missing User IDFV. Scans cannot be saved without a physical Device ID.",
      );
    }

    // Explicitly generate the physical UUID mapping asynchronously here skipping the synchronous PostgreSQL wait limits completely.
    const generatedScanId = crypto.randomUUID();
    parsedData.scan_id = generatedScanId;

    const backgroundTask = (async () => {
      try {
        const modResult = await evaluateAndProcessPayload(
          user.id,
          r2ObjectKey,
          imageBase64,
          finishReason,
          safetyRatings,
          userTier,
        );
        if (
          modResult.status === "SHADOWBANNED" ||
          modResult.status === "DELETED_WARNING"
        ) {
          console.error(
            "Media flagged by safety moderation. Halting background data ingestion.",
          );
          return;
        }
        let speciesId = null;

        // Upsert physical taxonomy object dictionary lookup cleanly
        if (
          parsedData.is_biological_subject &&
          parsedData.scientific_name &&
          parsedData.taxonomy
        ) {
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
                  `https://api.gbif.org/v1/species/match?name=${
                    encodeURIComponent(parsedData.scientific_name)
                  }`,
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
                  `https://en.wikipedia.org/api/rest_v1/page/summary/${
                    encodeURIComponent(
                      parsedData.scientific_name.replace(/ /g, "_"),
                    )
                  }`,
                  { signal: AbortSignal.timeout(2500) },
                );
                if (!wikiRes.ok) throw new Error("Wikipedia lookup failed");
                const wikiJson = await wikiRes.json();
                const url = wikiJson.content_urls?.desktop?.page || null;
                const extract = wikiJson.extract || null;
                const img = wikiJson.originalimage?.source ||
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

          const { data: unifiedSpecies, error: upsertError } =
            await supabaseAdmin
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
                    wikipedia: wikiExtract,
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
            const { data: existingSpecies, error: selectError } =
              await supabaseAdmin
                .from("species_dictionary")
                .select("id, wikipedia_url, reference_image_url, descriptions")
                .eq("scientific_name", parsedData.scientific_name)
                .single();

            if (selectError) {
              console.error(
                "Failed to fetch existing species cleanly: ",
                selectError,
              );
            } else {
              resolvedSpecies = existingSpecies;
            }
          }

          if (resolvedSpecies) {
            speciesId = resolvedSpecies.id;
            parsedData.wikipedia_url = resolvedSpecies.wikipedia_url;
            parsedData.wikipedia_extract =
              resolvedSpecies.descriptions?.wikipedia || wikiExtract;
            parsedData.reference_image_url =
              resolvedSpecies.reference_image_url;
          }
        }

        // Finally natively bind the architectural map directly down to the Ghost User UUID
        const { data: scanData, error: scanInsertError } = await supabaseAdmin
          .from("scans")
          .insert({
            id: generatedScanId,
            user_id: userId,
            species_id: speciesId,
            gps_lat_exact: gpsLatitude,
            gps_long_exact: gpsLongitude,
            gps_elevation: gpsElevation,
            ai_confidence_score: parsedData.confidence_score,
            blur_score: parsedData.blur_score,
            ecology_type: parsedData.ecology_type,
            is_invasive: parsedData.is_invasive,
            colors: parsedData.colors,
            regional_status_rationale:
              parsedData.insight_data.regional_status_rationale,
            is_live_capture: parsedData.is_live_capture,
            weather_condition: weatherCondition,
            weather_temperature_f: weatherTemperatureF,
            semantic_location: semanticLocation,
            device_locale: deviceLocale,
            current_month: currentMonth,
            time_of_day: timeOfDay,
            is_flash_fired: isFlashFired,
            camera_pitch_degrees: cameraPitchDegrees,
            compass_heading: compassHeading,
            relative_humidity: relativeHumidity,
            uv_index: uvIndex,
            depth_scale_text: depthScaleText,
            image_storage_urls: modResult.publicUrl
              ? [modResult.publicUrl]
              : [],
          })
          .select("id")
          .single();

        if (scanInsertError) {
          console.error("Failed to insert scan:", scanInsertError);
        }

        if (scanData) {
          // Redundant safely omitted since we pregenerated `parsedData.scan_id` dynamically prior!
        }
    } catch (e) {
        console.error("Background AI ingestion completely failed:", e);
      }
    })();

    // Supabase Edge Functions native execution handler 
    // deno-lint-ignore no-explicit-any
    if (typeof (globalThis as any).EdgeRuntime === "object" && typeof (globalThis as any).EdgeRuntime.waitUntil === "function") {
      // deno-lint-ignore no-explicit-any
      (globalThis as any).EdgeRuntime.waitUntil(backgroundTask);
    } else {
      // Graceful fallback for local development or Deno Core isolated workers
      backgroundTask.catch(console.error);
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
