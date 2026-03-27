import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { encodeBase64 } from "https://deno.land/std@0.224.0/encoding/base64.ts";

import {
  SchemaType,
  SafetyRating,
  Part,
  ResponseSchema,
} from "https://esm.sh/@google/generative-ai@0.24.1";
import { evaluateAndProcessPayload } from "./moderation.ts";
import { getR2Config } from "../_shared/aws.ts";
import {
  jsonResponse,
  withEdgeHandler,
  runBackground,
} from "../_shared/edgeHandler.ts";
import { fetchDiagnosticComparison } from "../_shared/diagnostic.ts";
import { _genAI, createFlashModel, extractJson } from "../_shared/gemini.ts";
import {
  getTierForUser,
  hasTierCached,
  setTierCache,
} from "../_shared/tierCache.ts";

// Scans below this threshold trigger an async diagnostic comparison via Flash.
const DIAGNOSTIC_THRESHOLD = 0.85;

async function fetchStaticEncyclopedicData(
  scientificName: string,
  locale: string,
) {
  const textModel = createFlashModel(
    `You are a world-class biologist. Provide encyclopedic identification traits, taxonomy, habitat, toxicity, conservation status, and global distribution for the provided scientific name. Keep descriptions concise. ALL text responses (habitat_description) must be returned in the following ISO language locale: ${locale}.`,
    1500,
  );

  const cacheSchema: Record<string, unknown> = {
    type: SchemaType.OBJECT,
    properties: {
      taxonomy: {
        type: SchemaType.OBJECT,
        properties: {
          kingdom: { type: SchemaType.STRING },
          phylum: { type: SchemaType.STRING },
          class: { type: SchemaType.STRING },
          order: { type: SchemaType.STRING },
          family: { type: SchemaType.STRING },
          genus: { type: SchemaType.STRING },
        },
        required: ["kingdom", "phylum", "class", "order", "family", "genus"],
      },
      iucn_red_list_status: {
        type: SchemaType.STRING,
        enum: [
          "not_evaluated",
          "data_deficient",
          "least_concern",
          "near_threatened",
          "vulnerable",
          "endangered",
          "critically_endangered",
          "extinct_in_the_wild",
          "extinct",
        ],
      },
      habitat_description: { type: SchemaType.STRING },
    },
    required: [
      "taxonomy",
      "iucn_red_list_status",
      "habitat_description",
    ],
  };

  try {
    const result = await textModel.generateContent({
      contents: [
        {
          role: "user",
          parts: [
            { text: `Generate metadata for the species: ${scientificName}` },
          ],
        },
      ],
      generationConfig: {
        responseMimeType: "application/json",
        responseSchema: cacheSchema as unknown as ResponseSchema,
      },
    });

    return extractJson(result.response.text());
  } catch (e) {
    console.error("Text Inference Miss fallback failed:", e);
    return {
      taxonomy: {
        kingdom: "Unknown",
        phylum: "Unknown",
        class: "Unknown",
        order: "Unknown",
        family: "Unknown",
        genus: "Unknown",
      },
      iucn_red_list_status: "not_evaluated",
      habitat_description: "No habitat data available.",
    };
  }
}

