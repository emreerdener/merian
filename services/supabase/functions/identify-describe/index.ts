import {
  jsonResponse,
  logStructuredError,
  runBackground,
  withEdgeHandler,
} from "../_shared/edgeHandler.ts";
import { geminiUsageModalityBreakdown } from "../_shared/aiUsage.ts";
import { fetchQuotaGuardedGroupTags } from "../_shared/groupTagQuota.ts";
import { fetchExternalEnrichment } from "../_shared/external.ts";
import { _genAI, extractJson } from "../_shared/gemini.ts";
import { tierTelemetryProperties } from "../_shared/entitlement.ts";
import {
  AIQuotaError,
  reserveAIProviderCall,
  resolveAIRequestId,
} from "../_shared/aiQuota.ts";
import { trackPostHogEvent } from "../_shared/posthog.ts";
import {
  parseJsonBody,
  PublicHttpError,
  requireParams,
} from "../_shared/http.ts";
import {
  buildObservationPrompt,
  normalizeCurrentMonth,
  sanitizeLifeStage,
  sanitizeObservationConfidence,
  sanitizeObservationEvidence,
  sanitizeReproductiveCondition,
  sanitizeSex,
} from "../_shared/identify/context.ts";
import {
  CachedSpeciesRow,
  ClientPayload,
  StaticSpeciesData,
} from "../_shared/identify/types.ts";
import {
  parseDescribeIdentification,
  parseIdentifySuccessEnvelope,
} from "../_shared/identify/contract.ts";
import {
  fetchCompletedIdentifyResponse,
  waitForCompletedIdentifyResponse,
} from "../_shared/identify/completedResponse.ts";
import {
  canonicalizeDomesticPetScientificName,
  sanitizePetIdentification,
  sanitizeScientificName,
} from "../identify/sanitize.ts";

import { diagnosticTriggerForTier } from "../_shared/identify/thresholds.ts";
import { createCompatibilityScanIngestionLedger } from "../_shared/scanIngestionCompatibility.ts";
import {
  getDescribeResponseSchema,
  getDescribeSystemInstruction,
} from "./schema.ts";
import {
  fetchCachedSpecies,
  fetchCandidateCommonNames,
  insertDescribeScan,
  mergeSpeciesCommonNames,
  updateGroupTags,
  upsertGhostUserIfMissing,
  upsertSpeciesDictionary,
} from "./db.ts";
import {
  isNewToMerianDictionary,
  normalizeWireHazardType,
} from "../_shared/identify/clientPayload.ts";
import { normalizeProcessedMaterialSubject } from "../_shared/identify/subjectClassification.ts";

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

