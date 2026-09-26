/** No environment lookup or production composition; callers supply a reviewed key. */
import { fetchWithDeadline, readResponseJsonWithinLimit } from "../outbound.ts";
import type {
  AIAdapter,
  AIProviderOutcome,
  AIRequest,
  AIResponseFacts,
  AIUsage,
} from "./contracts.ts";
import {
  buildOpenAIRequestParameters,
  decodeOpenAIDraft,
  type OpenAIEvaluationSnapshot,
} from "./openaiRequest.ts";

export const OPENAI_RESPONSES_URL = "https://api.openai.com/v1/responses";
export const OPENAI_RESPONSE_LIMIT = 512 * 1024;
const object = (v: unknown): Record<string, unknown> | null =>
  v !== null && typeof v === "object" && !Array.isArray(v)
    ? v as Record<string, unknown>
    : null;
const count = (v: unknown): number | null =>
  typeof v === "number" && Number.isSafeInteger(v) && v >= 0 && v <= 100000000
    ? v
    : null;
function usageFrom(value: unknown): AIUsage | null {
  const u = object(value);
  if (!u) return null;
  const input = count(u.input_tokens),
    output = count(u.output_tokens),
    reasoning = count(object(u.output_tokens_details)?.reasoning_tokens),
    cached = count(object(u.input_tokens_details)?.cached_tokens),
    writes = count(object(u.input_tokens_details)?.cache_write_tokens);
  return {
    promptTokens: input,
    // Responses output_tokens ALREADY includes reasoning. Never add it twice.
    candidateTokens:
      output !== null && reasoning !== null && reasoning <= output
        ? output - reasoning
        : null,
    thinkingTokens: reasoning,
    totalTokens: count(u.total_tokens),
    cachedTokens: cached,
    cacheWriteTokens: input !== null && cached !== null && writes !== null &&
        cached + writes <= input
      ? writes
      : null,
    toolTokens: 0, // This binding sends tools: []; unexpected output tools are rejected.
    modalityBreakdown: {}, // Responses does not report these modality counts.
  };
}
function decode(
  value: unknown,
  timing: Pick<AIResponseFacts, "providerDurationMs" | "providerCompletedAt">,
): AIProviderOutcome {
  const raw = object(value), status = raw?.status;
  const facts: AIResponseFacts = {
    ...timing,
    returnedModel: typeof raw?.model === "string" &&
        /^gpt-6-sol(?:-[a-zA-Z0-9.-]{1,80})?$/.test(raw.model)
      ? raw.model
      : null,
    usage: usageFrom(raw?.usage),
    finishReason: typeof status === "string" &&
        [
          "completed",
          "incomplete",
          "failed",
          "cancelled",
          "queued",
          "in_progress",
        ].includes(status)
      ? status
      : null,
    responseCharacters: 0,
  };
  if (status === "queued" || status === "in_progress" || !raw) {
    return { ...facts, kind: "unknown_execution" };
  }
  if (
    status === "incomplete" &&
    object(raw.incomplete_details)?.reason === "content_filter"
  ) return { ...facts, kind: "refusal" };
  if (status !== "completed") {
    return { ...facts, kind: "invalid_output", reason: "finish" };
  }
  if (!Array.isArray(raw.output)) {
    return { ...facts, kind: "invalid_output", reason: "json" };
  }
  const texts: string[] = [];
  let messages = 0, refused = false;
  for (const item of raw.output) {
    const message = object(item);
    if (message?.type === "reasoning") continue; // Never expose or persist reasoning items.
    if (
      message?.type !== "message" || message.role !== "assistant" ||
      message.status !== "completed" || !Array.isArray(message.content)
    ) {
      return { ...facts, kind: "invalid_output", reason: "finish" };
    }
    messages++;
    for (const partValue of message.content) {
      const part = object(partValue);
      if (part?.type === "refusal") refused = true;
      else if (part?.type === "output_text" && typeof part.text === "string") {
        texts.push(part.text);
      } else return { ...facts, kind: "invalid_output", reason: "json" };
    }
  }
  if (refused) return { ...facts, kind: "refusal" };
  if (messages !== 1 || texts.length !== 1) {
    return { ...facts, kind: "invalid_output", reason: "json" };
  }
  try {
    return {
      ...facts,
      responseCharacters: texts[0].length,
      kind: "draft",
      draft: decodeOpenAIDraft(JSON.parse(texts[0])),
    };
  } catch {
    return { ...facts, kind: "invalid_output", reason: "json" };
  }
}
export function createOpenAIEvaluationAdapter(
  credential: string,
  fetcher: typeof fetch = fetch,
): AIAdapter<OpenAIEvaluationSnapshot> {
  if (!credential || credential.length > 512 || /\s/.test(credential)) {
    throw new Error("openai_credential_invalid");
  }
  return Object.freeze({
    provider: "openai",
    prepare(request: AIRequest, snapshot: OpenAIEvaluationSnapshot) {
      // Capture serialized evidence now; later caller mutation cannot change dispatch.
      const body = JSON.stringify(
        buildOpenAIRequestParameters(request, snapshot),
      );
      if (new TextEncoder().encode(body).length > 8 * 1024 * 1024) {
        throw new Error("openai_input_unsupported");
      }
      const timeoutMs = snapshot.timeoutMs;
      return async (): Promise<AIProviderOutcome> => {
        const start = performance.now();
        const timing = () => ({
          providerDurationMs: Math.max(0, performance.now() - start),
          providerCompletedAt: Date.now(),
        });
        const failed = (
          kind: "unknown_execution" | "operational_failure",
        ): AIProviderOutcome => ({
          ...timing(),
          kind,
          returnedModel: null,
          usage: null,
          finishReason: null,
          responseCharacters: 0,
        });
        try {
          const response = await fetchWithDeadline(OPENAI_RESPONSES_URL, {
            method: "POST",
            redirect: "error",
            headers: {
              "Content-Type": "application/json",
              "Authorization": `Bearer ${credential}`,
            },
            body,
          }, { fetcher, timeoutMs });
          if (!response.ok) {
            await response.body?.cancel();
            return failed(
              [400, 401, 403, 404, 413, 422, 429].includes(response.status)
                ? "operational_failure"
                : "unknown_execution",
            );
          }
          const value = await readResponseJsonWithinLimit(
            response,
            OPENAI_RESPONSE_LIMIT,
          );
          return decode(value, timing());
        } catch {
          // Timeout, disconnect, oversized/malformed envelope or 5xx may have executed.
          // No response body, provider diagnostic, key or evidence escapes this adapter.
          return failed("unknown_execution");
        }
      };
    },
  });
}
