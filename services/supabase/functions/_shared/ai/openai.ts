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
import {
  buildOpenAIPhotoRequestParameters,
  openAIPhotoSafety,
  type OpenAIPhotoSnapshot,
} from "./openaiPhoto.ts";

import {
  buildOpenAIPhotoModelRequestParameters,
  type OpenAIPhotoModel,
  type OpenAIPhotoModelSnapshot,
} from "./openaiPhotoModels.ts";

import {
  buildSolPhotoRankRequest,
  solPhotoRankSnapshot,
} from "./openaiSolRank.ts";

import {
  buildSolPhotoPrimaryRequest,
  solPhotoPrimarySnapshot,
} from "./openaiSolPrimary.ts";
import { decodeSolPhotoPrimaryDraft } from "./openaiSolPrimaryContract.ts";
import {
  buildOpenAIConfidenceRequest,
  openAIConfidenceSnapshot,
} from "./openaiPhotoConfidence.ts";

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
    outputTokens: output,
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
  expectedModel: OpenAIPhotoModel = "gpt-6-sol",
  decodeDraft: (value: unknown) => unknown = decodeOpenAIDraft,
): AIProviderOutcome {
  const raw = object(value), status = raw?.status;
  const usage = usageFrom(raw?.usage);
  const unexpectedOutput = Array.isArray(raw?.output) &&
    raw.output.some((item) =>
      !["message", "reasoning"].includes(String(object(item)?.type))
    );
  const facts: AIResponseFacts = {
    ...timing,
    serviceTier: raw?.service_tier === "default" && raw?.model === expectedModel
      ? "default"
      : null,
    returnedModel: typeof raw?.model === "string" &&
        new RegExp(`^${expectedModel}(?:-[a-zA-Z0-9.-]{1,80})?$`).test(
          raw.model,
        )
      ? raw.model
      : null,
    usage: usage && unexpectedOutput ? { ...usage, toolTokens: null } : usage,
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
      return {
        ...facts,
        usage: facts.usage ? { ...facts.usage, toolTokens: null } : null,
        kind: "invalid_output",
        reason: "finish",
      };
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
      draft: decodeDraft(JSON.parse(texts[0])),
    };
  } catch {
    return { ...facts, kind: "invalid_output", reason: "json" };
  }
}
export function createOpenAIEvaluationAdapter(
  credential: string,
  fetcher: typeof fetch = fetch,
): AIAdapter<OpenAIEvaluationSnapshot> {
  return createOpenAIAdapter(credential, fetcher, (request, snapshot) => ({
    parameters: buildOpenAIRequestParameters(request, snapshot),
    decode,
  }));
}

/** Photo-only transport; production requires the exact database-admitted binding. */
export function createOpenAIPhotoAdapter(
  credential: string,
  fetcher: typeof fetch = fetch,
): AIAdapter<OpenAIPhotoSnapshot> {
  return createOpenAIAdapter(credential, fetcher, (request, snapshot) => {
    const parameters = buildOpenAIPhotoRequestParameters(request, snapshot);
    const hasText = parameters.input[0].content.some((part) =>
      part.type === "input_text"
    );
    return {
      parameters,
      decode: (value, timing) => decodeModeratedPhoto(value, timing, hasText),
    };
  });
}

/** Evaluator-only transport; callers still need a separately admitted run. */
export function createOpenAIPhotoModelEvaluationAdapter(
  credential: string,
  fetcher: typeof fetch = fetch,
): AIAdapter<OpenAIPhotoModelSnapshot> {
  return createOpenAIAdapter(credential, fetcher, (request, snapshot) => {
    const parameters = buildOpenAIPhotoModelRequestParameters(
      request,
      snapshot,
    );
    const hasText = parameters.input[0].content.some((part) =>
      part.type === "input_text"
    );
    const expectedModel = snapshot.model;
    return {
      parameters,
      decode: (value, timing) =>
        decodeModeratedPhoto(value, timing, hasText, expectedModel, true),
    };
  });
}

