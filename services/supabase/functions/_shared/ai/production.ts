import type { AIExecutionAuthority, AIRequest } from "./contracts.ts";
import { createAIExecution } from "./execution.ts";
import { geminiAdapter } from "./gemini.ts";
import { resolveAIClaim } from "./registry.ts";

/** The sole production composition. No adapter argument or runtime override. */
export function prepareAIExecution(
  request: AIRequest,
  authority: AIExecutionAuthority,
) {
  const snapshot = resolveAIClaim(request, authority);
  return createAIExecution(geminiAdapter, request, snapshot);
}
