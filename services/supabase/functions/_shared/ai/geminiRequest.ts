import { parseImageFocusRegion } from "../identify/imageFocus.ts";
import { audioUncertaintySystemInstruction } from "../../identify-multimodal/comparison/promptInstruction.ts";
import type { ThinkingLevel } from "@google/genai";
import type {
  GenerateContentParameters,
  HarmBlockThreshold,
  HarmCategory,
  Part,
  Schema,
} from "@google/genai";
import type { AIRequest, GeminiAttemptSnapshot } from "./contracts.ts";
import {
  getDescribeResponseSchema,
  getDescribeSystemInstruction,
} from "../../identify-describe/schema.ts";
import {
  BIOACOUSTIC_SYSTEM_INSTRUCTION,
  DESCRIBE_SYSTEM_INSTRUCTION,
  MULTIMODAL_BLENDED_SYSTEM_INSTRUCTION,
} from "../../identify-multimodal/instructions.ts";
import { BIOACOUSTIC_SYSTEM_INSTRUCTION as AUDIO_COMPAT_INSTRUCTION } from "../../audio-spec/instructions.ts";
import {
  getMerianAudioResponseSchema,
  getMerianResponseSchema,
  getSystemInstruction,
} from "../identify/schema.ts";
// Preserve the legacy vision route's explicit biological-photography policy.
// Primary multimodal and audio/description routes keep SDK safety defaults.
const BIOLOGICAL_SAFETY_SETTINGS = [
  {
    category: "HARM_CATEGORY_DANGEROUS_CONTENT" as HarmCategory,
    threshold: "BLOCK_ONLY_HIGH" as HarmBlockThreshold,
  },
  {
    category: "HARM_CATEGORY_SEXUALLY_EXPLICIT" as HarmCategory,
    threshold: "BLOCK_ONLY_HIGH" as HarmBlockThreshold,
  },
];

function diagnosticTrigger(snapshot: GeminiAttemptSnapshot): number {
  if (
    typeof snapshot.diagnosticTrigger !== "number" ||
    !Number.isFinite(snapshot.diagnosticTrigger)
  ) {
    throw new Error("ai_diagnostic_binding_missing");
  }
  return snapshot.diagnosticTrigger;
}

export function buildGeminiRequestParameters(
  request: AIRequest,
  snapshot: GeminiAttemptSnapshot,
  content?: {
    systemInstruction: string;
    responseSchema: Schema;
    contents: GenerateContentParameters["contents"];
  },
): GenerateContentParameters {
  const options = snapshot.generation;
  const focusedPrompt = snapshot.prompt === "identify_vision_focus_v1" ||
    snapshot.prompt === "identify_blended_focus_v1";
  const hasFocus = request.task === "identify" && request.evidence.some(
    (item) => item.kind === "image" && item.focusRegion !== undefined,
  );
  const hasAudio = request.task === "identify" && request.evidence.some(
    (item) => item.kind === "audio",
  );
  if (
    hasFocus !== focusedPrompt || (focusedPrompt &&
      (request.variant !== "multimodal" ||
        (snapshot.prompt === "identify_blended_focus_v1") !== hasAudio))
  ) {
    throw new Error("ai_image_focus_prompt_mismatch");
  }
  if (request.task !== "identify" && !content) {
    throw new Error("ai_content_projection_missing");
  }
  const systemInstruction = content?.systemInstruction ??
    (snapshot.prompt === "identify_describe_v1"
      ? getDescribeSystemInstruction()
      : (snapshot.prompt === "identify_blended_v1" ||
          snapshot.prompt === "identify_blended_focus_v1")
      ? MULTIMODAL_BLENDED_SYSTEM_INSTRUCTION
      : (snapshot.prompt === "identify_vision_v1" ||
          snapshot.prompt === "identify_vision_focus_v1")
      ? getSystemInstruction(
        snapshot.promptDiagnosticTrigger ?? diagnosticTrigger(snapshot),
      )
      : snapshot.prompt === "identify_audio_uncertainty_experiment_v1"
      ? audioUncertaintySystemInstruction()
      : snapshot.prompt === "identify_audio_v2"
      ? BIOACOUSTIC_SYSTEM_INSTRUCTION
      : snapshot.prompt === "identify_audio_compat_v2"
      ? AUDIO_COMPAT_INSTRUCTION
      : DESCRIBE_SYSTEM_INSTRUCTION);
  const schema = content?.responseSchema ??
    (snapshot.schema === "merian_describe_v1"
      ? getDescribeResponseSchema()
      : snapshot.schema === "merian_audio_v2"
      ? getMerianAudioResponseSchema()
      : getMerianResponseSchema(diagnosticTrigger(snapshot)));
  return {
    model: snapshot.model,
    contents: request.task === "identify"
      ? [{
        role: "user",
        parts: request.evidence.flatMap((item): Part[] => {
          if (item.kind === "text") return [{ text: item.text }];
          const media: Part = {
            inlineData: { mimeType: item.mimeType, data: item.data },
          };
          if (item.kind !== "image" || item.focusRegion === undefined) {
            return [media];
          }
          const focus = parseImageFocusRegion(item.focusRegion);
          if (!focus) throw new Error("ai_image_focus_invalid");
          if (item.lineage?.kind === "video_frame") {
            throw new Error("ai_image_focus_invalid");
          }
          const bounds = JSON.stringify({
            x: focus.x,
            y: focus.y,
            width: focus.width,
            height: focus.height,
          });
          const instruction = focus.source === "user_selection"
            ? "The user selected the intended subject in the following image. Focus identification on that subject; use the surrounding image as context."
            : "Automatic saliency suggests a possible subject in the following image. This is only a hint, not a user selection; assess the whole image.";
          return [{
            text:
              `${instruction} Rectangle in normalized image coordinates with top-left origin: ${bounds}. Selection does not establish identity or justify greater confidence.`,
          }, media];
        }),
      }]
      : content!.contents,
    config: {
      systemInstruction,
      maxOutputTokens: options.maxOutputTokens,
      ...("thinkingLevel" in options
        ? {
          thinkingConfig: {
            thinkingLevel: options.thinkingLevel === "medium"
              ? "MEDIUM" as ThinkingLevel
              : options.thinkingLevel === "low"
              ? "LOW" as ThinkingLevel
              : "MINIMAL" as ThinkingLevel,
          },
        }
        : {
          temperature: options.temperature,
          ...(options.seed === undefined ? {} : { seed: options.seed }),
          ...(options.topK === undefined ? {} : { topK: options.topK }),
          ...(options.thinkingBudget === undefined
            ? {}
            : { thinkingConfig: { thinkingBudget: options.thinkingBudget } }),
        }),
      responseMimeType: "application/json",
      responseSchema: structuredClone(schema),
      ...(snapshot.safety === "biological_vision_v1"
        ? { safetySettings: structuredClone(BIOLOGICAL_SAFETY_SETTINGS) }
        : {}),
    },
  };
}
