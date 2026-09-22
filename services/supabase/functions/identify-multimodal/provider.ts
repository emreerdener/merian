import type {
  IdentifyEvidence,
  MultimodalAIRequest,
} from "../_shared/ai/contracts.ts";
import {
  buildContextText,
  type TelemetryContextInput,
} from "../_shared/identify/context.ts";
import {
  type AudioMediaDescriptor,
  buildVisualMediaPrompt,
  type VisualMediaDescriptor,
} from "./capturedMedia.ts";

/** Receives only resolved evidence; ownership, WAV processing and bounds stay
 * with the caller. Preserve the existing text -> images -> WAVs -> context order.
 */
export function buildMultimodalAIRequest(input: {
  observationEvidenceTexts: string[];
  visualMediaItems: VisualMediaDescriptor[];
  imageBase64s: string[];
  imageMimeType: string;
  processedAudios: string[];
  audioMediaItems: AudioMediaDescriptor[];
  processedAudioInputIndexes: number[];
  hasVideoAudio: boolean;
  capture: MultimodalAIRequest["capture"];
  telemetry: TelemetryContextInput;
}): MultimodalAIRequest {
  const evidence: IdentifyEvidence[] = [];
  if (input.observationEvidenceTexts.length > 0) {
    evidence.push({
      kind: "text",
      source: "observation_context",
      order: evidence.length,
      text: `Additional observation context from user:\n${
        input.observationEvidenceTexts.join("\n")
      }`,
    });
  }
  const visualPrompt = buildVisualMediaPrompt(
    input.visualMediaItems,
    input.capture.hasVideo,
    input.imageBase64s.length,
    input.hasVideoAudio,
  );
  if (visualPrompt) {
    evidence.push({
      kind: "text",
      source: "visual_context",
      order: evidence.length,
      text: visualPrompt,
    });
  }
  input.imageBase64s.forEach((data, inputIndex) => {
    evidence.push({
      kind: "image",
      order: evidence.length,
      data,
      mimeType: input.imageMimeType,
      inputIndex,
      lineage: input.visualMediaItems[inputIndex]
        ? structuredClone(input.visualMediaItems[inputIndex])
        : null,
    });
  });
  input.processedAudios.forEach((data, index) => {
    evidence.push({
      kind: "audio",
      order: evidence.length,
      data,
      mimeType: "audio/wav",
      inputIndex: input.processedAudioInputIndexes[index],
      lineage: input.audioMediaItems[index]
        ? structuredClone(input.audioMediaItems[index])
        : null,
    });
  });
  evidence.push({
    kind: "text",
    source: "capture_context",
    order: evidence.length,
    text: buildContextText(input.telemetry),
  });
  return {
    task: "identify",
    variant: "multimodal",
    evidence,
    capture: { ...input.capture },
  };
}
