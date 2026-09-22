import type { SupabaseClient, User } from "@supabase/supabase-js";
import type { AIExecutionOutcome } from "../_shared/ai/contracts.ts";
import { prepareAIExecution } from "../_shared/ai/production.ts";
import { buildVisionAIRequest } from "./provider.ts";
import { evaluateAndProcessPayload } from "../_shared/identify/moderation.ts";
import { deleteR2ObjectIfPresent, getR2Config } from "../_shared/aws.ts";
import {
  jsonResponse,
  logStructuredError,
  runBackground,
  withEdgeHandler,
} from "../_shared/edgeHandler.ts";
import { fetchQuotaGuardedGroupTags } from "../_shared/groupTagQuota.ts";
import { fetchExternalEnrichment } from "../_shared/external.ts";
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
import {
  coalesceTaxonomyValue,
  normalizeTaxonomyValue,
} from "../_shared/taxonomy.ts";
import {
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
  Payload,
} from "../_shared/identify/types.ts";
import {
  type IdentifySuccessEnvelope,
  parseIdentifySuccessEnvelope,
  parseMerianIdentification,
} from "../_shared/identify/contract.ts";
import {
  fetchCompletedIdentifyResponse,
  waitForCompletedIdentifyResponse,
} from "../_shared/identify/completedResponse.ts";
import { diagnosticTriggerForTier } from "../_shared/identify/thresholds.ts";
import {
  resolveImagePayloads,
  stagedImageSourceKeys,
  validateImageR2ObjectKeys,
} from "../_shared/identify/media.ts";
import {
  MEDIA_BUDGETS,
  readRequestJsonWithinBudget,
} from "../_shared/mediaBudgets.ts";
import { createCompatibilityScanIngestionLedger } from "../_shared/scanIngestionCompatibility.ts";
import { recoverStrandedScanIngestionAttempt } from "../_shared/scanIngestionJobs.ts";
import { isScanPersistenceOutcomeUnknown } from "../_shared/scanPersistence.ts";
import {
  canonicalizeDomesticPetScientificName,
  sanitizePetIdentification,
  sanitizeScientificName,
} from "./sanitize.ts";
import {
  fetchCachedSpecies,
  fetchCandidateCommonNames,
  insertScan,
  mergeSpeciesCommonNames,
  updateGroupTags,
  upsertGhostUserIfMissing,
  upsertSpeciesDictionary,
} from "../_shared/identify/db.ts";
import {
  hydratePayloadFromCachedSpecies,
  isNewToMerianDictionary,
} from "../_shared/identify/clientPayload.ts";
import { normalizeProcessedMaterialSubject } from "../_shared/identify/subjectClassification.ts";

class CompatibilityModerationRejectedError extends Error {
  override name = "CompatibilityModerationRejectedError";
}

