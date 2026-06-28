import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  ChatScanContext,
  InsightChatConversationRow,
  InsightChatFeedbackRating,
  InsightChatMessagePayload,
  InsightChatMessageRow,
  ModelChatResult,
} from "./types.ts";

const MESSAGE_SELECT =
  "id,conversation_id,scan_id,user_id,role,message_text,client_message_id,model,llm_prompt_tokens,llm_candidate_tokens,llm_thinking_tokens,llm_total_tokens,llm_cached_tokens,is_refusal,refusal_reason,safety_metadata,created_at";
const CONVERSATION_SELECT = "id,scan_id,user_id,created_at,updated_at";
const SCAN_CONTEXT_SELECT = `
  id,user_id,timestamp,gps_elevation,weather_condition,weather_temperature_f,
  semantic_location,current_month,time_of_day,depth_scale_text,
  ai_confidence_score,ai_reasoning,candidates,image_quality_score,blur_score,zoom_factor,
  ecology_type,colors,life_stage,reproductive_condition,estimated_size_cm,individual_count,
  ecological_interactions,sex,sex_confidence,sex_evidence,
  is_invasive,is_biological_subject,user_identification_override,user_confirmed_identification,user_review_state,
  user_observation_context,confirmed_species_id,species_id,
  species_dictionary:species_id(
    id,scientific_name,common_names,wikipedia_overview,habitat_description,hazard_type,
    kingdom,phylum,class,order,family,genus,iucn_red_list_status,
    alternative_common_names,similar_species,group_tags
  ),
  confirmed_species:confirmed_species_id(
    id,scientific_name,common_names,wikipedia_overview,habitat_description,hazard_type,
    kingdom,phylum,class,order,family,genus,iucn_red_list_status,
    alternative_common_names,similar_species,group_tags
  )
`;
const SCAN_CONTEXT_SELECT_WITHOUT_ZOOM = SCAN_CONTEXT_SELECT.replace(
  "image_quality_score,blur_score,zoom_factor",
  "image_quality_score,blur_score",
);

export function formatMessage(
  row: InsightChatMessageRow,
): InsightChatMessagePayload {
  return {
    id: row.id,
    conversation_id: row.conversation_id,
    scan_id: row.scan_id,
    role: row.role,
    text: row.message_text,
    client_message_id: row.client_message_id,
    model: row.model,
    is_refusal: row.is_refusal,
    refusal_reason: row.refusal_reason,
    created_at: row.created_at,
  };
}

export async function fetchOwnedScan(
  userId: string,
  scanId: string,
  supabaseAdmin: SupabaseClient,
): Promise<ChatScanContext | null> {
  const result = await supabaseAdmin
    .from("scans")
    .select(SCAN_CONTEXT_SELECT)
    .eq("id", scanId)
    .maybeSingle();
  let data = result.data as Record<string, unknown> | null;
  let error = result.error;

  if (error && error.message.includes("zoom_factor")) {
    const fallback = await supabaseAdmin
      .from("scans")
      .select(SCAN_CONTEXT_SELECT_WITHOUT_ZOOM)
      .eq("id", scanId)
      .maybeSingle();
    const fallbackData = fallback.data as unknown as
      | Record<string, unknown>
      | null;
    data = fallbackData == null ? null : { ...fallbackData, zoom_factor: null };
    error = fallback.error;
  }

  if (error) throw new Error(`Failed to fetch scan context: ${error.message}`);
  if (!data) return null;
  if (data.user_id !== userId) {
    throw Object.assign(
      new Error(
        "Forbidden: You do not have permission to chat about this scan.",
      ),
      { status: 403 },
    );
  }
  return data as unknown as ChatScanContext;
}

export async function fetchConversation(
  userId: string,
  scanId: string,
  supabaseAdmin: SupabaseClient,
): Promise<InsightChatConversationRow | null> {
  const { data, error } = await supabaseAdmin
    .from("insight_chat_conversations")
    .select(CONVERSATION_SELECT)
    .eq("user_id", userId)
    .eq("scan_id", scanId)
    .maybeSingle();

  if (error) {
    throw new Error(`Failed to fetch chat conversation: ${error.message}`);
  }
  return (data as InsightChatConversationRow | null) ?? null;
}

export async function getOrCreateConversation(
  userId: string,
  scanId: string,
  supabaseAdmin: SupabaseClient,
): Promise<InsightChatConversationRow> {
  const existing = await fetchConversation(userId, scanId, supabaseAdmin);
  if (existing) return existing;

  const { data, error } = await supabaseAdmin
    .from("insight_chat_conversations")
    .insert({ user_id: userId, scan_id: scanId })
    .select(CONVERSATION_SELECT)
    .single();

  if (error) {
    if (error.code === "23505") {
      const raced = await fetchConversation(userId, scanId, supabaseAdmin);
      if (raced) return raced;
    }
    throw new Error(`Failed to create chat conversation: ${error.message}`);
  }
  return data as InsightChatConversationRow;
}

