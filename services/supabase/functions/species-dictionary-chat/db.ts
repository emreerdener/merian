import type { SupabaseClient } from "@supabase/supabase-js";
import { geminiUsageModalityBreakdown } from "../_shared/aiUsage.ts";
import {
  deriveFieldChatAssistantMessageId,
  fieldChatAssistantMetadata,
  fieldChatMessageRequestId,
} from "../_shared/fieldChatResponse.ts";
import {
  type FieldChatAdmission,
  reserveFieldChatSend,
} from "../_shared/fieldChatReservation.ts";
import {
  isPublicBiologicalSpeciesRow,
  type PublicSpeciesDictionaryRow,
  resolveOptionalPublicCommonName,
  resolvePublicCommonName,
  sanitizeAlternativeCommonNames,
  sanitizePublicStringArray,
  stringValue,
} from "../_shared/publicSpeciesProjection.ts";
import type {
  InsightChatFeedbackRating,
  ModelChatResult,
  SpeciesDictionaryChatContext,
  SpeciesDictionaryChatConversationRow,
  SpeciesDictionaryChatMessageRow,
} from "./types.ts";

const SPECIES_CONTEXT_SELECT =
  "id,scientific_name,common_names,alternative_common_names,kingdom,phylum,class,order,family,genus,wikipedia_overview,hazard_type,iucn_red_list_status,habitat_description,gbif_taxon_key,group_tags";
const LOOKALIKE_SELECT =
  "reason,visual_traits,sort_order,lookalike:species_dictionary!lookalike_id(scientific_name,common_names)";
const MESSAGE_SELECT =
  "id,conversation_id,species_dictionary_id,user_id,role,message_text,client_message_id,model,llm_prompt_tokens,llm_candidate_tokens,llm_thinking_tokens,llm_total_tokens,llm_cached_tokens,is_refusal,refusal_reason,safety_metadata,created_at";
const CONVERSATION_SELECT =
  "id,species_dictionary_id,user_id,created_at,updated_at";

interface SpeciesContextRow {
  id: string;
  scientific_name: string;
  common_names: Record<string, unknown> | null;
  alternative_common_names: string[] | null;
  kingdom: string | null;
  phylum: string | null;
  class: string | null;
  order: string | null;
  family: string | null;
  genus: string | null;
  wikipedia_overview: string | null;
  hazard_type: string | null;
  iucn_red_list_status: string | null;
  habitat_description: string | null;
  gbif_taxon_key: number | null;
  group_tags: string[] | null;
}

interface LookalikeSpeciesRow {
  scientific_name?: string | null;
  common_names?: Record<string, unknown> | null;
}

interface LookalikeRelationRow {
  reason?: string | null;
  visual_traits?: string[] | null;
  lookalike?: LookalikeSpeciesRow | LookalikeSpeciesRow[] | null;
}

function relationValue(
  value: LookalikeRelationRow["lookalike"],
): LookalikeSpeciesRow | null {
  if (Array.isArray(value)) return value[0] ?? null;
  return value ?? null;
}

function biologicalProjection(
  row: SpeciesContextRow,
): PublicSpeciesDictionaryRow {
  return {
    ...row,
    wikipedia_url: null,
    reference_image_url: null,
  };
}

export function formatMessage(row: SpeciesDictionaryChatMessageRow) {
  return {
    id: row.id,
    conversation_id: row.conversation_id,
    // Shared iOS compatibility: scan_id carries the exact chat subject UUID.
    scan_id: row.species_dictionary_id,
    role: row.role,
    text: row.message_text,
    client_message_id: fieldChatMessageRequestId(row),
    model: row.model,
    is_refusal: row.is_refusal,
    refusal_reason: row.refusal_reason,
    created_at: row.created_at,
  };
}

