import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { Part, SafetyRating } from "https://esm.sh/@google/genai@1.0.0";

import {
  jsonResponse,
  logStructuredError,
  runBackground,
  withEdgeHandler,
} from "../_shared/edgeHandler.ts";
import { _genAI, extractJson } from "../_shared/gemini.ts";
import { getTierForUser } from "../_shared/tierCache.ts";
import { trackPostHogEvent } from "../_shared/posthog.ts";
import { requireParams } from "../_shared/http.ts";
import { fetchExternalEnrichment } from "../_shared/external.ts";
import { fetchGroupTags } from "../_shared/biology.ts";
import { deleteR2Object, getR2Config } from "../_shared/aws.ts";

import {
  CachedSpeciesRow,
  ClientPayload,
  MerianIdentification,
  MultimodalPayload,
} from "../_shared/identify/types.ts";
import { hydratePayloadFromCachedSpecies } from "../_shared/identify/clientPayload.ts";
import {
  fetchCachedSpecies,
  fetchCandidateCommonNames,
  insertScan,
  updateGroupTags,
  upsertGhostUserIfMissing,
  upsertSpeciesDictionary,
} from "../_shared/identify/db.ts";
import { processWAV } from "./audio.ts";
import { resolveImagePayloads } from "../_shared/identify/media.ts";
import { evaluateAndProcessPayload } from "../_shared/identify/moderation.ts";

import { diagnosticTriggerForTier } from "../_shared/identify/thresholds.ts";
import {
  getMerianResponseSchema,
  getSystemInstruction as getVisionSystemInstruction,
} from "../_shared/identify/schema.ts";
import { sanitizeScientificName } from "../identify/sanitize.ts";

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
- Use authoritative nomenclature (Clements Checklist v2024 for birds, GBIF Backbone Taxonomy for all other taxa).
- Never fabricate scientific names.`;

const DESCRIBE_SYSTEM_INSTRUCTION = `# Role
You are a taxonomic analyst interpreting user text descriptions to identify biological subjects.

# Task
Read the user's description and identify the biological subject they are describing.`;

const MULTIMODAL_BLENDED_SYSTEM_INSTRUCTION = `# Role
You are an expert encyclopedic field-guide biologist and taxonomist with specialized expertise in cross-modal taxonomy.

# Core Directives
- **Holistic Evaluation:** Evaluate the provided audio spectrograms AND visual images sequentially before formulating a combined taxonomic confidence score.
- **Modality Synthesis:** Weigh BOTH visual and acoustic evidence. Prioritize the bio-acoustic trace unless it clearly contradicts the vision context or the vision context is overwhelmingly diagnostic.
- **Reporting:** Your \`ai_reasoning\` MUST encompass BOTH modalities, explaining how they corroborate or contradict each other.`;

const VALID_LIFE_STAGES = new Set([
  "egg",
  "larva",
  "pupa",
  "nymph",
  "juvenile",
  "subadult",
  "adult",
  "seedling",
  "sapling",
  "unknown",
]);

const VALID_REPRODUCTIVE_CONDITIONS = new Set([
  "flowering",
  "fruiting",
  "budding",
  "vegetative",
  "sporing",
  "pregnant",
  "gravid",
  "mating",
  "spawning",
  "nesting",
  "dormant",
  "not_applicable",
]);

