import { assertEquals, assertMatch, assertStringIncludes } from "@std/assert";
import { resolveAIClaim } from "../_shared/ai/registry.ts";
import type { AIExecutionOutcome } from "../_shared/ai/contracts.ts";
import {
  IDENTIFICATION_DIAGNOSTICS_HEADER,
  identificationDiagnosticHeaders,
} from "./diagnostics.ts";

export function diagnosticFixture(): AIExecutionOutcome {
  const execution = resolveAIClaim({
    task: "identify",
    variant: "multimodal",
    evidence: [{
      kind: "text",
      order: 0,
      source: "observation_context",
      text: "Synthetic fixture",
    }],
    capture: {
      hasVideo: false,
      videoClipCount: 0,
      declaredVideoFrameCount: 0,
      videoInferenceFrameCount: 0,
    },
  }, {
    kind: "user_request",
    userId: "synthetic-owner",
    permission: "google_gemini",
    operation: "scan_identification",
    reservation: {
      id: "synthetic-reservation",
      requestId: "synthetic-request",
      attemptCount: 1,
      policyVersion: 1,
      model: "gemini-2.5-flash",
      tier: { effective_tier: "free" },
    },
  });
  return {
    execution: { ...execution, durationMs: 20 },
    kind: "draft",
    draft: { privateProse: "synthetic-private-value" },
    providerDurationMs: 20,
    providerCompletedAt: 0,
    returnedModel: "gemini-2.5-flash",
    finishReason: "STOP",
    responseCharacters: 50,
    usage: {
      promptTokens: 100,
      candidateTokens: 20,
      thinkingTokens: 5,
      totalTokens: 125,
      cachedTokens: 10,
      toolTokens: 0,
      modalityBreakdown: { arbitrary: "synthetic-private-value" },
    },
  };
}

Deno.test("identification headers project actual attempt facts without content or identifiers", () => {
  const headers = identificationDiagnosticHeaders(diagnosticFixture());
  const text = headers[IDENTIFICATION_DIAGNOSTICS_HEADER];
  const d = JSON.parse(text);
  assertEquals(d.provider, "gemini");
  assertEquals(d.requestedModel, "gemini-2.5-flash");
  assertEquals(d.returnedModel, "gemini-2.5-flash");
  assertMatch(d.backendBundleSha256, /^[0-9a-f]{64}$/);
  assertEquals(d.usage, {
    promptTokens: 100,
    candidateTokens: 20,
    thinkingTokens: 5,
    totalTokens: 125,
    cachedTokens: 10,
    toolTokens: 0,
  });
  assertEquals(text.includes("synthetic"), false);
  assertEquals(text.length < 2048, true);
  assertStringIncludes(
    headers["Access-Control-Expose-Headers"],
    IDENTIFICATION_DIAGNOSTICS_HEADER,
  );
});

Deno.test("missing or malformed usage and model stay unknown without failing a response", () => {
  const fixture = diagnosticFixture();
  const result = {
    ...fixture,
    usage: {
      ...fixture.usage!,
      promptTokens: NaN,
      candidateTokens: -1,
      totalTokens: 10_000_001,
      toolTokens: 0.5,
    },
    returnedModel: "synthetic-private-value",
  };
  const d = JSON.parse(
    identificationDiagnosticHeaders(result)[IDENTIFICATION_DIAGNOSTICS_HEADER],
  );
  assertEquals([
    d.usage.promptTokens,
    d.usage.candidateTokens,
    d.usage.totalTokens,
    d.usage.toolTokens,
    d.returnedModel,
  ], [null, null, null, null, null]);
  assertEquals(
    JSON.parse(
      identificationDiagnosticHeaders({
        ...result,
        usage: null,
      })[IDENTIFICATION_DIAGNOSTICS_HEADER],
    ).usage,
    null,
  );
});
