import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { encodeBase64 } from "https://deno.land/std@0.224.0/encoding/base64.ts";

import { GoogleGenerativeAI, SchemaType, SafetyRating, Part, ResponseSchema } from "https://esm.sh/@google/generative-ai@0.24.1";
import { evaluateAndProcessPayload } from "./moderation.ts";
import { getR2Config } from "../_shared/aws.ts";
import { jsonResponse, withEdgeHandler, runBackground } from "../_shared/edgeHandler.ts";

// Instantiated once at module scope so warm isolate re-use avoids re-initialization overhead.
const _geminiApiKey = Deno.env.get("GEMINI_API_KEY")!;
const _genAI = new GoogleGenerativeAI(_geminiApiKey);

// Worker-level tier cache — persists across warm isolate re-use, eliminating the DB round-trip
// for every scan after the first. TTL of 5 minutes is short enough to pick up subscription
// changes without holding stale data across a full user session.
const _tierCache = new Map<string, { tier: string; ts: number }>();
const _TIER_CACHE_TTL_MS = 5 * 60_000;

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const fnStart = Date.now();
    const body = await req.json();
    const {
      r2ObjectKeys,
      imageBase64s,
      user_id,
      mimeType,
      gpsLatitude,
      gpsLongitude,
      gpsElevation,
      depthScaleText,
      zoomFactor,
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
      // Reject r2ObjectKeys that don't belong to the requesting user (IDOR prevention).
      // When imageBase64s are provided, the key is used only for the destination filename.
      for (const r2ObjectKey of r2ObjectKeys) {
        if ((!imageBase64s || imageBase64s.length === 0) && !r2ObjectKey.startsWith(`staging/${user.id}/`)) {
          console.error(`IDOR: r2ObjectKey ${r2ObjectKey} does not belong to user ${user.id}`);
          return jsonResponse({ error: "Forbidden: r2ObjectKey does not belong to the requesting user." }, 403);
        }
        if (r2ObjectKey.includes("..")) {
          return jsonResponse({ error: "Bad Request: Path traversal detected." }, 400);
        }
      }
    }

    if (!user_id) {
      return jsonResponse({ error: "Missing user_id parameter in body" }, 400);
    }

    const base64Payloads: string[] = [];

    if (imageBase64s && imageBase64s.length > 0) {
      if (imageBase64s.length > 5) {
        return jsonResponse({ error: "Too many images." }, 400);
      }
      const validBase64s: string[] = imageBase64s.filter((s: string) => s.length > 0);
      if (validBase64s.length === 0) {
        return jsonResponse({ error: "Bad Request: imageBase64s contains no valid image data." }, 400);
      }
      const totalB64Bytes = validBase64s.reduce((sum: number, s: string) => sum + s.length, 0);
      // base64 inflates raw size ~4/3; 5 MB raw ≈ 6.7 MB encoded
      if (totalB64Bytes > 7 * 1024 * 1024) {
        return jsonResponse({ error: "Payload Too Large: base64 payload exceeds 5 MB raw limit." }, 413);
      }
      base64Payloads.push(...validBase64s);
    } else if (r2ObjectKeys && r2ObjectKeys.length > 0) {
      console.log(`[⏱ BENCH] base64_validated: ${Date.now() - fnStart}ms`);
      const { s3Client, bucketName, endpoint } = getR2Config();

      const r2Responses = await Promise.allSettled(
        r2ObjectKeys.map((key: string) => s3Client.fetch(`${endpoint}/${bucketName}/${key}`))
      );

      // Process images serially: consume one body at a time so each ArrayBuffer is GC-eligible
      // before the next is loaded, preventing a peak spike of N × (raw + copy + base64) in heap.
      // Size is checked against ACTUAL bytes after consumption — Content-Length headers are
      // unreliable (absent on chunked transfer encoding) and must never be trusted as a
      // heap-exhaustion guard.
      let totalBytes = 0;
      for (const result of r2Responses) {
          if (result.status === "rejected") {
              throw new Error(`Failed to execute concurrent R2 fetch request.`);
          }
          const r2Response = result.value as Response;
          if (!r2Response.ok) {
              throw new Error(`Failed to fetch an image from R2: ${r2Response.statusText}`);
          }
          const arrayBuffer = await r2Response.arrayBuffer();
          totalBytes += arrayBuffer.byteLength;
          if (totalBytes > 5 * 1024 * 1024) {
              return jsonResponse({ error: "Payload Too Large: Combined images exceed 5MB limit." }, 413);
          }
          base64Payloads.push(encodeBase64(new Uint8Array(arrayBuffer)));
      }
    }

    console.log(`[⏱ BENCH] payload_resolved: ${Date.now() - fnStart}ms`);

    // Resolve tier for model selection. Cache hit (common case after first scan within a
    // 5-minute window) is near-instant. On miss: one lightweight SELECT — no upsert on the
    // critical path (ghost-user creation stays in the background task).
    let userTierForModel = "free";
    const cachedTierEntry = _tierCache.get(user.id);
    if (cachedTierEntry && Date.now() - cachedTierEntry.ts < _TIER_CACHE_TTL_MS) {
      userTierForModel = cachedTierEntry.tier;
    } else {
      const { data: tierData } = await supabaseAdmin
        .from("users")
        .select("subscription_tier")
        .eq("id", user.id)
        .maybeSingle();
      if (tierData) {
        userTierForModel = tierData.subscription_tier as string;
        _tierCache.set(user.id, { tier: userTierForModel, ts: Date.now() });
      }
      // Ghost users: default "free" for model selection; upsert happens in background task
    }

    // Pro users get gemini-2.5-pro for maximum identification depth (rare species, fossils,
    // subspecies, cultivars). Free users use gemini-2.5-flash for 2–3× lower latency.
    const targetModel = userTierForModel === "pro" ? "gemini-2.5-pro" : "gemini-2.5-flash";

    // Liveness instruction clarification: "liveness check" previously caused Flash to treat
    // fossils/specimens as is_biological_subject=false, returning generic names like
    // "Fossilized Shell" instead of the correct species common name (e.g. "Devil's Toenail"
    // for Gryphaea). Fossils and preserved specimens are biological subjects — only
    // is_live_capture changes.
    const systemInstruction = `Identify biology precisely. 1) Liveness: fossils, pressed/preserved/dried specimens are is_biological_subject=true with is_live_capture=false — identify to species level. Non-biological objects (rocks, buildings, food) are is_biological_subject=false. 2) Evaluate is_invasive based on GPS. 3) common_name must be maximally specific in strict title case (e.g. "Devil's Toenail" not "Fossilized Shell", "Monarch Butterfly" not "Butterfly"). 4) CRITICAL: Evaluate all provided images together. 5) CRITICAL: Multiple species → identify ONE primary (most prominent in first image). 6) CRITICAL: is_biological_subject=false → OMIT taxonomy, insight_data, diagnostic_comparison, iucn_red_list_status, is_invasive, ecology_type, scientific_name, colors, group_tags.`;

    const model = _genAI.getGenerativeModel({
      model: targetModel,
      systemInstruction: systemInstruction,
      generationConfig: {
        temperature: 0.1,
        maxOutputTokens: 800,
      },
    });

    const telemetryItems = [
      (gpsLatitude != null && gpsLongitude != null) ? `GPS:${gpsLatitude},${gpsLongitude}` : null,
      gpsElevation != null ? `Elev:${gpsElevation}m` : null,
      depthScaleText ? `Depth:${depthScaleText}` : null,
      (zoomFactor != null && zoomFactor > 1) ? `Zoom:${zoomFactor.toFixed(1)}x` : null,
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
        group_tags: {
          type: SchemaType.ARRAY,
          items: { type: SchemaType.STRING },
          description: "2-4 plain English categorical labels for the subject, broadest to most specific (e.g. ['bird', 'songbird']).",
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

    const parts: Part[] = base64Payloads.map(payload => ({
      inlineData: {
        mimeType: mimeType || "image/webp",
        data: payload,
      },
    }));
    parts.push({ text: combinedPrompt });

    console.log(`[⏱ BENCH] pre_gemini: ${Date.now() - fnStart}ms`);
    const geminiStart = Date.now();

    let finishReason: string | undefined;
    let safetyRatings: SafetyRating[] | undefined;
    let responseText = "";

    let llmPromptTokens: number | null = null;
    let llmCandidateTokens: number | null = null;
    let llmTotalTokens: number | null = null;
    try {
        const result = await model.generateContent({
            contents: [{ role: "user", parts }],
            generationConfig: {
                responseMimeType: "application/json",
                responseSchema: merianResponseSchema as unknown as ResponseSchema,
            },
        });
        const candidate = result.response.candidates?.[0];
        finishReason = candidate?.finishReason;
        safetyRatings = candidate?.safetyRatings;
        responseText = result.response.text();
        
        const usage = result.response.usageMetadata;
        if (usage) {
            console.log(`Token Usage [${user.id}]: Sent (Prompt): ${usage.promptTokenCount} | Received (Candidates): ${usage.candidatesTokenCount} | Total: ${usage.totalTokenCount}`);
            llmPromptTokens = usage.promptTokenCount;
            llmCandidateTokens = usage.candidatesTokenCount;
            llmTotalTokens = usage.totalTokenCount;
        }
        console.log(`[⏱ BENCH] gemini_done: ${Date.now() - fnStart}ms total, ${Date.now() - geminiStart}ms inference`);
    } catch (genError) {
        console.error("AI generation failed:", genError);
        return jsonResponse({ error: "AI processing error. Please try again." }, 400);
    }

    // Strip any markdown wrapper if the model produces non-JSON preamble
    const startIndex = responseText.indexOf('{');
    const endIndex = responseText.lastIndexOf('}');

    if (startIndex === -1 || endIndex === -1 || startIndex > endIndex) {
        console.error("Failed to extract JSON from AI response:", responseText);
        return jsonResponse({ error: "Processing Error: Malformed AI response." }, 422);
    }
    const cleanJsonString = responseText.substring(startIndex, endIndex + 1);
    let parsedData;
    try {
        parsedData = JSON.parse(cleanJsonString);
    } catch (parseError) {
        console.error("Failed to parse AI response JSON:", parseError);
        return jsonResponse({ error: "Processing Error: Invalid AI response format." }, 422);
    }

    const generatedScanId = crypto.randomUUID();
    parsedData.scan_id = generatedScanId;

    const backgroundTask = (async () => {
      try {
        // Tier lookup is only needed for the R2 storage path in moderation and to ensure
        // the ghost-user record exists before the scans FK insert. Both usages are here in
        // the background task, so the DB round-trip is completely off the Gemini critical path.
        let backgroundTier = "free";
        const cachedTier = _tierCache.get(user.id);
        if (cachedTier && Date.now() - cachedTier.ts < _TIER_CACHE_TTL_MS) {
          backgroundTier = cachedTier.tier;
        } else {
          const { data: existingUser } = await supabaseAdmin
            .from("users")
            .select("subscription_tier")
            .eq("id", user.id)
            .maybeSingle();
          if (existingUser) {
            backgroundTier = existingUser.subscription_tier as string;
            _tierCache.set(user.id, { tier: backgroundTier, ts: Date.now() });
          } else {
            // Ghost user — create the record required for the scans FK constraint.
            await supabaseAdmin
              .from("users")
              .upsert(
                { id: user.id, subscription_tier: "free" },
                { onConflict: "id", ignoreDuplicates: true },
              );
            _tierCache.set(user.id, { tier: "free", ts: Date.now() });
          }
        }

        const modResult = await evaluateAndProcessPayload(
          user.id,
          r2ObjectKeys,
          imageBase64s,
          finishReason,
          safetyRatings,
          backgroundTier,
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

        // Upsert species dictionary entry
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
              // GBIF taxonomy lookup
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

              // Wikipedia page summary lookup
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

          // If 'ignoreDuplicates' returns null on concurrent upsert conflict, fall back to a direct SELECT.
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

        const { error: scanInsertError } = await supabaseAdmin
          .from("scans")
          .insert({
            id: generatedScanId,
            user_id: user.id,
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
            group_tags: parsedData.group_tags,
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
          });

        if (scanInsertError) {
          console.error("Failed to insert scan:", scanInsertError);
          
          // Revert and purge R2 promotional uploads to prevent untracked orphans
          if (modResult.publicUrls && modResult.publicUrls.length > 0) {
            console.log("Rolling back R2 uploads due to database failure.");
            const r2Config = getR2Config();
            const { deleteR2Object } = await import("../_shared/aws.ts");
            const keysToPurge = modResult.publicUrls.map((url: string) => url.replace("https://media.merian.app/", ""));
            await Promise.allSettled(keysToPurge.map((key: string) => deleteR2Object(key, r2Config)));
          }
        }
    } catch (e) {
        // Log structured context so failed ingestions are visible and retryable.
        // A future dead-letter table / replay job can match on user_id + scan_id.
        console.error(JSON.stringify({
          event: "background_ingestion_failed",
          user_id: user.id,
          scan_id: generatedScanId,
          error: e instanceof Error ? e.message : String(e),
          ts: new Date().toISOString(),
        }));
      }
    })();

    runBackground(backgroundTask);

    console.log(`[⏱ BENCH] total_to_response: ${Date.now() - fnStart}ms`);
    return jsonResponse({ success: true, data: parsedData }, 200);
  })
);
