import { SafetyRating, Part } from "https://esm.sh/@google/generative-ai@0.24.1";
import { evaluateAndProcessPayload } from "./moderation.ts";
import { getR2Config, deleteR2Object } from "../_shared/aws.ts";
import { jsonResponse, withEdgeHandler, runBackground, logStructuredError } from "../_shared/edgeHandler.ts";
import { fetchGroupTags } from "../_shared/biology.ts";
import { fetchExternalEnrichment } from "../_shared/external.ts";
import { _genAI, extractJson } from "../_shared/gemini.ts";
import { getTierForUser } from "../_shared/tierCache.ts";
import { trackPostHogEvent } from "../_shared/posthog.ts";
import { requireParams } from "../_shared/http.ts";

import { MerianIdentification, ClientPayload, CachedSpeciesRow, StaticSpeciesData } from "./types.ts";
import { getSystemInstruction, getMerianResponseSchema } from "./schema.ts";
import { FLASH_DIAGNOSTIC_TRIGGER, PRO_DIAGNOSTIC_TRIGGER, diagnosticTriggerForTier } from "./thresholds.ts";
import { resolveImagePayloads } from "./media.ts";
import {
  upsertGhostUserIfMissing,
  fetchCachedSpecies,
  upsertSpeciesDictionary,
  insertScan,
  updateGroupTags,
} from "./db.ts";

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const modelCache = {
  flash: _genAI.getGenerativeModel({
    model: "gemini-2.5-flash",
    systemInstruction: getSystemInstruction(FLASH_DIAGNOSTIC_TRIGGER),
    generationConfig: { temperature: 0.1, maxOutputTokens: 1000 },
  }),
  pro: _genAI.getGenerativeModel({
    model: "gemini-2.5-pro",
    systemInstruction: getSystemInstruction(PRO_DIAGNOSTIC_TRIGGER),
    generationConfig: { temperature: 0.1, maxOutputTokens: 1000 },
  }),
};

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
      client_scan_id,
    } = body;

    // Range-validate GPS coordinates — out-of-bounds values from a corrupted or
    // tampered payload are sanitised to null rather than rejecting the scan.
    // Location is supplementary context; a bad coord should not kill identification.
    const safeGpsLat: number | null =
      gpsLatitude != null && Number.isFinite(gpsLatitude) &&
      gpsLatitude >= -90 && gpsLatitude <= 90
        ? gpsLatitude : null;
    const safeGpsLon: number | null =
      gpsLongitude != null && Number.isFinite(gpsLongitude) &&
      gpsLongitude >= -180 && gpsLongitude <= 180
        ? gpsLongitude : null;

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
    const diagnosticTrigger = diagnosticTriggerForTier(userTier === "pro" ? "pro" : "flash");

    const model = userTier === "pro" ? modelCache.pro : modelCache.flash;

    const telemetryItems = [
      safeGpsLat != null && safeGpsLon != null ? `GPS:${safeGpsLat},${safeGpsLon}` : null,
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
      { text: `Context: ${telemetryItems.join(", ")}. Perform biological identification.` },
      ...base64Payloads.map((payload) => ({
        inlineData: { mimeType: mimeType || "image/webp", data: payload },
      })),
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
          responseSchema: getMerianResponseSchema(diagnosticTrigger),
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

    // Sanitize scientific names at write time so the database is scientific-grade
    // and interoperable with GBIF, iNaturalist, and partner taxonomy systems.
    if (parsedData.scientific_name) {
      parsedData.scientific_name = sanitizeScientificName(parsedData.scientific_name);
    }
    if (Array.isArray(parsedData.candidates)) {
      parsedData.candidates = parsedData.candidates.map((c) => ({
        ...c,
        scientific_name: sanitizeScientificName(c.scientific_name),
      }));
    }

    // Cap the candidates list — the LLM schema enforces this but extractJson is an
    // unvalidated cast. Five alternatives is more than enough for the UI swipe modal.
    if (Array.isArray(parsedData.candidates)) {
      parsedData.candidates = parsedData.candidates.slice(0, 5);
    }

    // Cap unbounded LLM-generated array fields to protect V8 Isolate memory and
    // prevent oversized DB rows. Limits are generous — they exceed realistic model
    // output and exist purely as a hard safety boundary against malformed responses.
    if (Array.isArray(parsedData.extracted_visual_traits)) {
      parsedData.extracted_visual_traits = parsedData.extracted_visual_traits.slice(0, 10);
    }
    if (Array.isArray(parsedData.ecological_interactions)) {
      parsedData.ecological_interactions = parsedData.ecological_interactions.slice(0, 10);
    }
    if (typeof parsedData.ai_reasoning === "string" && parsedData.ai_reasoning.length > 2000) {
      parsedData.ai_reasoning = parsedData.ai_reasoning.slice(0, 2000);
    }
    // individual_count: must be a positive integer; reject negatives and impossibly large values.
    // Uses undefined (not null) to match the ?: number optional type; the insertScan call
    // converts undefined → null via ?? for the nullable DB column.
    if (parsedData.individual_count != null) {
      parsedData.individual_count =
        Number.isFinite(parsedData.individual_count) && parsedData.individual_count > 0
          ? Math.min(Math.round(parsedData.individual_count), 99999)
          : undefined;
    }

    // Derive blur_score from sharpness (1-10) for latency savings
    parsedData.blur_score = Math.max(0, (10 - (parsedData.image_quality?.sharpness ?? 10)) / 10);

    // Use the client-provided scan ID when available so the iOS offline queue can
    // correlate the server record with its local OfflineQueuedScan. Combined with the
    // idempotent upsert in insertScan, this makes replayed inference requests safe.
    const generatedScanId: string =
      typeof client_scan_id === "string" && client_scan_id.length > 0
        ? client_scan_id
        : crypto.randomUUID();
    const payloadReadyForClient: ClientPayload = {
      ...parsedData,
      scan_id: generatedScanId,
      inference_tier: userTier === "pro" ? "pro" : "flash",
    };

    // Strip candidates when confidence is above the tier's diagnosticTrigger threshold.
    // These values mirror MerianConfig.flashConfidence.diagnosticTrigger (0.96) and
    // MerianConfig.proConfidence.diagnosticTrigger (0.85) in the iOS client.
    // Fallback to 0.0 (not 1.0) on a null score: a missing confidence_score means the
    // LLM returned a malformed response — preserve candidates rather than silently strip them.
    if ((parsedData.confidence_score ?? 0.0) >= diagnosticTrigger) {
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
        if (modResult.status === "ERROR") {
          // Moderation pipeline failed (e.g. abuse strike write, R2 upload error).
          // Do not insert the scan — image_storage_urls would be null and the DB row
          // would be permanently orphaned with no media.
          console.error("Moderation pipeline returned ERROR. Halting background data ingestion.");
          return;
        }
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
          const externalData = await fetchExternalEnrichment(parsedData.scientific_name!);

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
              habitat_description: cachedSpecies?.habitat_description || undefined,
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
            gps_lat_exact: safeGpsLat,
            gps_long_exact: safeGpsLon,
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
            image_storage_urls: modResult.publicUrls ?? [],
            life_stage: parsedData.life_stage ?? "unknown",
            reproductive_condition: parsedData.reproductive_condition ?? "not_applicable",
            individual_count: parsedData.individual_count ?? null,
            ecological_interactions: parsedData.ecological_interactions ?? [],
            estimated_size_cm: (estimated_size_cm != null && Number.isFinite(estimated_size_cm) && estimated_size_cm > 0)
              ? Math.min(estimated_size_cm, 50000)
              : null,
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
        const bgWriteResults = await Promise.allSettled([
          needsGroupTags && groupTagsResult?.group_tags?.length
            ? updateGroupTags(parsedData.scientific_name!, groupTagsResult.group_tags, supabaseAdmin)
            : Promise.resolve(),
        ]);
        for (const result of bgWriteResults) {
          if (result.status === "rejected") {
            console.error(JSON.stringify({
              event: "bg_species_write_failed",
              scan_id: generatedScanId,
              error: result.reason instanceof Error ? result.reason.message : String(result.reason),
              ts: new Date().toISOString(),
            }));
          }
        }
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
            .insert({ scan_id: generatedScanId, user_id: user.id, error_message: errorMsg });
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
  }),
);

