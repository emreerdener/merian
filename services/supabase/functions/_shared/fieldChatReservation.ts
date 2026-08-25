import type { SupabaseClient } from "@supabase/supabase-js";
import {
  FIELD_CHAT_BUNDLE_SHA256,
  type FieldChatDeploymentFunction,
} from "./fieldChatDeploymentIdentity.ts";
import { publicHttpError } from "./http.ts";

const FIELD_CHAT_UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export const FIELD_CHAT_DEPLOYMENT_CONTRACT_HEADER =
  "X-Merian-Field-Chat-Contract";
export const FIELD_CHAT_DEPLOYMENT_CONTRACT_VERSION = "atomic-admission-v1";
export const FIELD_CHAT_BUNDLE_SHA256_HEADER =
  "X-Merian-Field-Chat-Bundle-SHA256";

export function fieldChatDeploymentContractHeaders(
  functionName: FieldChatDeploymentFunction,
): Readonly<Record<string, string>> {
  const digest = FIELD_CHAT_BUNDLE_SHA256[functionName];
  if (!/^[0-9a-f]{64}$/.test(digest) || /^0{64}$/.test(digest)) {
    throw new Error(`Invalid Field Chat bundle identity for ${functionName}`);
  }
  return Object.freeze({
    [FIELD_CHAT_DEPLOYMENT_CONTRACT_HEADER]:
      FIELD_CHAT_DEPLOYMENT_CONTRACT_VERSION,
    [FIELD_CHAT_BUNDLE_SHA256_HEADER]: digest,
  });
}

export type FieldChatSubjectType =
  | "insight"
  | "explore"
  | "species_dictionary";

interface StoredFieldChatUserMessage {
  id: string;
  conversation_id: string;
  scan_id?: string;
  post_id?: string;
  species_dictionary_id?: string;
  user_id: string;
  role: string;
  message_text: string;
  client_message_id: string | null;
}

interface FieldChatAdmissionRow {
  conversation_id: unknown;
  message: unknown;
  is_replay: unknown;
  sends_today: unknown;
}

export interface FieldChatAdmission<Message> {
  conversationId: string;
  message: Message;
  isReplay: boolean;
  sendsToday: number;
}

function canonicalUuid(value: string): string {
  return value.toLowerCase();
}

function admissionError(databaseMessage: string): Error {
  if (databaseMessage.includes("field_chat_idempotency_conflict")) {
    return publicHttpError(
      409,
      "This Field Chat retry key was already used for a different message.",
      "field_chat_idempotency_conflict",
    );
  }
  if (databaseMessage.includes("field_chat_send_in_progress")) {
    return publicHttpError(
      503,
      "Another Field Chat send is still completing. Please retry it first.",
      "field_chat_send_in_progress",
      2,
    );
  }
  if (databaseMessage.includes("field_chat_admission_cutover_pending")) {
    return publicHttpError(
      503,
      "Field Chat is briefly unavailable while daily admission accounting is activated. Please retry shortly.",
      "field_chat_admission_cutover_pending",
      60,
    );
  }
  if (databaseMessage.includes("field_chat_daily_limit_reached")) {
    return publicHttpError(
      429,
      "Daily Field Chat limit reached.",
      "daily_limit_reached",
      3600,
    );
  }
  if (databaseMessage.includes("field_chat_conversation_limit_reached")) {
    return publicHttpError(
      429,
      "Conversation message limit reached.",
      "conversation_limit_reached",
    );
  }
  if (databaseMessage.includes("field_chat_conversation_not_found")) {
    return publicHttpError(
      404,
      "Field Chat conversation not found.",
      "conversation_not_found",
    );
  }
  if (databaseMessage.includes("field_chat_access_forbidden")) {
    return publicHttpError(
      403,
      "You do not have permission to use this Field Chat conversation.",
      "field_chat_access_forbidden",
    );
  }
  if (databaseMessage.includes("field_chat_invalid_request")) {
    return publicHttpError(
      400,
      "Field Chat request is invalid.",
      "field_chat_invalid_request",
    );
  }
  return publicHttpError(
    503,
    "Field Chat is temporarily unavailable. Please try again.",
    "field_chat_admission_unavailable",
    2,
  );
}

