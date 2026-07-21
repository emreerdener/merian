import { SupabaseClient } from "@supabase/supabase-js";
import { fetchExplorePost } from "../get-explore-post/db.ts";
import { fetchExplorePostDetail } from "../get-explore-post-detail/db.ts";
import { geminiUsageModalityBreakdown } from "../_shared/aiUsage.ts";
import type {
  ExplorePostChatContext,
  ExplorePostChatConversationRow,
  ExplorePostChatMessageRow,
  InsightChatFeedbackRating,
  ModelChatResult,
} from "./types.ts";

const MESSAGE_SELECT =
  "id,conversation_id,post_id,user_id,role,message_text,client_message_id,model,llm_prompt_tokens,llm_candidate_tokens,llm_thinking_tokens,llm_total_tokens,llm_cached_tokens,is_refusal,refusal_reason,safety_metadata,created_at";
const CONVERSATION_SELECT =
  "id,post_id,user_id,species_dictionary_id,created_at,updated_at";

export function formatMessage(row: ExplorePostChatMessageRow) {
  return {
    id: row.id,
    conversation_id: row.conversation_id,
    // Keep the established iOS Field Chat envelope compatible. In this endpoint
    // the context identifier is an Explore post id, never an owner scan id.
    scan_id: row.post_id,
    role: row.role,
    text: row.message_text,
    client_message_id: row.client_message_id,
    model: row.model,
    is_refusal: row.is_refusal,
    refusal_reason: row.refusal_reason,
    created_at: row.created_at,
  };
}

export async function fetchPublicContext(
  userId: string,
  postId: string,
  supabaseAdmin: SupabaseClient,
): Promise<ExplorePostChatContext | null> {
  const [post, detail] = await Promise.all([
    fetchExplorePost(userId, postId, supabaseAdmin),
    fetchExplorePostDetail(userId, postId, supabaseAdmin),
  ]);
  return post && detail ? { post, detail } : null;
}

export async function fetchConversation(
  userId: string,
  postId: string,
  supabaseAdmin: SupabaseClient,
): Promise<ExplorePostChatConversationRow | null> {
  const { data, error } = await supabaseAdmin
    .from("explore_post_chat_conversations")
    .select(CONVERSATION_SELECT)
    .eq("user_id", userId)
    .eq("post_id", postId)
    .maybeSingle();
  if (error) throw new Error(`Failed to fetch Explore chat: ${error.message}`);
  return (data as ExplorePostChatConversationRow | null) ?? null;
}

export async function getOrCreateConversation(
  userId: string,
  postId: string,
  speciesDictionaryId: string | null,
  supabaseAdmin: SupabaseClient,
): Promise<ExplorePostChatConversationRow> {
  const existing = await fetchConversation(userId, postId, supabaseAdmin);
  if (existing?.species_dictionary_id === speciesDictionaryId) return existing;
  if (existing) {
    await deleteConversation(userId, postId, supabaseAdmin);
  }

  const { data, error } = await supabaseAdmin
    .from("explore_post_chat_conversations")
    .insert({
      user_id: userId,
      post_id: postId,
      species_dictionary_id: speciesDictionaryId,
    })
    .select(CONVERSATION_SELECT)
    .single();
  if (error) {
    if (error.code === "23505") {
      const raced = await fetchConversation(userId, postId, supabaseAdmin);
      if (raced?.species_dictionary_id === speciesDictionaryId) return raced;
    }
    throw new Error(`Failed to create Explore chat: ${error.message}`);
  }
  return data as ExplorePostChatConversationRow;
}

export async function fetchMessages(
  conversationId: string,
  supabaseAdmin: SupabaseClient,
): Promise<ExplorePostChatMessageRow[]> {
  const { data, error } = await supabaseAdmin
    .from("explore_post_chat_messages")
    .select(MESSAGE_SELECT)
    .eq("conversation_id", conversationId)
    .order("created_at", { ascending: true })
    .order("id", { ascending: true });
  if (error) throw new Error(`Failed to fetch Explore chat messages: ${error.message}`);
  return (data ?? []) as ExplorePostChatMessageRow[];
}