// ---------------------------------------------------------------------------
// Scientific Name Sanitization
// ---------------------------------------------------------------------------
//
// Applied to every scientific_name before it touches species_dictionary or
// the candidates JSONB payload. Ensures the database is interoperable with
// GBIF, iNaturalist, and partner taxonomy systems.
//
// Rules applied (in order):
//   1. Trim leading/trailing whitespace and collapse internal runs of spaces.
//   2. Strip author citations — e.g. "Rosa canina L." → "Rosa canina".
//      Author strings follow the specific epithet and begin with an uppercase
//      letter or parenthesis: "(L.)", "Karst.", "DC.", "Thunb. ex Murray".
//      Cultivar epithets in single quotes are NOT author citations and are kept.
//   3. Strip uncertainty qualifiers — "cf.", "aff.", "sp." — that indicate
//      the identification is tentative. These should be surfaced in a separate
//      confidence field, not embedded in the name key used for DB lookups.
//   4. Normalise capitalisation: genus capitalised, specific epithet and
//      infraspecific rank markers ("var.", "subsp.", "f.") lowercase.
//      Cultivar names in single quotes are preserved in their original case
//      per ICNCP convention (Title Case inside the quotes is standard).
//   5. Preserve hybrid markers (×) — "× Heucherella" is correct notation.
//
// Examples:
//   "rosa 'Radrazz'"              → "Rosa 'Radrazz'"
//   "Rosa canina L."              → "Rosa canina"
//   "Quercus robur (L.) Karst."   → "Quercus robur"
//   "cf. Pinus ponderosa"         → "Pinus ponderosa"
//   "Acer Palmatum"               → "Acer palmatum"
//   "Boletus edulis var. Edulis"  → "Boletus edulis var. edulis"
// ---------------------------------------------------------------------------

