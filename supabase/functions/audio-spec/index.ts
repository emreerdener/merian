import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { Schema, Type } from "https://esm.sh/@google/genai@1.0.0";
import { encodeBase64, decodeBase64 } from "https://deno.land/std@0.224.0/encoding/base64.ts";

import { jsonResponse, withEdgeHandler, runBackground, logStructuredError } from "../_shared/edgeHandler.ts";
import { _genAI, extractJson } from "../_shared/gemini.ts";
import { getTierForUser } from "../_shared/tierCache.ts";
import { trackPostHogEvent } from "../_shared/posthog.ts";
import { requireParams } from "../_shared/http.ts";
import { fetchExternalEnrichment } from "../_shared/external.ts";
import { fetchGroupTags } from "../_shared/biology.ts";
import { getR2Config, deleteR2Object } from "../_shared/aws.ts";

import { AudioClientRequest, AudioIdentification, AudioClientPayload, AudioCandidate } from "./types.ts";
import {
  upsertGhostUserIfMissing,
  fetchCachedSpecies,
  upsertSpeciesDictionary,
  insertScan,
  updateGroupTags,
} from "./db.ts";
import {
  parseWavHeader,
  extractSamplesAsFloat32,
  mixToMono,
  trimSilence,
  resampleLinear,
  encodeWav16,
} from "./wav.ts";

