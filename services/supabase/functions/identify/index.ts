import {
  HarmBlockThreshold,
  HarmCategory,
  Part,
  SafetyRating,
} from "npm:@google/genai@1.0.0";
import { evaluateAndProcessPayload } from "../_shared/identify/moderation.ts";
import { deleteR2Object, getR2Config } from "../_shared/aws.ts";
import {
  jsonResponse,
  logStructuredError,
  runBackground,
  withEdgeHandler,
} from "../_shared/edgeHandler.ts";
import { fetchGroupTags } from "../_shared/biology.ts";
import { fetchExternalEnrichment } from "../_shared/external.ts";
import { _genAI, extractJson } from "../_shared/gemini.ts";
import {
  resolveTierForUser,
  tierTelemetryProperties,
} from "../_shared/tierCache.ts";
import { trackPostHogEvent } from "../_shared/posthog.ts";
import { requireParams } from "../_shared/http.ts";
import {
  coalesceTaxonomyValue,
  normalizeTaxonomyValue,
} from "../_shared/taxonomy.ts";
import {
  buildContextText,
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
  MerianIdentification,
  Payload,
} from "../_shared/identify/types.ts";
import {
  getMerianResponseSchema,
  getSystemInstruction,
} from "../_shared/identify/schema.ts";
import {
  diagnosticTriggerForTier,
  FLASH_DIAGNOSTIC_TRIGGER,
  PRO_DIAGNOSTIC_TRIGGER,
} from "../_shared/identify/thresholds.ts";
import {
  resolveImagePayloads,
  validateImageR2ObjectKeys,
} from "../_shared/identify/media.ts";
import {
  MEDIA_BUDGETS,
  readRequestJsonWithinBudget,
} from "../_shared/mediaBudgets.ts";
import {
  canonicalizeDomesticPetScientificName,
  sanitizePetIdentification,
  sanitizeScientificName,
} from "./sanitize.ts";
import {
  fetchCachedSpecies,
  fetchCandidateCommonNames,
  insertScan,
  updateGroupTags,
  upsertGhostUserIfMissing,
  upsertSpeciesDictionary,
} from "../_shared/identify/db.ts";
import { hydratePayloadFromCachedSpecies } from "../_shared/identify/clientPayload.ts";

// Safety settings shared by all vision model tiers.
// Biological photography legitimately triggers Gemini's medium-sensitivity defaults:
//   - DANGEROUS_CONTENT: venomous animals, dead specimens, parasites, wounds
//   - SEXUALLY_EXPLICIT: mating behaviour, reproductive organs, fruiting bodies
// BLOCK_ONLY_HIGH passes all genuine field-biology content while still blocking
// unambiguously harmful material. HARASSMENT and HATE_SPEECH remain at defaults —
// they are not relevant to biological photography.
const BIOLOGICAL_SAFETY_SETTINGS = [
  {
    category: HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT,
    threshold: HarmBlockThreshold.BLOCK_ONLY_HIGH,
  },
  {
    category: HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT,
    threshold: HarmBlockThreshold.BLOCK_ONLY_HIGH,
  },
];