function sanitizeScientificName(name: string): string {
  if (!name) return name;

  // 1. Collapse whitespace
  let s = name.trim().replace(/\s+/g, " ");

  // 2. Strip uncertainty qualifiers at the start
  s = s.replace(/^(cf\.|aff\.|sp\.)\s+/i, "");

  // 3. Strip author citations
  //    Strategy: split on the first single-quoted cultivar block (if present)
  //    and only process the binomial prefix — authors never appear inside quotes.
  const cultivarMatch = s.match(/^(.*?)\s*('[^']*')\s*$/);
  if (cultivarMatch) {
    const binomial = stripAuthors(cultivarMatch[1].trim());
    const cultivar = cultivarMatch[2]; // preserve case per ICNCP
    s = `${binomial} ${cultivar}`;
  } else {
    s = stripAuthors(s);
  }

  // 4. Normalise capitalisation on the binomial portion
  s = normaliseBinomialCase(s);

  return s.trim();
}

// Removes trailing author citations from a name string that contains no cultivar.
// Author strings start after the specific epithet with an uppercase letter or "(".
// Rank markers (var., subsp., f.) and hybrid markers (×) are not author strings.
function stripAuthors(name: string): string {
  // Split into tokens and find where the author citation begins.
  // Tokens that are NOT part of the name: uppercase word or "(" not preceded by a rank marker.
  const rankMarkers = new Set(["var.", "subsp.", "f.", "ssp.", "cv.", "×", "x"]);
  const tokens = name.split(" ");
  let cutAt = tokens.length;

  for (let i = 2; i < tokens.length; i++) { // genus + epithet always kept
    const token = tokens[i];
    const prev = tokens[i - 1]?.toLowerCase();
    if (rankMarkers.has(prev)) continue; // next token after rank marker is a name, not author
    if (/^[A-Z(]/.test(token) && !rankMarkers.has(token.toLowerCase())) {
      cutAt = i;
      break;
    }
  }

  return tokens.slice(0, cutAt).join(" ");
}

// Genus capitalised, everything else lowercase except cultivar quotes and × marker.
function normaliseBinomialCase(name: string): string {
  const rankMarkers = new Set(["var.", "subsp.", "f.", "ssp.", "cv."]);
  const tokens = name.split(" ");
  return tokens
    .map((token, i) => {
      if (token.startsWith("'") && token.endsWith("'")) return token; // cultivar — keep as-is
      if (token === "×") return token; // hybrid marker
      if (i === 0) return token.charAt(0).toUpperCase() + token.slice(1).toLowerCase(); // genus
      if (rankMarkers.has(token.toLowerCase())) return token.toLowerCase(); // rank marker
      return token.toLowerCase(); // specific epithet and infraspecific names
    })
    .join(" ");
}
