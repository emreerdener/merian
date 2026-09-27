/** Invented test data only; never a biological reference or approved paid input. */
import {
  type ContractNode,
  merianModelContract,
} from "../../identify/contract.ts";
import type { MultimodalAIRequest } from "../contracts.ts";
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
