import {
  ChatScanContext,
  InsightChatMessageRow,
  SpeciesDictionaryContext,
} from "./types.ts";

const CONTEXT_CACHE_ANCHOR = `
Merian Insight Follow-up Chat Operating Manual:
You are Merian's field education assistant inside a saved scan Insight sheet. The user is asking about a biological observation they already captured. You do not have access to the raw image, the camera buffer, hidden pixels, storage URLs, or any visual evidence beyond the saved text evidence listed below. You must not imply that you can inspect the photo again. Answer from the scan metadata, the species dictionary, and the initial AI reasoning only.

Safety and scope rules:
- Educational field naturalist guidance is allowed.
- Do not provide edible or foraging certainty. If asked whether something is safe to eat, taste, brew, cook, feed to animals, or use medicinally, refuse the safety-critical part and redirect to expert/local guidance.
- Do not provide medical, veterinary, poison-control, or emergency treatment instructions. Recommend contacting qualified local professionals or emergency services where appropriate.
- Do not provide dangerous handling, capture, harassment, pesticide, poison, illegal collection, or habitat-damaging instructions.
- Do not identify or characterize human subjects.
- Be conservative around poisonous, venomous, allergenic, irritant, threatened, endangered, protected, or invasive organisms.
- When the saved scan context says "Merian Invasive Flag: Yes", treat that as authoritative Merian scan evidence that the species is flagged invasive. You may distinguish this from exact local legal status if no local authority is listed, but do not say the provided information does not indicate invasiveness.
- If the stored identification is uncertain, say so plainly and explain which stored evidence supports or limits the answer.
- Keep answers concise: normally 2 to 5 short paragraphs or a short bullet list.
- Prefer field-observable traits, seasonality, habitat, behavior, and lookalike comparison.
- Never invent authorities, exact legal status, coordinates, or unrecorded traits.
- For location-aware answers, use only the saved coarse location label, month, elevation, ecology type, and weather. Do not infer, reveal, request, or reconstruct exact GPS coordinates.
- If the user asks outside the scan/species context, briefly redirect back to the observation.

Response format:
Return JSON with exactly:
{
  "answer": "string",
  "is_refusal": boolean,
  "refusal_reason": "string or null"
}
`;

function relationValue<T>(value: T | T[] | null | undefined): T | null {
  if (Array.isArray(value)) return value[0] ?? null;
  return value ?? null;
}

function trimText(value: unknown, maxLength = 900): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  return trimmed.length > maxLength
    ? `${trimmed.slice(0, maxLength - 1)}...`
    : trimmed;
}

function englishCommonName(
  species: SpeciesDictionaryContext | null,
): string | null {
  const commonNames = species?.common_names;
  const value = commonNames && typeof commonNames === "object"
    ? commonNames.en
    : null;
  return trimText(value, 120);
}

function observationLabel(species: SpeciesDictionaryContext | null): string {
  const commonName = englishCommonName(species);
  const scientificName = trimText(species?.scientific_name, 160);
  if (commonName && scientificName) return `${commonName} (${scientificName})`;
  return commonName ?? scientificName ?? "this observation";
}

function formatArray(value: unknown, maxItems = 6): string | null {
  if (!Array.isArray(value)) return null;
  const items = value
    .filter((entry): entry is string => typeof entry === "string")
    .map((entry) => entry.trim())
    .filter(Boolean)
    .slice(0, maxItems);
  return items.length > 0 ? items.join(", ") : null;
}

function compactJson(value: unknown, maxLength = 800): string | null {
  if (value == null) return null;
  try {
    return trimText(JSON.stringify(value), maxLength);
  } catch {
    return null;
  }
}

function formatBooleanFlag(value: boolean | null | undefined): string {
  if (value === true) return "Yes";
  if (value === false) return "No";
  return "Unavailable";
}

function formatNumber(
  value: number | null | undefined,
  suffix = "",
): string {
  return typeof value === "number" && Number.isFinite(value)
    ? `${value}${suffix}`
    : "Unavailable";
}

