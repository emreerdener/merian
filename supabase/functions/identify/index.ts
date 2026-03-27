import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { encodeBase64 } from "https://deno.land/std@0.224.0/encoding/base64.ts";

import {
  GoogleGenerativeAI,
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
import { calculateRegionalStatus } from "../_shared/regionalStatus.ts";

// Instantiated once at module scope so warm isolate re-use avoids re-initialization overhead.
const _geminiApiKey = Deno.env.get("GEMINI_API_KEY")!;
const _genAI = new GoogleGenerativeAI(_geminiApiKey);

// Worker-level tier cache — persists across warm isolate re-use, eliminating the DB round-trip
// for every scan after the first. TTL of 5 minutes is short enough to pick up subscription
// changes without holding stale data across a full user session.
const _tierCache = new Map<string, { tier: string; ts: number }>();
const _TIER_CACHE_TTL_MS = 5 * 60_000;

// Scans below this threshold trigger an async diagnostic comparison via Flash.
const DIAGNOSTIC_THRESHOLD = 0.85;

async function fetchStaticEncyclopedicData(
  scientificName: string,
  locale: string,
  genAI: GoogleGenerativeAI,
) {
  const textModel = genAI.getGenerativeModel({
    model: "gemini-2.5-flash",
    systemInstruction: `You are a world-class biologist. Provide encyclopedic identification traits, taxonomy, habitat, toxicity, conservation status, and global distribution for the provided scientific name. Keep descriptions concise. ALL text responses (habitat_description) must be returned in the following ISO language locale: ${locale}.`,
    generationConfig: { temperature: 0.1, maxOutputTokens: 1500 },
  });

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
      global_distribution_regions: {
        type: SchemaType.ARRAY,
        items: { type: SchemaType.STRING },
      },
    },
    required: [
      "taxonomy",
      "iucn_red_list_status",
      "habitat_description",
      "global_distribution_regions",
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

    const responseText = result.response.text();
    const startIndex = responseText.indexOf("{");
    const endIndex = responseText.lastIndexOf("}");
    const cleanJsonString = responseText.substring(startIndex, endIndex + 1);
    return JSON.parse(cleanJsonString);
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
      global_distribution_regions: [],
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
    wikiExtract: wikiExtract,
    gbifKey: gbifKey,
    referenceImageUrl: combinedImageUrls,
  };
}

