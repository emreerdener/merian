import type { DescribeAIRequest } from "../_shared/ai/contracts.ts";
import {
  buildObservationPrompt,
  type TelemetryContextInput,
} from "../_shared/identify/context.ts";

export function buildDescribeAIRequest(
  description: string,
  telemetry: TelemetryContextInput,
): DescribeAIRequest {
  return {
    task: "identify",
    variant: "description_compat",
    evidence: [{
      kind: "text",
      source: "description",
      order: 0,
      text: buildObservationPrompt(description, telemetry),
    }],
  };
}