export async function fetchMessages(
  conversationId: string,
  supabaseAdmin: SupabaseClient,
): Promise<InsightChatMessageRow[]> {
  const { data, error } = await supabaseAdmin
    .from("insight_chat_messages")
    .select(MESSAGE_SELECT)
    .eq("conversation_id", conversationId)
    .order("created_at", { ascending: true })
    .order("id", { ascending: true });

  if (error) throw new Error(`Failed to fetch chat messages: ${error.message}`);
  return (data ?? []) as InsightChatMessageRow[];
}

export async function insertUserMessage(
  conversationId: string,
  userId: string,
  scanId: string,
  messageText: string,
  clientMessageId: string | null,
  supabaseAdmin: SupabaseClient,
): Promise<InsightChatMessageRow> {
  const { data, error } = await supabaseAdmin
    .from("insight_chat_messages")
    .insert({
      conversation_id: conversationId,
      user_id: userId,
      scan_id: scanId,
      role: "user",
      message_text: messageText,
      client_message_id: clientMessageId,
    })
    .select(MESSAGE_SELECT)
    .single();

  if (error) {
    if (error.code === "23505" && clientMessageId) {
      const { data: existing, error: fetchError } = await supabaseAdmin
        .from("insight_chat_messages")
        .select(MESSAGE_SELECT)
        .eq("conversation_id", conversationId)
        .eq("client_message_id", clientMessageId)
        .single();
      if (fetchError) {
        throw new Error(
          `Failed to fetch duplicate chat message: ${fetchError.message}`,
        );
      }
      return existing as InsightChatMessageRow;
    }
    throw new Error(`Failed to insert user chat message: ${error.message}`);
  }

  await touchConversation(conversationId, supabaseAdmin);
  return data as InsightChatMessageRow;
}

export async function insertAssistantMessage(
  conversationId: string,
  userId: string,
  scanId: string,
  result: ModelChatResult,
  supabaseAdmin: SupabaseClient,
): Promise<InsightChatMessageRow> {
  const usage = result.usage;
  const { data, error } = await supabaseAdmin
    .from("insight_chat_messages")
    .insert({
      conversation_id: conversationId,
      user_id: userId,
      scan_id: scanId,
      role: "assistant",
      message_text: result.answer,
      model: "gemini-2.5-flash",
      llm_prompt_tokens: usage?.promptTokenCount ?? null,
      llm_candidate_tokens: usage?.candidatesTokenCount ?? null,
      llm_thinking_tokens: usage?.thoughtsTokenCount ?? null,
      llm_total_tokens: usage?.totalTokenCount ?? null,
      llm_cached_tokens: usage?.cachedContentTokenCount ?? null,
      is_refusal: result.isRefusal,
      refusal_reason: result.refusalReason,
      safety_metadata: result.isRefusal
        ? { refusal_reason: result.refusalReason }
        : null,
    })
    .select(MESSAGE_SELECT)
    .single();

  if (error) {
    throw new Error(
      `Failed to insert assistant chat message: ${error.message}`,
    );
  }
  await touchConversation(conversationId, supabaseAdmin);
  return data as InsightChatMessageRow;
}

export async function touchConversation(
  conversationId: string,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error } = await supabaseAdmin
    .from("insight_chat_conversations")
    .update({ updated_at: new Date().toISOString() })
    .eq("id", conversationId);
  if (error) {
    throw new Error(
      `Failed to update chat conversation timestamp: ${error.message}`,
    );
  }
}

export async function deleteConversation(
  userId: string,
  scanId: string,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error } = await supabaseAdmin
    .from("insight_chat_conversations")
    .delete()
    .eq("user_id", userId)
    .eq("scan_id", scanId);
  if (error) {
    throw new Error(`Failed to delete chat conversation: ${error.message}`);
  }
}

export async function fetchOwnedAssistantMessage(
  userId: string,
  scanId: string,
  messageId: string,
  supabaseAdmin: SupabaseClient,
): Promise<InsightChatMessageRow | null> {
  const { data, error } = await supabaseAdmin
    .from("insight_chat_messages")
    .select(MESSAGE_SELECT)
    .eq("id", messageId)
    .eq("scan_id", scanId)
    .eq("user_id", userId)
    .eq("role", "assistant")
    .maybeSingle();

  if (error) {
    throw new Error(`Failed to fetch chat message: ${error.message}`);
  }
  return (data as InsightChatMessageRow | null) ?? null;
}

export async function upsertMessageFeedback(
  userId: string,
  message: InsightChatMessageRow,
  rating: InsightChatFeedbackRating,
  note: string | null,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error } = await supabaseAdmin
    .from("insight_chat_message_feedback")
    .upsert({
      message_id: message.id,
      conversation_id: message.conversation_id,
      scan_id: message.scan_id,
      user_id: userId,
      rating,
      note,
    }, {
      onConflict: "message_id,user_id",
    });

  if (error) {
    throw new Error(`Failed to save chat feedback: ${error.message}`);
  }
}

export async function countUserSendsToday(
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<number> {
  const start = new Date();
  start.setUTCHours(0, 0, 0, 0);
  const { count, error } = await supabaseAdmin
    .from("insight_chat_messages")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("role", "user")
    .gte("created_at", start.toISOString());

  if (error) {
    throw new Error(`Failed to count daily chat sends: ${error.message}`);
  }
  return count ?? 0;
}
