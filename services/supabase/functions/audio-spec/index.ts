import { Schema, Type } from "@google/genai";
import { geminiUsageModalityBreakdown } from "../_shared/aiUsage.ts";

import {
  jsonResponse,
  logStructuredError,
  runBackground,
  withEdgeHandler,
} from "../_shared/edgeHandler.ts";
import { _genAI, extractJson } from "../_shared/gemini.ts";
import {
  entitlementProtocolResponse,
  tierTelemetryProperties,
} from "../_shared/entitlement.ts";
import { isFlashFallbackEligible } from "../_shared/complimentaryScans.ts";
import {
  AIQuotaError,
  reserveAIProviderCall,
  resolveAIRequestId,
} from "../_shared/aiQuota.ts";
import { trackPostHogEvent } from "../_shared/posthog.ts";
import {
  publicErrorResponse,
  PublicHttpError,
  requireParams,
} from "../_shared/http.ts";
import { fetchExternalEnrichment } from "../_shared/external.ts";
import { fetchQuotaGuardedGroupTags } from "../_shared/groupTagQuota.ts";
import { deleteR2ObjectIfPresent, getR2Config } from "../_shared/aws.ts";
import {
  processWavBuffer,
  TARGET_AUDIO_SAMPLE_RATE,
} from "../_shared/audioProcessing.ts";
import { resolveAudioBuffers } from "../_shared/identify/media.ts";
import { promoteSafeMedia } from "../_shared/identify/moderation.ts";
import { mergeSpeciesCommonNames } from "../_shared/identify/db.ts";
import {
  buildContextText,
  normalizeCurrentMonth,
  sanitizeObservationConfidence,
  sanitizeObservationEvidence,
  sanitizeSex,
} from "../_shared/identify/context.ts";
import { isNewToMerianDictionary } from "../_shared/identify/clientPayload.ts";
import {
  fetchCompletedIdentifyResponse,
  waitForCompletedIdentifyResponse,
} from "../_shared/identify/completedResponse.ts";
import {
  type IdentifySuccessEnvelope,
  parseIdentifySuccessEnvelope,
} from "../_shared/identify/contract.ts";
import {
  MEDIA_BUDGETS,
  readRequestJsonWithinBudget,
} from "../_shared/mediaBudgets.ts";
import { createCompatibilityScanIngestionLedger } from "../_shared/scanIngestionCompatibility.ts";
import { recoverStrandedScanIngestionAttempt } from "../_shared/scanIngestionJobs.ts";
import { isScanPersistenceOutcomeUnknown } from "../_shared/scanPersistence.ts";

import {
  AudioCandidate,
  AudioClientPayload,
  AudioClientRequest,
  AudioIdentification,
} from "./types.ts";
import {
  CachedSpeciesRow,
  fetchCachedSpecies,
  insertScan,
  updateGroupTags,
  upsertGhostUserIfMissing,
  upsertSpeciesDictionary,
} from "./db.ts";
// Gemini confidence threshold below which candidates are forwarded to the iOS client.
const DIAGNOSTIC_TRIGGER = 0.95;

const BIOACOUSTIC_SYSTEM_INSTRUCTION = `# Role
You are a world-class bioacoustic field biologist with expertise in identifying species from their acoustic signatures across all taxa: birds, insects, frogs, mammals, and other wildlife.

# Task
Listen to the provided audio recording and identify the primary biological sound source, if any.

# Response Rules
- is_biological_subject: true only when a genuine biological vocalization is detected. false for wind, rain, mechanical noise, silence, or human speech without wildlife.
- scientific_name: formal binomial nomenclature (Genus species) for the primary identified species. Omit entirely if is_biological_subject is false.
- confidence_score: 0.0–1.0. Use below 0.70 when the recording is ambiguous, noisy, or the call is partially obscured.
- ai_reasoning: concise acoustic diagnosis citing observable call characteristics (frequency, tempo, pattern, note duration, harmonic structure). Be specific.
- ecology_type: "wild" for natural habitat, "urban" for urban/suburban, "domesticated" for pets or livestock.
- is_invasive, invasive_status_region, invasive_rationale, invasive_confidence: produce one location-aware invasive assessment from the supplied GPS/coarse location, species identity, and ecological context. invasive_status_region is the region label used, not the status. If location context is missing, return is_invasive=false, invasive_status_region="Unavailable", explain the limitation in invasive_rationale, and use low or null invasive_confidence. Omit these fields for non-biological sounds.
- sex: use female, male, mixed, hermaphrodite, cannot_determine, or not_applicable. Only report female/male/mixed when the recording contains explicit species-specific acoustic evidence that distinguishes sex; otherwise use cannot_determine. Never infer or report human sex/gender.
- sex_confidence: 0.0–1.0 confidence in the sex annotation from direct acoustic evidence only. Omit when sex is cannot_determine or not_applicable.
- sex_evidence: short acoustic cue supporting sex, such as sex-specific song, call type, or duet role. Omit when unsupported.
- candidates: up to 3 alternative species when confidence is below ${DIAGNOSTIC_TRIGGER}. Only species with genuinely similar acoustic signatures.
- Use authoritative nomenclature (Clements Checklist v2024 for birds, GBIF Backbone Taxonomy for all other taxa).
- Never fabricate scientific names.`;

