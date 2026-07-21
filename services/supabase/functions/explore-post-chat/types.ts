import type { ExplorePostRow } from "../get-explore-post/db.ts";
import type { ExplorePostDetailRow } from "../get-explore-post-detail/db.ts";
import type {
  InsightChatFeedbackRating,
  InsightChatRole,
  ModelChatResult,
} from "../insight-chat/types.ts";

export interface ExplorePostChatContext {
  post: ExplorePostRow;
  detail: ExplorePostDetailRow;
}

export interface ExplorePostChatConversationRow {
  id: string;
  post_id: string;
  user_id: string;
  species_dictionary_id: string | null;
  created_at: string;
  updated_at: string;
}

export interface ExplorePostChatMessageRow {
  id: string;
  conversation_id: string;
  post_id: string;
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