function selectedSpeciesSource(scan: ChatScanContext): string {
  if (scan.confirmed_species_id) return "Confirmed species";
  if (scan.species_id) return "Initial AI species";
  return "Unavailable";
}

function identificationSource(scan: ChatScanContext): string {
  if (trimText(scan.user_identification_override, 160)) {
    return "User corrected identification";
  }
  if (scan.user_confirmed_identification === true) {
    return "User confirmed AI identification";
  }
  if (scan.user_review_state === "ai_confirmed") {
    return "User confirmed AI identification";
  }
  if (scan.user_review_state === "user_overridden") {
    return "User corrected identification";
  }
  return "AI suggested identification";
}

export function resolvedSpecies(
  scan: ChatScanContext,
): SpeciesDictionaryContext | null {
  return relationValue(scan.confirmed_species) ??
    relationValue(scan.species_dictionary);
}

export function buildScanContextBlock(scan: ChatScanContext): string {
  const species = resolvedSpecies(scan);
  const taxonomy = [
    species?.kingdom,
    species?.phylum,
    species?.class,
    species?.order,
    species?.family,
    species?.genus,
  ].map((value) => trimText(value, 100)).filter(Boolean).join(" > ");

  const rows: string[] = [
    "[SAVED SCAN CONTEXT]",
    `Observation Label: ${observationLabel(species)}`,
    `Observed At: ${scan.timestamp}`,
    `Common Name: ${englishCommonName(species) ?? "Unavailable"}`,
    `Scientific Name: ${
      trimText(species?.scientific_name, 160) ?? "Unavailable"
    }`,
    `Taxonomy: ${taxonomy || "Unavailable"}`,
    `Alternative Common Names: ${
      formatArray(species?.alternative_common_names) ?? "Unavailable"
    }`,
    `Similar Species: ${
      formatArray(species?.similar_species) ?? "Unavailable"
    }`,
    `Habitat: ${trimText(species?.habitat_description, 900) ?? "Unavailable"}`,
    `Wikipedia Overview: ${
      trimText(species?.wikipedia_overview, 1000) ?? "Unavailable"
    }`,
    "",
    "[IDENTIFICATION PROVENANCE]",
    `Identification Source: ${identificationSource(scan)}`,
    `Selected Species Source: ${selectedSpeciesSource(scan)}`,
    `User Review State: ${
      trimText(scan.user_review_state, 80) ?? "Unavailable"
    }`,
    `AI Confidence: ${formatNumber(scan.ai_confidence_score)}`,
    `User Override: ${
      trimText(scan.user_identification_override, 160) ?? "None"
    }`,
    `User Confirmed ID: ${
      scan.user_confirmed_identification === true ? "Yes" : "No"
    }`,
    "",
    "[OBSERVED TRAITS]",
    `Colors: ${formatArray(scan.colors) ?? "Unavailable"}`,
    `Life Stage: ${trimText(scan.life_stage, 80) ?? "Unavailable"}`,
    `Reproductive Condition: ${
      trimText(scan.reproductive_condition, 80) ?? "Unavailable"
    }`,
    `Estimated Size Cm: ${formatNumber(scan.estimated_size_cm)}`,
    `Individual Count: ${formatNumber(scan.individual_count)}`,
    `Sex: ${trimText(scan.sex, 80) ?? "Unavailable"}`,
    `Sex Confidence: ${formatNumber(scan.sex_confidence)}`,
    `Sex Evidence: ${trimText(scan.sex_evidence, 240) ?? "Unavailable"}`,
    "",
    "[ECOLOGY]",
    `Ecology Type: ${trimText(scan.ecology_type, 80) ?? "Unavailable"}`,
    `Hazard Type: ${trimText(species?.hazard_type, 80) ?? "none"}`,
    `Merian Invasive Flag: ${formatBooleanFlag(scan.is_invasive)}`,
    `Ecological Interactions: ${
      formatArray(scan.ecological_interactions) ?? "Unavailable"
    }`,
    `Species Group Tags: ${formatArray(species?.group_tags) ?? "Unavailable"}`,
    `IUCN Red List Status: ${
      trimText(species?.iucn_red_list_status, 80) ?? "Unavailable"
    }`,
    "",
    "[ENCOUNTER CONTEXT]",
    `Month: ${scan.current_month ?? "Unavailable"}`,
    `Time Of Day: ${trimText(scan.time_of_day, 80) ?? "Unavailable"}`,
    `Location Label: ${trimText(scan.semantic_location, 180) ?? "Unavailable"}`,
    `Elevation: ${scan.gps_elevation ?? "Unavailable"}`,
    `Weather: ${trimText(scan.weather_condition, 120) ?? "Unavailable"}`,
    `Temperature F: ${scan.weather_temperature_f ?? "Unavailable"}`,
    `Depth/Scale Text: ${
      trimText(scan.depth_scale_text, 120) ?? "Unavailable"
    }`,
    `Observation Context: ${
      compactJson(scan.user_observation_context, 900) ?? "Unavailable"
    }`,
    `Candidate IDs: ${compactJson(scan.candidates, 900) ?? "Unavailable"}`,
    "",
    "[IMAGE/CAPTURE QUALITY]",
    `Image Quality Score: ${formatNumber(scan.image_quality_score)}`,
    `Blur Score: ${formatNumber(scan.blur_score)}`,
    `Zoom Factor: ${formatNumber(scan.zoom_factor, "x")}`,
    "",
    "[INITIAL VISION OBSERVATION]",
    trimText(scan.ai_reasoning, 1200) ?? "Unavailable",
  ];

  return rows.join("\n");
}

