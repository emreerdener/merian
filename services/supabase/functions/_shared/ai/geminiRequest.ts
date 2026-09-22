import type {
  GenerateContentParameters,
  HarmBlockThreshold,
  HarmCategory,
  Schema,
} from "@google/genai";
import type { AIAttemptSnapshot, AIRequest } from "./contracts.ts";
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

function diagnosticTrigger(snapshot: AIAttemptSnapshot): number {
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
  snapshot: AIAttemptSnapshot,
  content?: {
    systemInstruction: string;
    responseSchema: Schema;
    contents: GenerateContentParameters["contents"];
  },
): GenerateContentParameters {
  const options = snapshot.generation;
  if (request.task !== "identify" && !content) {
    throw new Error("ai_content_projection_missing");
  }
  const systemInstruction = content?.systemInstruction ??
    (snapshot.prompt === "identify_describe_v1"
      ? getDescribeSystemInstruction()
      : snapshot.prompt === "identify_blended_v1"
      ? MULTIMODAL_BLENDED_SYSTEM_INSTRUCTION
      : snapshot.prompt === "identify_vision_v1"
      ? getSystemInstruction(
        snapshot.promptDiagnosticTrigger ?? diagnosticTrigger(snapshot),
      )
      : snapshot.prompt === "identify_audio_v1"
      ? BIOACOUSTIC_SYSTEM_INSTRUCTION
      : snapshot.prompt === "identify_audio_compat_v1"
      ? AUDIO_COMPAT_INSTRUCTION
      : DESCRIBE_SYSTEM_INSTRUCTION);
  const schema = content?.responseSchema ??
    (snapshot.schema === "merian_describe_v1"
      ? getDescribeResponseSchema()
      : snapshot.schema === "merian_audio_v1"
      ? getMerianAudioResponseSchema()
      : getMerianResponseSchema(diagnosticTrigger(snapshot)));
  return {
    model: snapshot.model,
    contents: request.task === "identify"
      ? [{
        role: "user",
        parts: request.evidence.map((item) =>
          item.kind === "text"
            ? { text: item.text }
            : { inlineData: { mimeType: item.mimeType, data: item.data } }
        ),
      }]
      : content!.contents,
    config: {
      systemInstruction,
      temperature: options.temperature,
      ...(options.seed === undefined ? {} : { seed: options.seed }),
      ...(options.topK === undefined ? {} : { topK: options.topK }),
      maxOutputTokens: options.maxOutputTokens,
      ...(options.thinkingBudget === undefined
        ? {}
        : { thinkingConfig: { thinkingBudget: options.thinkingBudget } }),
      responseMimeType: "application/json",
      responseSchema: structuredClone(schema),
      ...(snapshot.safety === "biological_vision_v1"
        ? { safetySettings: structuredClone(BIOLOGICAL_SAFETY_SETTINGS) }
        : {}),
    },
  };
}