export async function fetchCanonicalSpeciesContext(
  speciesId: string,
  supabaseAdmin: SupabaseClient,
): Promise<SpeciesDictionaryChatContext | null> {
  const { data, error } = await supabaseAdmin
    .from("species_dictionary")
    .select(SPECIES_CONTEXT_SELECT)
    .eq("id", speciesId)
    .maybeSingle();
  if (error) {
    throw new Error(
      `Failed to fetch Species Dictionary chat context: ${error.message}`,
    );
  }
  const row = data as SpeciesContextRow | null;
  if (!row || !isPublicBiologicalSpeciesRow(biologicalProjection(row))) {
    return null;
  }

  const { data: lookalikeData, error: lookalikeError } = await supabaseAdmin
    .from("species_lookalikes")
    .select(LOOKALIKE_SELECT)
    .eq("species_id", speciesId)
    .neq("review_status", "rejected")
    .order("sort_order", { ascending: true })
    .order("created_at", { ascending: true })
    .limit(6);
  if (lookalikeError) {
    throw new Error(
      `Failed to fetch Species Dictionary chat lookalikes: ${lookalikeError.message}`,
    );
  }

  const commonName = resolvePublicCommonName(
    row.common_names,
    row.scientific_name,
  );
  const lookalikes = ((lookalikeData ?? []) as LookalikeRelationRow[])
    .map((relation) => {
      const lookalike = relationValue(relation.lookalike);
      const scientificName = stringValue(lookalike?.scientific_name);
      if (!scientificName) return null;
      return {
        scientificName,
        commonName: resolveOptionalPublicCommonName(lookalike?.common_names),
        reason: stringValue(relation.reason),
        visualTraits: sanitizePublicStringArray(relation.visual_traits).slice(
          0,
          6,
        ),
      };
    })
    .filter((value): value is NonNullable<typeof value> => value !== null);

  return {
    id: row.id,
    scientificName: row.scientific_name,
    commonName,
    alternativeCommonNames: sanitizeAlternativeCommonNames(
      row.alternative_common_names,
      commonName,
    ).slice(0, 8),
    taxonomy: {
      kingdom: row.kingdom,
      phylum: row.phylum,
      class: row.class,
      order: row.order,
      family: row.family,
      genus: row.genus,
    },
    overview: row.wikipedia_overview,
    habitat: row.habitat_description,
    hazardType: row.hazard_type,
    conservationStatus: row.iucn_red_list_status,
    groupTags: sanitizePublicStringArray(row.group_tags).slice(0, 12),
    lookalikes,
  };
}

export async function fetchConversation(
  userId: string,
  speciesId: string,
  supabaseAdmin: SupabaseClient,
): Promise<SpeciesDictionaryChatConversationRow | null> {
  const { data, error } = await supabaseAdmin
    .from("species_dictionary_chat_conversations")
    .select(CONVERSATION_SELECT)
    .eq("user_id", userId)
    .eq("species_dictionary_id", speciesId)
    .maybeSingle();
  if (error) {
    throw new Error(`Failed to fetch dictionary chat: ${error.message}`);
  }
  return (data as SpeciesDictionaryChatConversationRow | null) ?? null;
}

export async function getOrCreateConversation(
  userId: string,
  speciesId: string,
  supabaseAdmin: SupabaseClient,
): Promise<SpeciesDictionaryChatConversationRow> {
  const existing = await fetchConversation(userId, speciesId, supabaseAdmin);
  if (existing) return existing;

  const { data, error } = await supabaseAdmin
    .from("species_dictionary_chat_conversations")
    .insert({ user_id: userId, species_dictionary_id: speciesId })
    .select(CONVERSATION_SELECT)
    .single();
  if (error) {
    if (error.code === "23505") {
      const raced = await fetchConversation(userId, speciesId, supabaseAdmin);
      if (raced) return raced;
    }
    throw new Error(`Failed to create dictionary chat: ${error.message}`);
  }
  return data as SpeciesDictionaryChatConversationRow;
}

export async function fetchMessages(
  conversationId: string,
  supabaseAdmin: SupabaseClient,
): Promise<SpeciesDictionaryChatMessageRow[]> {
  const { data, error } = await supabaseAdmin
    .from("species_dictionary_chat_messages")
    .select(MESSAGE_SELECT)
    .eq("conversation_id", conversationId)
    .order("created_at", { ascending: true })
    .order("id", { ascending: true });
  if (error) {
    throw new Error(
      `Failed to fetch dictionary chat messages: ${error.message}`,
    );
  }
  return (data ?? []) as SpeciesDictionaryChatMessageRow[];
}

export async function insertUserMessage(
  conversationId: string,
  userId: string,
  speciesId: string,
  text: string,
  clientMessageId: string,
  supabaseAdmin: SupabaseClient,
): Promise<FieldChatAdmission<SpeciesDictionaryChatMessageRow>> {
  return await reserveFieldChatSend<SpeciesDictionaryChatMessageRow>(
    supabaseAdmin,
    {
      userId,
      conversationId,
      subjectType: "species_dictionary",
      subjectId: speciesId,
      messageText: text,
      clientMessageId,
    },
  );
}

