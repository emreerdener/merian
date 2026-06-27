import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildScanContextBlock,
  buildSystemInstruction,
  buildUserPrompt,
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
  is_biological_subject: true,
  user_identification_override: null,
  user_confirmed_identification: false,
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
  },
};

Deno.test("scan context uses text evidence and excludes image URLs", () => {
  const block = buildScanContextBlock(scan);
  assertStringIncludes(block, "Monarch");
  assertStringIncludes(block, "Orange wings");
  assertStringIncludes(block, "Danaus gilippus");
  assertStringIncludes(block, "0.8 meters");
  assertEquals(block.includes("image_storage_urls"), false);
  assertEquals(block.includes("https://"), false);
});

Deno.test("system instruction states raw image is unavailable", () => {
  const instruction = buildSystemInstruction(scan);
  assertStringIncludes(instruction, "You do not have access to the raw image");
  assertStringIncludes(
    instruction,
    "Do not provide edible or foraging certainty",
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
  assertStringIncludes(prompt, "Merian: It is often found near milkweed.");
  assertStringIncludes(prompt, "[CURRENT USER QUESTION]");
  assertStringIncludes(prompt, "What should I compare next?");
});
