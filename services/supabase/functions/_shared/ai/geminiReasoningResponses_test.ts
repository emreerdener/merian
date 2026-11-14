import { assert, assertEquals, assertThrows } from "@std/assert";
import { decodeProtectedChatProvider } from "../../insight-chat/protectedProvider.ts";
import { decodePhotoClassifier } from "../analysisHistory/photoClassifier.ts";
import { GeminiResponseRejected } from "./geminiEnvelope.ts";
import {
  candidateGeneration,
  GEMINI_CANDIDATE_PROFILES,
} from "./geminiProfiles.ts";
function envelope(model: string, text: string) {
  return {
    modelVersion: model,
    candidates: [{
      finishReason: "STOP",
      content: {
        role: "model",
        parts: [
          {
            text: "synthetic private thought",
            thought: true,
            thoughtSignature: "opaque-signature",
          },
          { text: text.slice(0, 8), thoughtSignature: "opaque-signature" },
          { text: text.slice(8) },
        ],
      },
    }],
    usageMetadata: {
      promptTokenCount: 100,
      candidatesTokenCount: 20,
      thoughtsTokenCount: 15,
      cachedContentTokenCount: 10,
      toolUsePromptTokenCount: 0,
      totalTokenCount: 135,
    },
  };
}
Deno.test("protected chat accepts bounded reasoning metadata and keeps visible answer strict", () => {
  const response = envelope(
    "gemini-3.5-flash-lite",
    JSON.stringify({
      answer: "Synthetic answer",
      is_refusal: false,
      refusal_reason: null,
    }),
  );
  const result = decodeProtectedChatProvider(response, "gemini-3.5-flash-lite");
  assertEquals(result.answer, "Synthetic answer");
  assertEquals(result.usage?.thinking_tokens, 15);
  assert(!JSON.stringify(result).includes("opaque-signature"));
  assert(!JSON.stringify(result).includes("private thought"));
});
Deno.test("photo moderation accepts nonzero thinking and cached input", () => {
  const response = envelope(
    "gemini-3.5-flash-lite",
    JSON.stringify({ decision: "allow", confidence: .99, categories: [] }),
  );
  const result = decodePhotoClassifier(response, "gemini-3.5-flash-lite");
  assertEquals(result.decision, "approved");
  assertEquals(result.usage, {
    input_tokens: 100,
    output_tokens: 35,
    total_tokens: 135,
  });
});
Deno.test("semantic rejection retains independent identity and counters", () => {
  for (
    const parse of [
      (value: unknown) =>
        decodeProtectedChatProvider(value, "gemini-3.5-flash-lite"),
      (value: unknown) => decodePhotoClassifier(value, "gemini-3.5-flash-lite"),
    ]
  ) {
    const error = assertThrows(
      () => parse(envelope("gemini-3.5-flash-lite", '{"unexpected":true}')),
      GeminiResponseRejected,
    );
    assertEquals(error.receipt.returnedModel, "gemini-3.5-flash-lite");
    assertEquals(error.receipt.usage?.thinkingTokens, 15);
    assertEquals(error.receipt.usage?.cachedTokens, 10);
    assert(!JSON.stringify(error.receipt).includes("unexpected"));
  }
});
Deno.test("legacy request returning a new model cannot be mistaken for migration", () => {
  const error = assertThrows(
    () => decodeProtectedChatProvider(envelope("gemini-3.5-flash-lite", "{}")),
    GeminiResponseRejected,
  );
  assertEquals(error.receipt.failure, "identity");
  assertEquals(error.receipt.usage?.totalTokens, 135);
});
Deno.test("every candidate profile omits legacy sampling and numeric thinking settings", () => {
  for (
    const operation of Object.keys(
      GEMINI_CANDIDATE_PROFILES,
    ) as (keyof typeof GEMINI_CANDIDATE_PROFILES)[]
  ) {
    const generation = candidateGeneration(operation);
    assertEquals(Object.keys(generation).sort(), [
      "maxOutputTokens",
      "thinkingConfig",
    ]);
    assertEquals(Object.keys(generation.thinkingConfig), ["thinkingLevel"]);
    assertEquals(
      generation.maxOutputTokens,
      GEMINI_CANDIDATE_PROFILES[operation].maxOutputTokens,
    );
  }
  assertEquals(
    candidateGeneration("field_chat").thinkingConfig.thinkingLevel,
    "LOW",
  );
  assertEquals(
    candidateGeneration("identify").thinkingConfig.thinkingLevel,
    "MEDIUM",
  );
  assertEquals(candidateGeneration("audio_moderation").maxOutputTokens, 4096);
});