// Target sample rate for Gemini audio ingestion.
// Downsampling from 48 kHz → 16 kHz reduces payload size ~3× without meaningful
// loss of bioacoustic frequency content (most calls fall well below 8 kHz Nyquist).
const TARGET_SAMPLE_RATE = 16_000;

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
    candidates: {
      type: Type.ARRAY,
      items: {
        type: Type.OBJECT,
        properties: {
          scientific_name: { type: Type.STRING },
          confidence_score: { type: Type.NUMBER },
          distinguishing_feature: { type: Type.STRING },
        },
        required: ["scientific_name", "confidence_score", "distinguishing_feature"],
      },
    },
  },
  required: ["is_biological_subject", "confidence_score", "ai_reasoning"],
};

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const fnStart = Date.now();
    const rawBody: Record<string, unknown> = await req.json();

    const paramError = requireParams(rawBody, ["user_id"]);
    if (paramError) return paramError;

    if (!rawBody.audio_r2_key && !rawBody.audio_base64) {
      return jsonResponse({ error: "Missing required parameter: audio_r2_key or audio_base64" }, 400);
    }

    const body = rawBody as unknown as AudioClientRequest;
    const {
      audio_r2_key,
      audio_base64,
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
    } = body;

    // GPS range validation — out-of-bounds values are sanitised to null (same policy as identify).
    const safeGpsLat: number | null =
      gps_latitude != null && Number.isFinite(gps_latitude) &&
      gps_latitude >= -90 && gps_latitude <= 90
        ? gps_latitude : null;
    const safeGpsLon: number | null =
      gps_longitude != null && Number.isFinite(gps_longitude) &&
      gps_longitude >= -180 && gps_longitude <= 180
        ? gps_longitude : null;

    // 1. Load audio — either from base64 inline payload (iOS live path) or R2 staging.
    let rawWavBuffer: ArrayBuffer;
    let r2Config: ReturnType<typeof getR2Config> | null = null;

    if (audio_base64) {
      // Inline path: iOS sends the WAV base64-encoded in the request body.
      rawWavBuffer = decodeBase64(audio_base64).buffer as ArrayBuffer;
      console.log(`[⏱ BENCH] base64_decode: ${Date.now() - fnStart}ms, size=${rawWavBuffer.byteLength}`);
    } else {
      // R2 path: IDOR + path traversal guards only apply here.
      if (!audio_r2_key!.startsWith(`staging/${user.id}/`)) {
        logStructuredError("audio_spec/idor_attempt", { user_id: user.id, audio_r2_key });
        return jsonResponse({ error: "Forbidden: audio_r2_key does not belong to the requesting user." }, 403);
      }
      if (audio_r2_key!.includes("..")) {
        return jsonResponse({ error: "Bad Request: path traversal detected." }, 400);
      }
      r2Config = getR2Config();
      const { s3Client, bucketName, endpoint } = r2Config;
      const r2Url = `${endpoint}/${bucketName}/${audio_r2_key}`;
      const r2Resp = await s3Client.fetch(r2Url, { method: "GET" });
      if (!r2Resp.ok) {
        return jsonResponse({ error: `Audio file not found in staging (${r2Resp.status}).` }, 404);
      }
      rawWavBuffer = await r2Resp.arrayBuffer();
      console.log(`[⏱ BENCH] r2_download: ${Date.now() - fnStart}ms, size=${rawWavBuffer.byteLength}`);
    }

    // 2. Process audio: parse → mono → trim silence → resample → re-encode
    let base64Audio: string;
    try {
      const header = parseWavHeader(rawWavBuffer);
      const interleaved = extractSamplesAsFloat32(rawWavBuffer, header);
      const mono = mixToMono(interleaved, header.numChannels);
      const trimmed = trimSilence(mono, header.sampleRate);
      const resampled = resampleLinear(trimmed, header.sampleRate, TARGET_SAMPLE_RATE);
      // Require at least 0.5 s of audio at 16 kHz after silence trimming.
      // A header-only WAV (resampled.length === 0) would be rejected by Gemini anyway;
      // returning 400 here gives the client a clean, actionable error.
      if (resampled.length < 8_000) {
        return jsonResponse({ error: "Audio too short to identify. Please record a longer clip." }, 400);
      }
      const processedWav = encodeWav16(resampled, TARGET_SAMPLE_RATE);
      base64Audio = encodeBase64(processedWav);
      console.log(
        `[audio-spec] WAV: ${header.sampleRate}Hz ${header.numChannels}ch → ${TARGET_SAMPLE_RATE}Hz mono, ` +
        `trimmed ${mono.length}→${trimmed.length} samples, encoded ${processedWav.byteLength} bytes`,
      );
    } catch (wavErr) {
      const msg = wavErr instanceof Error ? wavErr.message : String(wavErr);
      logStructuredError("audio_spec/wav_parse_failed", { user_id: user.id, error: msg });
      return jsonResponse({ error: "Invalid audio file format." }, 400);
    }

    // 3. Build telemetry context string (mirrors identify/index.ts telemetryItems pattern)
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

    // 4. Resolve user tier for PostHog tracking (non-blocking, cached after first scan)
    const userTier = await getTierForUser(user.id, supabaseAdmin);

    // 5. Call Gemini with audio inline data
    console.log(`[⏱ BENCH] pre_gemini: ${Date.now() - fnStart}ms`);
    const geminiStart = Date.now();

    let responseText = "";
    let llmPromptTokens: number | null = null;
    let llmCandidateTokens: number | null = null;
    let llmThinkingTokens: number | null = null;
    let llmTotalTokens: number | null = null;
    let finishReason: string | undefined;

    try {
      const result = await _genAI.models.generateContent({
        model: "gemini-2.5-flash",
        contents: [
          {
            role: "user",
            parts: [
              { text: `Context: ${telemetryItems || "no telemetry"}. Perform bioacoustic identification.` },
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
        if (firstPart && "text" in firstPart && typeof firstPart.text === "string") {
          responseText = firstPart.text;
        }
      }

      const usage = result.usageMetadata;
      if (usage) {
        llmPromptTokens = usage.promptTokenCount ?? null;
        llmCandidateTokens = usage.candidatesTokenCount ?? null;
        llmThinkingTokens = usage.thoughtsTokenCount ?? null;
        llmTotalTokens = usage.totalTokenCount ?? null;
        console.log(
          `Token Usage [audio-spec | ${user.id}]: Prompt: ${llmPromptTokens} | Candidates: ${llmCandidateTokens} | Thinking: ${llmThinkingTokens} | Total: ${llmTotalTokens}`,
        );
      }
      console.log(`[⏱ BENCH] gemini_done: ${Date.now() - fnStart}ms total, ${Date.now() - geminiStart}ms inference`);
    } catch (genErr) {
      const errMsg = genErr instanceof Error ? genErr.message : String(genErr);
      logStructuredError("audio_spec/gemini_failed", {
        user_id: user.id,
        elapsed_ms: Date.now() - geminiStart,
        error: errMsg,
      });
      return jsonResponse({ error: "AI processing error. Please try again." }, 503);
    }

    if (finishReason && finishReason !== "STOP" && finishReason !== "FINISH_REASON_UNSPECIFIED") {
      const isPermanent = finishReason === "SAFETY" || finishReason === "PROHIBITED_CONTENT";
      logStructuredError("audio_spec/non_stop_finish", { user_id: user.id, finish_reason: finishReason });
      return jsonResponse({ error: "AI processing error. Please try again." }, isPermanent ? 400 : 503);
    }

    // 6. Parse Gemini response
    let parsedData: AudioIdentification;
    try {
      parsedData = extractJson<AudioIdentification>(responseText);
    } catch (parseErr) {
      logStructuredError("audio_spec/parse_failed", {
        user_id: user.id,
        finish_reason: finishReason ?? "unknown",
        response_length: responseText.length,
        response_preview: responseText.slice(0, 500),
        error: parseErr instanceof Error ? parseErr.message : String(parseErr),
      });
      return jsonResponse({ error: "Processing Error: Malformed AI response." }, 422);
    }

    // Cap candidates list (schema enforces this but extractJson is an unvalidated cast)
    if (Array.isArray(parsedData.candidates)) {
      parsedData.candidates = parsedData.candidates.slice(0, 5);
    }

    const generatedScanId =
      typeof client_scan_id === "string" && client_scan_id.length > 0
        ? client_scan_id
        : crypto.randomUUID();

    const isIdentifiedBio = !!(parsedData.is_biological_subject && parsedData.scientific_name);

    // Strip candidates when confidence meets the diagnostic trigger threshold
    const forwardCandidates =
      (parsedData.confidence_score ?? 0) < DIAGNOSTIC_TRIGGER
        ? parsedData.candidates ?? null
        : null;

    // 7. Build initial payload (enriched further in the background task on cache hit)
    const payloadReadyForClient: AudioClientPayload = {
      scan_id: generatedScanId,
      is_biological_subject: parsedData.is_biological_subject,
      is_live_capture: true,
      scientific_name: parsedData.scientific_name,
      common_name: parsedData.common_name,
      confidence_score: parsedData.confidence_score,
      ecology_type: parsedData.ecology_type,
      is_invasive: parsedData.is_invasive,
      life_stage: "unknown",
      inference_tier: userTier === "pro" ? "pro" : "flash",
      candidates: forwardCandidates,
    };

    if (isIdentifiedBio) {
      payloadReadyForClient.insight_data = {
        ai_reasoning: parsedData.ai_reasoning || "Reasoning omitted.",
        hazard_type: "none",
      };
    }

    // 8. Background ingestion: ghost user, species enrichment, scan insert, R2 cleanup
    const runBackgroundIngestion = async () => {
      let scanInserted = false;
      try {
        await upsertGhostUserIfMissing(user.id, supabaseAdmin);

        let speciesId: string | null = null;
        let cachedSpecies = null;

        const needsGroupTags = isIdentifiedBio;

        if (isIdentifiedBio) {
          cachedSpecies = await fetchCachedSpecies(parsedData.scientific_name!, supabaseAdmin);

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
            payloadReadyForClient.iucn_red_list_status = cachedSpecies.iucn_red_list_status ?? undefined;
            payloadReadyForClient.reference_image_url = cachedSpecies.reference_image_url;
            payloadReadyForClient.wikipedia_url = cachedSpecies.wikipedia_url;
            payloadReadyForClient.wikipedia_overview = cachedSpecies.wikipedia_overview;
            if (cachedSpecies.group_tags?.length) {
              payloadReadyForClient.group_tags = cachedSpecies.group_tags;
            }
            if (cachedSpecies.gbif_taxon_key != null) {
              payloadReadyForClient.gbif_taxon_key = cachedSpecies.gbif_taxon_key;
            }
            if (cachedSpecies.common_names?.en) {
              payloadReadyForClient.common_name = cachedSpecies.common_names.en;
            }
            if (cachedSpecies.alternative_common_names?.length) {
              const primaryEn = (payloadReadyForClient.common_name ?? "").toLowerCase();
              payloadReadyForClient.alternative_common_names = cachedSpecies.alternative_common_names.filter(
                (n) => n.toLowerCase() !== primaryEn,
              );
            }
            if (cachedSpecies.hazard_type && payloadReadyForClient.insight_data) {
              payloadReadyForClient.insight_data.hazard_type = cachedSpecies.hazard_type;
            }
            if (cachedSpecies.habitat_description) {
              payloadReadyForClient.species_insights = {
                habitat_description: cachedSpecies.habitat_description,
              };
            }
          } else {
            // Cache miss: enrich species_dictionary in the background
            console.log(`Cache Miss: ${parsedData.scientific_name}. Background enrichment queued.`);
            const bgStart = Date.now();
            const externalData = await fetchExternalEnrichment(parsedData.scientific_name!);
            const freshSpecies = await fetchCachedSpecies(parsedData.scientific_name!, supabaseAdmin);

            const newCommonNames = {
              ...(freshSpecies?.common_names ?? {}),
              ...(parsedData.common_name ? { en: parsedData.common_name } : {}),
            };
            const primaryEn = (newCommonNames.en ?? "").toLowerCase();
            const newAltNames: string[] | null =
              externalData.alternativeCommonNames.length > 0
                ? externalData.alternativeCommonNames.filter((n) => n.toLowerCase() !== primaryEn)
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
                wikipedia_overview: freshSpecies?.wikipedia_overview ?? externalData.wikiExtract ?? null,
                hazard_type: freshSpecies?.hazard_type ?? "none",
                native_region: "Unknown",
                iucn_red_list_status: freshSpecies?.iucn_red_list_status ?? "not_evaluated",
                habitat_description: freshSpecies?.habitat_description ?? undefined,
                wikipedia_url: freshSpecies?.wikipedia_url || externalData.wikipediaUrl,
                gbif_taxon_key: freshSpecies?.gbif_taxon_key ?? externalData.gbifKey,
                reference_image_url: freshSpecies?.reference_image_url || externalData.referenceImageUrl,
              },
              supabaseAdmin,
            );
            speciesId = upsertedId || freshSpecies?.id || null;
            console.log(`[⏱ BENCH] bg_enrichment: ${Date.now() - bgStart}ms`);
          }
        }

        // Group tags (species-level, fire-and-forget)
        const groupTagsPromise = (needsGroupTags && !cachedSpecies?.group_tags?.length)
          ? fetchGroupTags(user, parsedData.scientific_name!)
          : Promise.resolve(null);

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
            blur_score: null,
            ecology_type: parsedData.ecology_type,
            is_invasive: parsedData.is_invasive,
            weather_condition: weather_condition ?? undefined,
            weather_temperature_f: weather_temperature_f ?? undefined,
            semantic_location: semantic_location ?? undefined,
            device_locale: device_locale ?? undefined,
            current_month: current_month ?? undefined,
            time_of_day: time_of_day ?? undefined,
            ai_reasoning: parsedData.ai_reasoning ?? null,
            extracted_visual_traits: [],
            colors: [],
            llm_prompt_tokens: llmPromptTokens,
            llm_candidate_tokens: llmCandidateTokens,
            llm_thinking_tokens: llmThinkingTokens,
            llm_cached_tokens: null,
            llm_total_tokens: llmTotalTokens,
            image_storage_urls: [],
            life_stage: "unknown",
            reproductive_condition: "not_applicable",
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

        // Delete audio staging file after successful scan insert (R2 path only).
        if (audio_r2_key && r2Config) {
          deleteR2Object(audio_r2_key, r2Config).catch((e) =>
            console.error(`audio_spec: failed to delete staging file ${audio_r2_key}:`, e),
          );
        }

        const groupTagsResult = await groupTagsPromise;
        if (groupTagsResult?.group_tags?.length && isIdentifiedBio) {
          await updateGroupTags(parsedData.scientific_name!, groupTagsResult.group_tags, supabaseAdmin);
        }

        trackPostHogEvent(user, "AudioScanCompleted", {
          is_biological_subject: parsedData.is_biological_subject,
          tier: userTier,
          llm_model: "gemini-2.5-flash",
          llm_prompt_tokens: llmPromptTokens,
          llm_candidate_tokens: llmCandidateTokens,
          llm_thinking_tokens: llmThinkingTokens,
          llm_total_tokens: llmTotalTokens,
          scientific_name: parsedData.scientific_name,
        }).catch((e) => console.error("PostHog tracking failed:", e));
      } catch (e) {
        const errorMsg = e instanceof Error ? e.message : String(e);
        logStructuredError("audio_spec/background_ingestion_failed", {
          user_id: user.id,
          scan_id: generatedScanId,
          error: errorMsg,
          scan_inserted: scanInserted,
        });

        if (!scanInserted) {
          try {
            const { error: dlErr } = await supabaseAdmin
              .from("failed_scan_ingestions")
              .insert({ scan_id: generatedScanId, user_id: user.id, error_message: errorMsg });
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
        }
      }
    };

    runBackground(runBackgroundIngestion());

    console.log(`[⏱ BENCH] total_to_response: ${Date.now() - fnStart}ms`);
    return jsonResponse({ success: true, data: payloadReadyForClient }, 200);
  }),
);
