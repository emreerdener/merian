import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import {
  jsonResponse,
  logStructuredError,
  runBackground,
  withEdgeHandler,
} from "../_shared/edgeHandler.ts";
import { fetchGroupTags } from "../_shared/biology.ts";
import { fetchExternalEnrichment } from "../_shared/external.ts";
import { _genAI, extractJson } from "../_shared/gemini.ts";
import { getTierForUser } from "../_shared/tierCache.ts";
import { requireParams } from "../_shared/http.ts";
import {
  buildObservationPrompt,
  normalizeCurrentMonth,
  sanitizeObservationConfidence,
  sanitizeObservationEvidence,
  sanitizeLifeStage,
  sanitizeReproductiveCondition,
  sanitizeSex,
} from "../_shared/identify/context.ts";
import {
  CachedSpeciesRow,
  ClientPayload,
  MerianIdentification,
  StaticSpeciesData,
} from "../_shared/identify/types.ts";
import { sanitizeScientificName } from "../identify/sanitize.ts";

import { diagnosticTriggerForTier } from "../_shared/identify/thresholds.ts";
import {
  getDescribeResponseSchema,
  getDescribeSystemInstruction,
} from "./schema.ts";
import {
  fetchCachedSpecies,
  fetchCandidateCommonNames,
  insertDescribeScan,
  updateGroupTags,
  upsertGhostUserIfMissing,
  upsertSpeciesDictionary,
} from "./db.ts";