async function fetchExternalEnrichment(scientificName: string) {
  let wikiUrl: string | null = null;
  let wikiExtract: string | null = null;
  let gbifKey: number | null = null;
  let combinedImageUrls: string | null = null;

  try {
    const fetchedUrls: string[] = [];

    const [gbifOutcome, wikiOutcome] = await Promise.allSettled([
      (async () => {
        let key: number | null = null;
        let urls: string[] = [];
        const gbifRes = await fetch(
          `https://api.gbif.org/v1/species/match?name=${encodeURIComponent(scientificName)}`,
          { signal: AbortSignal.timeout(2500) },
        );
        if (!gbifRes.ok) throw new Error("GBIF match lookup failed");
        const gbifJson = await gbifRes.json();
        key = gbifJson.usageKey || null;

        if (key) {
          const mediaRes = await fetch(
            `https://api.gbif.org/v1/species/${key}/media`,
            { signal: AbortSignal.timeout(2500) },
          );
          if (mediaRes.ok) {
            const mediaJson = await mediaRes.json();
            if (mediaJson.results && mediaJson.results.length > 0) {
              urls = mediaJson.results
                .filter(
                  (m: Record<string, string>) =>
                    m.type === "StillImage" && m.identifier,
                )
                .map((m: Record<string, string>) => m.identifier)
                .slice(0, 5);
            }
          }
        }
        return { key, urls };
      })(),

      (async () => {
        const wikiRes = await fetch(
          `https://en.wikipedia.org/api/rest_v1/page/summary/${encodeURIComponent(scientificName.replace(/ /g, "_"))}`,
          { signal: AbortSignal.timeout(2500) },
        );
        if (!wikiRes.ok) throw new Error("Wikipedia lookup failed");
        const wikiJson = await wikiRes.json();
        const url = wikiJson.content_urls?.desktop?.page || null;
        const extract = wikiJson.extract || null;
        const img =
          wikiJson.originalimage?.source || wikiJson.thumbnail?.source || null;
        return { url, extract, img };
      })(),
    ]);

    if (gbifOutcome.status === "fulfilled") {
      gbifKey = gbifOutcome.value.key;
      fetchedUrls.push(...gbifOutcome.value.urls);
    }
    if (wikiOutcome.status === "fulfilled") {
      wikiUrl = wikiOutcome.value.url;
      wikiExtract = wikiOutcome.value.extract;
      if (wikiOutcome.value.img) {
        fetchedUrls.unshift(wikiOutcome.value.img);
      }
    }

    if (fetchedUrls.length > 0) {
      combinedImageUrls = Array.from(new Set(fetchedUrls)).join(",");
    }
  } catch (e) {
    console.log("Data enrichment failed silently: ", e);
  }

  return {
    wikipediaUrl: wikiUrl,
    wikiExtract,
    gbifKey,
    referenceImageUrl: combinedImageUrls,
  };
}

