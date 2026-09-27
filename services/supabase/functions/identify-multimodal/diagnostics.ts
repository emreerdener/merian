import {
  AUDIO_PROMPT_COMPARISON_HEADER,
  type AudioPromptComparison,
  audioPromptComparisonReceipt,
} from "./comparison/promptAssignment.ts";
import type { AIExecutionOutcome } from "../_shared/ai/contracts.ts";
import { corsHeaders } from "../_shared/http.ts";
import { IDENTIFICATION_BUNDLE_SHA256 } from "./deploymentIdentity.ts";

import {
  AUDIO_COMPARISON_HEADER,
  type AudioComparison,
  audioComparisonReceipt,
} from "./comparison/assignment.ts";

export const IDENTIFICATION_DIAGNOSTICS_HEADER = "X-Merian-Identification";

function tokens(value: number | null | undefined): number | null {
  return typeof value === "number" && Number.isSafeInteger(value) &&
      value >= 0 && value <= 10_000_000
    ? value
    : null;
}

/** Only attach to a fresh successful primary attempt, after durable completion.
 * Never serialize the provider outcome, draft, modality map or caller identifiers.
 */
export function identificationDiagnosticHeaders(
  result: AIExecutionOutcome,
  comparison: AudioComparison | null = null,
  promptComparison: AudioPromptComparison | null = null,
): Record<string, string> {
  const usage = result.usage;
  const metadata = {
    version: 1,
    provider: result.execution.provider,
    requestedModel: result.execution.model,
    returnedModel: result.returnedModel &&
        result.returnedModel.trim() === result.returnedModel &&
        /^gemini-[a-zA-Z0-9.-]{1,100}$/.test(result.returnedModel)
      ? result.returnedModel
      : null,
    backendBundleSha256: IDENTIFICATION_BUNDLE_SHA256,
    usage: usage
      ? {
        promptTokens: tokens(usage.promptTokens),
        candidateTokens: tokens(usage.candidateTokens),
        thinkingTokens: tokens(usage.thinkingTokens),
        totalTokens: tokens(usage.totalTokens),
        cachedTokens: tokens(usage.cachedTokens),
        toolTokens: tokens(usage.toolTokens),
      }
      : null,
  };
  return {
    [IDENTIFICATION_DIAGNOSTICS_HEADER]: JSON.stringify(metadata),
    ...(comparison
      ? { [AUDIO_COMPARISON_HEADER]: audioComparisonReceipt(comparison) }
      : {}),
    ...(promptComparison
      ? {
        [AUDIO_PROMPT_COMPARISON_HEADER]: audioPromptComparisonReceipt(
          promptComparison,
        ),
      }
      : {}),
    "Access-Control-Expose-Headers": `${
      corsHeaders["Access-Control-Expose-Headers"]
    }, ${IDENTIFICATION_DIAGNOSTICS_HEADER}, X-Merian-Idempotent-Replay${
      comparison ? `, ${AUDIO_COMPARISON_HEADER}` : ""
    }${promptComparison ? `, ${AUDIO_PROMPT_COMPARISON_HEADER}` : ""}`,
  };
}
