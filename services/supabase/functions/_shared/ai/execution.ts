import type {
  AIAdapter,
  AIAttemptSnapshot,
  AIExecutionOutcome,
  AIRequest,
  PreparedAIExecution,
} from "./contracts.ts";

/** Content-free facts for existing optional analytics and usage metadata. */
export function aiExecutionMetadata(
  result: AIExecutionOutcome,
): Record<string, unknown> {
  return {
    ai_task: result.execution.task,
    ai_provider: result.execution.provider,
    ai_binding: result.execution.binding,
    ai_prompt: result.execution.prompt,
    ai_schema: result.execution.schema,
    ai_policy_version: result.execution.policyVersion,
    ai_context_kind: result.execution.contextKind,
    ai_returned_model: result.returnedModel,
    ai_provider_duration_ms: result.providerDurationMs,
    ai_outcome: result.kind,
  };
}

/** One invocation per admitted attempt; no admission, retries or settlement. */
export function createAIExecution(
  adapter: AIAdapter,
  request: AIRequest,
  snapshot: AIAttemptSnapshot,
): PreparedAIExecution {
  const invoke = adapter.prepare(request, snapshot);
  let started = false;
  return Object.freeze({
    snapshot,
    async invoke() {
      if (started) throw new Error("ai_attempt_already_invoked");
      started = true;
      const start = performance.now();
      const result = await invoke();
      return {
        ...result,
        execution: {
          ...snapshot,
          durationMs: Math.max(0, performance.now() - start),
        },
      };
    },
  });
}
