import type { CompatibilityMediaAIRequest } from "../_shared/ai/contracts.ts";
import {
  buildContextText,
  type TelemetryContextInput,
} from "../_shared/identify/context.ts";

/** Accept only the caller's already validated and processed WAV evidence. */
export function buildAudioAIRequest(
  processedWav: string,
  telemetry: TelemetryContextInput,
): CompatibilityMediaAIRequest {
  return {
    task: "identify",
    variant: "audio_compat",
    evidence: [
      {
        kind: "text",
        source: "capture_context",
        order: 0,
        text: buildContextText(
          telemetry,
          "Perform bioacoustic identification.",
        ),
      },
      {
        kind: "audio",
        order: 1,
        data: processedWav,
        mimeType: "audio/wav",
        inputIndex: 0,
        lineage: { kind: "audio", sourceIndex: 0 },
      },
    ],
  };
}