const audioSchema: Record<string, unknown> = {
  type: Type.OBJECT,
  properties: {
    is_biological_subject: { type: Type.BOOLEAN },
    scientific_name: { type: Type.STRING },
    common_name: { type: Type.STRING },
    confidence_score: { type: Type.NUMBER },
    ai_reasoning: { type: Type.STRING },
    ecology_type: {
      type: Type.STRING,
      enum: ["wild", "urban", "domesticated", "unknown"],
    },
    is_invasive: { type: Type.BOOLEAN },
    invasive_status_region: { type: Type.STRING },
    invasive_rationale: { type: Type.STRING },
    invasive_confidence: { type: Type.NUMBER },
    sex: {
      type: Type.STRING,
      enum: [
        "female",
        "male",
        "hermaphrodite",
        "mixed",
        "cannot_determine",
        "not_applicable",
      ],
    },
    sex_confidence: { type: Type.NUMBER },
    sex_evidence: { type: Type.STRING },
    candidates: {
      type: Type.ARRAY,
      items: {
        type: Type.OBJECT,
        properties: {
          scientific_name: { type: Type.STRING },
          confidence_score: { type: Type.NUMBER },
          distinguishing_feature: { type: Type.STRING },
        },
        required: [
          "scientific_name",
          "confidence_score",
          "distinguishing_feature",
        ],
      },
    },
  },
  required: ["is_biological_subject", "confidence_score", "ai_reasoning"],
};

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const protocolError = await entitlementProtocolResponse(
      req,
      supabaseAdmin,
    );
    if (protocolError) return protocolError;

    const fnStart = Date.now();
    const bodyReadResult = await readRequestJsonWithinBudget<
      Record<string, unknown>
    >(
      req,
      MEDIA_BUDGETS.maxAudioJsonBodyBytes,
    );
    if (bodyReadResult.error || !bodyReadResult.value) {
      return jsonResponse(
        { error: bodyReadResult.error?.message ?? "Invalid JSON body" },
        bodyReadResult.error?.status ?? 400,
      );
    }

    const rawBody = bodyReadResult.value;

    const paramError = requireParams(rawBody, ["user_id"]);
    if (paramError) return paramError;

    if (!rawBody.audio_r2_key && !rawBody.audio_base64) {
      return jsonResponse({
        error: "Missing required parameter: audio_r2_key or audio_base64",
      }, 400);
    }

    const body = rawBody as unknown as AudioClientRequest;
    const {
      audio_r2_key,
      audio_base64,
      client_scan_id,
      preferred_goal,
      timestamp,
      gps_latitude,
      gps_longitude,
      gps_elevation,
      semantic_location,
      public_location_label,
      geoprivacy,
      weather_condition,
      weather_temperature_f,
      device_locale,
      device_time_zone,
      device_region,
      current_month,
      time_of_day,
    } = body;
    // Inline bytes win when old clients send both bytes and a destination-name
    // hint. Never fetch, ledger, finalize, or delete an ignored hint.
    const stagedAudioSourceKey = audio_base64 ? undefined : audio_r2_key;
    const normalizedCurrentMonth = normalizeCurrentMonth(current_month);
    const generatedScanId = resolveAIRequestId(req, client_scan_id);
    let strandedRecovery;
    try {
      strandedRecovery = await recoverStrandedScanIngestionAttempt(
        generatedScanId,
        user.id,
        supabaseAdmin,
      );
    } catch (error) {
      logStructuredError("audio_spec/scan_ingestion_recovery_failed", {
        user_id: user.id,
        scan_id: generatedScanId,
        error: error instanceof Error ? error.message : String(error),
      });
      return publicErrorResponse(
        req,
        503,
        "scan_recovery_unavailable",
        "We couldn’t safely resume this observation. Please try again.",
        { retryAfterSeconds: 5 },
      );
    }
    if (
      strandedRecovery?.outcome === "media_restage_required" &&
      typeof stagedAudioSourceKey === "string" &&
      !stagedAudioSourceKey.startsWith(`staging/${user.id}/`)
    ) {
      return publicErrorResponse(
        req,
        409,
        "scan_media_restage_required",
        "This observation’s upload needs to be refreshed for your account.",
        { retryAfterSeconds: 1 },
      );
    }

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

    // GPS range validation — out-of-bounds values are sanitised to null (same policy as identify).
    const safeGpsLat: number | null =
      gps_latitude != null && Number.isFinite(gps_latitude) &&
        gps_latitude >= -90 && gps_latitude <= 90
        ? gps_latitude
        : null;
    const safeGpsLon: number | null =
      gps_longitude != null && Number.isFinite(gps_longitude) &&
        gps_longitude >= -180 && gps_longitude <= 180
        ? gps_longitude
        : null;

    // 1. Load audio — either from base64 inline payload (iOS live path) or R2 staging.
    const audioResolution = await resolveAudioBuffers({
      userId: user.id,
      audioR2ObjectKeys: stagedAudioSourceKey ? [stagedAudioSourceKey] : [],
      audioBase64s: audio_base64 ? [audio_base64] : [],
      idorEvent: "audio_spec/idor_attempt",
      r2FetchFailedEvent: "audio_spec/audio_r2_fetch_failed",
      pathTraversalMessage: "Bad Request: path traversal detected.",
      wrongUserMessage:
        "Forbidden: audio_r2_key does not belong to the requesting user.",
      r2FetchError: (response: Response) => ({
        message: `Audio file not found in staging (${response.status}).`,
        status: 404,
      }),
    });
    if (audioResolution.errorResponse) return audioResolution.errorResponse;
    const rawWavBuffer = audioResolution.audioBuffers[0];
    const r2Config = audioResolution.r2Config ?? null;
    console.log(
      `[⏱ BENCH] ${audio_base64 ? "base64_decode" : "r2_download"}: ${
        Date.now() - fnStart
      }ms, size=${rawWavBuffer.byteLength}`,
    );

    // 2. Process audio: parse → mono → trim silence → resample → re-encode
    let base64Audio: string;
    try {
      const processedAudio = processWavBuffer(rawWavBuffer);
      base64Audio = processedAudio.base64Audio;
      console.log(
        `[audio-spec] WAV: ${processedAudio.sourceSampleRate}Hz ${processedAudio.sourceChannels}ch → ` +
          `${TARGET_AUDIO_SAMPLE_RATE}Hz mono, trimmed ${processedAudio.originalSampleCount}` +
          `→${processedAudio.trimmedSampleCount} samples, resampled=${processedAudio.resampledSampleCount}, ` +
          `encoded ${processedAudio.encodedByteLength} bytes`,
      );
    } catch (wavErr) {
      const msg = wavErr instanceof Error ? wavErr.message : String(wavErr);
      logStructuredError("audio_spec/wav_parse_failed", {
        user_id: user.id,
        error: msg,
      });
      return jsonResponse({ error: "Invalid audio file format." }, 400);
    }

    try {
      await upsertGhostUserIfMissing(user.id, supabaseAdmin);
    } catch (error) {
      logStructuredError("audio_spec/scan_user_profile_unavailable", {
        user_id: user.id,
        scan_id: generatedScanId,
        error: error instanceof Error ? error.message : String(error),
      });
      return publicErrorResponse(
        req,
        503,
        "scan_user_profile_unavailable",
        "We couldn’t prepare this observation for saving. Please try again.",
        { retryAfterSeconds: 5 },
      );
    }

    // 4. Atomically resolve entitlement and reserve quota before provider work.
    let quotaLease;
    try {
      quotaLease = await reserveAIProviderCall(req, supabaseAdmin, {
        userId: user.id,
        operation: "scan_audio_identification",
        requestId: generatedScanId,
        originalAnalysisId: generatedScanId,
        flashFallbackEligible: isFlashFallbackEligible({
          imageCount: 0,
          audioCount: 1,
          descriptionCount: 0,
          videoCount: 0,
        }),
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
    let compatibilityLedger;
    try {
      compatibilityLedger = await createCompatibilityScanIngestionLedger(
        {
          scanId: generatedScanId,
          userId: user.id,
          endpoint: "audio-spec",
          audioKeys: stagedAudioSourceKey ? [stagedAudioSourceKey] : [],
          inlineAudioCount: audio_base64 ? 1 : 0,
          audioMediaItems: [{ kind: "audio", sourceIndex: 0, clipIndex: 0 }],
          preferredGoal: preferred_goal,
          telemetry: {
            timestamp,
            gpsLatitude: safeGpsLat,
            gpsLongitude: safeGpsLon,
            gpsElevation: gps_elevation,
            semanticLocation: semantic_location,
            publicLocationLabel: public_location_label,
            geoprivacy,
            weatherCondition: weather_condition,
            weatherTemperatureF: weather_temperature_f,
            deviceLocale: device_locale,
            deviceTimeZone: device_time_zone,
            deviceRegion: device_region,
            currentMonth: normalizedCurrentMonth,
            timeOfDay: time_of_day,
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

    // 5. Call Gemini with audio inline data
    console.log(`[⏱ BENCH] pre_gemini: ${Date.now() - fnStart}ms`);
    const geminiStart = Date.now();

    let responseText = "";
    let llmPromptTokens: number | null = null;
    let llmCandidateTokens: number | null = null;
    let llmThinkingTokens: number | null = null;
    let llmTotalTokens: number | null = null;
    let llmUsageMetadata: Record<string, unknown> = {};
    let finishReason: string | undefined;
    let providerAttempted = false;

    try {
      await quotaLease.commit();
      providerAttempted = true;
      const result = await _genAI.models.generateContent({
        model: quotaLease.reservation.model,
        contents: [
          {
            role: "user",
            parts: [
              {
                text: buildContextText(
                  {
                    safeGpsLat,
                    safeGpsLon,
                    gpsElevation: gps_elevation,
                    semanticLocation: semantic_location,
                    weatherCondition: weather_condition,
                    weatherTemperatureF: weather_temperature_f,
                    deviceLocale: device_locale,
                    deviceTimeZone: device_time_zone,
                    deviceRegion: device_region,
                    currentMonth: normalizedCurrentMonth,
                    timeOfDay: time_of_day,
                  },
                  "Perform bioacoustic identification.",
                ),
              },
              { inlineData: { mimeType: "audio/wav", data: base64Audio } },
            ],
          },
        ],
        config: {
          systemInstruction: BIOACOUSTIC_SYSTEM_INSTRUCTION,
          temperature: 0.1,
          seed: 42,
          maxOutputTokens: 2048,
          thinkingConfig: { thinkingBudget: 2048 },
          responseMimeType: "application/json",
          responseSchema: audioSchema as unknown as Schema,
        },
      });

      finishReason = result.candidates?.[0]?.finishReason;
      responseText = result.text ?? "";

      // Defensive fallback for @google/genai@1.0.0 text getter edge case
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
        llmThinkingTokens = usage.thoughtsTokenCount ?? null;
        llmTotalTokens = usage.totalTokenCount ?? null;
        console.log(
          `Token Usage [audio-spec | ${user.id}]: Prompt: ${llmPromptTokens} | Candidates: ${llmCandidateTokens} | Thinking: ${llmThinkingTokens} | Total: ${llmTotalTokens}`,
        );
      }
      console.log(
        `[⏱ BENCH] gemini_done: ${Date.now() - fnStart}ms total, ${
          Date.now() - geminiStart
        }ms inference`,
      );
    } catch (genErr) {
      if (providerAttempted) {
        await quotaLease.fail();
      } else {
        await quotaLease.refund();
      }
      const errMsg = genErr instanceof Error ? genErr.message : String(genErr);
      await compatibilityLedger.markRetryableFailure(
        "ai_provider_failed",
        errMsg,
      );
      logStructuredError("audio_spec/gemini_failed", {
        user_id: user.id,
        elapsed_ms: Date.now() - geminiStart,
        error: errMsg,
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
      const isPermanent = finishReason === "SAFETY" ||
        finishReason === "PROHIBITED_CONTENT";
      if (!isPermanent) await quotaLease.fail();
      if (isPermanent) {
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
      logStructuredError("audio_spec/non_stop_finish", {
        user_id: user.id,
        finish_reason: finishReason,
      });
      if (isPermanent) {
        return publicErrorResponse(
          req,
          400,
          "observation_rejected",
          "We couldn’t process this observation. Please try a different photo or recording.",
        );
      }
      return jsonResponse(
        { error: "AI processing error. Please try again." },
        503,
      );
    }

    // 6. Parse Gemini response
    let parsedData: AudioIdentification;
    try {
      parsedData = extractJson<AudioIdentification>(responseText);
    } catch (parseErr) {
      await quotaLease.fail();
      await compatibilityLedger.markRetryableFailure(
        "ai_response_parse_failed",
        parseErr,
      );
      logStructuredError("audio_spec/parse_failed", {
        user_id: user.id,
        finish_reason: finishReason ?? "unknown",
        response_length: responseText.length,
        response_preview: responseText.slice(0, 500),
        error: parseErr instanceof Error ? parseErr.message : String(parseErr),
      });
      return jsonResponse(
        { error: "Processing Error: Malformed AI response." },
        503,
      );
    }

    // Cap candidates list (schema enforces this but extractJson is an unvalidated cast)
    if (Array.isArray(parsedData.candidates)) {
      parsedData.candidates = parsedData.candidates.slice(0, 5);
    }

    parsedData.sex = sanitizeSex(parsedData.sex);
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
      (typeof semantic_location === "string" &&
        semantic_location.trim().length > 0);
    if (parsedData.is_biological_subject && !hasInvasiveLocationContext) {
      parsedData.is_invasive = false;
      parsedData.invasive_status_region ??= "Unavailable";
      parsedData.invasive_rationale ??=
        "Location context was unavailable, so Naturebook could not make a region-specific invasive assessment.";
      parsedData.invasive_confidence = undefined;
    }

    const isIdentifiedBio =
      !!(parsedData.is_biological_subject && parsedData.scientific_name);
    const cachedSpecies: CachedSpeciesRow | null = isIdentifiedBio
      ? await fetchCachedSpecies(parsedData.scientific_name!, supabaseAdmin)
        .catch((error) => {
          logStructuredError("audio_spec/species_cache_read_fallback", {
            user_id: user.id,
            scan_id: generatedScanId,
            error: error instanceof Error ? error.message : String(error),
          });
          return null;
        })
      : null;

    // Strip candidates when confidence meets the diagnostic trigger threshold
    const forwardCandidates =
      (parsedData.confidence_score ?? 0) < DIAGNOSTIC_TRIGGER
        ? parsedData.candidates ?? null
        : null;

    // 7. Build initial payload (enriched further in the background task on cache hit)
    let payloadReadyForClient: AudioClientPayload = {
      scan_id: generatedScanId,
      is_biological_subject: parsedData.is_biological_subject,
      is_live_capture: true,
      scientific_name: parsedData.scientific_name,
      common_name: parsedData.common_name,
      confidence_score: parsedData.confidence_score,
      ecology_type: parsedData.ecology_type,
      is_invasive: parsedData.is_invasive,
      invasive_status_region: parsedData.invasive_status_region,
      invasive_rationale: parsedData.invasive_rationale,
      invasive_confidence: parsedData.invasive_confidence,
      life_stage: "unknown",
      sex: parsedData.sex,
      sex_confidence: parsedData.sex_confidence,
      sex_evidence: parsedData.sex_evidence,
      inference_tier: userTier === "pro" ? "pro" : "flash",
      is_new_to_merian_dictionary: isNewToMerianDictionary(
        isIdentifiedBio,
        cachedSpecies,
      ),
      candidates: forwardCandidates,
      blur_score: 0,
      colors: [],
      estimated_size_cm: null,
      pet_identification: null,
      image_quality: {
        sharpness: 0,
        framing: 0,
        diagnostic_utility: 0,
        overall_score: 0,
      },
      ai_reasoning: parsedData.ai_reasoning || "Reasoning omitted.",
      extracted_visual_traits: [
        "bioacoustic evidence from the submitted audio",
      ],
    };

    if (isIdentifiedBio) {
      payloadReadyForClient.insight_data = {
        ai_reasoning: parsedData.ai_reasoning || "Reasoning omitted.",
        hazard_type: "none",
      };
    }

    let responseEnvelope: IdentifySuccessEnvelope;
    try {
      responseEnvelope = parseIdentifySuccessEnvelope({
        success: true,
        data: payloadReadyForClient,
      });
      // Keep background enrichment mutable without changing the exact body
      // returned and persisted for idempotent replay.
      payloadReadyForClient = structuredClone(
        responseEnvelope.data,
      ) as AudioClientPayload;
    } catch (error) {
      await quotaLease.fail();
      await compatibilityLedger.markTerminalFailure(
        "wire_contract_failed",
        error,
        "malformed_response",
      );
      logStructuredError("audio_spec/wire_contract_failed", {
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

    // 8. Durable ingestion: profile, enrichment, media promotion, scan insert,
    // and complete-last ledger finalization.
    const runBackgroundIngestion = async () => {
      let scanInserted = false;
      let ledgerCompleted = false;
      let audioStorageUrls: string[] = [];
      try {
        await upsertGhostUserIfMissing(user.id, supabaseAdmin);

        let speciesId: string | null = null;
        const needsGroupTags = isIdentifiedBio;

        if (isIdentifiedBio) {
          if (cachedSpecies?.kingdom) {
            // Cache hit: serve taxonomy and species metadata
            speciesId = cachedSpecies.id;
            payloadReadyForClient.taxonomy = {
              kingdom: cachedSpecies.kingdom ?? "Unknown",
              phylum: cachedSpecies.phylum ?? "Unknown",
              class: cachedSpecies.class ?? "Unknown",
              order: cachedSpecies.order ?? "Unknown",
              family: cachedSpecies.family ?? "Unknown",
              genus: cachedSpecies.genus ?? "Unknown",
            };
            payloadReadyForClient.iucn_red_list_status =
              cachedSpecies.iucn_red_list_status ?? undefined;
            payloadReadyForClient.reference_image_url =
              cachedSpecies.reference_image_url;
            payloadReadyForClient.wikipedia_url = cachedSpecies.wikipedia_url;
            payloadReadyForClient.wikipedia_overview =
              cachedSpecies.wikipedia_overview;
            if (cachedSpecies.group_tags?.length) {
              payloadReadyForClient.group_tags = cachedSpecies.group_tags;
            }
            if (cachedSpecies.gbif_taxon_key != null) {
              payloadReadyForClient.gbif_taxon_key =
                cachedSpecies.gbif_taxon_key;
            }
            if (cachedSpecies.common_names?.en) {
              payloadReadyForClient.common_name = cachedSpecies.common_names.en;
            }
            if (cachedSpecies.alternative_common_names?.length) {
              const primaryEn = (payloadReadyForClient.common_name ?? "")
                .toLowerCase();
              payloadReadyForClient.alternative_common_names = cachedSpecies
                .alternative_common_names.filter(
                  (n) => n.toLowerCase() !== primaryEn,
                );
            }
            if (
              cachedSpecies.hazard_type && payloadReadyForClient.insight_data
            ) {
              payloadReadyForClient.insight_data.hazard_type =
                cachedSpecies.hazard_type;
            }
            if (cachedSpecies.habitat_description) {
              payloadReadyForClient.species_insights = {
                habitat_description: cachedSpecies.habitat_description,
              };
            }
          } else {
            // Cache miss: enrich species_dictionary in the background
            console.log(
              `Cache Miss: ${parsedData.scientific_name}. Background enrichment queued.`,
            );
            const bgStart = Date.now();
            const externalData = await fetchExternalEnrichment(
              parsedData.scientific_name!,
            );
            const freshSpecies = await fetchCachedSpecies(
              parsedData.scientific_name!,
              supabaseAdmin,
            );

            const newCommonNames = mergeSpeciesCommonNames(
              freshSpecies?.common_names,
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
                iucn_red_list_status: freshSpecies?.iucn_red_list_status ??
                  "not_evaluated",
                habitat_description: freshSpecies?.habitat_description ??
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
            console.log(`[⏱ BENCH] bg_enrichment: ${Date.now() - bgStart}ms`);
          }
        }

        audioStorageUrls = await promoteSafeMedia({
          userId: user.id,
          r2ObjectKeys: stagedAudioSourceKey
            ? [stagedAudioSourceKey]
            : undefined,
          imageBase64s: audio_base64 ? [audio_base64] : undefined,
          userTier,
          r2Config: r2Config ?? getR2Config(),
          contentType: "audio/wav",
          fallbackExtension: "wav",
        });
        if (audioStorageUrls.length !== 1) {
          throw new Error(
            `Audio promotion returned ${audioStorageUrls.length}/1 URL(s).`,
          );
        }

        await insertScan(
          {
            id: generatedScanId,
            user_id: user.id,
            species_id: speciesId,
            timestamp: timestamp ?? undefined,
            gps_lat_exact: safeGpsLat,
            gps_long_exact: safeGpsLon,
            gps_elevation: gps_elevation ?? null,
            ai_confidence_score: parsedData.confidence_score,
            is_biological_subject: parsedData.is_biological_subject,
            blur_score: null,
            ecology_type: parsedData.ecology_type,
            is_invasive: parsedData.is_invasive,
            invasive_status_region: parsedData.invasive_status_region ?? null,
            invasive_rationale: parsedData.invasive_rationale ?? null,
            invasive_confidence: parsedData.invasive_confidence ?? null,
            weather_condition: weather_condition ?? undefined,
            weather_temperature_f: weather_temperature_f ?? undefined,
            semantic_location: semantic_location ?? undefined,
            public_location_label: public_location_label ?? undefined,
            geoprivacy: geoprivacy ?? undefined,
            device_locale: device_locale ?? undefined,
            device_time_zone: device_time_zone ?? undefined,
            current_month: normalizedCurrentMonth ?? null,
            time_of_day: time_of_day ?? undefined,
            ai_reasoning: parsedData.ai_reasoning ?? null,
            extracted_visual_traits: [],
            colors: [],
            llm_prompt_tokens: llmPromptTokens,
            llm_candidate_tokens: llmCandidateTokens,
            llm_thinking_tokens: llmThinkingTokens,
            llm_cached_tokens: null,
            llm_total_tokens: llmTotalTokens,
            llm_usage_metadata: llmUsageMetadata,
            image_storage_urls: [],
            audio_storage_urls: audioStorageUrls,
            life_stage: "unknown",
            reproductive_condition: "not_applicable",
            sex: parsedData.sex ?? null,
            sex_confidence: parsedData.sex_confidence ?? null,
            sex_evidence: parsedData.sex_evidence ?? null,
            individual_count: null,
            ecological_interactions: [],
            estimated_size_cm: null,
            inference_tier: userTier === "pro" ? "pro" : "flash",
            candidates: forwardCandidates as AudioCandidate[] | null,
            image_quality_score: null,
            is_live_capture: true,
          },
          supabaseAdmin,
        );
        scanInserted = true;

        const completion = await compatibilityLedger.markComplete({
          promotedUrlsByStorageKey: stagedAudioSourceKey
            ? new Map([[stagedAudioSourceKey, audioStorageUrls[0]!]])
            : new Map(),
          responseEnvelope,
        });
        if (completion.responseEnvelope) {
          responseEnvelope = parseIdentifySuccessEnvelope(
            completion.responseEnvelope,
          );
        }
        ledgerCompleted = true;

        runBackground(
          (async () => {
            const groupTagsResult =
              (needsGroupTags && !cachedSpecies?.group_tags?.length)
                ? await fetchQuotaGuardedGroupTags(
                  req,
                  user,
                  parsedData.scientific_name!,
                  supabaseAdmin,
                  quotaLease.reservation.requestId,
                )
                : null;
            if (groupTagsResult?.group_tags?.length && isIdentifiedBio) {
              await updateGroupTags(
                parsedData.scientific_name!,
                groupTagsResult.group_tags,
                supabaseAdmin,
              );
            }

            await trackPostHogEvent(user, "AudioScanCompleted", {
              is_biological_subject: parsedData.is_biological_subject,
              tier: userTier,
              ...tierTelemetryProperties(tierResolution),
              llm_model: quotaLease.reservation.model,
              llm_prompt_tokens: llmPromptTokens,
              llm_candidate_tokens: llmCandidateTokens,
              llm_thinking_tokens: llmThinkingTokens,
              llm_total_tokens: llmTotalTokens,
              scientific_name: parsedData.scientific_name,
            });
          })().catch((error) =>
            logStructuredError("audio_spec/optional_enrichment_failed", {
              user_id: user.id,
              scan_id: generatedScanId,
              error: error instanceof Error ? error.message : String(error),
            })
          ),
        );
      } catch (e) {
        const errorMsg = e instanceof Error ? e.message : String(e);
        const persistenceOutcomeUnknown = isScanPersistenceOutcomeUnknown(e);
        logStructuredError("audio_spec/background_ingestion_failed", {
          user_id: user.id,
          scan_id: generatedScanId,
          error: errorMsg,
          scan_inserted: scanInserted,
        });

        if (!ledgerCompleted) {
          try {
            await compatibilityLedger.markRetryableFailure(
              "background_ingestion_failed",
              errorMsg,
            );
          } catch (ledgerError) {
            logStructuredError("audio_spec/ledger_retry_mark_failed", {
              user_id: user.id,
              scan_id: generatedScanId,
              error: ledgerError instanceof Error
                ? ledgerError.message
                : String(ledgerError),
            });
          }
        }

        if (!scanInserted) {
          if (!persistenceOutcomeUnknown) {
            const quotaRetryEnabled = await quotaLease.fail();
            if (!quotaRetryEnabled) {
              logStructuredError("audio_spec/quota_retry_enable_failed", {
                user_id: user.id,
                scan_id: generatedScanId,
              });
            }
            try {
              const { error: dlErr } = await supabaseAdmin
                .from("failed_scan_ingestions")
                .insert({
                  scan_id: generatedScanId,
                  user_id: user.id,
                  error_message: errorMsg,
                });
              if (dlErr) {
                logStructuredError("audio_spec/dead_letter_write_failed", {
                  scan_id: generatedScanId,
                  error: dlErr.message,
                });
              }
            } catch (dlErr) {
              logStructuredError("audio_spec/dead_letter_write_failed", {
                scan_id: generatedScanId,
                error: dlErr instanceof Error ? dlErr.message : String(dlErr),
              });
            }

            // Promotion consumes the staging object. A definitely failed scan
            // insert must not leave an unowned public object; the client keeps
            // the local capture and establishes a fresh generation on retry.
            // An ambiguous write response preserves media because a committed
            // owner row may already reference it.
            const rollbackResults = await Promise.allSettled(
              audioStorageUrls.map((url) =>
                deleteR2ObjectIfPresent(
                  url.replace("https://media.merian.app/", ""),
                  r2Config ?? getR2Config(),
                )
              ),
            );
            if (
              rollbackResults.some((result) => result.status === "rejected")
            ) {
              logStructuredError("audio_spec/r2_rollback_partial_failure", {
                user_id: user.id,
                scan_id: generatedScanId,
                failed_count: rollbackResults.filter((result) =>
                  result.status === "rejected"
                ).length,
                total_count: rollbackResults.length,
              });
            }
          }
        }

        // The exact-owner analysis row is a durable response/replay surface
        // even if complete-last bookkeeping needs canonical recovery.
        if (scanInserted) return;
        throw e;
      }
    };

    try {
      await runBackgroundIngestion();
    } catch {
      return publicErrorResponse(
        req,
        503,
        "scan_persistence_failed",
        "We couldn’t finish saving this observation. Please try again.",
        { retryAfterSeconds: 5 },
      );
    }

    console.log(`[⏱ BENCH] total_to_response: ${Date.now() - fnStart}ms`);
    return jsonResponse(responseEnvelope, 200);
  })
);
