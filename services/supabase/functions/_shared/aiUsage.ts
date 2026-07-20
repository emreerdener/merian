import { SupabaseClient } from "@supabase/supabase-js";
import { logStructuredError, runBackground } from "./edgeHandler.ts";

export interface GeminiTokenModalityDetail {
  modality?: string;
  tokenCount?: number;
}

export interface GeminiUsageMetadata {
  promptTokenCount?: number;
  cachedContentTokenCount?: number;
  candidatesTokenCount?: number;
  thoughtsTokenCount?: number;
  toolUsePromptTokenCount?: number;
  totalTokenCount?: number;
  promptTokensDetails?: GeminiTokenModalityDetail[];
  cacheTokensDetails?: GeminiTokenModalityDetail[];
  candidatesTokensDetails?: GeminiTokenModalityDetail[];
  toolUsePromptTokensDetails?: GeminiTokenModalityDetail[];
}

export type AIUsageOutcome = "success" | "refusal" | "error";
export type AIInputModality =
  | "text"
  | "image"
  | "audio"
  | "video"
  | "mixed"
  | "unknown";

export interface AIUsageEventInput {
  operation: string;
  model: string;
  usage?: GeminiUsageMetadata | null;
  effectivePlan?: "free" | "pro_paid" | "pro_trial" | "unknown";
  inputModality?: AIInputModality;
  outcome?: AIUsageOutcome;
  userId?: string | null;
  scanId?: string | null;
  conversationId?: string | null;
  messageId?: string | null;
  sourceType?: string | null;
  sourceId?: string | null;
  metadata?: Record<string, unknown>;
  occurredAt?: string;
}

function detailsByModality(
  details: GeminiTokenModalityDetail[] | undefined,
): Record<string, number> {
  const output: Record<string, number> = {};
  for (const detail of details ?? []) {
    const modality = detail.modality?.trim().toLowerCase();
    const count = detail.tokenCount;
    if (!modality || typeof count !== "number" || !Number.isFinite(count)) {
      continue;
    }
    output[modality] = (output[modality] ?? 0) + Math.max(0, count);
  }
  return output;
}

export function geminiUsageModalityBreakdown(
  usage: GeminiUsageMetadata | null | undefined,
): Record<string, unknown> {
  if (!usage) return {};
  return {
    prompt: detailsByModality(usage.promptTokensDetails),
    cached: detailsByModality(usage.cacheTokensDetails),
    candidates: detailsByModality(usage.candidatesTokensDetails),
    tool: detailsByModality(usage.toolUsePromptTokensDetails),
  };
}

export async function recordAIUsageEvent(
  supabaseAdmin: SupabaseClient,
  input: AIUsageEventInput,
): Promise<string | null> {
  const usage = input.usage;
  const { data, error } = await supabaseAdmin.rpc("record_ai_usage_event", {
    p_operation: input.operation,
    p_model: input.model,
    p_effective_plan: input.effectivePlan ?? "unknown",
    p_input_modality: input.inputModality ?? "unknown",
    p_prompt_tokens: usage?.promptTokenCount ?? null,
    p_cached_tokens: usage?.cachedContentTokenCount ?? null,
    p_candidate_tokens: usage?.candidatesTokenCount ?? null,
    p_thinking_tokens: usage?.thoughtsTokenCount ?? null,
    p_tool_tokens: usage?.toolUsePromptTokenCount ?? null,
    p_total_tokens: usage?.totalTokenCount ?? null,
    p_prompt_tokens_by_modality: geminiUsageModalityBreakdown(usage),
    p_outcome: input.outcome ?? "success",
    p_user_id: input.userId ?? null,
    p_scan_id: input.scanId ?? null,
    p_conversation_id: input.conversationId ?? null,
    p_message_id: input.messageId ?? null,
    p_source_type: input.sourceType ?? null,
    p_source_id: input.sourceId ?? null,
    p_metadata: input.metadata ?? {},
    p_occurred_at: input.occurredAt ?? new Date().toISOString(),
  }).abortSignal(AbortSignal.timeout(3_000));

  if (error) {
    throw new Error(`AI usage ledger write failed: ${error.message}`);
  }
  return typeof data === "string" ? data : null;
}

export function recordAIUsageBestEffort(
  supabaseAdmin: SupabaseClient,
  input: AIUsageEventInput,
): void {
  runBackground(
    recordAIUsageEvent(supabaseAdmin, input).then(() => undefined).catch(
      (error: unknown) => {
        logStructuredError("ai_usage_ledger_write_failed", {
          operation: input.operation,
          model: input.model,
          error: error instanceof Error ? error.message : String(error),
        });
      },
    ),
  );
}
