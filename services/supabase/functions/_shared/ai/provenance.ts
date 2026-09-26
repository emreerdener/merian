import type { AIAttemptSnapshot } from "./contracts.ts";

/**
 * Content-free, durable configuration of a successful identification. The scan
 * shares these fixed configuration facts under its existing visibility policy.
 * Never add evidence, free-form provider output, account/attempt IDs or timing.
 * Version this shape when a future adapter needs different generation settings.
 */
export interface IdentificationProvenance {
  version: 1;
  provider: string;
  binding: string;
  model: string;
  variant: string;
  operation: string;
  policy_version: number;
  prompt: string;
  schema: string;
  confidence: string;
  diagnostic_trigger: number | null;
  prompt_diagnostic_trigger: number | null;
  safety: string | null;
  timeout_ms: number;
  generation: {
    temperature: number;
    seed: number | null;
    top_k: number | null;
    max_output_tokens: number;
    thinking_budget: number | null;
  };
}

/** Project only the admitted, immutable execution snapshot, never model JSON. */
export function identificationProvenance(
  snapshot: AIAttemptSnapshot,
): IdentificationProvenance {
  if (
    snapshot.task !== "identify" || snapshot.contextKind !== "user_request" ||
    snapshot.confidence === null || snapshot.policyVersion === null
  ) throw new Error("identification_provenance_authority_invalid");

  return Object.freeze({
    version: 1,
    provider: snapshot.provider,
    binding: snapshot.binding,
    model: snapshot.model,
    variant: snapshot.variant,
    operation: snapshot.operation,
    policy_version: snapshot.policyVersion,
    prompt: snapshot.prompt,
    schema: snapshot.schema,
    confidence: snapshot.confidence,
    diagnostic_trigger: snapshot.diagnosticTrigger ?? null,
    prompt_diagnostic_trigger: snapshot.promptDiagnosticTrigger ?? null,
    safety: snapshot.safety ?? null,
    timeout_ms: snapshot.timeoutMs,
    generation: Object.freeze({
      temperature: snapshot.generation.temperature,
      seed: snapshot.generation.seed ?? null,
      top_k: snapshot.generation.topK ?? null,
      max_output_tokens: snapshot.generation.maxOutputTokens,
      thinking_budget: snapshot.generation.thinkingBudget ?? null,
    }),
  });
}