export function sanitizeFieldNotesDraft(text: string): string {
  return text
    .replace(
      /\bObservation\s+[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}:\s*/gi,
      "",
    )
    .replace(
      /\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b/gi,
      "this observation",
    )
    .trim();
}

export function buildConversationHistory(
  messages: InsightChatMessageRow[],
): string {
  const recent = messages.slice(-12);
  if (recent.length === 0) return "[CHAT HISTORY]\nNo prior messages.";
  return [
    "[CHAT HISTORY]",
    ...recent.map((message) =>
      `${message.role === "user" ? "User" : "Merian"}: ${
        trimText(message.message_text, 900) ?? ""
      }`
    ),
  ].join("\n");
}

export function buildSystemInstruction(scan: ChatScanContext): string {
  return `${CONTEXT_CACHE_ANCHOR}\n\n${buildScanContextBlock(scan)}`;
}

export function buildUserPrompt(
  messages: InsightChatMessageRow[],
  userMessage: string,
): string {
  return `${
    buildConversationHistory(messages)
  }\n\n[CURRENT USER QUESTION]\n${userMessage}`;
}

export function buildPromptSuggestionsPrompt(
  messages: InsightChatMessageRow[],
): string {
  return `${buildConversationHistory(messages)}

[PROMPT CHIP REQUEST]
Generate three short, tappable follow-up questions for the user to ask next in
Merian Field chat. Each prompt must be grounded in the saved scan context and
recent conversation above. Make the prompts specific to this observation using
distinctive observed traits, lookalikes/candidates, confidence uncertainty,
hazard or invasive status, ecology/habitat, season/month, life stage,
reproductive state, colors, field notes, or recent user questions when useful.

Rules:
- Return exactly three prompt objects.
- Keep each prompt concise, ideally 55 characters or fewer.
- Avoid repeating user questions already present in chat history.
- Do not ask for edible certainty, medical/veterinary treatment, illegal
  collection, pesticide/poison instructions, exact GPS/location details, or
  human-subject identification.
- Prefer natural follow-ups that would help a field observer learn what to
  inspect next.
- Use one category for each prompt: lookalike_compare, hazard, invasive,
  evidence, habitat, season, confidence, ecology, field_notes, or generic.`;
}
