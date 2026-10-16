import {
  buildFieldChatReplyRequest,
  extractFieldChatReplyJson,
} from "../_shared/fieldChat/reply.ts";
import {
  fetchWithDeadline,
  readResponseJsonWithinLimit,
} from "../_shared/outbound.ts";
import { parseProtectedChatReply } from "./protectedReply.ts";
import {
  boundedStoredJSON,
  exactStoredObject,
  storedObject,
} from "./storedContextContract.ts";

export const PROTECTED_CHAT_PROVIDER_MS = 90_000;
const MODEL = "gemini-2.5-flash";
function unknown(): never {
  throw new Error("field_chat_execution_held");
}
function count(value: unknown): number | null {
  if (value === undefined || value === null) return null;
  if (
    typeof value !== "number" || !Number.isInteger(value) || value < 0 ||
    value > 2147483647
  ) return unknown();
  return value;
}
function modalities(value: unknown) {
  if (value === undefined) return {};
  if (!Array.isArray(value) || value.length > 6) return unknown();
  const result: Record<string, number> = {};
  for (const item of value) {
    const row = exactStoredObject(item, ["modality", "tokenCount"]);
    if (typeof row.modality !== "string") return unknown();
    const key = row.modality.toLowerCase();
    if (
      !["text", "image", "audio", "video", "document", "unspecified"].includes(
        key,
      ) || Object.hasOwn(result, key)
    ) return unknown();
    const tokens = count(row.tokenCount);
    if (tokens === null) return unknown();
    result[key] = tokens;
  }
  return result;
}
function safety(value: unknown) {
  if (value === undefined) return;
  if (!Array.isArray(value) || value.length > 16) return unknown();
  for (const entry of value) {
    const rating = storedObject(entry);
    if (rating.blocked !== undefined && rating.blocked !== false) {
      return unknown();
    }
  }
}
/** Closed normalization; malformed accounting is uncertainty, never invented usage. */
export function decodeProtectedChatProvider(value: unknown) {
  boundedStoredJSON(value, 32 * 1024);
  const root = storedObject(value);
  if (
    root.modelVersion !== MODEL || !Array.isArray(root.candidates) ||
    root.candidates.length !== 1
  ) return unknown();
  if (
    root.promptFeedback !== undefined &&
    storedObject(root.promptFeedback).blockReason !== undefined
  ) return unknown();
  if (root.promptFeedback !== undefined) {
    safety(storedObject(root.promptFeedback).safetyRatings);
  }
  const candidate = storedObject(root.candidates[0]);
  safety(candidate.safetyRatings);
  if (candidate.finishReason !== "STOP") return unknown();
  const content = storedObject(candidate.content);
  if (
    content.role !== "model" || !Array.isArray(content.parts) ||
    content.parts.length !== 1
  ) return unknown();
  const part = exactStoredObject(content.parts[0], ["text"]);
  if (typeof part.text !== "string") return unknown();
  const answer = exactStoredObject(extractFieldChatReplyJson(part.text), [
    "answer",
    "is_refusal",
    "refusal_reason",
  ]);
  if (
    typeof answer.answer !== "string" ||
    typeof answer.is_refusal !== "boolean" ||
    (answer.refusal_reason !== null &&
      typeof answer.refusal_reason !== "string")
  ) return unknown();
  const text = answer.answer.trim();
  if (!text || [...text].length > 4000) return unknown();
  const reason = answer.is_refusal && typeof answer.refusal_reason === "string"
    ? answer.refusal_reason.trim()
    : null;
  let usage = null;
  if (root.usageMetadata !== undefined && root.usageMetadata !== null) {
    const raw = storedObject(root.usageMetadata);
    usage = {
      prompt_tokens: count(raw.promptTokenCount),
      candidate_tokens: count(raw.candidatesTokenCount),
      thinking_tokens: count(raw.thoughtsTokenCount),
      total_tokens: count(raw.totalTokenCount),
      cached_tokens: count(raw.cachedContentTokenCount),
      modality_breakdown: {
        prompt: modalities(raw.promptTokensDetails),
        cached: modalities(raw.cacheTokensDetails),
        candidates: modalities(raw.candidatesTokensDetails),
        tool: modalities(raw.toolUsePromptTokensDetails),
      },
    };
  }
  return parseProtectedChatReply({
    answer: text,
    model: MODEL,
    is_refusal: answer.is_refusal,
    refusal_reason: reason,
    usage,
  });
}
/** Prepare before the irreversible grant; only its execution owner invokes once afterward. */
export function prepareProtectedChatProvider(
  systemInstruction: string,
  userPrompt: string,
  model: string,
  dependencies: { apiKey?: () => string | undefined; fetcher?: typeof fetch } =
    {},
) {
  if (model !== MODEL) return unknown();
  const apiKey =
    (dependencies.apiKey ?? (() => Deno.env.get("GEMINI_PAID_API_KEY")))()
      ?.trim();
  if (!apiKey) return unknown();
  const request = buildFieldChatReplyRequest(
    systemInstruction,
    userPrompt,
    model,
  );
  const config = request.config!;
  const body = JSON.stringify({
    systemInstruction: { role: "user", parts: [{ text: systemInstruction }] },
    contents: request.contents,
    generationConfig: {
      temperature: config.temperature,
      maxOutputTokens: config.maxOutputTokens,
      responseMimeType: config.responseMimeType,
      responseSchema: config.responseSchema,
      thinkingConfig: config.thinkingConfig,
      candidateCount: 1,
    },
  });
  if (new TextEncoder().encode(body).byteLength > 192 * 1024) return unknown();
  let invoked = false;
  return async (signal: AbortSignal) => {
    if (invoked) return unknown();
    invoked = true;
    const deadline = AbortSignal.any([
      signal,
      AbortSignal.timeout(PROTECTED_CHAT_PROVIDER_MS),
    ]);
    try {
      deadline.throwIfAborted();
      const response = await fetchWithDeadline(
        `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`,
        {
          method: "POST",
          redirect: "error",
          signal: deadline,
          headers: {
            "Content-Type": "application/json",
            "x-goog-api-key": apiKey,
          },
          body,
        },
        {
          fetcher: dependencies.fetcher,
          timeoutMs: PROTECTED_CHAT_PROVIDER_MS,
        },
      );
      if (
        !response.ok ||
        response.headers.get("content-type")?.split(";")[0].trim()
            .toLowerCase() !== "application/json"
      ) {
        void response.body?.cancel().catch(() => {});
        return unknown();
      }
      const bounded = response.body
        ? new Response(
          response.body.pipeThrough(
            new TransformStream<Uint8Array, Uint8Array>(),
            { signal: deadline },
          ),
          { headers: response.headers, status: response.status },
        )
        : response;
      const result = await readResponseJsonWithinLimit(bounded, 32 * 1024);
      deadline.throwIfAborted();
      return decodeProtectedChatProvider(result);
    } catch {
      return unknown();
    }
  };
}
