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
- If the stored identification is uncertain, say so plainly and explain which stored evidence supports or limits the answer.
- Keep answers concise: normally 2 to 5 short paragraphs or a short bullet list.
- Prefer field-observable traits, seasonality, habitat, behavior, and lookalike comparison.
- Never invent authorities, exact legal status, coordinates, or unrecorded traits.
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
    `Scan ID: ${scan.id}`,
    `Observed At: ${scan.timestamp}`,
    `Common Name: ${englishCommonName(species) ?? "Unavailable"}`,
    `Scientific Name: ${
      trimText(species?.scientific_name, 160) ?? "Unavailable"
    }`,
    `Taxonomy: ${taxonomy || "Unavailable"}`,
    `AI Confidence: ${scan.ai_confidence_score ?? "Unavailable"}`,
    `User Override: ${
      trimText(scan.user_identification_override, 160) ?? "None"
    }`,
    `User Confirmed ID: ${
      scan.user_confirmed_identification === true ? "Yes" : "No"
    }`,
    `Hazard Type: ${trimText(species?.hazard_type, 80) ?? "none"}`,
    `IUCN Red List Status: ${
      trimText(species?.iucn_red_list_status, 80) ?? "Unavailable"
    }`,
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
    `Image Quality Score: ${scan.image_quality_score ?? "Unavailable"}`,
    `Observation Context: ${
      compactJson(scan.user_observation_context, 900) ?? "Unavailable"
    }`,
    `Candidate IDs: ${compactJson(scan.candidates, 900) ?? "Unavailable"}`,
    "",
    "[INITIAL VISION OBSERVATION]",
    trimText(scan.ai_reasoning, 1200) ?? "Unavailable",
  ];

  return rows.join("\n");
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