export function createIdentifyHandler(prepare = prepareAIExecution) {
  return async (
    req: Request,
    user: User,
    supabaseAdmin: SupabaseClient,
  ): Promise<Response> => {
    const protocolError = await entitlementProtocolResponse(
      req,
      supabaseAdmin,
    );
    if (protocolError) return protocolError;

    const fnStart = Date.now();
    const bodyReadResult = await readRequestJsonWithinBudget<
      Payload & {
        description?: string;
        mimeType?: string;
        observation_context?: Record<string, unknown> | null;
      }
    >(
      req,
      MEDIA_BUDGETS.maxIdentifyJsonBodyBytes,
    );
    if (bodyReadResult.error || !bodyReadResult.value) {
      return jsonResponse(
        { error: bodyReadResult.error?.message ?? "Invalid JSON body" },
        bodyReadResult.error?.status ?? 400,
      );
    }

    const body = bodyReadResult.value;

    const paramError = requireParams(
      body as unknown as Record<string, unknown>,
      ["user_id"],
    );
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
      deviceTimeZone,
      deviceRegion,
      currentMonth,
      semanticLocation,
      publicLocationLabel,
      public_location_label,
      timeOfDay,
      timestamp,
      estimated_size_cm,
      client_scan_id,
      preferred_goal,
      description,
      observation_context,
    } = body;
    const publicExploreLocationLabel = publicLocationLabel ??
      public_location_label;
    const normalizedCurrentMonth = normalizeCurrentMonth(currentMonth);

    // Range-validate GPS coordinates — out-of-bounds values from a corrupted or
    // tampered payload are sanitised to null rather than rejecting the scan.
    // Location is supplementary context; a bad coord should not kill identification.
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

    if (
      (!r2ObjectKeys || r2ObjectKeys.length === 0) &&
      (!imageBase64s || imageBase64s.length === 0)
    ) {
      return jsonResponse(
        {
          error:
            "Missing structural boundary (neither r2ObjectKeys nor imageBase64s provided).",
        },
        400,
      );
    }

    const generatedScanId = resolveAIRequestId(req, client_scan_id);
    let strandedRecovery;
    try {
      strandedRecovery = await recoverStrandedScanIngestionAttempt(
        generatedScanId,
        user.id,
        supabaseAdmin,
      );
    } catch (error) {
      logStructuredError("identify/scan_ingestion_recovery_failed", {
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
      (r2ObjectKeys ?? []).some((key) => !key.startsWith(`staging/${user.id}/`))
    ) {
      return publicErrorResponse(
        req,
        409,
        "scan_media_restage_required",
        "This observation’s uploads need to be refreshed for your account.",
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

    const keyValidationError = validateImageR2ObjectKeys(
      r2ObjectKeys,
      user.id,
      {
        enforceOwnership: !imageBase64s || imageBase64s.length === 0,
        idorEvent: "identify/image_idor_attempt",
      },
    );
    if (keyValidationError) return keyValidationError;
    const stagedImageKeys = stagedImageSourceKeys(
      r2ObjectKeys,
      imageBase64s,
    );

    const { base64Payloads, errorResponse } = await resolveImagePayloads(
      r2ObjectKeys,
      imageBase64s,
      fnStart,
    );

    if (errorResponse) return errorResponse;

    if (!base64Payloads || base64Payloads.length === 0) {
      return jsonResponse({ error: "Failed to resolve image payloads." }, 400);
    }

    try {
      await upsertGhostUserIfMissing(user.id, supabaseAdmin);
    } catch (error) {
      logStructuredError("identify/scan_user_profile_unavailable", {
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

    console.log(`[⏱ BENCH] payload_resolved: ${Date.now() - fnStart}ms`);

    let quotaLease;
    try {
      quotaLease = await reserveAIProviderCall(req, supabaseAdmin, {
        userId: user.id,
        operation: "scan_identification",
        requestId: generatedScanId,
        originalAnalysisId: generatedScanId,
        flashFallbackEligible: isFlashFallbackEligible({
          imageCount: base64Payloads.length,
          audioCount: 0,
          descriptionCount: typeof description === "string" &&
              description.trim().length > 0
            ? 1
            : 0,
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
          endpoint: "identify",
          imageKeys: stagedImageKeys,
          inlineImageCount: imageBase64s?.length ?? 0,
          description,
          preferredGoal: preferred_goal,
          mimeType,
          telemetry: {
            timestamp,
            gpsLatitude: safeGpsLat,
            gpsLongitude: safeGpsLon,
            gpsElevation,
            semanticLocation,
            publicLocationLabel: publicExploreLocationLabel,
            geoprivacy: body.geoprivacy,
            weatherCondition,
            weatherTemperatureF,
            deviceLocale,
            deviceTimeZone,
            deviceRegion,
            currentMonth: normalizedCurrentMonth,
            timeOfDay,
            depthScaleText,
            zoomFactor,
            estimatedSizeCm: estimated_size_cm,
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

    const aiRequest = buildVisionAIRequest({
      imageBase64s: base64Payloads,
      mimeType,
      description,
      telemetry: {
        safeGpsLat,
        safeGpsLon,
        gpsElevation,
        depthScaleText,
        zoomFactor,
        estimatedSizeCm: estimated_size_cm,
        semanticLocation,
        weatherCondition,
        weatherTemperatureF,
        deviceLocale,
        deviceTimeZone,
        deviceRegion,
        currentMonth: normalizedCurrentMonth,
        timeOfDay,
      },
    });

    console.log(`[⏱ BENCH] pre_gemini: ${Date.now() - fnStart}ms`);
    const geminiStart = Date.now();

    let finishReason: string | undefined;
    let safetyRatings: AIExecutionOutcome["safetyRatings"];
    let result: AIExecutionOutcome;
    let llmPromptTokens: number | null = null;
    let llmCandidateTokens: number | null = null;
    let llmTotalTokens: number | null = null;
    let llmThinkingTokens: number | null = null;
    let llmCachedTokens: number | null = null;
    let llmUsageMetadata: Record<string, unknown> = {};
    let providerAttempted = false;

    try {
      const execution = prepare(aiRequest, {
        kind: "user_request",
        userId: user.id,
        permission: "google_gemini",
        operation: "scan_identification",
        reservation: quotaLease.reservation,
      });
      await quotaLease.commit();
      providerAttempted = true;
      result = await execution.invoke();
      if (
        result.kind === "operational_failure" ||
        result.kind === "unknown_execution"
      ) throw new Error(`ai_${result.kind}`);
      finishReason = result.finishReason ?? undefined;
      safetyRatings = result.safetyRatings;
      const usage = result.usage;
      if (usage) {
        llmUsageMetadata = usage.modalityBreakdown;
        llmPromptTokens = usage.promptTokens;
        llmCandidateTokens = usage.candidateTokens;
        llmTotalTokens = usage.totalTokens;
        // Preserve the provider's separate thinking-token accounting.
        llmThinkingTokens = usage.thinkingTokens;
        // Preserve this route's existing cached-token scan-row field.
        llmCachedTokens = usage.cachedTokens;
        console.log(
          `Token Usage [identify]: Prompt: ${llmPromptTokens} | Candidates: ${llmCandidateTokens} | Thinking: ${llmThinkingTokens} | Cached: ${llmCachedTokens} | Total: ${llmTotalTokens}`,
        );
      }
      console.log(
        `[⏱ BENCH] gemini_done: ${Date.now() - fnStart}ms total, ${
          Date.now() - geminiStart
        }ms inference`,
      );
    } catch (genError) {
      // The adapter exposes bounded failure kinds without provider diagnostics.
      const errMsg = genError instanceof Error
        ? genError.message
        : String(genError);
      const errStatus = (genError as Record<string, unknown>)?.status ??
        (genError as Record<string, unknown>)?.statusCode ?? null;
      if (providerAttempted) {
        await quotaLease.fail();
      } else {
        await quotaLease.refund();
      }
      await compatibilityLedger.markRetryableFailure(
        "ai_provider_failed",
        errMsg,
      );
      logStructuredError("identify/gemini_failed", {
        user_id: user.id,
        model: targetModel,
        elapsed_ms: Date.now() - geminiStart,
        error_message: errMsg,
        error_status: errStatus,
      });
      // Return 503 (not 400) so the iOS offline queue treats this as a transient failure
      // and schedules a persisted retry instead of marking the scan as terminal.
      // 400 is reserved for genuine client errors (bad params, IDOR). Gemini API errors
      // (rate limits, timeouts, internal errors) are all transient and should be retried.
      return jsonResponse(
        { error: "AI processing error. Please try again." },
        503,
      );
    }

    // The adapter distinguishes policy refusals from unusable provider output.
    // Keep the existing terminal/retryable settlement and public responses.
    // SAFETY / PROHIBITED_CONTENT = stable 400 observation_rejected (tombstone on iOS).
    // All other non-STOP reasons (MAX_TOKENS, RECITATION, OTHER) are transient → 503 (retry).
    if (
      result.kind === "refusal" ||
      (result.kind === "invalid_output" && result.reason === "finish")
    ) {
      const isPermanentContentFailure = result.kind === "refusal";
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
      logStructuredError("identify/non_stop_finish", {
        user_id: user.id,
        finish_reason: finishReason,
        response_length: result.responseCharacters,
        permanent: isPermanentContentFailure,
      });
      if (isPermanentContentFailure) {
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

    let parsedData;
    try {
      if (result.kind !== "draft") throw new Error("ai_response_json_invalid");
      parsedData = parseMerianIdentification(
        result.draft,
      );
    } catch (parseError) {
      await quotaLease.fail();
      await compatibilityLedger.markRetryableFailure(
        "ai_response_parse_failed",
        parseError,
      );
      // Keep diagnostics bounded; never log provider output or a preview.
      logStructuredError("identify/parse_failed", {
        user_id: user.id,
        finish_reason: finishReason ?? "unknown",
        response_length: result.responseCharacters,
        error: parseError instanceof Error
          ? parseError.message
          : String(parseError),
      });
      return jsonResponse(
        { error: "Processing Error: Malformed AI response." },
        503,
      );
    }

    // Sanitize scientific names at write time so the database is scientific-grade
    // and interoperable with GBIF, iNaturalist, and partner taxonomy systems.
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
    if (Array.isArray(parsedData.candidates)) {
      parsedData.candidates = parsedData.candidates.map((c) => ({
        ...c,
        scientific_name: sanitizeScientificName(c.scientific_name),
      }));
    }
    parsedData.pet_identification = sanitizePetIdentification(
      parsedData.pet_identification,
      parsedData.scientific_name,
    );

    // Cap the candidates list — the LLM schema enforces this but extractJson is an
    // unvalidated cast. Five alternatives is more than enough for the UI swipe modal.
    if (Array.isArray(parsedData.candidates)) {
      parsedData.candidates = parsedData.candidates.slice(0, 5);
    }

    // Cap unbounded LLM-generated array fields to protect V8 Isolate memory and
    // prevent oversized DB rows. Limits are generous — they exceed realistic model
    // output and exist purely as a hard safety boundary against malformed responses.
    if (Array.isArray(parsedData.extracted_visual_traits)) {
      parsedData.extracted_visual_traits = parsedData.extracted_visual_traits
        .slice(0, 10);
    }
    if (Array.isArray(parsedData.ecological_interactions)) {
      parsedData.ecological_interactions = parsedData.ecological_interactions
        .slice(0, 10);
    }
    if (
      typeof parsedData.ai_reasoning === "string" &&
      parsedData.ai_reasoning.length > 2000
    ) {
      parsedData.ai_reasoning = parsedData.ai_reasoning.slice(0, 2000);
    }
    // individual_count: must be a positive integer; reject negatives and impossibly large values.
    // Uses undefined (not null) to match the ?: number optional type; the insertScan call
    // converts undefined → null via ?? for the nullable DB column.
    if (parsedData.individual_count != null) {
      parsedData.individual_count =
        Number.isFinite(parsedData.individual_count) &&
          parsedData.individual_count > 0
          ? Math.min(Math.round(parsedData.individual_count), 99999)
          : undefined;
    }

    // Clamp enum fields to known-valid Postgres values. Gemini may return a
    // biologically correct term not yet in the DB enum — without this guard the
    // insertScan call throws 22P02 and silently drops the entire scan row.
    const sanitizedLifeStage = sanitizeLifeStage(parsedData.life_stage);
    if (
      parsedData.life_stage != null &&
      sanitizedLifeStage != parsedData.life_stage
    ) {
      logStructuredError("identify/unknown_life_stage", {
        user_id: user.id,
        value: parsedData.life_stage,
      });
    }
    parsedData.life_stage = sanitizedLifeStage;

    const sanitizedReproductiveCondition = sanitizeReproductiveCondition(
      parsedData.reproductive_condition,
    );
    if (
      parsedData.reproductive_condition != null &&
      sanitizedReproductiveCondition != parsedData.reproductive_condition
    ) {
      logStructuredError("identify/unknown_reproductive_condition", {
        user_id: user.id,
        value: parsedData.reproductive_condition,
      });
    }
    parsedData.reproductive_condition = sanitizedReproductiveCondition;

    const sanitizedSex = sanitizeSex(parsedData.sex);
    if (parsedData.sex != null && sanitizedSex != parsedData.sex) {
      logStructuredError("identify/unknown_sex", {
        user_id: user.id,
        value: parsedData.sex,
      });
    }
    parsedData.sex = sanitizedSex;
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
      logStructuredError("identify/processed_material_demoted", {
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

    // Derive blur_score from sharpness (1-10) for latency savings
    parsedData.blur_score = Math.max(
      0,
      (10 - (parsedData.image_quality?.sharpness ?? 10)) / 10,
    );

    let payloadReadyForClient: ClientPayload = {
      ...parsedData,
      scan_id: generatedScanId,
      blur_score: parsedData.blur_score ?? 0,
      colors: [],
      estimated_size_cm:
        (estimated_size_cm != null && Number.isFinite(estimated_size_cm) &&
            estimated_size_cm > 0)
          ? Math.min(estimated_size_cm, 50_000)
          : null,
      pet_identification: parsedData.pet_identification ?? null,
      inference_tier: userTier === "pro" ? "pro" : "flash",
    };

    // Strip candidates when confidence is at or above the tier's diagnosticTrigger threshold (0.99 both tiers).
    // Mirrors InferenceConfidencePolicy.flash/pro.diagnosticTrigger on iOS.
    // Fallback to 0.0 (not 1.0) on a null score: a missing confidence_score means the
    // LLM returned a malformed response — preserve candidates rather than silently strip them.
    if ((parsedData.confidence_score ?? 0.0) >= diagnosticTrigger) {
      payloadReadyForClient.candidates = null;
    }

    const isIdentifiedBio =
      !!(parsedData.is_biological_subject && parsedData.scientific_name);
    let speciesId: string | null = null;
    let cachedSpecies: CachedSpeciesRow | null = null;
    let missingCandidates: string[] = [];

    // Fire both DB lookups in parallel when both are needed.
    //
    // fetchCandidateCommonNames: enriches the candidates list with authoritative English names
    //   from species_dictionary. Only runs when candidates are being forwarded to the client.
    //   Non-fatal: returns an empty Map on DB error; candidates reach the client without names.
    //
    // fetchCachedSpecies: reads taxonomy, IUCN, wiki, and reference image for the primary species.
    //   Only runs when the subject was biologically identified.
    //
    // Both queries depend only on parsedData (resolved above) and are independent of each other.
    // Running them serially added a full DB round-trip to every scan that satisfied both conditions.
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
          .catch((error) => {
            logStructuredError("identify/species_cache_read_fallback", {
              user_id: user.id,
              scan_id: generatedScanId,
              error: error instanceof Error ? error.message : String(error),
            });
            return null;
          })
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

      if (cachedSpecies && normalizeTaxonomyValue(cachedSpecies.kingdom)) {
        console.log(
          `Cache Hit: Generating payload from DB for ${parsedData.scientific_name}`,
        );
        speciesId = cachedSpecies.id;
        payloadReadyForClient = hydratePayloadFromCachedSpecies(
          {
            ...payloadReadyForClient,
            insight_data: {
              ai_reasoning: parsedData.ai_reasoning || "Reasoning omitted.",
              hazard_type: "none",
            },
          },
          cachedSpecies,
        );
      } else {
        // Cache Miss: taxonomy, IUCN, and species insights are not in the vision response.
        // DB enrichment (Flash text + GBIF/Wikipedia upsert) runs in the background task so
        // the next scan of the same species becomes a Cache Hit with full metadata.
        console.log(
          `Cache Miss: ${parsedData.scientific_name}. Background enrichment queued.`,
        );
        payloadReadyForClient.insight_data = {
          ai_reasoning: parsedData.ai_reasoning || "Reasoning omitted.",
          hazard_type: "none",
        };
      }
    }

    let responseEnvelope: IdentifySuccessEnvelope;
    try {
      responseEnvelope = parseIdentifySuccessEnvelope({
        success: true,
        data: payloadReadyForClient,
      });
      // Use the parsed copy for persistence as well as the response so unknown
      // or malformed server-added values cannot cross either boundary.
      payloadReadyForClient = responseEnvelope.data;
    } catch (error) {
      await quotaLease.fail();
      await compatibilityLedger.markTerminalFailure(
        "wire_contract_failed",
        error,
        "malformed_response",
      );
      logStructuredError("identify/wire_contract_failed", {
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
      "durable_ingestion_pending",
      { leaseSeconds: 300 },
    );

    const needsGroupTags = isIdentifiedBio &&
      !cachedSpecies?.group_tags?.length;

    const runBackgroundIngestion = async () => {
      // modResult is hoisted outside the try so the catch can reference publicUrls
      // for R2 rollback if insertScan fails after media has already been committed.
      let modResult:
        | Awaited<ReturnType<typeof evaluateAndProcessPayload>>
        | undefined;
      let scanInserted = false;
      let ledgerCompleted = false;

      try {
        // Tier was already resolved on the critical path. The only remaining task here is
        // ghost-user creation: if the main path never found the user in the DB, the cache
        // entry was never set, so we upsert them now before the scans FK insert.
        await upsertGhostUserIfMissing(user.id, supabaseAdmin);

        modResult = await evaluateAndProcessPayload(
          user.id,
          stagedImageKeys,
          imageBase64s,
          finishReason,
          safetyRatings,
          userTier,
        );
        if (modResult.status === "ERROR") {
          // Moderation pipeline failed (e.g. abuse strike write, R2 upload error).
          // Do not insert the scan — image_storage_urls would be null and the DB row
          // would be permanently orphaned with no media.
          console.error(
            "Moderation pipeline returned ERROR. Halting background data ingestion.",
          );
          await compatibilityLedger.markRetryableFailure(
            "moderation_error",
            "Moderation pipeline returned ERROR.",
          );
          throw new Error("Moderation pipeline returned ERROR.");
        }
        if (
          modResult.status === "SHADOWBANNED" ||
          modResult.status === "DELETED_WARNING"
        ) {
          console.error(
            "Media flagged by safety moderation. Halting background data ingestion.",
          );
          await compatibilityLedger.markTerminalFailure(
            "moderation_rejected",
            "Media rejected by moderation.",
          );
          throw new CompatibilityModerationRejectedError(
            "Media rejected by moderation.",
          );
        }

        // Cache Miss: enrich species_dictionary so the next scan of the same species is a Cache Hit.
        // Runs after moderation so we don't persist data for flagged content.
        if (!speciesId && isIdentifiedBio) {
          const bgEnrichStart = Date.now();
          const externalData = await fetchExternalEnrichment(
            parsedData.scientific_name!,
          );

          // Re-read the species row immediately before the upsert to coalesce any taxonomy
          // written by a concurrent enrich-scan call that raced this background task.
          // fetchExternalEnrichment above takes 1-3 seconds (GBIF + Wikipedia I/O), giving
          // enrich-scan's updateSpeciesEnrichment write plenty of time to land.
          // Without this re-read, upsertSpeciesDictionary uses ignoreDuplicates: false
          // (ON CONFLICT DO UPDATE), so any real taxonomy already written by enrich-scan
          // would be overwritten with "Unknown" skeleton values from the original cache-miss
          // snapshot taken at the start of the request.
          const freshSpecies = await fetchCachedSpecies(
            parsedData.scientific_name!,
            supabaseAdmin,
          );

          const newCommonNames = mergeSpeciesCommonNames(
            freshSpecies?.common_names ?? cachedSpecies?.common_names,
            parsedData.common_name,
          );

          // Build the deduplicated alternative names list. Exclude the primary canonical
          // name (common_names.en) so the two lists are mutually exclusive on the client.
          // Prefer GBIF-sourced names; fall back to the freshly-read DB value if GBIF returned
          // nothing (e.g. timeout) and enrich-scan already populated the column.
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
              // Preserve any real taxonomy written by a concurrent enrich-scan call.
              // Null means "not known yet" and is intentionally safer than the old "Unknown"
              // sentinel, which polluted lookalike validation and same-genus linking.
              kingdom: coalesceTaxonomyValue(
                freshSpecies?.kingdom,
                cachedSpecies?.kingdom,
              ),
              phylum: coalesceTaxonomyValue(
                freshSpecies?.phylum,
                cachedSpecies?.phylum,
              ),
              class: coalesceTaxonomyValue(
                freshSpecies?.class,
                cachedSpecies?.class,
              ),
              order: coalesceTaxonomyValue(
                freshSpecies?.order,
                cachedSpecies?.order,
              ),
              family: coalesceTaxonomyValue(
                freshSpecies?.family,
                cachedSpecies?.family,
              ),
              genus: coalesceTaxonomyValue(
                freshSpecies?.genus,
                cachedSpecies?.genus,
              ),
              wikipedia_overview: freshSpecies?.wikipedia_overview ??
                cachedSpecies?.wikipedia_overview ??
                externalData.wikiExtract ?? null,
              hazard_type: freshSpecies?.hazard_type ??
                cachedSpecies?.hazard_type ?? "none",
              iucn_red_list_status: freshSpecies?.iucn_red_list_status ??
                cachedSpecies?.iucn_red_list_status ??
                "not_evaluated",
              habitat_description: freshSpecies?.habitat_description ||
                cachedSpecies?.habitat_description || undefined,
              wikipedia_url: freshSpecies?.wikipedia_url ||
                cachedSpecies?.wikipedia_url || externalData.wikipediaUrl,
              gbif_taxon_key: freshSpecies?.gbif_taxon_key ??
                cachedSpecies?.gbif_taxon_key ?? externalData.gbifKey,
              reference_image_url: freshSpecies?.reference_image_url ||
                cachedSpecies?.reference_image_url ||
                externalData.referenceImageUrl,
            },
            supabaseAdmin,
          );
          // freshSpecies?.id covers the case where the row already existed (created by a
          // concurrent enrich-scan write) but the upsert returned null because ignoreDuplicates
          // behaviour updated the row without returning the id separately.
          speciesId = upsertedId || freshSpecies?.id || cachedSpecies?.id ||
            null;
          console.log(
            `[⏱ BENCH] bg_enrichment: ${Date.now() - bgEnrichStart}ms`,
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
            gps_elevation: gpsElevation,
            ai_confidence_score: payloadReadyForClient.confidence_score,
            is_biological_subject: parsedData.is_biological_subject,
            blur_score: payloadReadyForClient.blur_score,
            zoom_factor: typeof zoomFactor === "number" &&
                Number.isFinite(zoomFactor) && zoomFactor > 0
              ? zoomFactor
              : null,
            ecology_type: payloadReadyForClient.ecology_type,
            is_invasive: payloadReadyForClient.is_invasive ?? undefined,
            invasive_status_region:
              payloadReadyForClient.invasive_status_region ?? null,
            invasive_rationale: payloadReadyForClient.invasive_rationale ??
              null,
            invasive_confidence: payloadReadyForClient.invasive_confidence ??
              null,
            weather_condition: weatherCondition,
            weather_temperature_f: weatherTemperatureF,
            semantic_location: semanticLocation,
            public_location_label: publicExploreLocationLabel,
            device_locale: deviceLocale,
            device_time_zone: deviceTimeZone,
            current_month: normalizedCurrentMonth ?? null,
            time_of_day: timeOfDay,
            depth_scale_text: depthScaleText,
            ai_reasoning: parsedData.ai_reasoning ?? null,
            extracted_visual_traits: parsedData.extracted_visual_traits ?? [],
            colors: [],
            llm_prompt_tokens: llmPromptTokens,
            llm_candidate_tokens: llmCandidateTokens,
            llm_thinking_tokens: llmThinkingTokens,
            llm_cached_tokens: llmCachedTokens,
            llm_total_tokens: llmTotalTokens,
            llm_usage_metadata: llmUsageMetadata,
            image_storage_urls: modResult.publicUrls ?? [],
            life_stage: parsedData.life_stage ?? "unknown",
            reproductive_condition: parsedData.reproductive_condition ??
              "not_applicable",
            sex: parsedData.sex ?? null,
            sex_confidence: parsedData.sex_confidence ?? null,
            sex_evidence: parsedData.sex_evidence ?? null,
            individual_count: parsedData.individual_count ?? null,
            ecological_interactions: parsedData.ecological_interactions ?? [],
            estimated_size_cm: (estimated_size_cm != null &&
                Number.isFinite(estimated_size_cm) && estimated_size_cm > 0)
              ? Math.min(estimated_size_cm, 50000)
              : null,
            inference_tier: userTier === "pro" ? "pro" : "flash",
            candidates: payloadReadyForClient.candidates ?? null,
            image_quality_score: parsedData.image_quality?.overall_score ??
              null,
            is_live_capture: parsedData.is_live_capture,
            pet_identification: parsedData.pet_identification ?? null,
            user_observation_context: (observation_context != null &&
                typeof observation_context === "object" &&
                !Array.isArray(observation_context))
              ? observation_context as Record<string, unknown>
              : null,
          },
          supabaseAdmin,
        );
        scanInserted = true;
        const promotedUrlsByStorageKey = new Map<string, string>();
        for (const [index, storageKey] of stagedImageKeys.entries()) {
          const publicUrl = modResult.publicUrls?.[index];
          if (!publicUrl) {
            throw new Error(
              `Missing promoted URL for staged image ${storageKey}.`,
            );
          }
          promotedUrlsByStorageKey.set(storageKey, publicUrl);
        }
        const completion = await compatibilityLedger.markComplete({
          promotedUrlsByStorageKey,
          responseEnvelope,
        });
        if (completion.responseEnvelope) {
          responseEnvelope = parseIdentifySuccessEnvelope(
            completion.responseEnvelope,
          );
        }
        ledgerCompleted = true;
      } catch (e) {
        const terminalFailure = e instanceof
          CompatibilityModerationRejectedError;
        const persistenceOutcomeUnknown = isScanPersistenceOutcomeUnknown(e);

        // Revert R2 uploads to prevent untracked orphans when the scan DB write failed.
        // Only roll back if modResult exists (media was committed) but the scan row wasn't
        // written yet. An ambiguous/lost DB response is not proof of failure:
        // deleting then could break a committed scan that references the media.
        if (
          !scanInserted &&
          !persistenceOutcomeUnknown &&
          modResult?.publicUrls?.length
        ) {
          console.log("Rolling back R2 uploads due to scan insert failure.");
          const r2Config = getR2Config();
          const keysToPurge = modResult.publicUrls.map((url: string) =>
            url.replace("https://media.merian.app/", "")
          );
          const rollbackResults = await Promise.allSettled(
            keysToPurge.map((key: string) =>
              deleteR2ObjectIfPresent(key, r2Config)
            ),
          );
          const failedRollbacks = rollbackResults.filter((r) =>
            r.status === "rejected"
          );
          if (failedRollbacks.length > 0) {
            logStructuredError("r2_rollback_partial_failure", {
              scan_id: generatedScanId,
              user_id: user.id,
              failed_count: failedRollbacks.length,
              total_count: keysToPurge.length,
            });
          }
        }

        const errorMsg = e instanceof Error ? e.message : String(e);

        logStructuredError("background_ingestion_failed", {
          user_id: user.id,
          scan_id: generatedScanId,
          error: errorMsg,
        });
        if (!ledgerCompleted && !terminalFailure) {
          try {
            await compatibilityLedger.markRetryableFailure(
              "background_ingestion_failed",
              errorMsg,
            );
          } catch (ledgerError) {
            logStructuredError("identify/ledger_retry_mark_failed", {
              user_id: user.id,
              scan_id: generatedScanId,
              error: ledgerError instanceof Error
                ? ledgerError.message
                : String(ledgerError),
            });
          }
        }
        if (!scanInserted && !terminalFailure) {
          if (!persistenceOutcomeUnknown) {
            const quotaRetryEnabled = await quotaLease.fail();
            if (!quotaRetryEnabled) {
              logStructuredError("identify/quota_retry_enable_failed", {
                user_id: user.id,
                scan_id: generatedScanId,
              });
            }
          }
        }

        // Keep the legacy dead-letter row as detailed insert-failure evidence.
        // The compatibility scan_ingestion_jobs / scan_ingestion_intents rows above
        // are now the primary recovery surface; this table remains useful for ops
        // history and older tooling.
        // Best-effort: if this insert also fails (e.g. DB is down), the structured log
        // above is still the recovery signal.
        if (!scanInserted && !terminalFailure) {
          try {
            const { error: dlErr } = await supabaseAdmin
              .from("failed_scan_ingestions")
              .insert({
                scan_id: generatedScanId,
                user_id: user.id,
                error_message: errorMsg,
              });
            // PostgREST surfaces DB-level failures in { error }, not as thrown exceptions.
            if (dlErr) {
              logStructuredError("dead_letter_write_failed", {
                scan_id: generatedScanId,
                error: dlErr.message,
              });
            }
          } catch (dlErr) {
            // Network / client-level exception (e.g. DB unreachable).
            logStructuredError("dead_letter_write_failed", {
              scan_id: generatedScanId,
              error: dlErr instanceof Error ? dlErr.message : String(dlErr),
            });
          }
        }

        // Scan insertion follows successful moderation and completed media
        // promotion. It is an exact-owner durable replay surface even if the
        // normalized-media finalizer or optional enrichment later fails.
        if (scanInserted && !terminalFailure) return;
        throw e;
      }
    };

    try {
      // A 200 response is a durability promise consumed immediately by sync,
      // Field Chat, Explore sharing, and Field Trips.
      await runBackgroundIngestion();
    } catch (error) {
      if (error instanceof CompatibilityModerationRejectedError) {
        return publicErrorResponse(
          req,
          400,
          "observation_rejected",
          "We couldn’t process this observation. Please try a different photo.",
        );
      }
      return publicErrorResponse(
        req,
        503,
        "scan_persistence_failed",
        "We couldn’t finish saving this observation. Please try again.",
        { retryAfterSeconds: 5 },
      );
    }

    const runOptionalCompletionWork = async () => {
      try {
        const groupTagsPromise = needsGroupTags
          ? fetchQuotaGuardedGroupTags(
            req,
            user,
            parsedData.scientific_name!,
            supabaseAdmin,
            quotaLease.reservation.requestId,
          )
          : Promise.resolve(null);

        const capturedCandidates = missingCandidates.slice();
        const candidateEnrichmentPromise = Promise.allSettled(
          capturedCandidates.map(async (candidateName) => {
            const externalData = await fetchExternalEnrichment(candidateName);
            const primaryEnName = (externalData.wikiTitle &&
                externalData.wikiTitle.toLowerCase() !==
                  candidateName.toLowerCase())
              ? externalData.wikiTitle.replace(/\s*\([^)]+\)$/, "").trim()
              : (externalData.alternativeCommonNames[0] ?? null);
            const freshCandidateSpecies = await fetchCachedSpecies(
              candidateName,
              supabaseAdmin,
            );
            const candidateCommonNames = mergeSpeciesCommonNames(
              freshCandidateSpecies?.common_names,
              primaryEnName,
            );
            const primaryEnLower = (candidateCommonNames.en ?? "")
              .toLowerCase();

            await upsertSpeciesDictionary(
              {
                scientific_name: candidateName,
                common_names: candidateCommonNames,
                alternative_common_names:
                  externalData.alternativeCommonNames.length > 0
                    ? externalData.alternativeCommonNames.filter(
                      (name) => name.toLowerCase() !== primaryEnLower,
                    )
                    : null,
                kingdom: null,
                phylum: null,
                class: null,
                order: null,
                family: null,
                genus: null,
                wikipedia_overview: externalData.wikiExtract ?? null,
                hazard_type: "none",
                iucn_red_list_status: "not_evaluated",
                habitat_description: undefined,
                wikipedia_url: externalData.wikipediaUrl,
                gbif_taxon_key: externalData.gbifKey,
                reference_image_url: externalData.referenceImageUrl,
              },
              supabaseAdmin,
            );
          }),
        );

        const [groupTagsResult, candidateResults] = await Promise.all([
          groupTagsPromise,
          candidateEnrichmentPromise,
        ]);
        for (const [index, result] of candidateResults.entries()) {
          if (result.status === "rejected") {
            logStructuredError("identify/candidate_enrichment_failed", {
              scan_id: generatedScanId,
              scientific_name: capturedCandidates[index] ?? null,
              error: result.reason instanceof Error
                ? result.reason.message
                : String(result.reason),
            });
          }
        }

        if (needsGroupTags && groupTagsResult?.group_tags?.length) {
          await updateGroupTags(
            parsedData.scientific_name!,
            groupTagsResult.group_tags,
            supabaseAdmin,
          );
        }

        const totalTokens = (llmTotalTokens ?? 0) +
          (groupTagsResult?.usage?.totalTokenCount ?? 0);
        await trackPostHogEvent(user, "ScanCompleted", {
          is_biological_subject: parsedData.is_biological_subject,
          tier: userTier,
          ...tierTelemetryProperties(tierResolution),
          llm_model: targetModel,
          ai_provider: result.execution.provider,
          ai_binding: result.execution.binding,
          ai_prompt: result.execution.prompt,
          ai_schema: result.execution.schema,
          ai_policy_version: result.execution.policyVersion,
          ai_context_kind: result.execution.contextKind,
          ai_returned_model: result.returnedModel,
          ai_provider_duration_ms: result.providerDurationMs,
          llm_prompt_tokens: llmPromptTokens,
          llm_candidate_tokens: llmCandidateTokens,
          llm_thinking_tokens: llmThinkingTokens,
          llm_cached_tokens: llmCachedTokens,
          llm_total_tokens: llmTotalTokens,
          encyclopedic_tokens: 0,
          similar_species_tokens: 0,
          group_tags_tokens: groupTagsResult?.usage?.totalTokenCount ?? 0,
          cumulative_scan_tokens: totalTokens,
          scientific_name: parsedData.scientific_name,
        });
      } catch (error) {
        logStructuredError("identify/optional_completion_work_failed", {
          user_id: user.id,
          scan_id: generatedScanId,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    };
    runBackground(runOptionalCompletionWork());

    console.log(`[⏱ BENCH] total_to_response: ${Date.now() - fnStart}ms`);
    return jsonResponse(responseEnvelope, 200);
  };
}

const handleIdentifyRequest = createIdentifyHandler();

if (import.meta.main) {
  Deno.serve((req: Request) =>
    withEdgeHandler(
      req,
      (user, supabaseAdmin) => handleIdentifyRequest(req, user, supabaseAdmin),
    )
  );
}