export async function insertAssistantMessage(
  conversationId: string,
  userId: string,
  speciesId: string,
  requestId: string,
  result: ModelChatResult,
  supabaseAdmin: SupabaseClient,
  model = "gemini-2.5-flash",
): Promise<SpeciesDictionaryChatMessageRow> {
  const usage = result.usage;
  const assistantMessageId = await deriveFieldChatAssistantMessageId(
    conversationId,
    requestId,
  );
  const { data, error } = await supabaseAdmin
    .from("species_dictionary_chat_messages")
    .insert({
      id: assistantMessageId,
      conversation_id: conversationId,
      species_dictionary_id: speciesId,
      user_id: userId,
      role: "assistant",
      message_text: result.answer,
      model: usage ? model : null,
      llm_prompt_tokens: usage?.promptTokenCount ?? null,
      llm_candidate_tokens: usage?.candidatesTokenCount ?? null,
      llm_thinking_tokens: usage?.thoughtsTokenCount ?? null,
      llm_total_tokens: usage?.totalTokenCount ?? null,
      llm_cached_tokens: usage?.cachedContentTokenCount ?? null,
      is_refusal: result.isRefusal,
      refusal_reason: result.refusalReason,
      safety_metadata: fieldChatAssistantMetadata(
        requestId,
        usage
          ? { prompt_tokens_by_modality: geminiUsageModalityBreakdown(usage) }
          : {},
      ),
    })
    .select(MESSAGE_SELECT)
    .single();
  if (error) {
    if (error.code === "23505") {
      const { data: existing, error: fetchError } = await supabaseAdmin
        .from("species_dictionary_chat_messages")
        .select(MESSAGE_SELECT)
        .eq("id", assistantMessageId)
        .maybeSingle();
      const existingMessage = existing as
        | SpeciesDictionaryChatMessageRow
        | null;
      if (
        !fetchError && existingMessage &&
        existingMessage.conversation_id === conversationId &&
        existingMessage.user_id === userId &&
        existingMessage.species_dictionary_id === speciesId &&
        existingMessage.role === "assistant" &&
        fieldChatMessageRequestId(existingMessage) === requestId.toLowerCase()
      ) {
        return existingMessage;
      }
    }
    throw new Error(`Failed to save dictionary chat answer: ${error.message}`);
  }

  const { error: touchError } = await supabaseAdmin
    .from("species_dictionary_chat_conversations")
    .update({ updated_at: new Date().toISOString() })
    .eq("id", conversationId);
  if (touchError) {
    throw new Error(`Failed to update dictionary chat: ${touchError.message}`);
  }
  return data as SpeciesDictionaryChatMessageRow;
}

export async function deleteConversation(
  userId: string,
  speciesId: string,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error } = await supabaseAdmin
    .from("species_dictionary_chat_conversations")
    .delete()
    .eq("user_id", userId)
    .eq("species_dictionary_id", speciesId);
  if (error) {
    throw new Error(`Failed to delete dictionary chat: ${error.message}`);
  }
}

export async function fetchAssistantMessage(
  userId: string,
  speciesId: string,
  messageId: string,
  supabaseAdmin: SupabaseClient,
): Promise<SpeciesDictionaryChatMessageRow | null> {
  const { data, error } = await supabaseAdmin
    .from("species_dictionary_chat_messages")
    .select(MESSAGE_SELECT)
    .eq("id", messageId)
    .eq("species_dictionary_id", speciesId)
    .eq("user_id", userId)
    .eq("role", "assistant")
    .maybeSingle();
  if (error) {
    throw new Error(`Failed to fetch dictionary chat answer: ${error.message}`);
  }
  return (data as SpeciesDictionaryChatMessageRow | null) ?? null;
}

export async function upsertFeedback(
  userId: string,
  message: SpeciesDictionaryChatMessageRow,
  rating: InsightChatFeedbackRating,
  note: string | null,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error } = await supabaseAdmin
    .from("species_dictionary_chat_message_feedback")
    .upsert({
      message_id: message.id,
      conversation_id: message.conversation_id,
      species_dictionary_id: message.species_dictionary_id,
      user_id: userId,
      rating,
      note,
    }, { onConflict: "message_id,user_id" });
  if (error) {
    throw new Error(
      `Failed to save dictionary chat feedback: ${error.message}`,
    );
  }
}
