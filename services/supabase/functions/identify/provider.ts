import type {
  CompatibilityMediaAIRequest,
  IdentifyEvidence,
} from "../_shared/ai/contracts.ts";
import {
  buildContextText,
  type TelemetryContextInput,
} from "../_shared/identify/context.ts";

/** Preserve legacy context -> images -> optional description ordering. */
export function buildVisionAIRequest(input: {
  imageBase64s: string[];
  mimeType?: string;
  description?: string;
  telemetry: TelemetryContextInput;
}): CompatibilityMediaAIRequest {
  const evidence: IdentifyEvidence[] = [{
    kind: "text",
    source: "capture_context",
    order: 0,
    text: buildContextText(
      input.telemetry,
      "Perform biological identification.",
    ),
  }];
  input.imageBase64s.forEach((data, inputIndex) =>
    evidence.push({
      kind: "image",
      order: evidence.length,
      data,
      mimeType: input.mimeType || "image/webp",
      inputIndex,
      lineage: { kind: "image", sourceIndex: inputIndex },
    })
  );
  if (input.description && input.description.trim().length > 0) {
    evidence.push({
      kind: "text",
      source: "observation_context",
      order: evidence.length,
      text:
        `\n\nAdditional observation context from user:\n${input.description.trim()}`,
    });
  }
  return { task: "identify", variant: "vision_compat", evidence };
}
