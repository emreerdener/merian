import type {
  InsightChatFeedbackRating,
  InsightChatRole,
  ModelChatResult,
} from "../insight-chat/types.ts";

export interface SpeciesDictionaryChatLookalike {
  scientificName: string;
  commonName: string | null;
  reason: string | null;
  visualTraits: string[];
}

export interface SpeciesDictionaryChatContext {
  id: string;
  scientificName: string;
  commonName: string;
  alternativeCommonNames: string[];
  taxonomy: {
    kingdom: string | null;
    phylum: string | null;
    class: string | null;
    order: string | null;
    family: string | null;
    genus: string | null;
  };
  overview: string | null;
  habitat: string | null;
  hazardType: string | null;
  conservationStatus: string | null;
  groupTags: string[];
  lookalikes: SpeciesDictionaryChatLookalike[];
}

export interface SpeciesDictionaryChatConversationRow {
  id: string;
  species_dictionary_id: string;
  user_id: string;
  created_at: string;
  updated_at: string;
}

export interface SpeciesDictionaryChatMessageRow {
  id: string;
  conversation_id: string;
  species_dictionary_id: string;
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

export type { InsightChatFeedbackRating, ModelChatResult };
