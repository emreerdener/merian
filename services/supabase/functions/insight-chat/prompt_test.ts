import { assertEquals, assertStringIncludes } from "@std/assert";
import {
  buildPromptSuggestionsPrompt,
  buildScanContextBlock,
  buildSystemInstruction,
  buildUserPrompt,
  sanitizeFieldNotesDraft,
} from "./prompt.ts";
import { ChatScanContext, InsightChatMessageRow } from "./types.ts";

const scan: ChatScanContext = {
  id: "00000000-0000-4000-8000-000000000001",
  user_id: "00000000-0000-4000-8000-000000000002",
  timestamp: "2026-06-26T12:00:00Z",
  gps_elevation: 120,
  weather_condition: "Clear",
  weather_temperature_f: 71,
  semantic_location: "Oak woodland",
  current_month: 6,
  time_of_day: "7:15 AM",
  depth_scale_text: "0.8 meters",
  ai_confidence_score: 0.91,
  ai_reasoning:
    "Orange wings with black veins support the butterfly identification.",
  candidates: [{ scientific_name: "Danaus gilippus" }],
  image_quality_score: 88,
  blur_score: 0.12,
  zoom_factor: 2,
  ecology_type: "wild",
  colors: ["orange", "black"],
  life_stage: "adult",
  reproductive_condition: "not_applicable",
  estimated_size_cm: 8.5,
  individual_count: 2,
  ecological_interactions: ["nectaring on milkweed"],
  sex: "cannot_determine",
  sex_confidence: null,
  sex_evidence: null,
  is_invasive: true,
  invasive_status_region: "Central Texas",
  invasive_rationale:
    "The original assessment flagged this species as invasive in Central Texas based on the scan location.",
  invasive_confidence: 0.82,
  is_biological_subject: true,
  user_identification_override: null,
  user_confirmed_identification: false,
  user_review_state: "unreviewed",
  user_observation_context: { free_text: "Near milkweed." },
  confirmed_species_id: null,
  species_id: "00000000-0000-4000-8000-000000000003",
  confirmed_species: null,
  species_dictionary: {
    id: "00000000-0000-4000-8000-000000000003",
    scientific_name: "Danaus plexippus",
    common_names: { en: "Monarch" },
    wikipedia_overview: "A migratory butterfly.",
    habitat_description: "Open fields and milkweed patches.",
    hazard_type: "none",
    kingdom: "Animalia",
    phylum: "Arthropoda",
    class: "Insecta",
    order: "Lepidoptera",
    family: "Nymphalidae",
    genus: "Danaus",
    iucn_red_list_status: "least_concern",
    alternative_common_names: ["Milkweed butterfly"],
    similar_species: ["Danaus gilippus"],
    group_tags: ["animal", "insect", "butterfly"],
  },
};

Deno.test("scan context uses text evidence and excludes image URLs", () => {
  const block = buildScanContextBlock(scan);
  assertStringIncludes(block, "Observation Label: Monarch (Danaus plexippus)");
  assertStringIncludes(block, "Monarch");
  assertStringIncludes(block, "Orange wings");
  assertStringIncludes(block, "Danaus gilippus");
  assertStringIncludes(block, "0.8 meters");
  assertStringIncludes(block, "[IDENTIFICATION PROVENANCE]");
  assertStringIncludes(
    block,
    "Identification Source: AI suggested identification",
  );
  assertStringIncludes(block, "Selected Species Source: Initial AI species");
  assertStringIncludes(block, "User Review State: unreviewed");
  assertStringIncludes(block, "[OBSERVED TRAITS]");
  assertStringIncludes(block, "Colors: orange, black");
  assertStringIncludes(block, "Life Stage: adult");
  assertStringIncludes(block, "Estimated Size Cm: 8.5");
  assertStringIncludes(block, "Individual Count: 2");
  assertStringIncludes(block, "[ECOLOGY]");
  assertStringIncludes(block, "Ecology Type: wild");
  assertStringIncludes(block, "Naturebook Invasive Flag: Yes");
  assertStringIncludes(block, "Invasive Status Region: Central Texas");
  assertStringIncludes(
    block,
    "Invasive Rationale: The original assessment flagged this species as invasive in Central Texas based on the scan location.",
  );
  assertStringIncludes(block, "Invasive Confidence: 0.82");
  assertStringIncludes(
    block,
    "Ecological Interactions: nectaring on milkweed",
  );
  assertStringIncludes(block, "Species Group Tags: animal, insect, butterfly");
  assertStringIncludes(block, "[IMAGE/CAPTURE QUALITY]");
  assertStringIncludes(block, "Image Quality Score: 88");
  assertStringIncludes(block, "Blur Score: 0.12");
  assertStringIncludes(block, "Zoom Factor: 2x");
  assertEquals(block.includes("image_storage_urls"), false);
  assertEquals(block.includes("storage_key"), false);
  assertEquals(block.includes("latitude"), false);
  assertEquals(block.includes("longitude"), false);
  assertEquals(block.includes("https://"), false);
  assertEquals(block.includes(`Scan ID: ${scan.id}`), false);
  assertEquals(block.includes(scan.id), false);
});