function normalizeCurrentMonth(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) {
    const month = Math.trunc(value);
    return month >= 1 && month <= 12 ? month : undefined;
  }

  if (typeof value === "string") {
    const trimmed = value.trim();
    if (/^\d{1,2}$/.test(trimmed)) {
      const month = Number(trimmed);
      return month >= 1 && month <= 12 ? month : undefined;
    }
  }

  return undefined;
}

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const fnStart = Date.now();
    const rawBody: Record<string, unknown> = await req.json();

    const paramError = requireParams(rawBody, ["user_id"]);
    if (paramError) return paramError;

    const payload = rawBody as unknown as MultimodalPayload; // Trigger TS Language Server refresh
    const {
      client_scan_id,
      timestamp,
      imageBase64s = [],
      audioBase64s = [],
      observation_contexts = [],
      r2ObjectKeys = [],
      mimeType = "image/webp",
    } = payload;

    // The active Swift client sends camelCase telemetry while older queued payloads and
    // some server-side tooling still use snake_case. Accept both forms so the live path
    // remains backward-compatible during migrations and offline queue replays.
    const gpsLatitude = payload.gpsLatitude ?? payload.gps_latitude;
    const gpsLongitude = payload.gpsLongitude ?? payload.gps_longitude;
    const gpsElevation = payload.gpsElevation ?? payload.gps_elevation;
    const semanticLocation =
      payload.semanticLocation ?? payload.semantic_location;
    const weatherCondition =
      payload.weatherCondition ?? payload.weather_condition;
    const weatherTemperatureF =
      payload.weatherTemperatureF ?? payload.weather_temperature_f;
    const deviceLocale = payload.deviceLocale ?? payload.device_locale;
    const deviceTimeZone =
      payload.deviceTimeZone ?? payload.device_time_zone;
    const deviceRegion = payload.deviceRegion ?? payload.device_region;
    const currentMonth = normalizeCurrentMonth(
      payload.currentMonth ?? payload.current_month,
    );
    const timeOfDay = payload.timeOfDay ?? payload.time_of_day;
    const depthScaleText =
      payload.depthScaleText ?? payload.depth_scale_text;
    const zoomFactor = payload.zoomFactor;
    const estimatedSizeCm =
      payload.estimatedSizeCm ?? payload.estimated_size_cm;

    const generatedScanId =
      typeof client_scan_id === "string" && client_scan_id.length > 0
        ? client_scan_id
        : crypto.randomUUID();

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

    // 1. Image Resolution (R2 Fetching + IDOR Check)
    if (r2ObjectKeys && r2ObjectKeys.length > 0) {
      for (const r2ObjectKey of r2ObjectKeys) {
        if (r2ObjectKey.includes("..")) {
          return jsonResponse({
            error: "Bad Request: Path traversal detected.",
          }, 400);
        }
        if (!r2ObjectKey.startsWith(`staging/${user.id}/`)) {
          console.error(
            `IDOR: r2ObjectKey ${r2ObjectKey} does not belong to user ${user.id}`,
          );
          return jsonResponse(
            {
              error:
                "Forbidden: r2ObjectKey does not belong to the requesting user.",
            },
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

    const resolvedImageBase64s = base64Payloads || [];

    // 2. WAV Preprocessing Loop
    let processedAudios: string[] = [];
    if (audioBase64s.length > 0) {
      try {
        const decodes = audioBase64s.map((b64) => {
          const buf = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)).buffer;
          return processWAV(buf);
        });
        processedAudios = await Promise.all(decodes);
      } catch (wavErr) {
        logStructuredError("multimodal/wav_parse_failed", {
          user_id: user.id,
          error: String(wavErr),
        });
        return jsonResponse({ error: "Invalid audio file format." }, 400);
      }
    }

    // 2. Dispatch Rule
    const userTier = await getTierForUser(user.id, supabaseAdmin);
    const diagnosticTrigger = diagnosticTriggerForTier(
      userTier as "pro" | "flash",
    );

    let instructionToUse = "";
    if (resolvedImageBase64s.length > 0 && processedAudios.length > 0) {
      instructionToUse = MULTIMODAL_BLENDED_SYSTEM_INSTRUCTION;
    } else if (resolvedImageBase64s.length > 0) {
      instructionToUse = getVisionSystemInstruction(diagnosticTrigger);
    } else if (processedAudios.length > 0) {
      instructionToUse = BIOACOUSTIC_SYSTEM_INSTRUCTION;
    } else {
      instructionToUse = DESCRIBE_SYSTEM_INSTRUCTION;
    }

    // 3. Modality Assembly
    const partsArray: Part[] = [];
    let hasObservationContextText = false;
    if (observation_contexts.length > 0) {
      const mergedContexts = observation_contexts
        .map((c) =>
          typeof c.freeText === "string" && c.freeText.trim().length > 0
            ? c.freeText.trim()
            : (typeof c.free_text === "string" && c.free_text.trim().length > 0
              ? c.free_text.trim()
              : null)
        )
        .filter((text): text is string => text != null);
      if (mergedContexts.length > 0) {
        hasObservationContextText = true;
        partsArray.push({
          text: `Additional observation context from user:\n${
            mergedContexts.join(
              "\n",
            )
          }`,
        });
      }
    }

    for (const b64 of resolvedImageBase64s) {
      partsArray.push({ inlineData: { mimeType, data: b64 } });
    }

    for (const audio of processedAudios) {
      partsArray.push({ inlineData: { mimeType: "audio/wav", data: audio } });
    }

    const telemetryItems = [
      safeGpsLat != null && safeGpsLon != null
        ? `GPS:${safeGpsLat},${safeGpsLon}`
        : null,
      gpsElevation != null ? `Elev:${gpsElevation}m` : null,
      depthScaleText ? `Depth:${depthScaleText}` : null,
      zoomFactor != null && Number.isFinite(zoomFactor) && zoomFactor > 1
        ? `Zoom:${zoomFactor.toFixed(1)}x`
        : null,
      (estimatedSizeCm != null && Number.isFinite(estimatedSizeCm) &&
          estimatedSizeCm > 0)
        ? `Size:${estimatedSizeCm}cm`
        : null,
      semanticLocation ? `Loc:${semanticLocation}` : null,
      weatherCondition ? `Wx:${weatherCondition}` : null,
      weatherTemperatureF != null ? `Temp:${weatherTemperatureF}F` : null,
      deviceLocale ? `Locale:${deviceLocale}` : null,
      deviceTimeZone ? `TZ:${deviceTimeZone}` : null,
      deviceRegion ? `Region:${deviceRegion}` : null,
      currentMonth != null ? `Month:${currentMonth}` : null,
      timeOfDay ? `Time:${timeOfDay}` : null,
    ].filter(Boolean).join(", ");
    partsArray.push({ text: `Context: ${telemetryItems || "no telemetry"}.` });

    if (partsArray.length === 1 && !hasObservationContextText) {
      return jsonResponse({
        error: "At least one media element or description is required",
      }, 400);
    }

    // 4. Invocation
    const geminiStart = Date.now();
    let responseText = "";
    let finishReason: string | undefined;
    let safetyRatings: SafetyRating[] | undefined;

    let llmPromptTokens: number | null = null;
    let llmCandidateTokens: number | null = null;
    let llmThinkingTokens: number | null = null;
    let llmTotalTokens: number | null = null;

    try {
      const result = await _genAI.models.generateContent({
        model: userTier === "pro" ? "gemini-2.5-pro" : "gemini-2.5-flash",
        contents: [{ role: "user", parts: partsArray }],
        config: {
          systemInstruction: instructionToUse,
          temperature: 0.1,
          seed: 42,
          maxOutputTokens: 8192,
          thinkingConfig: userTier === "pro"
            ? { thinkingBudget: 5000 }
            : undefined,
          responseMimeType: "application/json",
          responseSchema: getMerianResponseSchema(diagnosticTrigger),
        },
      });

      finishReason = result.candidates?.[0]?.finishReason;
      safetyRatings = result.candidates?.[0]?.safetyRatings;
      responseText = result.text ?? "";

      const usage = result.usageMetadata;
      if (usage) {
        llmPromptTokens = usage.promptTokenCount ?? null;
        llmCandidateTokens = usage.candidatesTokenCount ?? null;
        llmThinkingTokens = usage.thoughtsTokenCount ?? null;
        llmTotalTokens = usage.totalTokenCount ?? null;
      }
    } catch (genErr) {
      logStructuredError("multimodal/gemini_failed", {
        user_id: user.id,
        error: String(genErr),
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
      logStructuredError("multimodal/non_stop_finish", {
        user_id: user.id,
        finish_reason: finishReason,
      });
      return jsonResponse(
        { error: `AI processing error (${finishReason}).` },
        isPermanent ? 400 : 503,
      );
    }

    let parsedData: MerianIdentification;
    try {
      parsedData = extractJson<MerianIdentification>(responseText);
    } catch {
      return jsonResponse(
        { error: "Processing Error: Malformed AI response." },
        422,
      );
    }

    if (parsedData.scientific_name) {
      parsedData.scientific_name = sanitizeScientificName(
        parsedData.scientific_name,
      );
    }
    if (Array.isArray(parsedData.candidates)) {
      parsedData.candidates = parsedData.candidates
        .map((candidate) => ({
          ...candidate,
          scientific_name: sanitizeScientificName(candidate.scientific_name),
        }))
        .slice(0, 5);
    }
    if (Array.isArray(parsedData.extracted_visual_traits)) {
      parsedData.extracted_visual_traits =
        parsedData.extracted_visual_traits.slice(0, 10);
    }
    if (Array.isArray(parsedData.ecological_interactions)) {
      parsedData.ecological_interactions =
        parsedData.ecological_interactions.slice(0, 10);
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
    if (
      parsedData.life_stage != null &&
      !VALID_LIFE_STAGES.has(parsedData.life_stage)
    ) {
      logStructuredError("multimodal/unknown_life_stage", {
        user_id: user.id,
        value: parsedData.life_stage,
      });
      parsedData.life_stage = "unknown";
    }
    if (
      parsedData.reproductive_condition != null &&
      !VALID_REPRODUCTIVE_CONDITIONS.has(parsedData.reproductive_condition)
    ) {
      logStructuredError("multimodal/unknown_reproductive_condition", {
        user_id: user.id,
        value: parsedData.reproductive_condition,
      });
      parsedData.reproductive_condition = "not_applicable";
    }
    parsedData.blur_score = Math.max(
      0,
      (10 - (parsedData.image_quality?.sharpness ?? 10)) / 10,
    );

    let referenceImageUrl: string | null = null;
    let wikipediaUrl: string | null = null;
    let wikipediaOverview: string | null = null;
    let alternativeCommonNames: string[] | null = null;

    const isIdentifiedBio =
      !!(parsedData.is_biological_subject && parsedData.scientific_name);
    let cachedSpecies: CachedSpeciesRow | null = null;
    let externalData:
      | Awaited<ReturnType<typeof fetchExternalEnrichment>>
      | null = null;
    let missingCandidates: string[] = [];

    let payloadReadyForClient: ClientPayload = {
      scan_id: generatedScanId,
      is_biological_subject: parsedData.is_biological_subject,
      is_live_capture: parsedData.is_live_capture,
      scientific_name: parsedData.scientific_name,
      common_name: parsedData.common_name,
      confidence_score: parsedData.confidence_score,
      blur_score: parsedData.blur_score,
      ecology_type: parsedData.ecology_type,
      is_invasive: parsedData.is_invasive,
      life_stage: parsedData.life_stage ?? "unknown",
      inference_tier: userTier === "pro" ? "pro" : "flash",
      candidates: parsedData.candidates,
      image_quality: parsedData.image_quality,
      ai_reasoning: parsedData.ai_reasoning,
      insight_data: {
        ai_reasoning: parsedData.ai_reasoning,
        hazard_type: "none",
      },
      extracted_visual_traits: parsedData.extracted_visual_traits,
      reference_image_url: referenceImageUrl,
      wikipedia_url: wikipediaUrl,
      wikipedia_overview: wikipediaOverview,
      alternative_common_names: alternativeCommonNames,
    };

    if ((parsedData.confidence_score ?? 0.0) >= diagnosticTrigger) {
      payloadReadyForClient.candidates = null;
    }

    const hasCandidates =
      Array.isArray(payloadReadyForClient.candidates) &&
      payloadReadyForClient.candidates.length > 0;

    const [commonNameMap, fetchedCachedSpecies] = await Promise.all([
      hasCandidates
        ? fetchCandidateCommonNames(
          payloadReadyForClient.candidates!.map((candidate) =>
            candidate.scientific_name
          ),
          supabaseAdmin,
        )
        : Promise.resolve(new Map<string, string>()),
      isIdentifiedBio
        ? fetchCachedSpecies(parsedData.scientific_name!, supabaseAdmin).catch(
          (err) => {
            console.error("Synchronous enrichment error:", err);
            return null;
          },
        )
        : Promise.resolve(null),
    ]);

    if (hasCandidates) {
      const candidateNames = payloadReadyForClient.candidates!.map((candidate) =>
        candidate.scientific_name
      );
      missingCandidates = candidateNames.filter((name) =>
        !commonNameMap.has(name)
      );
      if (commonNameMap.size > 0) {
        payloadReadyForClient.candidates = payloadReadyForClient.candidates!
          .map((candidate) => ({
            ...candidate,
            common_name: commonNameMap.get(candidate.scientific_name),
          }));
      }
    }

    if (isIdentifiedBio) {
      cachedSpecies = fetchedCachedSpecies;

      if (cachedSpecies?.kingdom) {
        payloadReadyForClient = hydratePayloadFromCachedSpecies(
          payloadReadyForClient,
          cachedSpecies,
        );
        referenceImageUrl = payloadReadyForClient.reference_image_url ?? null;
        wikipediaUrl = payloadReadyForClient.wikipedia_url ?? null;
        wikipediaOverview = payloadReadyForClient.wikipedia_overview ?? null;
        alternativeCommonNames =
          payloadReadyForClient.alternative_common_names ?? null;
      } else {
        try {
          externalData = await fetchExternalEnrichment(
            parsedData.scientific_name!,
          );
          if (externalData) {
            referenceImageUrl = externalData.referenceImageUrl;
            wikipediaUrl = externalData.wikipediaUrl;
            wikipediaOverview = externalData.wikiExtract;
            const primaryEn = (payloadReadyForClient.common_name ?? "")
              .toLowerCase();
            alternativeCommonNames =
              externalData.alternativeCommonNames.filter((name) =>
                name.toLowerCase() !== primaryEn
              );
          }
        } catch (err) {
          console.error("Synchronous enrichment error:", err);
        }
      }
    }

    payloadReadyForClient.reference_image_url = referenceImageUrl;
    payloadReadyForClient.wikipedia_url = wikipediaUrl;
    payloadReadyForClient.wikipedia_overview = wikipediaOverview;
    payloadReadyForClient.alternative_common_names = alternativeCommonNames;

    const persistedObservationContext = observation_contexts.find((context) =>
      context != null && typeof context === "object" && !Array.isArray(context)
    ) as Record<string, unknown> | undefined;

    const runBackgroundIngestion = async () => {
      let modResult:
        | Awaited<ReturnType<typeof evaluateAndProcessPayload>>
        | undefined;
      let scanInserted = false;
      try {
        await upsertGhostUserIfMissing(user.id, supabaseAdmin);
        const hasImagePayload = imageBase64s.length > 0 ||
          r2ObjectKeys.length > 0;
        if (hasImagePayload) {
          modResult = await evaluateAndProcessPayload(
            user.id,
            r2ObjectKeys,
            imageBase64s,
            finishReason,
            safetyRatings,
            userTier,
          );
          if (modResult.status === "ERROR") {
            console.error(
              "Multimodal moderation pipeline returned ERROR. Halting background data ingestion.",
            );
            return;
          }
          if (
            modResult.status === "SHADOWBANNED" ||
            modResult.status === "DELETED_WARNING"
          ) {
            console.error(
              "Multimodal media flagged by safety moderation. Halting background data ingestion.",
            );
            return;
          }
        }

        let speciesId: string | null = null;
        const needsGroupTags =
          isIdentifiedBio && !cachedSpecies?.group_tags?.length;
        const groupTagsPromise = needsGroupTags
          ? fetchGroupTags(user, parsedData.scientific_name!)
          : Promise.resolve(null);

        if (isIdentifiedBio) {
          if (cachedSpecies?.kingdom) {
            speciesId = cachedSpecies.id;
          } else if (externalData) {
            const freshSpecies = await fetchCachedSpecies(
              parsedData.scientific_name!,
              supabaseAdmin,
            );
            const upsertedId = await upsertSpeciesDictionary(
              {
                scientific_name: parsedData.scientific_name!,
                common_names: {
                  ...(freshSpecies?.common_names ?? {}),
                  ...(payloadReadyForClient.common_name
                    ? { en: payloadReadyForClient.common_name }
                    : {}),
                },
                kingdom: freshSpecies?.kingdom || "Unknown",
                phylum: freshSpecies?.phylum || "Unknown",
                class: freshSpecies?.class || "Unknown",
                order: freshSpecies?.order || "Unknown",
                family: freshSpecies?.family || "Unknown",
                genus: freshSpecies?.genus || "Unknown",
                native_region: "Unknown",
                wikipedia_url: externalData.wikipediaUrl,
                wikipedia_overview: externalData.wikiExtract,
                gbif_taxon_key: externalData.gbifKey,
                reference_image_url: externalData.referenceImageUrl,
                alternative_common_names: externalData.alternativeCommonNames,
              },
              supabaseAdmin,
            );
            speciesId = upsertedId || freshSpecies?.id || null;
          } else {
            speciesId = cachedSpecies?.id || null;
          }
        }

        await insertScan(
          {
            id: generatedScanId,
            user_id: user.id,
            species_id: speciesId,
            timestamp: timestamp ?? undefined,
            gps_lat_exact: safeGpsLat,
            gps_long_exact: safeGpsLon,
            gps_elevation: gpsElevation ?? null,
            ai_confidence_score: parsedData.confidence_score,
            blur_score: parsedData.blur_score,
            ecology_type: parsedData.ecology_type,
            is_invasive: parsedData.is_invasive,
            weather_condition: weatherCondition ?? undefined,
            weather_temperature_f: weatherTemperatureF ?? undefined,
            semantic_location: semanticLocation ?? undefined,
            device_locale: deviceLocale ?? undefined,
            current_month: currentMonth ?? null,
            time_of_day: timeOfDay ?? undefined,
            depth_scale_text: depthScaleText ?? undefined,
            ai_reasoning: parsedData.ai_reasoning ?? null,
            extracted_visual_traits: parsedData.extracted_visual_traits ?? [],
            colors: [],
            llm_prompt_tokens: llmPromptTokens,
            llm_candidate_tokens: llmCandidateTokens,
            llm_thinking_tokens: llmThinkingTokens,
            llm_cached_tokens: null,
            llm_total_tokens: llmTotalTokens,
            image_storage_urls: modResult?.publicUrls ?? [],
            life_stage: parsedData.life_stage ?? "unknown",
            reproductive_condition:
              parsedData.reproductive_condition ?? "not_applicable",
            individual_count: parsedData.individual_count ?? null,
            ecological_interactions: parsedData.ecological_interactions ?? [],
            estimated_size_cm:
              (estimatedSizeCm != null && Number.isFinite(estimatedSizeCm) &&
                  estimatedSizeCm > 0)
                ? Math.min(estimatedSizeCm, 50000)
                : null,
            inference_tier: userTier === "pro" ? "pro" : "flash",
            candidates: payloadReadyForClient.candidates ?? null,
            image_quality_score: parsedData.image_quality?.overall_score ?? null,
            is_live_capture: parsedData.is_live_capture,
            user_observation_context: persistedObservationContext ?? null,
          },
          supabaseAdmin,
        );
        scanInserted = true;

        let candidateEnrichmentTask: Promise<void> = Promise.resolve();
        if (missingCandidates.length > 0) {
          const capturedCandidates = missingCandidates.slice();
          candidateEnrichmentTask = Promise.allSettled(
            capturedCandidates.map(async (candidateName) => {
              const candidateExternalData = await fetchExternalEnrichment(
                candidateName,
              );

              const primaryEnName =
                (candidateExternalData.wikiTitle &&
                    candidateExternalData.wikiTitle.toLowerCase() !==
                      candidateName.toLowerCase())
                  ? candidateExternalData.wikiTitle.replace(/\s*\([^)]+\)$/, "")
                    .trim()
                  : (candidateExternalData.alternativeCommonNames[0] ?? null);

              const primaryEnLower = (primaryEnName ?? "").toLowerCase();
              const newAltNames: string[] | null =
                candidateExternalData.alternativeCommonNames.length > 0
                  ? candidateExternalData.alternativeCommonNames.filter((name) =>
                    name.toLowerCase() !== primaryEnLower
                  )
                  : null;

              await upsertSpeciesDictionary(
                {
                  scientific_name: candidateName,
                  common_names: primaryEnName ? { en: primaryEnName } : {},
                  alternative_common_names: newAltNames,
                  kingdom: "Unknown",
                  phylum: "Unknown",
                  class: "Unknown",
                  order: "Unknown",
                  family: "Unknown",
                  genus: "Unknown",
                  wikipedia_overview: candidateExternalData.wikiExtract ?? null,
                  hazard_type: "none",
                  native_region: "Unknown",
                  iucn_red_list_status: "not_evaluated",
                  habitat_description: undefined,
                  wikipedia_url: candidateExternalData.wikipediaUrl,
                  gbif_taxon_key: candidateExternalData.gbifKey,
                  reference_image_url: candidateExternalData.referenceImageUrl,
                },
                supabaseAdmin,
              );
            }),
          ).then((results) => {
            for (let i = 0; i < results.length; i++) {
              const result = results[i];
              if (result.status === "rejected") {
                console.error(
                  `[multimodal/candidate_enrichment] Failed to enrich ${
                    capturedCandidates[i]
                  }: ${
                    result.reason instanceof Error
                      ? result.reason.message
                      : String(result.reason)
                  }`,
                );
              }
            }
          });
        }

        const groupTagsResult = await groupTagsPromise;

        trackPostHogEvent(user.id, "scan_completed", {
          scan_id: generatedScanId,
          inference_tier: userTier === "pro" ? "pro" : "flash",
          is_identified: isIdentifiedBio,
          species_name: parsedData.scientific_name || null,
          gemini_latency_ms: Date.now() - geminiStart,
        }).catch((e) => console.error("PostHog tracking failed:", e));

        const bgWriteResults = await Promise.allSettled([
          needsGroupTags && groupTagsResult?.group_tags?.length
            ? updateGroupTags(
              parsedData.scientific_name!,
              groupTagsResult.group_tags,
              supabaseAdmin,
            )
            : Promise.resolve(),
          candidateEnrichmentTask,
        ]);
        for (const result of bgWriteResults) {
          if (result.status === "rejected") {
            console.error(
              JSON.stringify({
                event: "multimodal/bg_species_write_failed",
                scan_id: generatedScanId,
                error: result.reason instanceof Error
                  ? result.reason.message
                  : String(result.reason),
                ts: new Date().toISOString(),
              }),
            );
          }
        }
      } catch (e) {
        const errorMsg = e instanceof Error ? e.message : String(e);
        logStructuredError("multimodal/background_ingestion_failed", {
          user_id: user.id,
          scan_id: generatedScanId,
          error: errorMsg,
          scan_inserted: scanInserted,
        });

        // Dead-Letter Fallback
        if (!scanInserted) {
          try {
            await supabaseAdmin
              .from("failed_scan_ingestions")
              .insert({
                scan_id: generatedScanId,
                user_id: user.id,
                error_message: errorMsg,
              });
          } catch (dlErr) {
            logStructuredError("multimodal/dead_letter_write_failed", {
              scan_id: generatedScanId,
              error: String(dlErr),
            });
          }
        }

        if (!scanInserted && modResult?.publicUrls?.length) {
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
            logStructuredError("multimodal/r2_rollback_partial_failure", {
              scan_id: generatedScanId,
              user_id: user.id,
              failed_count: failedRollbacks.length,
              total_count: keysToPurge.length,
            });
          }
        }
      }
    };

    runBackground(runBackgroundIngestion());

    return jsonResponse({ success: true, data: payloadReadyForClient }, 200);
  })
);