interface DescribeRequestBody extends Record<string, unknown> {
  user_id?: string;
  description?: string;
  gpsLatitude?: number | null;
  gpsLongitude?: number | null;
  gpsElevation?: number | null;
  weatherCondition?: string | null;
  weatherTemperatureF?: number | null;
  deviceLocale?: string | null;
  deviceTimeZone?: string | null;
  deviceRegion?: string | null;
  currentMonth?: unknown;
  semanticLocation?: string | null;
  publicLocationLabel?: string | null;
  public_location_label?: string | null;
  geoprivacy?: string | null;
  timeOfDay?: string | null;
  timestamp?: string | null;
  client_scan_id?: unknown;
  preferred_goal?: unknown;
  observation_context?: unknown;
}

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const fnStart = Date.now();
    const body = await parseJsonBody<DescribeRequestBody>(req, {
      limit: "standard",
    });
    if (body instanceof Response) return body;

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
      geoprivacy,
      timeOfDay,
      timestamp,
      client_scan_id,
      preferred_goal,
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

    const generatedScanId = resolveAIRequestId(req, client_scan_id);
    const existingCompletion = await fetchCompletedIdentifyResponse(
      generatedScanId,
      user.id,
      supabaseAdmin,
    );
    if (existingCompletion) {
      return jsonResponse(existingCompletion.envelope, 200, {
        "X-Merian-Idempotent-Replay": existingCompletion.source,
      });
    }

    console.log(`[⏱ BENCH] payload_parsed: ${Date.now() - fnStart}ms`);

    let quotaLease;
    try {
      quotaLease = await reserveAIProviderCall(req, supabaseAdmin, {
        userId: user.id,
        operation: "scan_identification",
        requestId: generatedScanId,
      });
    } catch (error) {
      if (
        error instanceof AIQuotaError &&
        (
          error.code === "ai_request_already_completed" ||
          error.code === "ai_request_in_progress"
        )
      ) {
        const replay = await waitForCompletedIdentifyResponse(
          generatedScanId,
          user.id,
          supabaseAdmin,
        );
        if (replay) {
          return jsonResponse(replay.envelope, 200, {
            "X-Merian-Idempotent-Replay": replay.source,
          });
        }
      }
      throw error;
    }
    const tierResolution = quotaLease.reservation.tier;
    const userTier = tierResolution.effective_tier;
    const targetModel = quotaLease.reservation.model;
    const diagnosticTrigger = diagnosticTriggerForTier(
      userTier === "pro" ? "pro" : "flash",
    );
    let compatibilityLedger;
    try {
      compatibilityLedger = await createCompatibilityScanIngestionLedger(
        {
          scanId: generatedScanId,
          userId: user.id,
          endpoint: "identify-describe",
          description,
          preferredGoal: preferred_goal,
          observationContexts: observation_context &&
              typeof observation_context === "object" &&
              !Array.isArray(observation_context)
            ? [observation_context as Record<string, unknown>]
            : [],
          telemetry: {
            timestamp,
            gpsLatitude: safeGpsLat,
            gpsLongitude: safeGpsLon,
            gpsElevation,
            semanticLocation,
            publicLocationLabel: publicExploreLocationLabel,
            geoprivacy,
            weatherCondition,
            weatherTemperatureF,
            deviceLocale,
            deviceTimeZone,
            deviceRegion,
            currentMonth: normalizedCurrentMonth,
            timeOfDay,
          },
          logStructuredError,
        },
        supabaseAdmin,
      );
    } catch (error) {
      await quotaLease.refund();
      if (
        error instanceof PublicHttpError &&
        error.code === "scan_already_complete"
      ) {
        const replay = await fetchCompletedIdentifyResponse(
          generatedScanId,
          user.id,
          supabaseAdmin,
        );
        if (replay) {
          return jsonResponse(replay.envelope, 200, {
            "X-Merian-Idempotent-Replay": replay.source,
          });
        }
      }
      throw error;
    }
    const modelCfg = targetModel === "gemini-2.5-pro"
      ? modelConfigs.pro
      : modelConfigs.flash;

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
    let llmUsageMetadata: Record<string, unknown> = {};
    let providerAttempted = false;

    try {
      await quotaLease.commit();
      providerAttempted = true;
      const result = await _genAI.models.generateContent({
        model: targetModel,
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
        llmUsageMetadata = geminiUsageModalityBreakdown(usage);
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
      if (providerAttempted) {
        await quotaLease.fail();
      } else {
        await quotaLease.refund();
      }
      const errMsg = genError instanceof Error
        ? genError.message
        : String(genError);
      await compatibilityLedger.markRetryableFailure(
        "ai_provider_failed",
        errMsg,
      );
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
      if (!isPermanentContentFailure) await quotaLease.fail();
      if (isPermanentContentFailure) {
        await compatibilityLedger.markTerminalFailure(
          "ai_provider_policy_rejected",
          `Provider finish reason: ${finishReason}`,
          "content_policy_rejected",
        );
      } else {
        await compatibilityLedger.markRetryableFailure(
          "ai_provider_non_stop_finish",
          `Provider finish reason: ${finishReason}`,
        );
      }
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

    let parsedData;
    try {
      parsedData = parseDescribeIdentification(
        extractJson<unknown>(responseText),
      );
    } catch (parseError) {
      await quotaLease.fail();
      await compatibilityLedger.markRetryableFailure(
        "ai_response_parse_failed",
        parseError,
      );
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
      parsedData.scientific_name = canonicalizeDomesticPetScientificName(
        parsedData.scientific_name,
        parsedData.pet_identification,
        parsedData.common_name,
      );
    }
    parsedData.pet_identification = sanitizePetIdentification(
      parsedData.pet_identification,
      parsedData.scientific_name,
    );
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
    parsedData.invasive_status_region = sanitizeObservationEvidence(
      parsedData.invasive_status_region,
      160,
    );
    parsedData.invasive_rationale = sanitizeObservationEvidence(
      parsedData.invasive_rationale,
      500,
    );
    parsedData.invasive_confidence = sanitizeObservationConfidence(
      parsedData.invasive_confidence,
    );
    const processedMaterialNormalization = normalizeProcessedMaterialSubject(
      parsedData,
    );
    if (processedMaterialNormalization.demoted) {
      logStructuredError("identify-describe/processed_material_demoted", {
        user_id: user.id,
        reason: processedMaterialNormalization.reason,
        previous_common_name:
          processedMaterialNormalization.previousCommonName ?? null,
        previous_scientific_name:
          processedMaterialNormalization.previousScientificName ?? null,
      });
    }
    if (!parsedData.is_biological_subject) {
      parsedData.is_invasive = undefined;
      parsedData.invasive_status_region = undefined;
      parsedData.invasive_rationale = undefined;
      parsedData.invasive_confidence = undefined;
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
    const hasInvasiveLocationContext =
      (safeGpsLat != null && safeGpsLon != null) ||
      (typeof semanticLocation === "string" &&
        semanticLocation.trim().length > 0);
    if (parsedData.is_biological_subject && !hasInvasiveLocationContext) {
      parsedData.is_invasive = false;
      parsedData.invasive_status_region ??= "Unavailable";
      parsedData.invasive_rationale ??=
        "Location context was unavailable, so Naturebook could not make a region-specific invasive assessment.";
      parsedData.invasive_confidence = undefined;
    }

    // Describes always have zero blur (no image).
    parsedData.blur_score = 0;

    let payloadReadyForClient: ClientPayload = {
      ...parsedData,
      scan_id: generatedScanId,
      blur_score: parsedData.blur_score ?? 0,
      colors: [],
      estimated_size_cm: null,
      pet_identification: parsedData.pet_identification ?? null,
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
      payloadReadyForClient.is_new_to_merian_dictionary =
        isNewToMerianDictionary(isIdentifiedBio, cachedSpecies);
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
          hazard_type: normalizeWireHazardType(
            cachedSpecies.hazard_type,
          ),
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
        hazard_type: normalizeWireHazardType(staticData.hazard_type),
      };
      if (staticData.speciesHabitat) {
        payloadReadyForClient.species_insights = {
          habitat_description: staticData.speciesHabitat,
        };
      }
    }

    let responseEnvelope;
    try {
      responseEnvelope = parseIdentifySuccessEnvelope({
        success: true,
        data: payloadReadyForClient,
      });
      payloadReadyForClient = responseEnvelope.data;
    } catch (error) {
      await quotaLease.fail();
      await compatibilityLedger.markRetryableFailure(
        "wire_contract_failed",
        error,
      );
      logStructuredError("identify-describe/wire_contract_failed", {
        user_id: user.id,
        scan_id: generatedScanId,
        error: error instanceof Error ? error.message : String(error),
      });
      return jsonResponse(
        {
          error: "AI response validation failed. Please retry.",
          code: "identify_response_invalid",
        },
        502,
      );
    }

    await compatibilityLedger.mark(
      "finalizing",
      "background_ingestion_queued",
      { leaseSeconds: 300 },
    );

    const runBackgroundIngestion = async () => {
      let scanInserted = false;
      try {
        await upsertGhostUserIfMissing(user.id, supabaseAdmin);

        const needsGroupTags = isIdentifiedBio &&
          !cachedSpecies?.group_tags?.length;
        const groupTagsPromise = needsGroupTags
          ? fetchQuotaGuardedGroupTags(
            req,
            user,
            parsedData.scientific_name!,
            supabaseAdmin,
            quotaLease.reservation.requestId,
          )
          : Promise.resolve(null);

        if (!speciesId && isIdentifiedBio) {
          const externalData = await fetchExternalEnrichment(
            parsedData.scientific_name!,
          );
          const freshSpecies = await fetchCachedSpecies(
            parsedData.scientific_name!,
            supabaseAdmin,
          );

          const newCommonNames = mergeSpeciesCommonNames(
            freshSpecies?.common_names ?? cachedSpecies?.common_names,
            parsedData.common_name,
          );
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
            ecology_type: payloadReadyForClient.ecology_type ?? undefined,
            is_invasive: payloadReadyForClient.is_invasive ?? undefined,
            invasive_status_region:
              payloadReadyForClient.invasive_status_region ?? null,
            invasive_rationale: payloadReadyForClient.invasive_rationale ??
              null,
            invasive_confidence: payloadReadyForClient.invasive_confidence ??
              null,
            weather_condition: weatherCondition ?? undefined,
            weather_temperature_f: weatherTemperatureF ?? undefined,
            semantic_location: semanticLocation ?? undefined,
            public_location_label: publicExploreLocationLabel,
            geoprivacy,
            device_locale: deviceLocale ?? undefined,
            device_time_zone: deviceTimeZone ?? undefined,
            current_month: normalizedCurrentMonth ?? null,
            time_of_day: timeOfDay ?? undefined,
            ai_reasoning: parsedData.ai_reasoning ?? null,
            extracted_visual_traits: parsedData.extracted_visual_traits ?? [],
            colors: [],
            image_storage_urls: [],
            llm_prompt_tokens: llmPromptTokens,
            llm_candidate_tokens: llmCandidateTokens,
            llm_thinking_tokens: llmThinkingTokens,
            llm_cached_tokens: llmCachedTokens,
            llm_total_tokens: llmTotalTokens,
            llm_usage_metadata: llmUsageMetadata,
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
            pet_identification: parsedData.pet_identification ?? null,
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
        scanInserted = true;
        await compatibilityLedger.markComplete({ responseEnvelope });

        const resolvedGroupTags = await groupTagsPromise;
        if (resolvedGroupTags?.group_tags?.length && isIdentifiedBio) {
          await updateGroupTags(
            parsedData.scientific_name!,
            resolvedGroupTags.group_tags,
            supabaseAdmin,
          );
        }

        if (missingCandidates.length > 0) {
          await Promise.allSettled(
            missingCandidates.slice().map(async (candidateName) => {
              const externalData = await fetchExternalEnrichment(candidateName);
              if (externalData.wikiExtract || externalData.gbifKey) {
                const primaryEnName = (externalData.wikiTitle &&
                    externalData.wikiTitle.toLowerCase() !==
                      candidateName.toLowerCase())
                  ? externalData.wikiTitle.replace(/\s*\([^)]+\)$/, "").trim()
                  : (externalData.alternativeCommonNames[0] ?? null);
                const freshCandidateSpecies = await fetchCachedSpecies(
                  candidateName,
                  supabaseAdmin,
                );
                await upsertSpeciesDictionary(
                  {
                    scientific_name: candidateName,
                    common_names: mergeSpeciesCommonNames(
                      freshCandidateSpecies?.common_names,
                      primaryEnName,
                    ),
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

        const totalTokens = (llmTotalTokens ?? 0) +
          (resolvedGroupTags?.usage?.totalTokenCount ?? 0);
        trackPostHogEvent(user, "ScanCompleted", {
          is_biological_subject: parsedData.is_biological_subject,
          tier: userTier,
          ...tierTelemetryProperties(tierResolution),
          llm_model: targetModel,
          llm_prompt_tokens: llmPromptTokens,
          llm_candidate_tokens: llmCandidateTokens,
          llm_thinking_tokens: llmThinkingTokens,
          llm_cached_tokens: llmCachedTokens,
          llm_total_tokens: llmTotalTokens,
          encyclopedic_tokens: 0,
          similar_species_tokens: 0,
          group_tags_tokens: resolvedGroupTags?.usage?.totalTokenCount ?? 0,
          cumulative_scan_tokens: totalTokens,
          scientific_name: parsedData.scientific_name,
        }).catch((e) => console.error("PostHog tracking failed:", e));
      } catch (bgError) {
        if (!scanInserted) {
          await compatibilityLedger.markRetryableFailure(
            "background_ingestion_failed",
            bgError,
          );
        }
        logStructuredError("identify-describe/background_ingestion_failed", {
          user_id: user.id,
          scan_id: generatedScanId,
          error: bgError instanceof Error ? bgError.message : String(bgError),
          scan_inserted: scanInserted,
        });
      }
    };

    runBackground(runBackgroundIngestion());

    console.log(`[⏱ BENCH] total: ${Date.now() - fnStart}ms`);
    return jsonResponse(responseEnvelope);
  })
);
