import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { Part } from "https://esm.sh/@google/genai@1.0.0";

import { jsonResponse, withEdgeHandler, runBackground, logStructuredError } from "../_shared/edgeHandler.ts";
import { _genAI, extractJson } from "../_shared/gemini.ts";
import { getTierForUser } from "../_shared/tierCache.ts";
import { trackPostHogEvent } from "../_shared/posthog.ts";
import { requireParams } from "../_shared/http.ts";
import { fetchExternalEnrichment } from "../_shared/external.ts";
import { fetchGroupTags } from "../_shared/biology.ts";
import { getR2Config, deleteR2Object } from "../_shared/aws.ts";

import { MultimodalPayload, ClientPayload, MerianIdentification } from "./types.ts";
import {
  upsertGhostUserIfMissing,
  fetchCachedSpecies,
  upsertSpeciesDictionary,
  insertScan,
  updateGroupTags,
} from "./db.ts";
import { processWAV } from "./audio.ts";
import { resolveImagePayloads } from "./media.ts";

import { diagnosticTriggerForTier } from "./thresholds.ts";
import { getSystemInstruction as getVisionSystemInstruction, getMerianResponseSchema } from "./schema.ts";

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

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const fnStart = Date.now();
    const rawBody: Record<string, unknown> = await req.json();

    const paramError = requireParams(rawBody, ["user_id"]);
    if (paramError) return paramError;

    const payload = rawBody as unknown as MultimodalPayload;
    const {
      client_scan_id,
      timestamp,
      gps_latitude,
      gps_longitude,
      gps_elevation,
      semantic_location,
      weather_condition,
      weather_temperature_f,
      device_locale,
      device_time_zone,
      device_region,
      current_month,
      time_of_day,
      imageBase64s = [],
      audioBase64s = [],
      observation_contexts = [],
      r2ObjectKeys = [],
      mimeType = "image/webp"
    } = payload;

    const generatedScanId =
      typeof client_scan_id === "string" && client_scan_id.length > 0
        ? client_scan_id
        : crypto.randomUUID();

    const safeGpsLat: number | null =
      gps_latitude != null && Number.isFinite(gps_latitude) &&
      gps_latitude >= -90 && gps_latitude <= 90
        ? gps_latitude : null;
    const safeGpsLon: number | null =
      gps_longitude != null && Number.isFinite(gps_longitude) &&
      gps_longitude >= -180 && gps_longitude <= 180
        ? gps_longitude : null;

    // 1. Image Resolution (R2 Fetching + IDOR Check)
    if (r2ObjectKeys && r2ObjectKeys.length > 0) {
      for (const r2ObjectKey of r2ObjectKeys) {
        if (r2ObjectKey.includes("..")) {
          return jsonResponse({ error: "Bad Request: Path traversal detected." }, 400);
        }
        if (!r2ObjectKey.startsWith(`staging/${user.id}/`)) {
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

    const resolvedImageBase64s = base64Payloads || [];

    // 2. WAV Preprocessing Loop
    let processedAudios: string[] = [];
    if (audioBase64s.length > 0) {
      try {
        const decodes = audioBase64s.map(b64 => {
          const buf = Uint8Array.from(atob(b64), c => c.charCodeAt(0)).buffer;
          return processWAV(buf);
        });
        processedAudios = await Promise.all(decodes);
      } catch (wavErr) {
        logStructuredError("multimodal/wav_parse_failed", { user_id: user.id, error: String(wavErr) });
        return jsonResponse({ error: "Invalid audio file format." }, 400);
      }
    }

    // 2. Dispatch Rule
    const userTier = await getTierForUser(user.id, supabaseAdmin);
    const diagnosticTrigger = diagnosticTriggerForTier(userTier as "pro" | "flash");

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
    if (observation_contexts.length > 0) {
      const mergedContexts = observation_contexts.map(c => c.freeText).join("\\n");
      partsArray.push({ text: `Additional observation context from user:\n${mergedContexts}` });
    }

    for (const b64 of resolvedImageBase64s) {
      partsArray.push({ inlineData: { mimeType, data: b64 } });
    }

    for (const audio of processedAudios) {
      partsArray.push({ inlineData: { mimeType: "audio/wav", data: audio } });
    }

    const telemetryItems = [
      safeGpsLat != null && safeGpsLon != null ? `GPS:${safeGpsLat},${safeGpsLon}` : null,
      gps_elevation != null ? `Elev:${gps_elevation}m` : null,
      semantic_location ? `Loc:${semantic_location}` : null,
      weather_condition ? `Wx:${weather_condition}` : null,
      weather_temperature_f != null ? `Temp:${weather_temperature_f}F` : null,
      device_locale ? `Locale:${device_locale}` : null,
      device_time_zone ? `TZ:${device_time_zone}` : null,
      device_region ? `Region:${device_region}` : null,
      current_month ? `Month:${current_month}` : null,
      time_of_day ? `Time:${time_of_day}` : null,
    ].filter(Boolean).join(", ");
    partsArray.push({ text: `Context: ${telemetryItems || "no telemetry"}.` });

    if (partsArray.length === 1 && !observation_contexts.length) {
      return jsonResponse({ error: "At least one media element or description is required" }, 400);
    }

    // 4. Invocation
    const geminiStart = Date.now();
    let responseText = "";
    let finishReason: string | undefined;
    
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
          maxOutputTokens: userTier === "pro" ? 8192 : 2048,
          thinkingConfig: userTier === "pro" ? { thinkingBudget: 5000 } : undefined,
          responseMimeType: "application/json",
          responseSchema: getMerianResponseSchema(diagnosticTrigger),
        },
      });

      finishReason = result.candidates?.[0]?.finishReason;
      responseText = result.text ?? "";

      const usage = result.usageMetadata;
      if (usage) {
        llmPromptTokens = usage.promptTokenCount ?? null;
        llmCandidateTokens = usage.candidatesTokenCount ?? null;
        llmThinkingTokens = usage.thoughtsTokenCount ?? null;
        llmTotalTokens = usage.totalTokenCount ?? null;
      }
    } catch (genErr) {
      logStructuredError("multimodal/gemini_failed", { user_id: user.id, error: String(genErr) });
      return jsonResponse({ error: "AI processing error. Please try again." }, 503);
    }

    if (finishReason && finishReason !== "STOP" && finishReason !== "FINISH_REASON_UNSPECIFIED") {
      const isPermanent = finishReason === "SAFETY" || finishReason === "PROHIBITED_CONTENT";
      logStructuredError("multimodal/non_stop_finish", { user_id: user.id, finish_reason: finishReason });
      return jsonResponse({ error: "AI processing error." }, isPermanent ? 400 : 503);
    }

    let parsedData: MerianIdentification;
    try {
      parsedData = extractJson<MerianIdentification>(responseText);
    } catch {
      return jsonResponse({ error: "Processing Error: Malformed AI response." }, 422);
    }

    if (Array.isArray(parsedData.candidates)) {
      parsedData.candidates = parsedData.candidates.slice(0, 5);
    }

    const payloadReadyForClient: ClientPayload = {
      scan_id: generatedScanId,
      is_biological_subject: parsedData.is_biological_subject,
      is_live_capture: parsedData.is_live_capture,
      scientific_name: parsedData.scientific_name,
      common_name: parsedData.common_name,
      confidence_score: parsedData.confidence_score,
      ecology_type: parsedData.ecology_type,
      is_invasive: parsedData.is_invasive,
      life_stage: parsedData.life_stage ?? "unknown",
      inference_tier: userTier === "pro" ? "pro" : "flash",
      candidates: parsedData.candidates,
      image_quality: parsedData.image_quality,
      ai_reasoning: parsedData.ai_reasoning,
      insight_data: {
        ai_reasoning: parsedData.ai_reasoning,
        hazard_type: parsedData.hazard_type || "none"
      },
      extracted_visual_traits: parsedData.extracted_visual_traits,
    };

    const runBackgroundIngestion = async () => {
      let scanInserted = false;
      try {
        await upsertGhostUserIfMissing(user.id, supabaseAdmin);
        let speciesId: string | null = null;
        
        const isIdentifiedBio = !!(parsedData.is_biological_subject && parsedData.scientific_name);
        
        if (isIdentifiedBio) {
          const cachedSpecies = await fetchCachedSpecies(parsedData.scientific_name!, supabaseAdmin);
          if (cachedSpecies?.kingdom) {
            speciesId = cachedSpecies.id;
          } else {
             const externalData = await fetchExternalEnrichment(parsedData.scientific_name!);
             const freshSpecies = await fetchCachedSpecies(parsedData.scientific_name!, supabaseAdmin);
             const upsertedId = await upsertSpeciesDictionary(
               {
                 scientific_name: parsedData.scientific_name!,
                 common_names: { ...(freshSpecies?.common_names ?? {}), ...(parsedData.common_name ? { en: parsedData.common_name } : {}) },
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
            gps_elevation: gps_elevation ?? null,
            ai_confidence_score: parsedData.confidence_score,
            ecology_type: parsedData.ecology_type,
            is_invasive: parsedData.is_invasive,
            weather_condition: weather_condition ?? undefined,
            weather_temperature_f: weather_temperature_f ?? undefined,
            semantic_location: semantic_location ?? undefined,
            device_locale: device_locale ?? undefined,
            current_month: current_month ?? undefined,
            time_of_day: time_of_day ?? undefined,
            ai_reasoning: parsedData.ai_reasoning ?? null,
            extracted_visual_traits: parsedData.extracted_visual_traits ?? [],
            colors: [],
            llm_prompt_tokens: llmPromptTokens,
            llm_candidate_tokens: llmCandidateTokens,
            llm_thinking_tokens: llmThinkingTokens,
            llm_cached_tokens: null,
            llm_total_tokens: llmTotalTokens,
            image_storage_urls: [],
            life_stage: parsedData.life_stage ?? "unknown",
            reproductive_condition: "not_applicable",
            ecological_interactions: [],
            inference_tier: userTier === "pro" ? "pro" : "flash",
            candidates: parsedData.candidates,
          },
          supabaseAdmin,
        );
        scanInserted = true;
        
        trackPostHogEvent(user.id, "scan_completed", {
          scan_id: generatedScanId,
          inference_tier: userTier === "pro" ? "pro" : "flash",
          is_identified: isIdentifiedBio,
          species_name: parsedData.scientific_name || null,
          gemini_latency_ms: Date.now() - geminiStart,
        }).catch((e) => console.error("PostHog tracking failed:", e));

        if (isIdentifiedBio && parsedData.scientific_name) {
          fetchGroupTags(user, parsedData.scientific_name).then((groupTagData) => {
            if (groupTagData && groupTagData.group_tags && groupTagData.group_tags.length > 0) {
              updateGroupTags(parsedData.scientific_name!, groupTagData.group_tags, supabaseAdmin).catch(console.error);
            }
          }).catch(console.error);
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
              .insert({ scan_id: generatedScanId, user_id: user.id, error_message: errorMsg });
          } catch (dlErr) {
            logStructuredError("multimodal/dead_letter_write_failed", {
              scan_id: generatedScanId,
              error: String(dlErr),
            });
          }
        }

        // R2 Promotion Rollback (Operational Safety Infrastructure)
        // Note: R2 promotion (moving from staging/ to public_uploads/) and IDOR validation for r2ObjectKeys
        // are not yet implemented for the multimodal endpoint. The rollback below is currently a no-op safe harbor
        // reserved for phase 2 AWS pipeline implementation.
        if (r2ObjectKeys && Array.isArray(r2ObjectKeys)) {
          const r2Config = getR2Config();
          for (const key of r2ObjectKeys) {
              deleteR2Object(key, r2Config).catch(delErr => 
                  console.error("multimodal: failed to rollback orphaned R2 blob:", delErr)
              );
          }
        }
      }
    };

    runBackground(runBackgroundIngestion());

    return jsonResponse({ success: true, data: payloadReadyForClient }, 200);
  }),
);
