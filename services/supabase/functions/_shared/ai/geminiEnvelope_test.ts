import { assertEquals } from "@std/assert";
import { normalizeGeminiEnvelope } from "./geminiEnvelope.ts";
import { assertThrows } from "@std/assert";
import {
  assertGeminiLegacyDispatchOpen,
  candidateGeneration,
  GEMINI_LEGACY_DISPATCH_CUTOFF,
} from "./geminiProfiles.ts";

function response() {
  return {
    modelVersion: "gemini-3.5-flash-lite",
    candidates: [{
      finishReason: "STOP",
      content: {
        role: "model",
        parts: [
          {
            text: "Synthetic thought, never application output",
            thought: true,
          },
          { text: '{"answer":', thoughtSignature: "synthetic-signature" },
          { text: '"Synthetic answer"}' },
        ],
      },
    }],
    usageMetadata: {
      promptTokenCount: 100,
      candidatesTokenCount: 20,
      thoughtsTokenCount: 30,
      cachedContentTokenCount: 40,
      totalTokenCount: 150,
    },
  };
}
Deno.test("reasoning envelope accepts signatures and excludes thoughts without losing usage", () => {
  const result = normalizeGeminiEnvelope(response(), "gemini-3.5-flash-lite");
  assertEquals(result.failure, null);
  assertEquals(result.text, '{"answer":"Synthetic answer"}');
  assertEquals(result.usage?.thinkingTokens, 30);
  assertEquals(result.usageConsistent, true);
  assertEquals(JSON.stringify(result).includes("synthetic-signature"), false);
});
Deno.test("rerouted legacy response retains accounting but cannot pass identity", () => {
  const result = normalizeGeminiEnvelope(response(), "gemini-2.5-flash");
  assertEquals(result.failure, "identity");
  assertEquals(result.returnedModel, "gemini-3.5-flash-lite");
  assertEquals(result.usage?.totalTokens, 150);
  assertEquals(result.text, null);
});
Deno.test("unsupported parts and truncated output retain independent response facts", () => {
  const value = response();
  value.candidates[0].finishReason = "MAX_TOKENS";
  assertEquals(
    normalizeGeminiEnvelope(value, value.modelVersion).usage?.totalTokens,
    150,
  );
  assertEquals(
    normalizeGeminiEnvelope(value, value.modelVersion).failure,
    "finish",
  );
  const result = normalizeGeminiEnvelope({
    ...response(),
    candidates: [{
      finishReason: "STOP",
      content: {
        role: "model",
        parts: [{ functionCall: { name: "unexpected" } }],
      },
    }],
  }, value.modelVersion);
  assertEquals(result.failure, "parts");
  assertEquals(result.usage?.thinkingTokens, 30);
});
Deno.test("invalid usage does not erase valid counters or invent zero", () => {
  const result = normalizeGeminiEnvelope({
    ...response(),
    usageMetadata: {
      promptTokenCount: 10,
      candidatesTokenCount: -1,
      totalTokenCount: 20,
    },
  }, "gemini-3.5-flash-lite");
  assertEquals(result.usage?.promptTokens, 10);
  assertEquals(result.usage?.candidateTokens, null);
  assertEquals(result.usage?.thinkingTokens, null);
  assertEquals(result.usageConsistent, false);
});
Deno.test("bounded normalization rejects oversized and excessive parts", () => {
  assertEquals(
    normalizeGeminiEnvelope(response(), "gemini-3.5-flash-lite", 4).usage,
    null,
  );
  const value = response();
  value.candidates[0].content.parts = Array.from(
    { length: 33 },
    () => ({ text: "{}" }),
  );
  assertEquals(
    normalizeGeminiEnvelope(value, value.modelVersion).failure,
    "parts",
  );
});
Deno.test("candidate profiles preserve audio ceiling and cutoff rejects only legacy dispatch", () => {
  assertEquals(candidateGeneration("audio_moderation").maxOutputTokens, 4096);
  assertEquals(
    candidateGeneration("field_chat").thinkingConfig.thinkingLevel,
    "LOW",
  );
  assertGeminiLegacyDispatchOpen(
    "gemini-2.5-pro",
    GEMINI_LEGACY_DISPATCH_CUTOFF - 1,
  );
  assertThrows(() =>
    assertGeminiLegacyDispatchOpen(
      "gemini-2.5-pro",
      GEMINI_LEGACY_DISPATCH_CUTOFF,
    )
  );
  assertGeminiLegacyDispatchOpen(
    "gemini-3.8-flash",
    GEMINI_LEGACY_DISPATCH_CUTOFF,
  );
});
