import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { encodeBase64 } from "https://deno.land/std@0.224.0/encoding/base64.ts";

import { GoogleGenerativeAI, SchemaType, SafetyRating } from "https://esm.sh/@google/generative-ai@0.24.1";
import { evaluateAndProcessPayload } from "./moderation.ts";
import { getR2Config } from "../_shared/aws.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const body = await req.json();
    const {
      r2ObjectKeys,
      imageBase64s,
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
      timestamp,
    } = body;

    if ((!r2ObjectKeys || r2ObjectKeys.length === 0) && (!imageBase64s || imageBase64s.length === 0)) {
      throw new Error("Missing structural boundary (neither r2ObjectKeys nor imageBase64s provided).");
    }

    if (r2ObjectKeys && r2ObjectKeys.length > 0) {
      // CRITICAL SEC FIX: Prevent malicious actors from submitting spoofed payloads extracting foreign blobs.
      // If `imageBase64s` is present, the key is strictly used for destination filename creation and is securely force-prefixed in `moderation.ts`!
      for (const r2ObjectKey of r2ObjectKeys) {
          if ((!imageBase64s || imageBase64s.length === 0) && !r2ObjectKey.startsWith(`staging/${user.id}/`)) {
            console.error(`IDOR MISMATCH: r2ObjectKey was ${r2ObjectKey} but user.id is ${user.id}`);
            return jsonResponse({ error: "SECURITY VIOLATION (IDOR): Attempting to scrape foreign r2ObjectKey bounds." }, 403);
          }
          if (r2ObjectKey.includes("..")) {
            return jsonResponse({ error: "SECURITY VIOLATION: Path traversal detected inside payload boundaries." }, 400);
          }
      }
    }

    if (!user_id) {
      return jsonResponse({ error: "Missing user_id parameter in body" }, 400);
    }

    const base64Payloads: string[] = [];

    if (imageBase64s && imageBase64s.length > 0) {
      base64Payloads.push(...imageBase64s);
    } else if (r2ObjectKeys && r2ObjectKeys.length > 0) {
      const { s3Client, bucketName, endpoint } = getR2Config();
      
      const r2Responses = await Promise.allSettled(
        r2ObjectKeys.map((key: string) => s3Client.fetch(`${endpoint}/${bucketName}/${key}`))
      );
      
      let totalBytes = 0;
      const validResponses: Response[] = [];
      
      for (const result of r2Responses) {
          if (result.status === "rejected") {
              throw new Error(`Failed to execute concurrent R2 fetch request.`);
          }
          const r2Response = result.value as Response;
          if (!r2Response.ok) {
              throw new Error(`Failed to fetch an image from R2: ${r2Response.statusText}`);
          }
          
          // Phase 2: S3 Object Sizing Attack Protection - Limit dynamically to 5MB to prevent OOM cumulatively
          const contentLengthStr = r2Response.headers.get("Content-Length");
          if (contentLengthStr) {
             totalBytes += parseInt(contentLengthStr, 10);
          }
          validResponses.push(r2Response);
      }
      
      if (totalBytes > 5 * 1024 * 1024) {
          return jsonResponse({ error: "Payload Too Large: Combined payload inherently exceeds 5MB boundary natively locking Deno heap." }, 413);
      }
      
      // Map safe cumulative physical arrays into memory simultaneously
      const arrayBuffers = await Promise.all(validResponses.map(res => res.arrayBuffer()));
      for (const arrayBuffer of arrayBuffers) {
          base64Payloads.push(encodeBase64(new Uint8Array(arrayBuffer)));
      }
    }

    let userTier = "free";
    const { data: existingUser } = await supabaseAdmin
      .from("users")
      .select("subscription_tier")
      .eq("id", user!.id)
      .maybeSingle();

    if (existingUser) {
      userTier = existingUser.subscription_tier;
    } else {
      // Ensure the Ghost User exists before proceeding
      await supabaseAdmin
        .from("users")
        .upsert(
          { id: user!.id, subscription_tier: "free" },
          { onConflict: "id", ignoreDuplicates: true },
        );
    }

    const geminiApiKey = Deno.env.get("GEMINI_API_KEY")!;

    const genAI = new GoogleGenerativeAI(geminiApiKey);

    const systemInstruction = `Merian AI: Identify biology. 1) Enforce liveness check. 2) Evaluate is_invasive based on GPS. 3) Output common_name in strict title case. 4) CRITICAL: Evaluate the combined visual context of all provided images organically to compute the absolute most accurate identification. 5) CRITICAL: If the images display multiple distinct biological species, strictly identify exactly ONE primary species (the most prominent or centered subject in the first image) and briefly mention the secondary species within the insight_data description. 6) CRITICAL: If the subject is non-biological (is_biological_subject = false), you MUST completely OMIT all taxonomy, insight_data, diagnostic_comparison, iucn_red_list_status, is_invasive, ecology_type, scientific_name, and colors fields to conserve output tokens.`;

    const targetModel = userTier === "pro"
      ? "gemini-2.5-pro"
      : "gemini-2.5-flash";

    const model = genAI.getGenerativeModel({
      model: targetModel,
      systemInstruction: systemInstruction,
      generationConfig: {
        temperature: 0.1, // Strict logical routing, preventing biological hallucination
        maxOutputTokens: 800, // Forcefully cap thinking tokens and hybrid reasoning natively limits
      },
    });

    const telemetryItems = [
      (gpsLatitude != null && gpsLongitude != null) ? `GPS:${gpsLatitude},${gpsLongitude}` : null,
      gpsElevation != null ? `Elev:${gpsElevation}m` : null,
      depthScaleText ? `Depth:${depthScaleText}` : null,
      semanticLocation ? `Loc:${semanticLocation}` : null,
      weatherCondition ? `Wx:${weatherCondition}` : null,
      weatherTemperatureF != null ? `Temp:${weatherTemperatureF}F` : null,
      deviceLocale ? `Locale:${deviceLocale}` : null,
      currentMonth ? `Month:${currentMonth}` : null,
      timeOfDay ? `Time:${timeOfDay}` : null
    ].filter(Boolean);

    const combinedPrompt = `Context: ${telemetryItems.join(", ")}. Perform biological identification.`;

    const merianResponseSchema = {
      type: SchemaType.OBJECT,
      properties: {
        is_biological_subject: { type: SchemaType.BOOLEAN },
        is_live_capture: { type: SchemaType.BOOLEAN },
        ecology_type: {
          type: SchemaType.STRING,
          enum: ["wild", "urban", "domesticated", "unknown"],
        },
        scientific_name: { type: SchemaType.STRING },
        common_name: { type: SchemaType.STRING },
        confidence_score: {
          type: SchemaType.NUMBER,
        },
        blur_score: {
          type: SchemaType.NUMBER,
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
              items: { type: SchemaType.STRING },
              description: "Array of strings describing differences against lookalike."
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
        },
      },
      required: [
        "is_biological_subject",
        "is_live_capture",
        "common_name",
        "confidence_score",
        "blur_score",
      ],
    };

    // Dynamically insert mapped image layers chronologically sequentially to form the prompt
    // deno-lint-ignore no-explicit-any
    const parts: any[] = base64Payloads.map(payload => ({
      inlineData: {
        mimeType: "image/jpeg",
        data: payload,
      },
    }));
    parts.push({ text: combinedPrompt });

    let finishReason: string | undefined;
    let safetyRatings: SafetyRating[] | undefined;
    let responseText = "";
    
    // Telemetry pointers securely initialized natively
    let llmPromptTokens: number | null = null;
    let llmCandidateTokens: number | null = null;
    let llmTotalTokens: number | null = null;
    try {
        const result = await model.generateContent({
            contents: [{ role: "user", parts }],
            generationConfig: {
                responseMimeType: "application/json",
                // Route through explicit cast to bypass Deno structural constraint mappings securely
                // deno-lint-ignore no-explicit-any
                responseSchema: merianResponseSchema as any,
            },
        });
        const candidate = result.response.candidates?.[0];
        finishReason = candidate?.finishReason;
        safetyRatings = candidate?.safetyRatings;
        responseText = result.response.text();
        
        // Extract native Gemini token usage bounds natively
        const usage = result.response.usageMetadata;
        if (usage) {
            console.log(`Token Usage [${user.id}]: Sent (Prompt): ${usage.promptTokenCount} | Received (Candidates): ${usage.candidatesTokenCount} | Total: ${usage.totalTokenCount}`);
            llmPromptTokens = usage.promptTokenCount;
            llmCandidateTokens = usage.candidatesTokenCount;
            llmTotalTokens = usage.totalTokenCount;
        }
    } catch (genError) {
        console.error("Gemini Critical Extraction Failure:", genError);
        return jsonResponse({ error: `Gemini Validation Error: ${(genError as Error).message}` }, 400);
    }

    // Strip markdown formatting if Gemini hallucinates markdown blocks or conversational text
    const startIndex = responseText.indexOf('{');
    const endIndex = responseText.lastIndexOf('}');
    
    if (startIndex === -1 || endIndex === -1 || startIndex > endIndex) {
        console.error("Failed to extract JSON structure from Gemini response:", responseText);
        return jsonResponse({ error: "Gemini Hallucination: Missing JSON payload" }, 422);
    }
    const cleanJsonString = responseText.substring(startIndex, endIndex + 1);
    let parsedData;
    try {
        parsedData = JSON.parse(cleanJsonString);
    } catch (parseError) {
        console.error("Failed to parse extracted JSON structure:", parseError);
        return jsonResponse({ error: "Gemini Hallucination: Malformed JSON payload" }, 422);
    }

    const userId = user!.id;
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
          user!.id,
          r2ObjectKeys,
          imageBase64s,
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
            user_id: user!.id,
            species_id: speciesId,
            timestamp: timestamp ? timestamp : undefined,
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
            depth_scale_text: depthScaleText,
            llm_prompt_tokens: llmPromptTokens,
            llm_candidate_tokens: llmCandidateTokens,
            llm_total_tokens: llmTotalTokens,
            image_storage_urls: modResult.publicUrls && modResult.publicUrls.length > 0
              ? modResult.publicUrls
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
    const globalObj = globalThis as unknown as { EdgeRuntime?: { waitUntil: (p: Promise<void>) => void } };
    
    if (typeof globalObj.EdgeRuntime === "object" && typeof globalObj.EdgeRuntime.waitUntil === "function") {
      globalObj.EdgeRuntime.waitUntil(backgroundTask);
    } else {
      // Graceful fallback for local development or Deno Core isolated workers
      backgroundTask.catch(console.error);
    }

    // Return standard nested JSON array to prevent iOS decoding double-escaped strings
    return jsonResponse({ success: true, data: parsedData }, 200);
  })
);
