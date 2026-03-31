import { SafetyRating, Part, UsageMetadata } from "https://esm.sh/@google/generative-ai@0.24.1";
import { evaluateAndProcessPayload } from "./moderation.ts";
import { getR2Config, deleteR2Object } from "../_shared/aws.ts";
import { jsonResponse, withEdgeHandler, runBackground } from "../_shared/edgeHandler.ts";
import { fetchGroupTags } from "../_shared/biology.ts";
import { fetchExternalEnrichment } from "../_shared/external.ts";
import { _genAI, extractJson } from "../_shared/gemini.ts";
import { getTierForUser } from "../_shared/tierCache.ts";
import { trackPostHogEvent } from "../_shared/posthog.ts";
import { requireParams } from "../_shared/http.ts";

import { MerianIdentification, ClientPayload, CachedSpeciesRow, StaticSpeciesData } from "./types.ts";
import { systemInstruction, merianResponseSchema } from "./schema.ts";
import { resolveImagePayloads } from "./media.ts";
  upsertGhostUserIfMissing,
  fetchCachedSpecies,
  upsertSpeciesDictionary,
  insertScan,
  updateGroupTags,
} from "./db.ts";

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const fnStart = Date.now();
    const body = await req.json();

    const paramError = requireParams(body, ["user_id"]);
    if (paramError) return paramError;

    const {
      r2ObjectKeys,
      imageBase64s,
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
      estimated_size_cm,
    } = body;

    if (
      (!r2ObjectKeys || r2ObjectKeys.length === 0) &&
      (!imageBase64s || imageBase64s.length === 0)
    ) {
      return jsonResponse(
        { error: "Missing structural boundary (neither r2ObjectKeys nor imageBase64s provided)." },
        400,
      );
    }

    if (r2ObjectKeys && r2ObjectKeys.length > 0) {
      for (const r2ObjectKey of r2ObjectKeys) {
        if (r2ObjectKey.includes("..")) {
          return jsonResponse({ error: "Bad Request: Path traversal detected." }, 400);
        }
        // Reject r2ObjectKeys that don't belong to the requesting user (IDOR prevention).
        // When imageBase64s are provided, the key is used only for the destination filename.
        if (
          (!imageBase64s || imageBase64s.length === 0) &&
          !r2ObjectKey.startsWith(`staging/${user.id}/`)
        ) {
          console.error(`IDOR: r2ObjectKey ${r2ObjectKey} does not belong to user ${user.id}`);
          return jsonResponse(
            { error: "Forbidden: r2ObjectKey does not belong to the requesting user." },
            403,
          );
        }
      }
    }

    const { base64Payloads, errorResponse } = await resolveImagePayloads(
      r2ObjectKeys,
      imageBase64s,
      fnStart,
    );

    if (errorResponse) return errorResponse;

    if (!base64Payloads || base64Payloads.length === 0) {
      return jsonResponse({ error: "Failed to resolve image payloads." }, 400);
    }

    console.log(`[⏱ BENCH] payload_resolved: ${Date.now() - fnStart}ms`);

    // Resolve tier for model selection. Cache hit (common case after first scan within a
    // 5-minute window) is near-instant. On miss: one lightweight SELECT — no upsert on the
    // critical path (ghost-user creation stays in the background task).
    const userTier = await getTierForUser(user.id, supabaseAdmin);

    // Pro users get gemini-2.5-pro for maximum identification depth (rare species, fossils,
    // subspecies, cultivars). Free users use gemini-2.5-flash for 2–3× lower latency.
    const targetModel = userTier === "pro" ? "gemini-2.5-pro" : "gemini-2.5-flash";

    const model = _genAI.getGenerativeModel({
      model: targetModel,
      systemInstruction,
      generationConfig: { temperature: 0.1, maxOutputTokens: 1000 },
    });

    const telemetryItems = [
      gpsLatitude != null && gpsLongitude != null ? `GPS:${gpsLatitude},${gpsLongitude}` : null,
      gpsElevation != null ? `Elev:${gpsElevation}m` : null,
      depthScaleText ? `Depth:${depthScaleText}` : null,
      zoomFactor != null && zoomFactor > 1 ? `Zoom:${zoomFactor.toFixed(1)}x` : null,
      semanticLocation ? `Loc:${semanticLocation}` : null,
      weatherCondition ? `Wx:${weatherCondition}` : null,
      weatherTemperatureF != null ? `Temp:${weatherTemperatureF}F` : null,
      deviceLocale ? `Locale:${deviceLocale}` : null,
      currentMonth ? `Month:${currentMonth}` : null,
      timeOfDay ? `Time:${timeOfDay}` : null,
    ].filter(Boolean);

    const parts: Part[] = [
      ...base64Payloads.map((payload) => ({
        inlineData: { mimeType: mimeType || "image/webp", data: payload },
      })),
      { text: `Context: ${telemetryItems.join(", ")}. Perform biological identification.` },
    ];

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
          responseSchema: merianResponseSchema,
        },
      });
      const candidate = result.response.candidates?.[0];
      finishReason = candidate?.finishReason;
      safetyRatings = candidate?.safetyRatings;
      responseText = result.response.text();

      const usage = result.response.usageMetadata;
      if (usage) {
        console.log(
          `Token Usage [${user.id}]: Sent (Prompt): ${usage.promptTokenCount} | Received (Candidates): ${usage.candidatesTokenCount} | Total: ${usage.totalTokenCount}`,
        );
        llmPromptTokens = usage.promptTokenCount;
        llmCandidateTokens = usage.candidatesTokenCount;
        llmTotalTokens = usage.totalTokenCount;
      }
      console.log(
        `[⏱ BENCH] gemini_done: ${Date.now() - fnStart}ms total, ${Date.now() - geminiStart}ms inference`,
      );
    } catch (genError) {
      console.error("AI generation failed:", genError);
      return jsonResponse({ error: "AI processing error. Please try again." }, 400);
    }

    let parsedData: MerianIdentification;
    try {
      parsedData = extractJson<MerianIdentification>(responseText);
    } catch (parseError) {
      console.error("Failed to parse AI response:", parseError);
      return jsonResponse({ error: "Processing Error: Malformed AI response." }, 422);
    }

    const generatedScanId = crypto.randomUUID();
    const payloadReadyForClient: ClientPayload = {
      ...parsedData,
      scan_id: generatedScanId,
      inference_tier: userTier === "pro" ? "pro" : "flash",
    };

    // Strip candidates when confidence is above the tier's diagnosticTrigger threshold.
    // These values mirror MerianConfig.flashConfidence.diagnosticTrigger (0.88) and
    // MerianConfig.proConfidence.diagnosticTrigger (0.80) in the iOS client.
    const diagnosticTrigger = userTier === "pro" ? 0.80 : 0.88;
    if ((parsedData.confidence_score ?? 1.0) >= diagnosticTrigger) {
      payloadReadyForClient.candidates = null;
    }

    const isIdentifiedBio = !!(parsedData.is_biological_subject && parsedData.scientific_name);
    let speciesId: string | null = null;
    let cachedSpecies: CachedSpeciesRow | null = null;

    if (isIdentifiedBio) {
      cachedSpecies = await fetchCachedSpecies(parsedData.scientific_name!, supabaseAdmin);

      let staticData: StaticSpeciesData = { hazard_type: "none" };

      if (cachedSpecies?.kingdom) {
        console.log(`Cache Hit: Generating payload from DB for ${parsedData.scientific_name}`);
        staticData = {
          taxonomy: {
            kingdom: cachedSpecies.kingdom ?? "Unknown",
            phylum: cachedSpecies.phylum ?? "Unknown",
            class: cachedSpecies.class ?? "Unknown",
            order: cachedSpecies.order ?? "Unknown",
            family: cachedSpecies.family ?? "Unknown",
            genus: cachedSpecies.genus ?? "Unknown",
          },
          iucn_red_list_status: cachedSpecies.iucn_red_list_status ?? "not_evaluated",
          hazard_type: cachedSpecies.hazard_type || "none",
          speciesHabitat: cachedSpecies.habitat_description ?? undefined,
        };
        speciesId = cachedSpecies.id;
        // common_name is always sourced from the vision model — DB value is locale storage only.
        payloadReadyForClient.reference_image_url = cachedSpecies.reference_image_url;
        payloadReadyForClient.wikipedia_url = cachedSpecies.wikipedia_url;
        payloadReadyForClient.wikipedia_overview = cachedSpecies.wikipedia_overview;
        if (cachedSpecies.group_tags?.length) {
          payloadReadyForClient.group_tags = cachedSpecies.group_tags;
        }
        // gbif_taxon_key is available to all tiers — it is a deterministic REST-sourced
        // lookup key, not AI-generated.
        if (cachedSpecies.gbif_taxon_key != null) {
          payloadReadyForClient.gbif_taxon_key = cachedSpecies.gbif_taxon_key;
        }
      } else {
        // Cache Miss: taxonomy, IUCN, and species insights are not in the vision response.
        // DB enrichment (Flash text + GBIF/Wikipedia upsert) runs in the background task so
        // the next scan of the same species becomes a Cache Hit with full metadata.
        console.log(`Cache Miss: ${parsedData.scientific_name}. Background enrichment queued.`);
      }

      if (staticData.taxonomy) payloadReadyForClient.taxonomy = staticData.taxonomy;
      if (staticData.iucn_red_list_status) {
        payloadReadyForClient.iucn_red_list_status = staticData.iucn_red_list_status;
      }

      payloadReadyForClient.insight_data = {
        ai_reasoning: parsedData.ai_reasoning || "Reasoning omitted.",
        hazard_type: staticData.hazard_type,
      };

      // Species insights are sourced exclusively from the DB (Cache Hit) — never from the
      // vision model. Served to all tiers when already stored; otherwise the client
      // triggers a follow-up enrich-scan call to populate them.
      if (staticData.speciesHabitat) {
        payloadReadyForClient.species_insights = { habitat_description: staticData.speciesHabitat };
      }
    }

    const runBackgroundIngestion = async () => {
      // modResult is hoisted outside the try so the catch can reference publicUrls
      // for R2 rollback if insertScan fails after media has already been committed.
      let modResult: Awaited<ReturnType<typeof evaluateAndProcessPayload>> | undefined;
      let scanInserted = false;

      try {
        // Tier was already resolved on the critical path. The only remaining task here is
        // ghost-user creation: if the main path never found the user in the DB, the cache
        // entry was never set, so we upsert them now before the scans FK insert.
        await upsertGhostUserIfMissing(user.id, supabaseAdmin);

        modResult = await evaluateAndProcessPayload(
          user.id,
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
          console.error("Media flagged by safety moderation. Halting background data ingestion.");
          return;
        }

        // Start diagnostic group-tag Flash call.
        // Cheap, species-level, and skipped when already cached.
        const needsGroupTags = isIdentifiedBio && !cachedSpecies?.group_tags?.length;
        const groupTagsPromise = needsGroupTags
          ? fetchGroupTags(user, parsedData.scientific_name!)
          : Promise.resolve(null);

        // Cache Miss: enrich species_dictionary so the next scan of the same species is a Cache Hit.
        // Runs after moderation so we don't persist data for flagged content.
        if (!speciesId && isIdentifiedBio) {
          const bgEnrichStart = Date.now();
          const [externalData] = await Promise.all([
            fetchExternalEnrichment(parsedData.scientific_name!),
          ]);

          const newCommonNames = {
            ...(cachedSpecies?.common_names ?? {}),
            ...(parsedData.common_name ? { en: parsedData.common_name } : {}),
          };

          const upsertedId = await upsertSpeciesDictionary(
            {
              scientific_name: parsedData.scientific_name!,
              common_names: newCommonNames,
              kingdom: cachedSpecies?.kingdom ?? "Unknown",
              phylum: cachedSpecies?.phylum ?? "Unknown",
              class: cachedSpecies?.class ?? "Unknown",
              order: cachedSpecies?.order ?? "Unknown",
              family: cachedSpecies?.family ?? "Unknown",
              genus: cachedSpecies?.genus ?? "Unknown",
              wikipedia_overview:
                cachedSpecies?.wikipedia_overview ?? externalData.wikiExtract ?? null,
              hazard_type: cachedSpecies?.hazard_type ?? "none",
              native_region: "Unknown",
              iucn_red_list_status: cachedSpecies?.iucn_red_list_status ?? "not_evaluated",
              habitat_description: cachedSpecies?.habitat_description ?? null,
              wikipedia_url: cachedSpecies?.wikipedia_url || externalData.wikipediaUrl,
              gbif_taxon_key: cachedSpecies?.gbif_taxon_key || externalData.gbifKey,
              reference_image_url:
                cachedSpecies?.reference_image_url || externalData.referenceImageUrl,
            },
            supabaseAdmin,
          );
          speciesId = upsertedId || cachedSpecies?.id || null;
          console.log(`[⏱ BENCH] bg_enrichment: ${Date.now() - bgEnrichStart}ms`);
        }

        await insertScan(
          {
            id: generatedScanId,
            user_id: user.id,
            species_id: speciesId,
            timestamp: timestamp ?? undefined,
            gps_lat_exact: gpsLatitude,
            gps_long_exact: gpsLongitude,
            gps_elevation: gpsElevation,
            ai_confidence_score: payloadReadyForClient.confidence_score,
            blur_score: payloadReadyForClient.blur_score,
            ecology_type: payloadReadyForClient.ecology_type,
            is_invasive: payloadReadyForClient.is_invasive,
            weather_condition: weatherCondition,
            weather_temperature_f: weatherTemperatureF,
            semantic_location: semanticLocation,
            device_locale: deviceLocale,
            current_month: currentMonth,
            time_of_day: timeOfDay,
            depth_scale_text: depthScaleText,
            ai_reasoning: parsedData.ai_reasoning ?? null,
            extracted_visual_traits: parsedData.extracted_visual_traits ?? [],
            colors: [],
            llm_prompt_tokens: llmPromptTokens,
            llm_candidate_tokens: llmCandidateTokens,
            llm_total_tokens: llmTotalTokens,
            image_storage_urls: modResult.publicUrls?.length ? modResult.publicUrls : [],
            life_stage: parsedData.life_stage ?? "unknown",
            reproductive_condition: parsedData.reproductive_condition ?? "not_applicable",
            individual_count: parsedData.individual_count ?? null,
            ecological_interactions: parsedData.ecological_interactions ?? [],
            estimated_size_cm: estimated_size_cm ?? null,
            inference_tier: userTier === "pro" ? "pro" : "flash",
            candidates: payloadReadyForClient.candidates ?? null,
            image_quality_score: parsedData.image_quality?.overall_score ?? null,
            is_live_capture: parsedData.is_live_capture,
          },
          supabaseAdmin,
        );
        scanInserted = true;

        // Await species-level Flash call
        const groupTagsResult = await groupTagsPromise;

        const totalTokens =
          (llmTotalTokens ?? 0) +
          (groupTagsResult?.usage?.totalTokenCount ?? 0);

        // Fire PostHog as fire-and-forget — analytics must never add latency to ingestion.
        trackPostHogEvent(user, "ScanCompleted", {
          is_biological_subject: parsedData.is_biological_subject,
          tier: userTier,
          llm_model: targetModel,
          llm_prompt_tokens: llmPromptTokens,
          llm_candidate_tokens: llmCandidateTokens,
          llm_total_tokens: llmTotalTokens,
          encyclopedic_tokens: 0,
          similar_species_tokens: 0,
          group_tags_tokens: groupTagsResult?.usage?.totalTokenCount ?? 0,
          cumulative_scan_tokens: totalTokens,
          scientific_name: parsedData.scientific_name,
        }).catch((e) => console.error("PostHog tracking failed:", e));

        const bgWriteStart = Date.now();
        await Promise.allSettled([
          needsGroupTags && groupTagsResult?.group_tags?.length
            ? updateGroupTags(parsedData.scientific_name!, groupTagsResult.group_tags, supabaseAdmin)
            : Promise.resolve(),
        ]);
        console.log(`[⏱ BENCH] bg_species_writes: ${Date.now() - bgWriteStart}ms`);
      } catch (e) {
        // Revert R2 uploads to prevent untracked orphans when the scan DB write failed.
        // Only roll back if modResult exists (media was committed) but the scan row wasn't
        // written yet — a post-insert failure would leave a valid scan referencing the media.
        if (!scanInserted && modResult?.publicUrls?.length) {
          console.log("Rolling back R2 uploads due to scan insert failure.");
          const r2Config = getR2Config();
          const keysToPurge = modResult.publicUrls.map((url: string) =>
            url.replace("https://media.merian.app/", ""),
          );
          await Promise.allSettled(
            keysToPurge.map((key: string) => deleteR2Object(key, r2Config)),
          );
        }
        // Log structured context so failed ingestions are visible and retryable.
        // A future dead-letter table / replay job can match on user_id + scan_id.
        console.error(
          JSON.stringify({
            event: "background_ingestion_failed",
            user_id: user.id,
            scan_id: generatedScanId,
            error: e instanceof Error ? e.message : String(e),
            ts: new Date().toISOString(),
          }),
        );
      }
    };

    runBackground(runBackgroundIngestion());

    console.log(`[⏱ BENCH] total_to_response: ${Date.now() - fnStart}ms`);
    return jsonResponse({ success: true, data: payloadReadyForClient }, 200);
  }),
);