Deno.test("field notes summary text removes internal UUID labels", () => {
  assertEquals(
    sanitizeFieldNotesDraft(
      "Observation 46b35079-75a1-4e47-bfd3-0414c2fdda00: An adult Indian Fig Opuntia was fruiting.",
    ),
    "An adult Indian Fig Opuntia was fruiting.",
  );
  assertEquals(
    sanitizeFieldNotesDraft(
      "Follow-up for 46b35079-75a1-4e47-bfd3-0414c2fdda00 confirmed cactus traits.",
    ),
    "Follow-up for this observation confirmed cactus traits.",
  );
  assertEquals(
    sanitizeFieldNotesDraft(
      "Observation 019fab61-1e83-7e64-90e7-ef275922fa7e: The saved evidence supports the identification.",
    ),
    "The saved evidence supports the identification.",
  );
  assertEquals(
    sanitizeFieldNotesDraft(
      "Follow-up for 019fab61-1e83-7e64-90e7-ef275922fa7e compared two traits.",
    ),
    "Follow-up for this observation compared two traits.",
  );
  assertEquals(
    sanitizeFieldNotesDraft(
      "Observation 019fab61-1e83-7e64-90e7-ef275922fa7e:",
    ),
    "Field chat discussed the saved observation and follow-up identification context.",
  );
  assertEquals(
    sanitizeFieldNotesDraft(""),
    "Field chat discussed the saved observation and follow-up identification context.",
  );
});

Deno.test("system instruction states raw image is unavailable", () => {
  const instruction = buildSystemInstruction(scan);
  assertStringIncludes(instruction, "You do not have access to the raw image");
  assertStringIncludes(
    instruction,
    "Do not provide edible or foraging certainty",
  );
  assertStringIncludes(instruction, "Naturebook Invasive Flag: Yes");
  assertStringIncludes(
    instruction,
    "do not say the provided information does not indicate invasiveness",
  );
});

Deno.test("conversation prompt appends current question after history", () => {
  const messages = [{
    id: "m1",
    conversation_id: "c1",
    scan_id: scan.id,
    user_id: scan.user_id,
    role: "assistant",
    message_text: "It is often found near milkweed.",
    client_message_id: null,
    model: "gemini-2.5-flash",
    llm_prompt_tokens: null,
    llm_candidate_tokens: null,
    llm_thinking_tokens: null,
    llm_total_tokens: null,
    llm_cached_tokens: null,
    is_refusal: false,
    refusal_reason: null,
    safety_metadata: null,
    created_at: "2026-06-26T12:00:01Z",
  }] satisfies InsightChatMessageRow[];

  const prompt = buildUserPrompt(messages, "What should I compare next?");
  assertStringIncludes(prompt, "Naturebook: It is often found near milkweed.");
  assertStringIncludes(prompt, "[CURRENT USER QUESTION]");
  assertStringIncludes(prompt, "What should I compare next?");
});

Deno.test("prompt suggestion prompt uses history and safety constraints", () => {
  const messages = [{
    id: "m1",
    conversation_id: "c1",
    scan_id: scan.id,
    user_id: scan.user_id,
    role: "user",
    message_text: "Which wing traits support this ID?",
    client_message_id: null,
    model: null,
    llm_prompt_tokens: null,
    llm_candidate_tokens: null,
    llm_thinking_tokens: null,
    llm_total_tokens: null,
    llm_cached_tokens: null,
    is_refusal: false,
    refusal_reason: null,
    safety_metadata: null,
    created_at: "2026-06-26T12:00:01Z",
  }] satisfies InsightChatMessageRow[];

  const prompt = buildPromptSuggestionsPrompt(messages);
  assertStringIncludes(prompt, "[PROMPT CHIP REQUEST]");
  assertStringIncludes(prompt, "Which wing traits support this ID?");
  assertStringIncludes(prompt, "Avoid repeating user questions");
  assertStringIncludes(prompt, "Do not ask for edible certainty");
  assertStringIncludes(prompt, "exact GPS/location details");
  assertStringIncludes(prompt, "lookalike_compare");
});
