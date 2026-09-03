import { buildFieldChatReplyRequest } from "../functions/_shared/fieldChatReply.ts";
import {
  buildSystemInstruction as insightSystem,
  buildUserPrompt as insightQuestion,
} from "../functions/insight-chat/prompt.ts";
import {
  type ChatScanContext,
  INSIGHT_CHAT_MODEL,
  type InsightChatMessageRow,
  type SpeciesDictionaryContext,
} from "../functions/insight-chat/types.ts";
import {
  buildSystemInstruction as exploreSystem,
  buildUserPrompt as exploreQuestion,
} from "../functions/explore-post-chat/prompt.ts";
import {
  buildSystemInstruction as dictionarySystem,
  buildUserPrompt as dictionaryQuestion,
} from "../functions/species-dictionary-chat/prompt.ts";

// Entirely synthetic context. Never substitute a saved user scan or chat here.
const syntheticId = "00000000-0000-4000-8000-000000000001";
const species: SpeciesDictionaryContext = {
  id: syntheticId,
  scientific_name: "Adenium obesum",
  common_names: { en: "Desert Rose" },
  kingdom: "Plantae",
  phylum: "Tracheophyta",
  class: "Magnoliopsida",
  order: "Gentianales",
  family: "Apocynaceae",
  genus: "Adenium",
  wikipedia_overview: null,
  habitat_description: null,
  hazard_type: "poisonous",
  iucn_red_list_status: null,
  alternative_common_names: null,
  similar_species: null,
  group_tags: ["plant"],
};

const scan: ChatScanContext = {
  id: syntheticId,
  user_id: syntheticId,
  timestamp: "2026-01-01T12:00:00Z",
  gps_elevation: null,
  weather_condition: null,
  weather_temperature_f: null,
  semantic_location: null,
  current_month: null,
  time_of_day: null,
  depth_scale_text: null,
  ai_confidence_score: 0.95,
  ai_reasoning: null,
  candidates: null,
  image_quality_score: null,
  blur_score: null,
  zoom_factor: null,
  ecology_type: null,
  colors: null,
  life_stage: null,
  reproductive_condition: null,
  estimated_size_cm: null,
  individual_count: null,
  ecological_interactions: null,
  sex: null,
  sex_confidence: null,
  sex_evidence: null,
  is_invasive: null,
  invasive_status_region: null,
  invasive_rationale: null,
  invasive_confidence: null,
  is_biological_subject: true,
  user_identification_override: null,
  user_confirmed_identification: true,
  user_review_state: "ai_confirmed",
  user_observation_context: null,
  confirmed_species_id: null,
  species_id: syntheticId,
  species_dictionary: species,
  confirmed_species: null,
};

const priorAnswer: InsightChatMessageRow = {
  id: syntheticId,
  conversation_id: syntheticId,
  scan_id: syntheticId,
  user_id: syntheticId,
  role: "assistant",
  message_text: "I can answer only from the saved record.",
  client_message_id: null,
  model: INSIGHT_CHAT_MODEL,
  llm_prompt_tokens: null,
  llm_candidate_tokens: null,
  llm_thinking_tokens: null,
  llm_total_tokens: null,
  llm_cached_tokens: null,
  is_refusal: false,
  refusal_reason: null,
  safety_metadata: null,
  created_at: "2026-01-01T12:00:01Z",
};

export function buildFieldChatAnswerCases() {
  const routes = [{
    route: "insight-chat",
    system: insightSystem(scan),
    question: (text: string, includeHistory: boolean) =>
      insightQuestion(includeHistory ? [priorAnswer] : [], text),
  }, {
    route: "explore-post-chat",
    system: exploreSystem({
      post: {
        post_id: syntheticId,
        scan_id: syntheticId,
        hero_image_url: "",
        shared_at: scan.timestamp,
        author_user_id: syntheticId,
        author_name: "Synthetic observer",
        species_common_name: "Desert Rose",
        species_scientific_name: "Adenium obesum",
        public_location_label: null,
        location_sharing: "private",
        time_of_day: null,
        current_month: null,
        weather_condition: null,
        weather_temperature_f: null,
        like_count: 0,
        comment_count: 0,
        viewer_has_liked: false,
        is_owned_by_viewer: false,
      },
      detail: {
        post_id: syntheticId,
        species_dictionary_id: syntheticId,
        location_sharing: "private",
        taxonomy_kingdom: species.kingdom,
        taxonomy_phylum: species.phylum,
        taxonomy_class: species.class,
        taxonomy_order: species.order,
        taxonomy_family: species.family,
        taxonomy_genus: species.genus,
        field_notes: null,
        ai_reasoning: null,
        wikipedia_overview: null,
        habitat_description: null,
        hazard_type: species.hazard_type,
        iucn_red_list_status: null,
        similar_species: [],
      },
    }),
    question: (text: string, includeHistory: boolean) =>
      exploreQuestion(
        includeHistory ? [{ ...priorAnswer, post_id: syntheticId }] : [],
        text,
      ),
  }, {
    route: "species-dictionary-chat",
    system: dictionarySystem({
      id: syntheticId,
      scientificName: "Adenium obesum",
      commonName: "Desert Rose",
      alternativeCommonNames: [],
      taxonomy: {
        kingdom: species.kingdom,
        phylum: species.phylum,
        class: species.class,
        order: species.order,
        family: species.family,
        genus: species.genus,
      },
      overview: null,
      habitat: null,
      hazardType: species.hazard_type,
      conservationStatus: null,
      groupTags: ["plant"],
      lookalikes: [],
    }),
    question: (text: string, includeHistory: boolean) =>
      dictionaryQuestion(
        includeHistory
          ? [{ ...priorAnswer, species_dictionary_id: syntheticId }]
          : [],
        text,
      ),
  }];

  const questions = [{
    name: "general-fragrance",
    question: "Do they smell good?",
    includeHistory: false,
    expectation: "general" as const,
  }, {
    name: "general-fragrance-after-deflection",
    question: "Do they smell good?",
    includeHistory: true,
    expectation: "general" as const,
  }, {
    name: "individual-fragrance",
    question: "Does this particular flower smell strong right now?",
    includeHistory: false,
    expectation: "individual" as const,
  }];

  return routes.flatMap((route) =>
    questions.map((question) => ({
      id: `${route.route}/${question.name}`,
      expectation: question.expectation,
      request: buildFieldChatReplyRequest(
        route.system,
        route.question(question.question, question.includeHistory),
        INSIGHT_CHAT_MODEL,
      ),
    }))
  );
}

export type FieldChatAnswerCase = ReturnType<
  typeof buildFieldChatAnswerCases
>[number];