/** Closed Sol-rank evaluation adapter; never a production catalog binding. */
export function createOpenAISolRankEvaluationAdapter(
  credential: string,
  fetcher: typeof fetch = fetch,
): AIAdapter<ReturnType<typeof solPhotoRankSnapshot>> {
  return createOpenAIAdapter(credential, fetcher, (request, snapshot) => {
    const parameters = buildSolPhotoRankRequest(request, snapshot);
    const hasText = parameters.input[0].content.some((p) =>
      p.type === "input_text"
    );
    return {
      parameters,
      decode: (value, timing) =>
        decodeModeratedPhoto(value, timing, hasText, "gpt-6-sol", true),
    };
  });
}

/** Explicit-primary evaluator only; never selected by production composition. */
export function createOpenAISolPrimaryEvaluationAdapter(
  credential: string,
  fetcher: typeof fetch = fetch,
): AIAdapter<ReturnType<typeof solPhotoPrimarySnapshot>> {
  return createOpenAIAdapter(credential, fetcher, (request, snapshot) => {
    const parameters = buildSolPhotoPrimaryRequest(request, snapshot);
    const hasText = parameters.input[0].content.some((p) =>
      p.type === "input_text"
    );
    return {
      parameters,
      decode: (value, timing) =>
        decodeModeratedPhoto(
          value,
          timing,
          hasText,
          "gpt-6-sol",
          true,
          decodeSolPhotoPrimaryDraft,
        ),
    };
  });
}

/** Prepared confidence assessment only; active production still uses its exact snapshot. */
export function createOpenAIConfidenceEvaluationAdapter(
  credential: string,
  fetcher: typeof fetch = fetch,
): AIAdapter<ReturnType<typeof openAIConfidenceSnapshot>> {
  return createOpenAIAdapter(credential, fetcher, (request, snapshot) => {
    const parameters = buildOpenAIConfidenceRequest(request, snapshot);
    const hasText = parameters.input[0].content.some((p) =>
      p.type === "input_text"
    );
    return {
      parameters,
      decode: (value, timing) => decodeModeratedPhoto(value, timing, hasText),
    };
  });
}

function decodeModeratedPhoto(
  value: unknown,
  timing: Pick<AIResponseFacts, "providerDurationMs" | "providerCompletedAt">,
  hasText: boolean,
  expectedModel: OpenAIPhotoModel = "gpt-6-sol",
  exactModel = false,
  decodeDraft: (value: unknown) => unknown = decodeOpenAIDraft,
): AIProviderOutcome {
  const outcome = decode(value, timing, expectedModel, decodeDraft);
  const mediaSafety = openAIPhotoSafety(
    object(value)?.moderation,
    hasText,
  );
  if (mediaSafety.disposition === "rejected") {
    const { kind: _kind, draft: _draft, reason: _reason, ...facts } = {
      draft: undefined,
      reason: undefined,
      ...outcome,
    };
    // A native denial stays terminal even if generated JSON is malformed.
    return { ...facts, mediaSafety, kind: "refusal" };
  }
  if (outcome.kind !== "draft") return { ...outcome, mediaSafety };
  const { draft, kind: _kind, ...facts } = outcome;
  if (
    mediaSafety.disposition !== "allowed" || facts.returnedModel === null ||
    (exactModel && facts.returnedModel !== expectedModel)
  ) {
    return {
      ...facts,
      mediaSafety,
      kind: "invalid_output",
      reason: "safety",
    };
  }
  return { ...facts, mediaSafety, kind: "draft", draft };
}

function createOpenAIAdapter<Snapshot extends { readonly timeoutMs: number }>(
  credential: string,
  fetcher: typeof fetch,
  prepare: (request: AIRequest, snapshot: Snapshot) => {
    parameters: unknown;
    decode: typeof decode;
  },
): AIAdapter<Snapshot> {
  if (!credential || credential.length > 512 || /\s/.test(credential)) {
    throw new Error("openai_credential_invalid");
  }
  return Object.freeze({
    provider: "openai",
    prepare(request: AIRequest, snapshot: Snapshot) {
      const prepared = prepare(request, snapshot);
      // Capture serialized evidence now; later caller mutation cannot change dispatch.
      const body = JSON.stringify(
        prepared.parameters,
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
          return prepared.decode(value, timing());
        } catch {
          // Timeout, disconnect, oversized/malformed envelope or 5xx may have executed.
          // No response body, provider diagnostic, key or evidence escapes this adapter.
          return failed("unknown_execution");
        }
      };
    },
  });
}