// Text-only model configs — no image parts, so thinking budgets are smaller.
// Flash text calls for describes are less ambiguous than vision (the user already
// filtered by organism class) so 1,024 tokens is sufficient headroom.
const modelConfigs = {
  flash: {
    model: "gemini-2.5-flash" as const,
    config: {
      systemInstruction: getDescribeSystemInstruction(),
      temperature: 0.15,
      seed: 42,
      topK: 40,
      maxOutputTokens: 2048,
      thinkingConfig: { thinkingBudget: 1024 },
    },
  },
  pro: {
    model: "gemini-2.5-pro" as const,
    config: {
      systemInstruction: getDescribeSystemInstruction(),
      temperature: 0.15,
      seed: 42,
      topK: 40,
      maxOutputTokens: 4096,
      thinkingConfig: { thinkingBudget: 3000 },
    },
  },
};

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const fnStart = Date.now();
    const body = await req.json();

    const paramError = requireParams(body, ["user_id", "description"]);
    if (paramError) return paramError;

    const {
      description,
      gpsLatitude,
      gpsLongitude,
      gpsElevation,
      weatherCondition,
      weatherTemperatureF,
      deviceLocale,
      deviceTimeZone,
      deviceRegion,
      currentMonth,
      semanticLocation,
      publicLocationLabel,
      public_location_label,
      timeOfDay,
      timestamp,
      client_scan_id,
      observation_context,
    } = body;
    const publicExploreLocationLabel = publicLocationLabel ??
      public_location_label;
    const normalizedCurrentMonth = normalizeCurrentMonth(currentMonth);

    if (typeof description !== "string" || description.trim().length === 0) {
      return jsonResponse(
        { error: "description must be a non-empty string." },
        400,
      );
    }

    // Range-validate GPS — same guard as identify/index.ts.
    const safeGpsLat: number | null =
      gpsLatitude != null && Number.isFinite(gpsLatitude) &&
        gpsLatitude >= -90 && gpsLatitude <= 90
        ? gpsLatitude
        : null;
    const safeGpsLon: number | null =
      gpsLongitude != null && Number.isFinite(gpsLongitude) &&
        gpsLongitude >= -180 && gpsLongitude <= 180
        ? gpsLongitude
        : null;

    console.log(`[⏱ BENCH] payload_parsed: ${Date.now() - fnStart}ms`);

    const userTier = await getTierForUser(user.id, supabaseAdmin);
    const targetModel = userTier === "pro"
      ? "gemini-2.5-pro"
      : "gemini-2.5-flash";
    const diagnosticTrigger = diagnosticTriggerForTier(
      userTier === "pro" ? "pro" : "flash",
    );
    const modelCfg = userTier === "pro" ? modelConfigs.pro : modelConfigs.flash;

    const promptText = buildObservationPrompt(description, {
      safeGpsLat,
      safeGpsLon,
      gpsElevation,
      semanticLocation,
      weatherCondition,
      weatherTemperatureF,
      deviceLocale,
      deviceTimeZone,
      deviceRegion,
      currentMonth: normalizedCurrentMonth,
      timeOfDay,
    });

    console.log(`[⏱ BENCH] pre_gemini: ${Date.now() - fnStart}ms`);
    const geminiStart = Date.now();

    let finishReason: string | undefined;
    let responseText = "";
    let llmPromptTokens: number | null = null;
    let llmCandidateTokens: number | null = null;
    let llmTotalTokens: number | null = null;
    let llmThinkingTokens: number | null = null;
    let llmCachedTokens: number | null = null;

    try {
      const result = await _genAI.models.generateContent({
        model: modelCfg.model,
        contents: [{ role: "user", parts: [{ text: promptText }] }],
        config: {
          ...modelCfg.config,
          responseMimeType: "application/json",
          responseSchema: getDescribeResponseSchema(),
        },
      });

      const candidate = result.candidates?.[0];
      finishReason = candidate?.finishReason;
      responseText = result.text ?? "";

      if (!responseText) {
        const firstPart = result.candidates?.[0]?.content?.parts?.[0];
        if (
          firstPart && "text" in firstPart && typeof firstPart.text === "string"
        ) {
          responseText = firstPart.text;
        }
      }

      const usage = result.usageMetadata;
      if (usage) {
        llmPromptTokens = usage.promptTokenCount ?? null;
        llmCandidateTokens = usage.candidatesTokenCount ?? null;
        llmTotalTokens = usage.totalTokenCount ?? null;
        llmThinkingTokens = usage.thoughtsTokenCount ?? null;
        llmCachedTokens = usage.cachedContentTokenCount ?? null;
        console.log(
          `Token Usage [${user.id}]: Prompt: ${llmPromptTokens} | Candidates: ${llmCandidateTokens} | Thinking: ${llmThinkingTokens} | Cached: ${llmCachedTokens} | Total: ${llmTotalTokens}`,
        );
      }
      console.log(
        `[⏱ BENCH] gemini_done: ${Date.now() - fnStart}ms total, ${
          Date.now() - geminiStart
        }ms inference`,
      );
    } catch (genError) {
      const errMsg = genError instanceof Error
        ? genError.message
        : String(genError);
      logStructuredError("identify-describe/gemini_failed", {
        user_id: user.id,
        model: targetModel,
        elapsed_ms: Date.now() - geminiStart,
        error_message: errMsg,
      });
      return jsonResponse(
        { error: "AI processing error. Please try again." },
        503,
      );
    }

    if (
      finishReason && finishReason !== "STOP" &&
      finishReason !== "FINISH_REASON_UNSPECIFIED"
    ) {
      const isPermanentContentFailure = finishReason === "SAFETY" ||
        finishReason === "PROHIBITED_CONTENT";
      logStructuredError("identify-describe/non_stop_finish", {
        user_id: user.id,
        finish_reason: finishReason,
        permanent: isPermanentContentFailure,
      });
      return jsonResponse(
        { error: "AI processing error. Please try again." },
        isPermanentContentFailure ? 400 : 503,
      );
    }

    let parsedData: MerianIdentification;
    try {
      parsedData = extractJson<MerianIdentification>(responseText);
    } catch (parseError) {
      logStructuredError("identify-describe/parse_failed", {
        user_id: user.id,
        finish_reason: finishReason ?? "unknown",
        response_length: responseText.length,
        response_preview: responseText.slice(0, 500),
        error: parseError instanceof Error
          ? parseError.message
          : String(parseError),
      });
      return jsonResponse(
        { error: "Processing Error: Malformed AI response." },
        422,
      );
    }

    // Sanitize names and clamp arrays — same guards as identify/index.ts.
    if (parsedData.scientific_name) {
      parsedData.scientific_name = sanitizeScientificName(
        parsedData.scientific_name,
      );
    }
    if (Array.isArray(parsedData.candidates)) {
      parsedData.candidates = parsedData.candidates
        .map((c) => ({
          ...c,
          scientific_name: sanitizeScientificName(c.scientific_name),
        }))
        .slice(0, 5);
    }
    if (Array.isArray(parsedData.extracted_visual_traits)) {
      parsedData.extracted_visual_traits = parsedData.extracted_visual_traits
        .slice(0, 10);
    }
    if (
      typeof parsedData.ai_reasoning === "string" &&
      parsedData.ai_reasoning.length > 2000
    ) {
      parsedData.ai_reasoning = parsedData.ai_reasoning.slice(0, 2000);
    }
    if (parsedData.individual_count != null) {
      parsedData.individual_count =
        Number.isFinite(parsedData.individual_count) &&
          parsedData.individual_count > 0
          ? Math.min(Math.round(parsedData.individual_count), 99999)
          : undefined;
    }
    parsedData.life_stage = sanitizeLifeStage(parsedData.life_stage) ??
      parsedData.life_stage;
    parsedData.reproductive_condition =
      sanitizeReproductiveCondition(parsedData.reproductive_condition) ??
        parsedData.reproductive_condition;
    parsedData.sex = sanitizeSex(parsedData.sex) ?? parsedData.sex;
    parsedData.sex_confidence = sanitizeObservationConfidence(
      parsedData.sex_confidence,
    );
    parsedData.sex_evidence = sanitizeObservationEvidence(
      parsedData.sex_evidence,
    );
    if (!parsedData.is_biological_subject) {
      parsedData.sex = undefined;
      parsedData.sex_confidence = undefined;
      parsedData.sex_evidence = undefined;
    } else if (
      parsedData.sex == null ||
      parsedData.sex === "cannot_determine" ||
      parsedData.sex === "not_applicable"
    ) {
      parsedData.sex_confidence = undefined;
      parsedData.sex_evidence = undefined;
    }

    // Describes always have zero blur (no image).
    parsedData.blur_score = 0;

    const generatedScanId: string =
      typeof client_scan_id === "string" && client_scan_id.length > 0
        ? client_scan_id
        : crypto.randomUUID();

    const payloadReadyForClient: ClientPayload = {
      ...parsedData,
      scan_id: generatedScanId,
      inference_tier: userTier === "pro" ? "pro" : "flash",
    };

    if ((parsedData.confidence_score ?? 0.0) >= diagnosticTrigger) {
      payloadReadyForClient.candidates = null;
    }

    const isIdentifiedBio =
      !!(parsedData.is_biological_subject && parsedData.scientific_name);
    let speciesId: string | null = null;
    let cachedSpecies: CachedSpeciesRow | null = null;
    let missingCandidates: string[] = [];

    const hasCandidates = Array.isArray(payloadReadyForClient.candidates) &&
      payloadReadyForClient.candidates.length > 0;

    const [commonNameMap, fetchedCachedSpecies] = await Promise.all([
      hasCandidates
        ? fetchCandidateCommonNames(
          payloadReadyForClient.candidates!.map((c) => c.scientific_name),
          supabaseAdmin,
        )
        : Promise.resolve(new Map<string, string>()),
      isIdentifiedBio
        ? fetchCachedSpecies(parsedData.scientific_name!, supabaseAdmin)
        : Promise.resolve(null),
    ]);

    if (hasCandidates) {
      const candidateNames = payloadReadyForClient.candidates!.map((c) =>
        c.scientific_name
      );
      missingCandidates = candidateNames.filter((n) => !commonNameMap.has(n));
      if (commonNameMap.size > 0) {
        payloadReadyForClient.candidates = payloadReadyForClient.candidates!
          .map((c) => ({
            ...c,
            common_name: commonNameMap.get(c.scientific_name),
          }));
      }
    }

    if (isIdentifiedBio) {
      cachedSpecies = fetchedCachedSpecies;
      let staticData: StaticSpeciesData = { hazard_type: "none" };

      if (cachedSpecies?.kingdom) {
        staticData = {
          taxonomy: {
            kingdom: cachedSpecies.kingdom ?? "Unknown",
            phylum: cachedSpecies.phylum ?? "Unknown",
            class: cachedSpecies.class ?? "Unknown",
            order: cachedSpecies.order ?? "Unknown",
            family: cachedSpecies.family ?? "Unknown",
            genus: cachedSpecies.genus ?? "Unknown",
          },
          iucn_red_list_status: cachedSpecies.iucn_red_list_status ??
            "not_evaluated",
          hazard_type: cachedSpecies.hazard_type || "none",
          speciesHabitat: cachedSpecies.habitat_description ?? undefined,
        };
        speciesId = cachedSpecies.id;
        if (cachedSpecies.common_names?.en) {
          payloadReadyForClient.common_name = cachedSpecies.common_names.en;
        }
        if (cachedSpecies.alternative_common_names?.length) {
          const primaryEn = (payloadReadyForClient.common_name ?? "")
            .toLowerCase();
          payloadReadyForClient.alternative_common_names = cachedSpecies
            .alternative_common_names.filter((n) =>
              n.toLowerCase() !== primaryEn
            );
        }
        payloadReadyForClient.reference_image_url =
          cachedSpecies.reference_image_url;
        payloadReadyForClient.wikipedia_url = cachedSpecies.wikipedia_url;
        payloadReadyForClient.wikipedia_overview =
          cachedSpecies.wikipedia_overview;
        if (cachedSpecies.group_tags?.length) {
          payloadReadyForClient.group_tags = cachedSpecies.group_tags;
        }
        if (cachedSpecies.gbif_taxon_key != null) {
          payloadReadyForClient.gbif_taxon_key = cachedSpecies.gbif_taxon_key;
        }
      }

      if (staticData.taxonomy) {
        payloadReadyForClient.taxonomy = staticData.taxonomy;
      }
      if (staticData.iucn_red_list_status) {
        payloadReadyForClient.iucn_red_list_status =
          staticData.iucn_red_list_status;
      }
      payloadReadyForClient.insight_data = {
        ai_reasoning: parsedData.ai_reasoning || "Reasoning omitted.",
        hazard_type: staticData.hazard_type,
      };
      if (staticData.speciesHabitat) {
        payloadReadyForClient.species_insights = {
          habitat_description: staticData.speciesHabitat,
        };
      }
    }

    const runBackgroundIngestion = async () => {
      try {
        await upsertGhostUserIfMissing(user.id, supabaseAdmin);

        const needsGroupTags = isIdentifiedBio &&
          !cachedSpecies?.group_tags?.length;
        const groupTagsPromise = needsGroupTags
          ? fetchGroupTags(user, parsedData.scientific_name!)
          : Promise.resolve(null);

        if (!speciesId && isIdentifiedBio) {
          const externalData = await fetchExternalEnrichment(
            parsedData.scientific_name!,
          );
          const freshSpecies = await fetchCachedSpecies(
            parsedData.scientific_name!,
            supabaseAdmin,
          );

          const newCommonNames = {
            ...(freshSpecies?.common_names ?? cachedSpecies?.common_names ??
              {}),
            ...(parsedData.common_name ? { en: parsedData.common_name } : {}),
          };
          const primaryEn = (newCommonNames.en ?? "").toLowerCase();
          const newAltNames: string[] | null =
            externalData.alternativeCommonNames.length > 0
              ? externalData.alternativeCommonNames.filter((n) =>
                n.toLowerCase() !== primaryEn
              )
              : freshSpecies?.alternative_common_names ?? null;

          const upsertedId = await upsertSpeciesDictionary(
            {
              scientific_name: parsedData.scientific_name!,
              common_names: newCommonNames,
              alternative_common_names: newAltNames,
              kingdom: freshSpecies?.kingdom || "Unknown",
              phylum: freshSpecies?.phylum || "Unknown",
              class: freshSpecies?.class || "Unknown",
              order: freshSpecies?.order || "Unknown",
              family: freshSpecies?.family || "Unknown",
              genus: freshSpecies?.genus || "Unknown",
              wikipedia_overview: freshSpecies?.wikipedia_overview ??
                externalData.wikiExtract ?? null,
              hazard_type: freshSpecies?.hazard_type ?? "none",
              native_region: "Unknown",
              iucn_red_list_status: freshSpecies?.iucn_red_list_status ??
                "not_evaluated",
              habitat_description: freshSpecies?.habitat_description ||
                undefined,
              wikipedia_url: freshSpecies?.wikipedia_url ||
                externalData.wikipediaUrl,
              gbif_taxon_key: freshSpecies?.gbif_taxon_key ??
                externalData.gbifKey,
              reference_image_url: freshSpecies?.reference_image_url ||
                externalData.referenceImageUrl,
            },
            supabaseAdmin,
          );
          speciesId = upsertedId || freshSpecies?.id || null;
        }

        await insertDescribeScan(
          {
            id: generatedScanId,
            user_id: user.id,
            species_id: speciesId,
            timestamp: timestamp ?? undefined,
            gps_lat_exact: safeGpsLat,
            gps_long_exact: safeGpsLon,
            gps_elevation: gpsElevation,
            ai_confidence_score: payloadReadyForClient.confidence_score,
            is_biological_subject: parsedData.is_biological_subject,
            ecology_type: payloadReadyForClient.ecology_type,
            is_invasive: payloadReadyForClient.is_invasive,
            weather_condition: weatherCondition,
            weather_temperature_f: weatherTemperatureF,
            semantic_location: semanticLocation,
            public_location_label: publicExploreLocationLabel,
            device_locale: deviceLocale,
            device_time_zone: deviceTimeZone,
            current_month: normalizedCurrentMonth ?? null,
            time_of_day: timeOfDay,
            ai_reasoning: parsedData.ai_reasoning ?? null,
            extracted_visual_traits: parsedData.extracted_visual_traits ?? [],
            colors: [],
            image_storage_urls: [],
            llm_prompt_tokens: llmPromptTokens,
            llm_candidate_tokens: llmCandidateTokens,
            llm_thinking_tokens: llmThinkingTokens,
            llm_cached_tokens: llmCachedTokens,
            llm_total_tokens: llmTotalTokens,
            life_stage: parsedData.life_stage ?? "unknown",
            reproductive_condition: parsedData.reproductive_condition ??
              "not_applicable",
            sex: parsedData.sex ?? null,
            sex_confidence: parsedData.sex_confidence ?? null,
            sex_evidence: parsedData.sex_evidence ?? null,
            individual_count: parsedData.individual_count ?? null,
            ecological_interactions: [],
            inference_tier: userTier === "pro" ? "pro" : "flash",
            candidates: payloadReadyForClient.candidates ?? null,
            image_quality_score: null,
            is_live_capture: false,
            user_observation_context: (observation_context != null &&
                typeof observation_context === "object" &&
                !Array.isArray(observation_context))
              ? observation_context as Record<string, unknown>
              : null,
          },
          supabaseAdmin,
        );

        const resolvedGroupTags = await groupTagsPromise;
        if (resolvedGroupTags?.group_tags?.length && isIdentifiedBio) {
          await updateGroupTags(
            parsedData.scientific_name!,
            resolvedGroupTags.group_tags,
            supabaseAdmin,
          );
          if (!payloadReadyForClient.group_tags?.length) {
            payloadReadyForClient.group_tags = resolvedGroupTags.group_tags;
          }
        }

        if (missingCandidates.length > 0) {
          await Promise.allSettled(
            missingCandidates.slice().map(async (candidateName) => {
              const externalData = await fetchExternalEnrichment(candidateName);
              if (externalData.wikiExtract || externalData.gbifKey) {
                await upsertSpeciesDictionary(
                  {
                    scientific_name: candidateName,
                    common_names: {},
                    native_region: "Unknown",
                    wikipedia_overview: externalData.wikiExtract ?? null,
                    wikipedia_url: externalData.wikipediaUrl,
                    gbif_taxon_key: externalData.gbifKey,
                    reference_image_url: externalData.referenceImageUrl,
                  },
                  supabaseAdmin,
                );
              }
            }),
          );
        }
      } catch (bgError) {
        logStructuredError("identify-describe/background_ingestion_failed", {
          user_id: user.id,
          error: bgError instanceof Error ? bgError.message : String(bgError),
        });
      }
    };

    runBackground(runBackgroundIngestion());

    console.log(`[⏱ BENCH] total: ${Date.now() - fnStart}ms`);
    return jsonResponse({ success: true, data: payloadReadyForClient });
  })
);