// Vision model config objects — pre-built at module scope for warm isolate re-use.
// @google/genai has no getGenerativeModel() — config is passed per-call to
// _genAI.models.generateContent(). Pre-defining them here keeps the call site clean.
//
// Thinking budget strategy:
//   Flash (free tier): 2,048 tokens. Raised from 1,024 after production data showed
//   invasive/complex species (e.g. Carpobrotus edulis) hitting 1,016/1,024 — effectively
//   capped. 2,048 provides headroom for the observed worst-case while keeping cost low.
//
//   Pro: 5,000 tokens. Covers the hardest observed case (~3,200 tokens for an ambiguous
//   subject) with headroom for fossils, rare cultivars, and subspecies discrimination —
//   the exact use cases Pro users pay for.
//
//   Text-only Flash calls (encyclopedic, similar species, group tags) use thinkingBudget: 0
//   via createFlashModel() in _shared/gemini.ts — no visual ambiguity, no benefit.
const modelConfigs = {
  flash: {
    model: "gemini-2.5-flash" as const,
    config: {
      systemInstruction: getSystemInstruction(FLASH_DIAGNOSTIC_TRIGGER),
      temperature: 0.1,
      // seed pins the random sampler to a fixed starting state. For identical
      // inputs (same image bytes + same context parts), this produces the same
      // token sequence, making repeated scans of the same subject converge on
      // the same identification rather than drifting across runs.
      seed: 42,
      // topK=40 explicitly caps the candidate-token pool, complementing the
      // already-low temperature. The combination narrows the distribution enough
      // that borderline identifications consistently resolve to the same species.
      topK: 40,
      maxOutputTokens: 4096,
      thinkingConfig: { thinkingBudget: 2048 },
      safetySettings: BIOLOGICAL_SAFETY_SETTINGS,
    },
  },
  pro: {
    model: "gemini-2.5-pro" as const,
    config: {
      systemInstruction: getSystemInstruction(PRO_DIAGNOSTIC_TRIGGER),
      temperature: 0.1,
      seed: 42,
      topK: 40,
      maxOutputTokens: 8192,
      thinkingConfig: { thinkingBudget: 5000 },
      safetySettings: BIOLOGICAL_SAFETY_SETTINGS,
    },
  },
};

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
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

    const keyValidationError = validateImageR2ObjectKeys(
      r2ObjectKeys,
      user.id,
      {
        enforceOwnership: !imageBase64s || imageBase64s.length === 0,
        idorEvent: "identify/image_idor_attempt",
      },
    );
    if (keyValidationError) return keyValidationError;

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
    const tierResolution = await resolveTierForUser(user.id, supabaseAdmin);
    const userTier = tierResolution.effective_tier;

    // Pro users get gemini-2.5-pro for maximum identification depth (rare species, fossils,
    // subspecies, cultivars). Free users use gemini-2.5-flash for 2–3× lower latency.
    const targetModel = userTier === "pro"
      ? "gemini-2.5-pro"
      : "gemini-2.5-flash";
    const diagnosticTrigger = diagnosticTriggerForTier(
      userTier === "pro" ? "pro" : "flash",
    );

    const modelCfg = userTier === "pro" ? modelConfigs.pro : modelConfigs.flash;

    // Build the multipart content array. Image parts always come first so the model
    // anchors its visual read before seeing the user's text. The description part is
    // appended only when the user staged a describe note alongside their images —
    // it provides morphological cues (colour, size, behaviour) that the image alone
    // may not convey, sharpening subspecies and look-alike disambiguation.
    const descriptionPart: Part[] = description && description.trim().length > 0
      ? [{
        text:
          `\n\nAdditional observation context from user:\n${description.trim()}`,
      }]
      : [];

    const parts: Part[] = [
      {
        text: buildContextText(
          {
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
          "Perform biological identification.",
        ),
      },
      ...base64Payloads.map((payload) => ({
        inlineData: { mimeType: mimeType || "image/webp", data: payload },
      })),
      ...descriptionPart,
    ];

    console.log(`[⏱ BENCH] pre_gemini: ${Date.now() - fnStart}ms`);
    const geminiStart = Date.now();

    let finishReason: string | undefined;
    let safetyRatings: SafetyRating[] | undefined;
    let responseText = "";
    let llmPromptTokens: number | null = null;
    let llmCandidateTokens: number | null = null;
    let llmTotalTokens: number | null = null;
    let llmThinkingTokens: number | null = null;
    let llmCachedTokens: number | null = null;

    try {
      const result = await _genAI.models.generateContent({
        model: modelCfg.model,
        contents: [{ role: "user", parts }],
        config: {
          ...modelCfg.config,
          responseMimeType: "application/json",
          responseSchema: getMerianResponseSchema(diagnosticTrigger),
        },
      });
      const candidate = result.candidates?.[0];
      finishReason = candidate?.finishReason;
      safetyRatings = candidate?.safetyRatings;
      responseText = result.text ?? "";

      // Defensive fallback: result.text returns "" when the @google/genai@1.0.0
      // text getter finds no non-thought text parts — observed when candidatesTokenCount > 0
      // but all parts are typed differently under schema-constrained JSON output.
      // Directly reading parts[0].text recovers the response in that case.
      if (!responseText) {
        const firstPart = result.candidates?.[0]?.content?.parts?.[0];
        if (
          firstPart && "text" in firstPart && typeof firstPart.text === "string"
        ) {
          responseText = firstPart.text;
          console.log(
            `[identify] result.text was empty; recovered ${responseText.length} chars from parts[0].text`,
          );
        }
      }

      const usage = result.usageMetadata;
      if (usage) {
        llmPromptTokens = usage.promptTokenCount ?? null;
        llmCandidateTokens = usage.candidatesTokenCount ?? null;
        llmTotalTokens = usage.totalTokenCount ?? null;
        // thoughtsTokenCount is properly typed in @google/genai's UsageMetadata —
        // this is what previously appeared as the unexplained gap in totalTokenCount.
        llmThinkingTokens = usage.thoughtsTokenCount ?? null;
        // cachedContentTokenCount is non-zero when Gemini's implicit caching
        // triggered on this request (system instruction prefix matched a cached
        // context). Non-null only after the system instruction exceeds the 1,024
        // token minimum for gemini-2.5-flash. Used to verify caching is active.
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
      // Extract structured details so Supabase function logs surface the exact
      // Gemini error without needing to decode a stringified Error object.
      const errMsg = genError instanceof Error
        ? genError.message
        : String(genError);
      const errStatus = (genError as Record<string, unknown>)?.status ??
        (genError as Record<string, unknown>)?.statusCode ?? null;
      logStructuredError("identify/gemini_failed", {
        user_id: user.id,
        model: modelCfg.model,
        elapsed_ms: Date.now() - geminiStart,
        error_message: errMsg,
        error_status: errStatus,
      });
      // Return 503 (not 400) so the iOS offline queue treats this as a transient failure
      // and retries up to maxUploadRetries times rather than tombstoning the scan permanently.
      // 400 is reserved for genuine client errors (bad params, IDOR). Gemini API errors
      // (rate limits, timeouts, internal errors) are all transient and should be retried.
      return jsonResponse(
        { error: "AI processing error. Please try again." },
        503,
      );
    }

    // Guard non-STOP finish reasons before attempting JSON extraction.
    // When finishReason is SAFETY/RECITATION/OTHER, result.text is "" and
    // extractJson throws "no JSON object found" — producing a confusing 422.
    // SAFETY / PROHIBITED_CONTENT = permanent content policy failure → 400 (tombstone on iOS).
    // All other non-STOP reasons (MAX_TOKENS, RECITATION, OTHER) are transient → 503 (retry).
    if (
      finishReason && finishReason !== "STOP" &&
      finishReason !== "FINISH_REASON_UNSPECIFIED"
    ) {
      const isPermanentContentFailure = finishReason === "SAFETY" ||
        finishReason === "PROHIBITED_CONTENT";
      logStructuredError("identify/non_stop_finish", {
        user_id: user.id,
        finish_reason: finishReason,
        response_length: responseText.length,
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
      // Log enough context to diagnose the root cause without re-reading the code.
      // finish_reason, response_length, and the first 500 chars of responseText cover
      // the two main failure modes: truncated JSON (MAX_TOKENS) and empty response.
      logStructuredError("identify/parse_failed", {
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

    // Derive blur_score from sharpness (1-10) for latency savings
    parsedData.blur_score = Math.max(
      0,
      (10 - (parsedData.image_quality?.sharpness ?? 10)) / 10,
    );

    // Use the client-provided scan ID when available so the iOS offline queue can
    // correlate the server record with its local OfflineQueuedScan. Combined with the
    // idempotent upsert in insertScan, this makes replayed inference requests safe.
    const generatedScanId: string =
      typeof client_scan_id === "string" && client_scan_id.length > 0
        ? client_scan_id
        : crypto.randomUUID();
    let payloadReadyForClient: ClientPayload = {
      ...parsedData,
      scan_id: generatedScanId,
      inference_tier: userTier === "pro" ? "pro" : "flash",
    };

    // Strip candidates when confidence is at or above the tier's diagnosticTrigger threshold (0.99 both tiers).
    // Mirrors MerianConfig.flashConfidence.diagnosticTrigger and MerianConfig.proConfidence.diagnosticTrigger.
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

    const runBackgroundIngestion = async () => {
      // modResult is hoisted outside the try so the catch can reference publicUrls
      // for R2 rollback if insertScan fails after media has already been committed.
      let modResult:
        | Awaited<ReturnType<typeof evaluateAndProcessPayload>>
        | undefined;
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
        if (modResult.status === "ERROR") {
          // Moderation pipeline failed (e.g. abuse strike write, R2 upload error).
          // Do not insert the scan — image_storage_urls would be null and the DB row
          // would be permanently orphaned with no media.
          console.error(
            "Moderation pipeline returned ERROR. Halting background data ingestion.",
          );
          return;
        }
        if (
          modResult.status === "SHADOWBANNED" ||
          modResult.status === "DELETED_WARNING"
        ) {
          console.error(
            "Media flagged by safety moderation. Halting background data ingestion.",
          );
          return;
        }

        // Start diagnostic group-tag Flash call.
        // Cheap, species-level, and skipped when already cached.
        const needsGroupTags = isIdentifiedBio &&
          !cachedSpecies?.group_tags?.length;
        const groupTagsPromise = needsGroupTags
          ? fetchGroupTags(user, parsedData.scientific_name!)
          : Promise.resolve(null);

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

          const newCommonNames = {
            ...(freshSpecies?.common_names ?? cachedSpecies?.common_names ??
              {}),
            ...(parsedData.common_name ? { en: parsedData.common_name } : {}),
          };

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
              native_region: "Unknown",
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
            depth_scale_text: depthScaleText,
            ai_reasoning: parsedData.ai_reasoning ?? null,
            extracted_visual_traits: parsedData.extracted_visual_traits ?? [],
            colors: [],
            llm_prompt_tokens: llmPromptTokens,
            llm_candidate_tokens: llmCandidateTokens,
            llm_thinking_tokens: llmThinkingTokens,
            llm_cached_tokens: llmCachedTokens,
            llm_total_tokens: llmTotalTokens,
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

        // Capture the candidate enrichment promise before the final bgWriteTasks await so
        // EdgeRuntime.waitUntil cannot terminate the isolate while external DNS resolution
        // and upsertSpeciesDictionary writes are still in flight. A floating (un-awaited)
        // Promise.allSettled is invisible to waitUntil and will be killed mid-flight the
        // moment runBackgroundIngestion returns.
        let candidateEnrichmentTask: Promise<void> = Promise.resolve();
        if (missingCandidates.length > 0) {
          const bgCandidateEnrichStart = Date.now();
          const capturedCandidates = missingCandidates.slice();
          candidateEnrichmentTask = Promise.allSettled(
            capturedCandidates.map(async (candidateName) => {
              const externalData = await fetchExternalEnrichment(candidateName);

              const primaryEnName = (externalData.wikiTitle &&
                  externalData.wikiTitle.toLowerCase() !==
                    candidateName.toLowerCase())
                ? externalData.wikiTitle.replace(/\s*\([^)]+\)$/, "").trim()
                : (externalData.alternativeCommonNames[0] ?? null);

              const primaryEnLower = (primaryEnName ?? "").toLowerCase();
              const newAltNames: string[] | null =
                externalData.alternativeCommonNames.length > 0
                  ? externalData.alternativeCommonNames.filter(
                    (n) => n.toLowerCase() !== primaryEnLower,
                  )
                  : null;

              await upsertSpeciesDictionary(
                {
                  scientific_name: candidateName,
                  common_names: primaryEnName ? { en: primaryEnName } : {},
                  alternative_common_names: newAltNames,
                  kingdom: null,
                  phylum: null,
                  class: null,
                  order: null,
                  family: null,
                  genus: null,
                  wikipedia_overview: externalData.wikiExtract ?? null,
                  hazard_type: "none",
                  native_region: "Unknown",
                  iucn_red_list_status: "not_evaluated",
                  habitat_description: undefined,
                  wikipedia_url: externalData.wikipediaUrl,
                  gbif_taxon_key: externalData.gbifKey,
                  reference_image_url: externalData.referenceImageUrl,
                },
                supabaseAdmin,
              );
            }),
          ).then((results) => {
            for (let i = 0; i < results.length; i++) {
              const res = results[i];
              if (res.status === "rejected") {
                console.error(
                  `[bg_candidate_enrichment] Failed to enrich ${
                    capturedCandidates[i]
                  }:`,
                  res.reason instanceof Error
                    ? res.reason.message
                    : String(res.reason),
                );
              }
            }
            console.log(
              `[⏱ BENCH] bg_candidate_enrichment: ${
                Date.now() - bgCandidateEnrichStart
              }ms`,
            );
          });
        }

        // Await species-level Flash call
        const groupTagsResult = await groupTagsPromise;

        const totalTokens = (llmTotalTokens ?? 0) +
          (groupTagsResult?.usage?.totalTokenCount ?? 0);

        // Fire PostHog as fire-and-forget — analytics must never add latency to ingestion.
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
          group_tags_tokens: groupTagsResult?.usage?.totalTokenCount ?? 0,
          cumulative_scan_tokens: totalTokens,
          scientific_name: parsedData.scientific_name,
        }).catch((e) => console.error("PostHog tracking failed:", e));

        const bgWriteStart = Date.now();
        const bgWriteResults = await Promise.allSettled([
          needsGroupTags && groupTagsResult?.group_tags?.length
            ? updateGroupTags(
              parsedData.scientific_name!,
              groupTagsResult.group_tags,
              supabaseAdmin,
            )
            : Promise.resolve(),
          // Bind candidate enrichment into the waitUntil execution lock so the isolate
          // cannot terminate before all upsertSpeciesDictionary writes have resolved.
          candidateEnrichmentTask,
        ]);
        for (const result of bgWriteResults) {
          if (result.status === "rejected") {
            console.error(JSON.stringify({
              event: "bg_species_write_failed",
              scan_id: generatedScanId,
              error: result.reason instanceof Error
                ? result.reason.message
                : String(result.reason),
              ts: new Date().toISOString(),
            }));
          }
        }
        console.log(
          `[⏱ BENCH] bg_species_writes: ${Date.now() - bgWriteStart}ms`,
        );
      } catch (e) {
        // Revert R2 uploads to prevent untracked orphans when the scan DB write failed.
        // Only roll back if modResult exists (media was committed) but the scan row wasn't
        // written yet — a post-insert failure would leave a valid scan referencing the media.
        if (!scanInserted && modResult?.publicUrls?.length) {
          console.log("Rolling back R2 uploads due to scan insert failure.");
          const r2Config = getR2Config();
          const keysToPurge = modResult.publicUrls.map((url: string) =>
            url.replace("https://media.merian.app/", "")
          );
          const rollbackResults = await Promise.allSettled(
            keysToPurge.map((key: string) => deleteR2Object(key, r2Config)),
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

        // Write to dead-letter table so failed ingestions are durable and retryable.
        // The iOS client already received a 200 and holds the scan in local SwiftData,
        // but without this record the server-side row is permanently missing (multi-device
        // sync gap, absent from DwC-A exports). Ops can query failed_scan_ingestions to
        // identify and manually trigger recovery for affected users.
        // Best-effort: if this insert also fails (e.g. DB is down), the structured log
        // above is still the recovery signal.
        //
        // TODO(transactional-outbox): Replace this reactive dead-letter pattern with a
        // proactive transactional outbox. Before returning 200 to the iOS client, write a
        // "pending" outbox record. The background task marks it "done" on success; a
        // separate worker retries "pending" records older than N minutes automatically.
        // This eliminates the window where the iOS client has the scan locally but the
        // server row is permanently missing (current gap: failure between 200 response and
        // DB insert). Tracked: search codebase for "transactional-outbox".
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
    };

    runBackground(runBackgroundIngestion());

    console.log(`[⏱ BENCH] total_to_response: ${Date.now() - fnStart}ms`);
    return jsonResponse({ success: true, data: payloadReadyForClient }, 200);
  })
);