function singleAdmissionRow(data: unknown): FieldChatAdmissionRow | null {
  if (!Array.isArray(data) || data.length !== 1) return null;
  const row = data[0];
  if (!row || typeof row !== "object" || Array.isArray(row)) return null;
  return row as FieldChatAdmissionRow;
}

function isBoundUserMessage(
  value: unknown,
  input: {
    userId: string;
    conversationId: string;
    subjectType: FieldChatSubjectType;
    subjectId: string;
    messageText: string;
    clientMessageId: string;
  },
): value is StoredFieldChatUserMessage {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const message = value as Partial<StoredFieldChatUserMessage>;
  const subjectId = input.subjectType === "insight"
    ? message.scan_id
    : input.subjectType === "explore"
    ? message.post_id
    : message.species_dictionary_id;
  return (
    typeof message.id === "string" &&
    FIELD_CHAT_UUID_PATTERN.test(message.id) &&
    typeof message.conversation_id === "string" &&
    canonicalUuid(message.conversation_id) ===
      canonicalUuid(input.conversationId) &&
    typeof message.user_id === "string" &&
    canonicalUuid(message.user_id) === canonicalUuid(input.userId) &&
    typeof subjectId === "string" &&
    canonicalUuid(subjectId) === canonicalUuid(input.subjectId) &&
    message.role === "user" &&
    message.message_text === input.messageText &&
    typeof message.client_message_id === "string" &&
    canonicalUuid(message.client_message_id) ===
      canonicalUuid(input.clientMessageId)
  );
}

export async function reserveFieldChatSend<Message>(
  supabaseAdmin: SupabaseClient,
  input: {
    userId: string;
    conversationId: string;
    subjectType: FieldChatSubjectType;
    subjectId: string;
    messageText: string;
    clientMessageId: string;
  },
): Promise<FieldChatAdmission<Message>> {
  let result: {
    data: unknown;
    error: { message: string } | null;
  };
  try {
    result = await supabaseAdmin.rpc("reserve_field_chat_send", {
      p_user_id: input.userId,
      p_conversation_id: input.conversationId,
      p_subject_type: input.subjectType,
      p_subject_id: input.subjectId,
      p_message_text: input.messageText,
      p_client_message_id: input.clientMessageId,
    }).abortSignal(AbortSignal.timeout(5_000));
  } catch {
    throw admissionError("field_chat_admission_unavailable");
  }

  if (result.error) throw admissionError(result.error.message);
  const row = singleAdmissionRow(result.data);
  if (
    !row ||
    typeof row.is_replay !== "boolean" ||
    typeof row.conversation_id !== "string" ||
    !FIELD_CHAT_UUID_PATTERN.test(row.conversation_id) ||
    !Number.isSafeInteger(row.sends_today) ||
    (row.sends_today as number) < 0 ||
    !isBoundUserMessage(row.message, {
      ...input,
      conversationId: row.conversation_id,
    })
  ) {
    throw admissionError("field_chat_admission_unavailable");
  }

  return {
    conversationId: canonicalUuid(row.conversation_id as string),
    message: row.message as Message,
    isReplay: row.is_replay,
    sendsToday: row.sends_today as number,
  };
}

export async function recoverStaleFieldChatQuota(
  supabaseAdmin: SupabaseClient,
  input: {
    userId: string;
    operation:
      | "insight_chat_reply"
      | "explore_post_chat_reply"
      | "species_dictionary_chat_reply";
    requestId: string;
    conversationId: string;
    subjectId: string;
  },
): Promise<boolean> {
  let result: {
    data: unknown;
    error: { message: string } | null;
  };
  try {
    result = await supabaseAdmin.rpc("recover_stale_field_chat_quota", {
      p_user_id: input.userId,
      p_operation: input.operation,
      p_request_id: input.requestId,
      p_conversation_id: input.conversationId,
      p_subject_id: input.subjectId,
    }).abortSignal(AbortSignal.timeout(5_000));
  } catch {
    throw publicHttpError(
      503,
      "Field Chat recovery is temporarily unavailable.",
      "field_chat_recovery_unavailable",
      2,
    );
  }

  if (result.error || typeof result.data !== "boolean") {
    throw publicHttpError(
      503,
      "Field Chat recovery is temporarily unavailable.",
      "field_chat_recovery_unavailable",
      2,
    );
  }
  return result.data;
}
