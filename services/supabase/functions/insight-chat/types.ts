export const INSIGHT_CHAT_MODEL = "gemini-2.5-flash";
export const MAX_USER_MESSAGE_CHARS = 600;
export const MAX_MESSAGES_PER_CONVERSATION = 30;
export const DAILY_SEND_LIMIT = 20;

export type InsightChatAction =
  | "load"
  | "send"
  | "delete"
  | "feedback"
  | "feature_feedback"
  | "summarize_notes"
  | "suggest_prompts";
export type InsightChatRole = "user" | "assistant";
export type InsightChatFeedbackRating =
  | "helpful"
  | "not_helpful"
  | "wrong"
  | "unsafe"
  | "other";
export type InsightChatFeatureFeedbackSentiment = "positive" | "negative";

export interface InsightChatMessageRow {
  id: string;
  conversation_id: string;
  scan_id: string;
  user_id: string;
  role: InsightChatRole;
  message_text: string;
  client_message_id: string | null;
  model: string | null;
  llm_prompt_tokens: number | null;
  llm_candidate_tokens: number | null;
  llm_thinking_tokens: number | null;
  llm_total_tokens: number | null;
  llm_cached_tokens: number | null;
  is_refusal: boolean;
  refusal_reason: string | null;
  safety_metadata: Record<string, unknown> | null;
  created_at: string;
}

export interface InsightChatConversationRow {
  id: string;
  scan_id: string;
  user_id: string;
  created_at: string;
  updated_at: string;
}

export interface InsightChatMessagePayload {
  id: string;
  conversation_id: string;
  scan_id: string;
  role: InsightChatRole;
  text: string;
  client_message_id: string | null;
  model: string | null;
  is_refusal: boolean;
  refusal_reason: string | null;
  created_at: string;
}

export interface InsightChatResponsePayload {
  conversation_id: string | null;
  messages: InsightChatMessagePayload[];
  limits: {
    max_user_message_chars: number;
    max_messages_per_conversation: number;
    daily_send_limit: number;
    sends_remaining_today: number;
  };
}

export interface InsightChatFeedbackPayload {
  ok: boolean;
  message_id: string;
  rating: InsightChatFeedbackRating;
}

export interface InsightChatFeatureFeedbackPayload {
  ok: boolean;
  id: string;
  sentiment: InsightChatFeatureFeedbackSentiment | null;
}

export interface InsightChatSummaryPayload {
  summary_text: string;
}

export interface InsightChatPromptSuggestionPayload {
  text: string;
  category: string;
}

export interface InsightChatPromptSuggestionsPayload {
  conversation_id: string | null;
  prompts: InsightChatPromptSuggestionPayload[];
}

export interface ChatScanContext {
  id: string;
  user_id: string;
  timestamp: string;
  gps_elevation: number | null;
  weather_condition: string | null;
  weather_temperature_f: number | null;
  semantic_location: string | null;
  current_month: number | null;
  time_of_day: string | null;
  depth_scale_text: string | null;
  ai_confidence_score: number | null;
  ai_reasoning: string | null;
  candidates: unknown;
  image_quality_score: number | null;
  blur_score: number | null;
  zoom_factor: number | null;
  ecology_type: string | null;
  colors: string[] | null;
  life_stage: string | null;
  reproductive_condition: string | null;
  estimated_size_cm: number | null;
  individual_count: number | null;
  ecological_interactions: string[] | null;
  sex: string | null;
  sex_confidence: number | null;
  sex_evidence: string | null;
  is_invasive: boolean | null;
  invasive_status_region: string | null;
  invasive_rationale: string | null;
  invasive_confidence: number | null;
  is_biological_subject: boolean | null;
  user_identification_override: string | null;
  user_confirmed_identification: boolean | null;
  user_review_state: string | null;
  user_observation_context: unknown;
  confirmed_species_id: string | null;
  species_id: string | null;
  species_dictionary:
    | SpeciesDictionaryContext
    | SpeciesDictionaryContext[]
    | null;
  confirmed_species:
    | SpeciesDictionaryContext
    | SpeciesDictionaryContext[]
    | null;
}

export interface SpeciesDictionaryContext {
  id: string;
  scientific_name: string | null;
  common_names: Record<string, unknown> | null;
  wikipedia_overview: string | null;
  habitat_description: string | null;
  hazard_type: string | null;
  kingdom: string | null;
  phylum: string | null;
  class: string | null;
  order: string | null;
  family: string | null;
  genus: string | null;
  iucn_red_list_status: string | null;
  alternative_common_names: string[] | null;
  similar_species: string[] | null;
  group_tags: string[] | null;
}

export interface ModelChatResult {
  answer: string;
  isRefusal: boolean;
  refusalReason: string | null;
  usage:
    | {
      promptTokenCount?: number;
      candidatesTokenCount?: number;
      totalTokenCount?: number;
      thoughtsTokenCount?: number;
      cachedContentTokenCount?: number;
    }
    | null
    | undefined;
}