async function fetchDiagnosticComparison(
  scientificName: string,
  genAI: GoogleGenerativeAI,
) {
  const model = genAI.getGenerativeModel({
    model: "gemini-2.5-flash",
    systemInstruction:
      "You are a world-class biologist. Given a species scientific name, return a brief diagnostic comparison explaining the primary identification rationale, the most commonly confused lookalike species, and the key morphological or behavioural features that differentiate them.",
    generationConfig: { temperature: 0.1, maxOutputTokens: 400 },
  });

  const schema: Record<string, unknown> = {
    type: SchemaType.OBJECT,
    properties: {
      primary_match_rationale: { type: SchemaType.STRING },
      confusing_lookalike_name: { type: SchemaType.STRING },
      key_differentiators: {
        type: SchemaType.ARRAY,
        items: { type: SchemaType.STRING },
        description: "2–4 concise differentiating features vs. the lookalike.",
      },
    },
    required: [
      "primary_match_rationale",
      "confusing_lookalike_name",
      "key_differentiators",
    ],
  };

  try {
    const result = await model.generateContent({
      contents: [
        {
          role: "user",
          parts: [{ text: `Diagnostic comparison for: ${scientificName}` }],
        },
      ],
      generationConfig: {
        responseMimeType: "application/json",
        responseSchema: schema as unknown as ResponseSchema,
      },
    });
    const text = result.response.text();
    const start = text.indexOf("{");
    const end = text.lastIndexOf("}");
    if (start === -1 || end === -1) throw new Error("Malformed response");
    return JSON.parse(text.substring(start, end + 1)) as {
      primary_match_rationale: string;
      confusing_lookalike_name: string;
      key_differentiators: string[];
    };
  } catch (e) {
    console.error("fetchDiagnosticComparison failed:", e);
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
      for (const result of r2Responses) {
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
    let userTierForModel = "free";
    const cachedTierEntry = _tierCache.get(user.id);
    if (
      cachedTierEntry &&
      Date.now() - cachedTierEntry.ts < _TIER_CACHE_TTL_MS
    ) {
      userTierForModel = cachedTierEntry.tier;
    } else {
      const { data: tierData } = await supabaseAdmin
        .from("users")
        .select("subscription_tier")
        .eq("id", user.id)
        .maybeSingle();
      if (tierData) {
        userTierForModel = tierData.subscription_tier as string;
        _tierCache.set(user.id, { tier: userTierForModel, ts: Date.now() });
      }
      // Ghost users: default "free" for model selection; upsert happens in background task
    }

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
      systemInstruction: systemInstruction,
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
          "A precise 2-4 sentence expert biological analysis detailing why the subject was identified as this specific species. Point out the key diagnostic features, phenotypic traits, and contextual clues present in the image that led to this exact conclusion.",
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
        description: "Hazard classification: 'none' if safe, 'poisonous' if harmful by ingestion/contact, 'venomous' if injects toxin via bite/sting, 'allergenic' if triggers allergic reactions, 'irritant' if causes skin/eye irritation.",
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

    // Strip any markdown wrapper if the model produces non-JSON preamble
    const startIndex = responseText.indexOf("{");
    const endIndex = responseText.lastIndexOf("}");

    if (startIndex === -1 || endIndex === -1 || startIndex > endIndex) {
      console.error("Failed to extract JSON from AI response:", responseText);
      return jsonResponse(
        { error: "Processing Error: Malformed AI response." },
        422,
      );
    }
    const cleanJsonString = responseText.substring(startIndex, endIndex + 1);
    let parsedData;
    try {
      parsedData = JSON.parse(cleanJsonString);
    } catch (parseError) {
      console.error("Failed to parse AI response JSON:", parseError);
      return jsonResponse(
        { error: "Processing Error: Invalid AI response format." },
        422,
      );
    }

    const generatedScanId = crypto.randomUUID();
    const payloadReadyForClient = { ...parsedData, scan_id: generatedScanId };
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
      descriptions: Record<string, Record<string, string>> | null;
      hazard_type: string | null;
      reference_image_url: string | null;
      wikipedia_url: string | null;
      iucn_red_list_status: string | null;
      habitat_description: string | null;
      global_distribution_regions: string[] | null;
      gbif_taxon_key: number | null;
      diagnostic_primary_rationale: string | null;
    } | null = null;

    if (parsedData.is_biological_subject && parsedData.scientific_name) {
      const { data: _cachedSpecies } = await supabaseAdmin
        .from("species_dictionary")
        .select(
          "id, common_names, kingdom, phylum, class, order, family, genus, descriptions, hazard_type, reference_image_url, wikipedia_url, iucn_red_list_status, habitat_description, global_distribution_regions, gbif_taxon_key, diagnostic_primary_rationale",
        )
        .eq("scientific_name", parsedData.scientific_name)
        .maybeSingle();
      cachedSpecies = _cachedSpecies;

      // Definite assignment: always set in both branches of the if/else below.
      let staticData!: {
        taxonomy?: Record<string, string>;
        iucn_red_list_status?: string;
        hazard_type: string;
        premium_habitat?: string;
        premium_regions?: string[];
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
          premium_habitat: cachedSpecies.habitat_description ?? undefined,
          premium_regions:
            cachedSpecies.global_distribution_regions ?? undefined,
        };
        speciesId = cachedSpecies.id;
        // common_name is always sourced from the vision model — DB value is locale storage only.
        payloadReadyForClient.reference_image_url =
          cachedSpecies.reference_image_url;
        payloadReadyForClient.wikipedia_url = cachedSpecies.wikipedia_url;
        payloadReadyForClient.wikipedia_extract =
          cachedSpecies.descriptions?.["en"]?.wikipedia;
      } else {
        // Cache Miss: taxonomy, IUCN, and premium insights are not in the vision response.
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

      const calculatedRegionalStatus = calculateRegionalStatus(
        semanticLocation,
        !!parsedData.is_invasive,
        staticData.premium_regions ?? null,
      );

      payloadReadyForClient.insight_data = {
        ai_reasoning: parsedData.ai_reasoning || "Reasoning omitted.",
        regional_status_rationale: calculatedRegionalStatus,
        hazard_type: staticData.hazard_type,
      };

      // Premium insights are sourced exclusively from the DB (Cache Hit) — never from the
      // vision model. Pro users receive them when already stored; otherwise the client
      // triggers a follow-up enrich-scan call.
      if (
        targetModel === "gemini-2.5-pro" &&
        (staticData.premium_habitat || staticData.premium_regions)
      ) {
        payloadReadyForClient.premium_insights = {
          habitat_description: staticData.premium_habitat,
          global_distribution_regions: staticData.premium_regions,
        };
      }
    }

    const backgroundTask = (async () => {
      try {
        // Tier lookup is only needed for the R2 storage path in moderation and to ensure
        // the ghost-user record exists before the scans FK insert. Both usages are here in
        // the background task, so the DB round-trip is completely off the Gemini critical path.
        let backgroundTier = "free";
        const cachedTier = _tierCache.get(user.id);
        if (cachedTier && Date.now() - cachedTier.ts < _TIER_CACHE_TTL_MS) {
          backgroundTier = cachedTier.tier;
        } else {
          const { data: existingUser } = await supabaseAdmin
            .from("users")
            .select("subscription_tier")
            .eq("id", user.id)
            .maybeSingle();
          if (existingUser) {
            backgroundTier = existingUser.subscription_tier as string;
            _tierCache.set(user.id, { tier: backgroundTier, ts: Date.now() });
          } else {
            // Ghost user — create the record required for the scans FK constraint.
            await supabaseAdmin
              .from("users")
              .upsert(
                { id: user.id, subscription_tier: "free" },
                { onConflict: "id", ignoreDuplicates: true },
              );
            _tierCache.set(user.id, { tier: "free", ts: Date.now() });
          }
        }

        const modResult = await evaluateAndProcessPayload(
          user.id,
          r2ObjectKeys,
          imageBase64s,
          finishReason,
          safetyRatings,
          backgroundTier,
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
        // Start diagnostic Flash in parallel with enrichment — it's cheap (400 tokens) and
        // only fires for low-confidence scans. Awaited after the scan INSERT.
        // Skip if the species already has cached diagnostic data — no need to re-run Flash.
        const needsDiagnostic =
          parsedData.is_biological_subject &&
          parsedData.scientific_name &&
          (parsedData.confidence_score ?? 1) < DIAGNOSTIC_THRESHOLD &&
          !cachedSpecies?.diagnostic_primary_rationale;
        const diagnosticPromise = needsDiagnostic
          ? fetchDiagnosticComparison(parsedData.scientific_name, _genAI)
          : Promise.resolve(null);

        // Cache Miss: enrich species_dictionary so the next scan of the same species is a Cache Hit.
        // Runs after moderation so we don't persist data for flagged content.
        if (
          !speciesId &&
          parsedData.is_biological_subject &&
          parsedData.scientific_name
        ) {
          const bgEnrichStart = Date.now();
          const [textResult, externalData] = await Promise.all([
            fetchStaticEncyclopedicData(
              parsedData.scientific_name,
              deviceLocale || "en",
              _genAI,
            ),
            fetchExternalEnrichment(parsedData.scientific_name),
          ]);

          const newCommonNames = cachedSpecies
            ? { ...cachedSpecies.common_names, en: parsedData.common_name }
            : { en: parsedData.common_name };

          const newDescriptions = cachedSpecies
            ? {
                ...cachedSpecies.descriptions,
                ...(externalData.wikiExtract && {
                  en: {
                    ...cachedSpecies.descriptions?.["en"],
                    wikipedia: externalData.wikiExtract,
                  },
                }),
              }
            : {
                ...(externalData.wikiExtract && {
                  en: { wikipedia: externalData.wikiExtract },
                }),
              };

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
                descriptions: newDescriptions,
                hazard_type:
                  cachedSpecies?.hazard_type ?? (parsedData.hazard_type ?? "none"),
                native_region: "Unknown",
                iucn_red_list_status:
                  cachedSpecies?.iucn_red_list_status ??
                  textResult.iucn_red_list_status,
                habitat_description:
                  cachedSpecies?.habitat_description ??
                  textResult.habitat_description,
                global_distribution_regions:
                  (cachedSpecies?.global_distribution_regions?.length ?? 0) > 0
                    ? cachedSpecies!.global_distribution_regions
                    : textResult.global_distribution_regions,
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
          parsedData.is_biological_subject &&
          parsedData.scientific_name &&
          (!cachedSpecies.habitat_description || !(cachedSpecies.global_distribution_regions?.length))
        ) {
          // Premium gap-fill: species exists in the DB but was stored before premium fields
          // were introduced. Fetch from Flash and backfill silently for all tiers.
          // Pro users see the data on their next scan (Cache Hit); free users' data is stored
          // but not returned until they upgrade.
          const bgPremiumStart = Date.now();
          const textResult = await fetchStaticEncyclopedicData(
            parsedData.scientific_name,
            deviceLocale || "en",
            _genAI,
          );
          await supabaseAdmin
            .from("species_dictionary")
            .update({
              habitat_description: textResult.habitat_description,
              global_distribution_regions:
                textResult.global_distribution_regions,
            })
            .eq("id", cachedSpecies.id);
          console.log(
            `[⏱ BENCH] bg_premium_fill: ${Date.now() - bgPremiumStart}ms`,
          );
        }

        const { error: scanInsertError } = await supabaseAdmin
          .from("scans")
          .insert({
            id: generatedScanId,
            user_id: user.id,
            species_id: speciesId,
            timestamp: timestamp ? timestamp : undefined,
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
            llm_prompt_tokens: llmPromptTokens,
            llm_candidate_tokens: llmCandidateTokens,
            llm_total_tokens: llmTotalTokens,
            image_storage_urls:
              modResult.publicUrls && modResult.publicUrls.length > 0
                ? modResult.publicUrls
                : [],
          });

        if (scanInsertError) {
          console.error("Failed to insert scan:", scanInsertError);

          // Revert and purge R2 promotional uploads to prevent untracked orphans
          if (modResult.publicUrls && modResult.publicUrls.length > 0) {
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

        // Await the diagnostic Flash call started above and UPDATE the scan record.
        // Runs for all tiers — display is gated client-side based on confidence threshold.
        if (needsDiagnostic) {
          const diagStart = Date.now();
          const diagResult = await diagnosticPromise;
          if (diagResult) {
            await supabaseAdmin
              .from("species_dictionary")
              .update({
                diagnostic_primary_rationale:
                  diagResult.primary_match_rationale,
                diagnostic_lookalike_name: diagResult.confusing_lookalike_name,
                diagnostic_differentiators_json: JSON.stringify(
                  diagResult.key_differentiators,
                ),
              })
              .eq("scientific_name", parsedData.scientific_name);
          }
          console.log(`[⏱ BENCH] bg_diagnostic: ${Date.now() - diagStart}ms`);
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
