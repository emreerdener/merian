/** Invented test data only; never a biological reference or approved paid input. */
import {
  type ContractNode,
  merianModelContract,
} from "../../identify/contract.ts";
import type { MultimodalAIRequest } from "../contracts.ts";
import { OPENAI_PHOTO_MODERATION_MODEL } from "../openaiPhoto.ts";
export const openAITextFixture = (): MultimodalAIRequest => ({
  task: "identify",
  variant: "multimodal",
  capture: {
    hasVideo: false,
    videoClipCount: 0,
    declaredVideoFrameCount: 0,
    videoInferenceFrameCount: 0,
  },
  evidence: [{
    kind: "text",
    order: 0,
    source: "observation_context",
    text: "An invented striped organism.",
  }],
});
function minimal(node: ContractNode): unknown {
  switch (node.kind) {
    case "union":
      throw new Error("Wire-only contract cannot be an OpenAI output fixture.");
    case "object":
      return Object.fromEntries(
        Object.entries(node.fields).map((
          [k, f],
        ) => [k, f.required ? minimal(f.contract) : null]),
      );
    case "array":
      return Array.from(
        { length: node.minItems ?? 0 },
        () => minimal(node.items),
      );
    case "string":
      return node.enum?.[0] ?? "Synthetic fixture";
    case "boolean":
      return node.const ?? true;
    default:
      return node.minimum;
  }
}
export function openAIDraftFixture(): Record<string, unknown> {
  return {
    ...minimal(merianModelContract) as Record<string, unknown>,
    scientific_name: "Syntheticus example",
    common_name: "Synthetic organism",
    confidence_score: .99,
  };
}
export function openAIResponseFixture() {
  return {
    model: "gpt-6-sol",
    status: "completed",
    output: [{
      type: "message",
      role: "assistant",
      status: "completed",
      content: [{
        type: "output_text",
        text: JSON.stringify(openAIDraftFixture()),
      }],
    }],
    usage: {
      input_tokens: 100,
      output_tokens: 40,
      total_tokens: 140,
      input_tokens_details: { cached_tokens: 20 },
      output_tokens_details: { reasoning_tokens: 10 },
    },
  };
}

export function openAIPhotoRequestFixture(): MultimodalAIRequest {
  return {
    ...openAITextFixture(),
    evidence: [{
      kind: "image",
      order: 0,
      inputIndex: 0,
      lineage: { kind: "image", sourceIndex: 0 },
      mimeType: "image/png",
      data: "AQID",
    }, {
      kind: "text",
      source: "observation_context",
      order: 1,
      text: "An invented observation note.",
    }],
  };
}

const imageCategories = [
  "sexual",
  "self-harm",
  "self-harm/intent",
  "self-harm/instructions",
  "violence",
  "violence/graphic",
];
const allCategories = [
  ...imageCategories,
  "sexual/minors",
  "harassment",
  "harassment/threatening",
  "hate",
  "hate/threatening",
  "illicit",
  "illicit/violent",
];
function moderationResult(input: boolean) {
  return {
    type: "moderation_result",
    model: OPENAI_PHOTO_MODERATION_MODEL,
    flagged: false,
    categories: Object.fromEntries(allCategories.map((key) => [key, false])),
    category_scores: Object.fromEntries(
      allCategories.map((key) => [key, 0.001]),
    ),
    category_applied_input_types: Object.fromEntries(
      allCategories.map((
        key,
      ) => [
        key,
        input && imageCategories.includes(key) ? ["text", "image"] : ["text"],
      ]),
    ),
  };
}
export const openAIPhotoModerationFixture = () => ({
  input: moderationResult(true),
  output: moderationResult(false),
});