async function fetchGroupTags(
  scientificName: string,
): Promise<string[] | null> {
  const model = createFlashModel(
    'You are a world-class biologist. Given a species scientific name, return 1–5 categorical group labels ordered from most broad to most specific (e.g. ["animal", "bird", "songbird", "warbler"]). Use plain lowercase English nouns only. Omit proper names and scientific names.',
    100,
  );

  const schema: Record<string, unknown> = {
    type: SchemaType.OBJECT,
    properties: {
      group_tags: {
        type: SchemaType.ARRAY,
        items: { type: SchemaType.STRING },
        description: "1–5 categorical group labels, broad to specific.",
      },
    },
    required: ["group_tags"],
  };

  try {
    const result = await model.generateContent({
      contents: [
        {
          role: "user",
          parts: [{ text: `Group tags for: ${scientificName}` }],
        },
      ],
      generationConfig: {
        responseMimeType: "application/json",
        responseSchema: schema as unknown as ResponseSchema,
      },
    });
    const parsed = extractJson<{ group_tags: string[] }>(result.response.text());
    return parsed.group_tags ?? null;
  } catch (e) {
    console.error("fetchGroupTags failed:", e);
    return null;
  }
}

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const fnStart = Date.now();
    const body = await req.json();
    const {
      r2ObjectKeys,
      imageBase64s,
      user_id,
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
    } = body;

    if (
      (!r2ObjectKeys || r2ObjectKeys.length === 0) &&
      (!imageBase64s || imageBase64s.length === 0)
    ) {
      throw new Error(
        "Missing structural boundary (neither r2ObjectKeys nor imageBase64s provided).",
      );
    }

    if (r2ObjectKeys && r2ObjectKeys.length > 0) {
      // Reject r2ObjectKeys that don't belong to the requesting user (IDOR prevention).
      // When imageBase64s are provided, the key is used only for the destination filename.
      for (const r2ObjectKey of r2ObjectKeys) {
        if (
          (!imageBase64s || imageBase64s.length === 0) &&
          !r2ObjectKey.startsWith(`staging/${user.id}/`)
        ) {
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
        if (r2ObjectKey.includes("..")) {
          return jsonResponse(
            { error: "Bad Request: Path traversal detected." },
            400,
          );
        }
      }
    }

    if (!user_id) {
      return jsonResponse({ error: "Missing user_id parameter in body" }, 400);
    }

    const base64Payloads: string[] = [];

    if (imageBase64s && imageBase64s.length > 0) {
      if (imageBase64s.length > 5) {
        return jsonResponse({ error: "Too many images." }, 400);
      }
      const validBase64s: string[] = imageBase64s.filter(
        (s: string) => s.length > 0,
      );
      if (validBase64s.length === 0) {
        return jsonResponse(
          { error: "Bad Request: imageBase64s contains no valid image data." },
          400,
        );
      }
      const totalB64Bytes = validBase64s.reduce(
        (sum: number, s: string) => sum + s.length,
        0,
      );
      // base64 inflates raw size ~4/3; 5 MB raw ≈ 6.7 MB encoded
      if (totalB64Bytes > 7 * 1024 * 1024) {
        return jsonResponse(
          {
            error: "Payload Too Large: base64 payload exceeds 5 MB raw limit.",
          },
          413,
        );
      }
      base64Payloads.push(...validBase64s);
    } else if (r2ObjectKeys && r2ObjectKeys.length > 0) {
      console.log(`[⏱ BENCH] base64_validated: ${Date.now() - fnStart}ms`);
      const { s3Client, bucketName, endpoint } = getR2Config();

      const r2Responses = await Promise.allSettled(
        r2ObjectKeys.map((key: string) =>
          s3Client.fetch(`${endpoint}/${bucketName}/${key}`),
        ),
      );

      // Process images serially: consume one body at a time so each ArrayBuffer is GC-eligible
      // before the next is loaded, preventing a peak spike of N × (raw + copy + base64) in heap.
      // Size is checked against ACTUAL bytes after consumption — Content-Length headers are
      // unreliable (absent on chunked transfer encoding) and must never be trusted as a
      // heap-exhaustion guard.
      let totalBytes = 0;
      while (r2Responses.length > 0) {
        const result = r2Responses.shift()!;
        if (result.status === "rejected") {
          throw new Error(`Failed to execute concurrent R2 fetch request.`);
        }
        const r2Response = result.value as Response;
        if (!r2Response.ok) {
          throw new Error(
            `Failed to fetch an image from R2: ${r2Response.statusText}`,
          );
        }
        const arrayBuffer = await r2Response.arrayBuffer();
        totalBytes += arrayBuffer.byteLength;
        if (totalBytes > 5 * 1024 * 1024) {
          return jsonResponse(
            { error: "Payload Too Large: Combined images exceed 5MB limit." },
            413,
          );
        }
        base64Payloads.push(encodeBase64(new Uint8Array(arrayBuffer)));
      }
    }

    console.log(`[⏱ BENCH] payload_resolved: ${Date.now() - fnStart}ms`);

    // Resolve tier for model selection. Cache hit (common case after first scan within a
    // 5-minute window) is near-instant. On miss: one lightweight SELECT — no upsert on the
    // critical path (ghost-user creation stays in the background task).
    const userTierForModel = await getTierForUser(user.id, supabaseAdmin);

    // Pro users get gemini-2.5-pro for maximum identification depth (rare species, fossils,
    // subspecies, cultivars). Free users use gemini-2.5-flash for 2–3× lower latency.
    const targetModel =
      userTierForModel === "pro" ? "gemini-2.5-pro" : "gemini-2.5-flash";

    // Liveness instruction clarification: "liveness check" previously caused Flash to treat
    // fossils/specimens as is_biological_subject=false, returning generic names like
    // "Fossilized Shell" instead of the correct species common name (e.g. "Devil's Toenail"
    // for Gryphaea). Fossils and preserved specimens are biological subjects — only
    // is_live_capture changes.
    const systemInstruction = `Identify biology precisely. 1) Liveness: fossils, pressed/preserved/dried specimens are is_biological_subject=true with is_live_capture=false — identify to species level. Non-biological objects (rocks, buildings, food) are is_biological_subject=false. 2) Evaluate is_invasive based on GPS. 3) common_name must be maximally specific in strict title case. 4) CRITICAL: Evaluate all provided images together. 5) CRITICAL: Multiple species → identify ONE primary. 6) CRITICAL: is_biological_subject=false → OMIT is_invasive, ecology_type, scientific_name, colors, regional_status_rationale, common_name.`;

    const model = _genAI.getGenerativeModel({
      model: targetModel,
      systemInstruction,
      generationConfig: {
        temperature: 0.1,
        maxOutputTokens: 1000,
      },
    });

    const telemetryItems = [
      gpsLatitude != null && gpsLongitude != null
        ? `GPS:${gpsLatitude},${gpsLongitude}`
        : null,
      gpsElevation != null ? `Elev:${gpsElevation}m` : null,
      depthScaleText ? `Depth:${depthScaleText}` : null,
      zoomFactor != null && zoomFactor > 1
        ? `Zoom:${zoomFactor.toFixed(1)}x`
        : null,
      semanticLocation ? `Loc:${semanticLocation}` : null,
      weatherCondition ? `Wx:${weatherCondition}` : null,
      weatherTemperatureF != null ? `Temp:${weatherTemperatureF}F` : null,
      deviceLocale ? `Locale:${deviceLocale}` : null,
      currentMonth ? `Month:${currentMonth}` : null,
      timeOfDay ? `Time:${timeOfDay}` : null,
    ].filter(Boolean);

    const combinedPrompt = `Context: ${telemetryItems.join(", ")}. Perform biological identification.`;

    const schemaProperties: Record<string, ResponseSchema> = {
      is_biological_subject: { type: SchemaType.BOOLEAN },
      is_live_capture: { type: SchemaType.BOOLEAN },
      ecology_type: {
        type: SchemaType.STRING,
        format: "enum",
        enum: ["wild", "urban", "domesticated", "unknown"],
      },
      scientific_name: { type: SchemaType.STRING },
      confidence_score: { type: SchemaType.NUMBER },
      blur_score: { type: SchemaType.NUMBER },
      is_invasive: { type: SchemaType.BOOLEAN },
      ai_reasoning: {
        type: SchemaType.STRING,
        description:
          "A 2-4 sentence intelligence analysis breaking down the exact reasoning behind this identification. Detail the specific physical attributes, structural nuances, and visual evidence extracted from the image that substantiate this classification.",
      },
      colors: {
        type: SchemaType.ARRAY,
        items: { type: SchemaType.STRING },
        description: "1–3 dominant biological colors of the subject.",
      },
      common_name: {
        type: SchemaType.STRING,
        description:
          "Most specific commonly recognised English name in strict title case.",
      },
      hazard_type: {
        type: SchemaType.STRING,
        format: "enum",
        enum: ["none", "poisonous", "venomous", "allergenic", "irritant"],
        description:
          "Hazard classification: 'none' if safe, 'poisonous' if harmful by ingestion/contact, 'venomous' if injects toxin via bite/sting, 'allergenic' if triggers allergic reactions, 'irritant' if causes skin/eye irritation.",
      },
    };

    const merianResponseSchema: ResponseSchema = {
      type: SchemaType.OBJECT,
      properties: schemaProperties,
      required: [
        "is_biological_subject",
        "is_live_capture",
        "ai_reasoning",
        "confidence_score",
        "blur_score",
      ],
    };

    const parts: Part[] = base64Payloads.map((payload) => ({
      inlineData: {
        mimeType: mimeType || "image/webp",
        data: payload,
      },
    }));
    parts.push({ text: combinedPrompt });

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
      return jsonResponse(
        { error: "AI processing error. Please try again." },
        400,
      );
    }

    let parsedData;
    try {
      parsedData = extractJson(responseText);
    } catch (parseError) {
      console.error("Failed to parse AI response:", parseError);
      return jsonResponse(
        { error: "Processing Error: Malformed AI response." },
        422,
      );
    }

    const generatedScanId = crypto.randomUUID();
    const payloadReadyForClient = { ...parsedData, scan_id: generatedScanId };
    const isIdentifiedBio = !!(parsedData.is_biological_subject && parsedData.scientific_name);
    let speciesId: string | null = null;
    // Hoisted so the background task can reference it for the Cache Miss enrichment upsert.
    let cachedSpecies: {
      id: string;
      common_names: Record<string, string> | null;
      kingdom: string | null;
      phylum: string | null;
      class: string | null;
      order: string | null;
      family: string | null;
      genus: string | null;
      wikipedia_overview: string | null;
      hazard_type: string | null;
      reference_image_url: string | null;
      wikipedia_url: string | null;
      iucn_red_list_status: string | null;
      habitat_description: string | null;
      gbif_taxon_key: number | null;
      diagnostic_primary_rationale: string | null;
      group_tags: string[] | null;
    } | null = null;

    if (isIdentifiedBio) {
      const { data: _cachedSpecies } = await supabaseAdmin
        .from("species_dictionary")
        .select(
          "id, common_names, kingdom, phylum, class, order, family, genus, wikipedia_overview, hazard_type, reference_image_url, wikipedia_url, iucn_red_list_status, habitat_description, gbif_taxon_key, diagnostic_primary_rationale, group_tags",
        )
        .eq("scientific_name", parsedData.scientific_name)
        .maybeSingle();
      cachedSpecies = _cachedSpecies;

      // Definite assignment: always set in both branches of the if/else below.
      let staticData!: {
        taxonomy?: Record<string, string>;
        iucn_red_list_status?: string;
        hazard_type: string;
        speciesHabitat?: string;
      };

      if (cachedSpecies && cachedSpecies.kingdom) {
        console.log(
          `Cache Hit: Generating payload from DB for ${parsedData.scientific_name}`,
        );
        staticData = {
          taxonomy: {
            kingdom: cachedSpecies.kingdom ?? "Unknown",
            phylum: cachedSpecies.phylum ?? "Unknown",
            class: cachedSpecies.class ?? "Unknown",
            order: cachedSpecies.order ?? "Unknown",
            family: cachedSpecies.family ?? "Unknown",
            genus: cachedSpecies.genus ?? "Unknown",
          },
          iucn_red_list_status:
            cachedSpecies.iucn_red_list_status ?? "not_evaluated",
          hazard_type: cachedSpecies.hazard_type || "none",
          speciesHabitat: cachedSpecies.habitat_description ?? undefined,
        };
        speciesId = cachedSpecies.id;
        // common_name is always sourced from the vision model — DB value is locale storage only.
        payloadReadyForClient.reference_image_url =
          cachedSpecies.reference_image_url;
        payloadReadyForClient.wikipedia_url = cachedSpecies.wikipedia_url;
        payloadReadyForClient.wikipedia_overview =
          cachedSpecies.wikipedia_overview;
        if (cachedSpecies.group_tags && cachedSpecies.group_tags.length > 0) {
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
        console.log(
          `Cache Miss: ${parsedData.scientific_name}. Background enrichment queued.`,
        );
        staticData = {
          hazard_type: parsedData.hazard_type ?? "none",
        };
        // speciesId remains null here; the background task upserts species_dictionary first,
        // then sets speciesId before inserting the scan row.
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

      // Species insights are sourced exclusively from the DB (Cache Hit) — never from the
      // vision model. Served to all tiers when already stored; otherwise the client
      // triggers a follow-up enrich-scan call to populate them.
      if (staticData.speciesHabitat) {
        payloadReadyForClient.species_insights = {
          habitat_description: staticData.speciesHabitat,
        };
      }
    }

    const backgroundTask = (async () => {
      try {
        // Tier was already resolved on the critical path. The only remaining task here is
        // ghost-user creation: if the main path never found the user in the DB, the cache
        // entry was never set, so we upsert them now before the scans FK insert.
        if (!hasTierCached(user.id)) {
          const { data: existingUser } = await supabaseAdmin
            .from("users")
            .select("subscription_tier")
            .eq("id", user.id)
            .maybeSingle();
          if (existingUser) {
            setTierCache(user.id, existingUser.subscription_tier as string);
          } else {
            // Ghost user — create the record required for the scans FK constraint.
            await supabaseAdmin
              .from("users")
              .upsert(
                { id: user.id, subscription_tier: "free" },
                { onConflict: "id", ignoreDuplicates: true },
              );
            setTierCache(user.id, "free");
          }
        }

        const modResult = await evaluateAndProcessPayload(
          user.id,
          r2ObjectKeys,
          imageBase64s,
          finishReason,
          safetyRatings,
          userTierForModel,
        );
        if (
          modResult.status === "SHADOWBANNED" ||
          modResult.status === "DELETED_WARNING"
        ) {
          console.error(
            "Media flagged by safety moderation. Halting background data ingestion.",
          );
          return;
        }
        // Start diagnostic and group-tag Flash calls in parallel with enrichment.
        // Both are cheap, species-level, and skipped when already cached.
        const needsDiagnostic =
          isIdentifiedBio &&
          (parsedData.confidence_score ?? 1) < DIAGNOSTIC_THRESHOLD &&
          !cachedSpecies?.diagnostic_primary_rationale;
        const diagnosticPromise = needsDiagnostic
          ? fetchDiagnosticComparison(parsedData.scientific_name)
          : Promise.resolve(null);

        const needsGroupTags =
          isIdentifiedBio &&
          !cachedSpecies?.group_tags?.length;
        const groupTagsPromise = needsGroupTags
          ? fetchGroupTags(parsedData.scientific_name)
          : Promise.resolve(null);

        // Cache Miss: enrich species_dictionary so the next scan of the same species is a Cache Hit.
        // Runs after moderation so we don't persist data for flagged content.
        if (!speciesId && isIdentifiedBio) {
          const bgEnrichStart = Date.now();
          const [textResult, externalData] = await Promise.all([
            fetchStaticEncyclopedicData(
              parsedData.scientific_name,
              deviceLocale || "en",
            ),
            fetchExternalEnrichment(parsedData.scientific_name),
          ]);

          const newCommonNames = cachedSpecies
            ? { ...cachedSpecies.common_names, en: parsedData.common_name }
            : { en: parsedData.common_name };

          // Never overwrite data a previous scan already stored in the DB.
          const { data: upsertedSpecies } = await supabaseAdmin
            .from("species_dictionary")
            .upsert(
              {
                scientific_name: parsedData.scientific_name,
                common_names: newCommonNames,
                kingdom: cachedSpecies?.kingdom ?? textResult.taxonomy.kingdom,
                phylum: cachedSpecies?.phylum ?? textResult.taxonomy.phylum,
                class: cachedSpecies?.class ?? textResult.taxonomy.class,
                order: cachedSpecies?.order ?? textResult.taxonomy.order,
                family: cachedSpecies?.family ?? textResult.taxonomy.family,
                genus: cachedSpecies?.genus ?? textResult.taxonomy.genus,
                wikipedia_overview:
                  cachedSpecies?.wikipedia_overview ??
                  externalData.wikiExtract ??
                  null,
                hazard_type:
                  cachedSpecies?.hazard_type ??
                  parsedData.hazard_type ??
                  "none",
                native_region: "Unknown",
                iucn_red_list_status:
                  cachedSpecies?.iucn_red_list_status ??
                  textResult.iucn_red_list_status,
                habitat_description:
                  cachedSpecies?.habitat_description ??
                  textResult.habitat_description,
                wikipedia_url:
                  cachedSpecies?.wikipedia_url || externalData.wikipediaUrl,
                gbif_taxon_key:
                  cachedSpecies?.gbif_taxon_key || externalData.gbifKey,
                reference_image_url:
                  cachedSpecies?.reference_image_url ||
                  externalData.referenceImageUrl,
              },
              { onConflict: "scientific_name", ignoreDuplicates: false },
            )
            .select("id")
            .maybeSingle();

          speciesId = upsertedSpecies?.id || cachedSpecies?.id || null;
          console.log(
            `[⏱ BENCH] bg_enrichment: ${Date.now() - bgEnrichStart}ms`,
          );
        } else if (
          cachedSpecies &&
          isIdentifiedBio &&
          !cachedSpecies.habitat_description
        ) {
          // Enrichment gap-fill: species exists in the DB but was stored before enrichment
          // fields were introduced. Fetch from Flash and backfill silently for all tiers.
          const bgEnrichStart = Date.now();
          const textResult = await fetchStaticEncyclopedicData(
            parsedData.scientific_name,
            deviceLocale || "en",
          );
          await supabaseAdmin
            .from("species_dictionary")
            .update({
              habitat_description: textResult.habitat_description,
            })
            .eq("id", cachedSpecies.id);
          console.log(
            `[⏱ BENCH] bg_enrichment_fill: ${Date.now() - bgEnrichStart}ms`,
          );
        }

        const { error: scanInsertError } = await supabaseAdmin
          .from("scans")
          .insert({
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
            colors: parsedData.colors ?? [],
            llm_prompt_tokens: llmPromptTokens,
            llm_candidate_tokens: llmCandidateTokens,
            llm_total_tokens: llmTotalTokens,
            image_storage_urls: modResult.publicUrls?.length
              ? modResult.publicUrls
              : [],
          });

        if (scanInsertError) {
          console.error("Failed to insert scan:", scanInsertError);

          // Revert and purge R2 promotional uploads to prevent untracked orphans
          if (modResult.publicUrls?.length) {
            console.log("Rolling back R2 uploads due to database failure.");
            const r2Config = getR2Config();
            const { deleteR2Object } = await import("../_shared/aws.ts");
            const keysToPurge = modResult.publicUrls.map((url: string) =>
              url.replace("https://media.merian.app/", ""),
            );
            await Promise.allSettled(
              keysToPurge.map((key: string) => deleteR2Object(key, r2Config)),
            );
          }
          return;
        }

        // Await species-level Flash calls and upsert results to species_dictionary.
        const [diagResult, groupTagsResult] = await Promise.all([
          diagnosticPromise,
          groupTagsPromise,
        ]);

        if (needsDiagnostic && diagResult) {
          const diagStart = Date.now();
          await supabaseAdmin
            .from("species_dictionary")
            .update({
              diagnostic_primary_rationale: diagResult.primary_match_rationale,
              diagnostic_lookalike_name: diagResult.confusing_lookalike_name,
              diagnostic_differentiators_json: JSON.stringify(
                diagResult.key_differentiators,
              ),
            })
            .eq("scientific_name", parsedData.scientific_name);
          console.log(`[⏱ BENCH] bg_diagnostic: ${Date.now() - diagStart}ms`);
        }

        if (needsGroupTags && groupTagsResult && groupTagsResult.length > 0) {
          const tagsStart = Date.now();
          await supabaseAdmin
            .from("species_dictionary")
            .update({ group_tags: groupTagsResult })
            .eq("scientific_name", parsedData.scientific_name);
          console.log(`[⏱ BENCH] bg_group_tags: ${Date.now() - tagsStart}ms`);
        }
      } catch (e) {
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
    })();

    runBackground(backgroundTask);

    console.log(`[⏱ BENCH] total_to_response: ${Date.now() - fnStart}ms`);
    return jsonResponse({ success: true, data: payloadReadyForClient }, 200);
  }),
);