export async function insertUserMessage(
  conversationId: string,
  userId: string,
  postId: string,
  text: string,
  clientMessageId: string | null,
  supabaseAdmin: SupabaseClient,
): Promise<ExplorePostChatMessageRow> {
  const { data, error } = await supabaseAdmin
    .from("explore_post_chat_messages")
    .insert({
      conversation_id: conversationId,
      post_id: postId,
      user_id: userId,
      role: "user",
      message_text: text,
      client_message_id: clientMessageId,
    })
    .select(MESSAGE_SELECT)
    .single();
  if (error) throw new Error(`Failed to save Explore chat message: ${error.message}`);
  return data as ExplorePostChatMessageRow;
}

export async function insertAssistantMessage(
  conversationId: string,
  userId: string,
  postId: string,
  result: ModelChatResult,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const usage = result.usage;
  const { error } = await supabaseAdmin.from("explore_post_chat_messages").insert({
    conversation_id: conversationId,
    post_id: postId,
    user_id: userId,
    role: "assistant",
    message_text: result.answer,
    model: usage ? "gemini-2.5-flash" : null,
    llm_prompt_tokens: usage?.promptTokenCount ?? null,
    llm_candidate_tokens: usage?.candidatesTokenCount ?? null,
    llm_thinking_tokens: usage?.thoughtsTokenCount ?? null,
    llm_total_tokens: usage?.totalTokenCount ?? null,
    llm_cached_tokens: usage?.cachedContentTokenCount ?? null,
    is_refusal: result.isRefusal,
    refusal_reason: result.refusalReason,
    safety_metadata: usage
      ? { prompt_tokens_by_modality: geminiUsageModalityBreakdown(usage) }
      : null,
  });
  if (error) throw new Error(`Failed to save Explore chat answer: ${error.message}`);
  const { error: touchError } = await supabaseAdmin
    .from("explore_post_chat_conversations")
    .update({ updated_at: new Date().toISOString() })
    .eq("id", conversationId);
  if (touchError) throw new Error(`Failed to update Explore chat: ${touchError.message}`);
}

export async function deleteConversation(
  userId: string,
  postId: string,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error } = await supabaseAdmin
    .from("explore_post_chat_conversations")
    .delete()
    .eq("user_id", userId)
    .eq("post_id", postId);
  if (error) throw new Error(`Failed to delete Explore chat: ${error.message}`);
}

export async function fetchAssistantMessage(
  userId: string,
  postId: string,
  messageId: string,
  supabaseAdmin: SupabaseClient,
): Promise<ExplorePostChatMessageRow | null> {
  const { data, error } = await supabaseAdmin
    .from("explore_post_chat_messages")
    .select(MESSAGE_SELECT)
    .eq("id", messageId)
    .eq("post_id", postId)
    .eq("user_id", userId)
    .eq("role", "assistant")
    .maybeSingle();
  if (error) throw new Error(`Failed to fetch Explore chat answer: ${error.message}`);
  return (data as ExplorePostChatMessageRow | null) ?? null;
}

export async function upsertFeedback(
  userId: string,
  message: ExplorePostChatMessageRow,
  rating: InsightChatFeedbackRating,
  note: string | null,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error } = await supabaseAdmin
    .from("explore_post_chat_message_feedback")
    .upsert({
      message_id: message.id,
      conversation_id: message.conversation_id,
      post_id: message.post_id,
      user_id: userId,
      rating,
      note,
    }, { onConflict: "message_id,user_id" });
  if (error) throw new Error(`Failed to save Explore chat feedback: ${error.message}`);
}

async function countTableSendsToday(
  table: string,
  userId: string,
  start: string,
  supabaseAdmin: SupabaseClient,
): Promise<number> {
  const { count, error } = await supabaseAdmin
    .from(table)
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("role", "user")
    .gte("created_at", start);
  if (error) throw new Error(`Failed to count Field chat sends: ${error.message}`);
  return count ?? 0;
}

export async function countAllFieldChatSendsToday(
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<number> {
  const start = new Date();
  start.setUTCHours(0, 0, 0, 0);
  const iso = start.toISOString();
  const [insight, explore] = await Promise.all([
    countTableSendsToday("insight_chat_messages", userId, iso, supabaseAdmin),
    countTableSendsToday("explore_post_chat_messages", userId, iso, supabaseAdmin),
  ]);
  return insight + explore;
}
