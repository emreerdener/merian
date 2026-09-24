import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import { IDENTIFICATION_BUNDLE_SHA256 } from "../deploymentIdentity.ts";
import {
  AUDIO_PROMPT_COMPARISON_PLAN,
  AUDIO_PROMPT_COMPARISON_PLAN_SHA256,
} from "./promptPlan.ts";
import {
  audioPromptComparisonScanId,
  processPromptComparisonAudio,
  requirePromptComparisonReservation,
  resolveAudioPromptComparison,
  verifyPromptComparisonExecution,
} from "./promptAssignment.ts";
import { AUDIO_COMPARISON_PLAN } from "./plan.ts";
import { resolveAIClaim } from "../../_shared/ai/registry.ts";
import { buildGeminiRequestParameters } from "../../_shared/ai/geminiRequest.ts";
import { fixtureAuthority } from "../../../scripts/identification_evaluation/profiles.ts";
import {
  buildOfflineAudioPromptPair,
  prepareAudioPromptPair,
} from "../../../scripts/identification_evaluation/audioPromptComparison.ts";
import { encodeWav16 } from "../../audio-spec/wav.ts";
import { buildMultimodalAIRequest } from "../provider.ts";
import { AUDIO_PROMPT_CONTEXT } from "../../../scripts/identification_evaluation/audioPromptComparison.ts";
import { encodeBase64 } from "../../_shared/encoding.ts";
import { fingerprintJson } from "./fingerprint.ts";

const owner = "00000000-0000-4000-8000-000000000201";
const now = Date.parse("2026-09-24T18:30:00.000Z");
const configuration = {
  version: 1,
  block: 1,
  ownerId: owner,
  startsAt: "2026-09-24T18:00:00.000Z",
  expiresAt: "2026-09-24T19:00:00.000Z",
  planSha256: AUDIO_PROMPT_COMPARISON_PLAN_SHA256,
  backendBundleSha256: IDENTIFICATION_BUNDLE_SHA256,
};
async function input(slot = 1) {
  const scanId = await audioPromptComparisonScanId(slot);
  return {
    userId: owner,
    scanId,
    now,
    configuration: JSON.stringify({
      ...configuration,
      block: Math.ceil(slot / 12),
    }),
    body: {
      user_id: owner,
      client_scan_id: scanId,
      geoprivacy: "private",
      mimeType: "image/webp",
      deviceLocale: "en",
      deviceTimeZone: "UTC",
      currentMonth: 1,
      timeOfDay: "12:00 PM",
      audioBase64s: ["synthetic-only"],
      audioMediaItems: [{ kind: "audio", sourceIndex: 0 }],
      ownerMediaTimeline: [{
        kind: "audio",
        sourceIndex: 0,
        audioInputIndex: 0,
      }],
      audio_prompt_comparison: {
        planSha256: AUDIO_PROMPT_COMPARISON_PLAN_SHA256,
        slot,
      },
    },
  };
}
Deno.test("prompt plan reserves 36 new stable identities and restricts each activation to its 12-slot block", async () => {
  assertEquals(
    await fingerprintJson(AUDIO_PROMPT_COMPARISON_PLAN),
    AUDIO_PROMPT_COMPARISON_PLAN_SHA256,
  );
  const ids = [];
  for (const slot of AUDIO_PROMPT_COMPARISON_PLAN.assignments) {
    const value = await input(slot.slot);
    ids.push(value.scanId);
    assertEquals((await resolveAudioPromptComparison(value))?.assignment, slot);
    await assertRejects(() =>
      resolveAudioPromptComparison({
        ...value,
        configuration: JSON.stringify({
          ...configuration,
          block: slot.block % 3 + 1,
        }),
      })
    );
  }
  assertEquals(new Set(ids).size, 36);
  assert(ids.every((id) => id.startsWith("ac0b0001-")));
  assertEquals(AUDIO_COMPARISON_PLAN.assignments.length, 12);
  for (const slot of [0, 37, 1.5, NaN]) {
    await assertRejects(() => audioPromptComparisonScanId(slot));
  }
});

Deno.test("prompt lane fails closed before recovery for absent, malformed, expired, wrong-owner and mixed handles", async () => {
  const v = await input();
  for (
    const config of [
      undefined,
      "",
      "{}",
      "null",
      JSON.stringify({ ...configuration, block: "1" }),
      JSON.stringify({
        ...configuration,
        expiresAt: "2026-09-24T22:00:00.000Z",
      }),
      JSON.stringify({
        ...configuration,
        ownerId: "00000000-0000-4000-8000-000000000202",
      }),
      JSON.stringify({ ...configuration, backendBundleSha256: "0".repeat(64) }),
      JSON.stringify({ ...configuration, planSha256: "0".repeat(64) }),
    ]
  ) {
    await assertRejects(() =>
      resolveAudioPromptComparison({ ...v, configuration: config })
    );
  }
  for (
    const instant of [
      Date.parse(configuration.startsAt) - 1,
      Date.parse(configuration.expiresAt),
    ]
  ) {
    await assertRejects(() =>
      resolveAudioPromptComparison({ ...v, now: instant })
    );
  }
  for (
    const changed of [
      { ...v, internalReplayAttempt: 1 },
      { ...v, body: {} },
      { ...v, body: { ...v.body, audio_comparison: { slot: 1 } } },
      {
        ...v,
        body: { ...v.body, prompt: "identify_audio_uncertainty_experiment_v1" },
      },
      { ...v, body: { ...v.body, currentMonth: 2 } },
      { ...v, scanId: "00000000-0000-4000-8000-000000000001" },
    ]
  ) await assertRejects(() => resolveAudioPromptComparison(changed));
  assertEquals(
    await resolveAudioPromptComparison({
      ...v,
      body: {},
      scanId: "00000000-0000-4000-8000-000000000001",
      configuration: undefined,
    }),
    null,
  );
});

Deno.test("prompt reservation excludes retries, expiry, lower tier and fallback", () => {
  const comparison = {
    assignment: AUDIO_PROMPT_COMPARISON_PLAN.assignments[0],
    expiresAt: now + 1,
  };
  const reservation = {
    attemptCount: 1,
    model: "gemini-2.5-pro" as const,
    tier: { effective_tier: "pro" as const },
    flashFallbackUsed: false,
  };
  requirePromptComparisonReservation(comparison, reservation, now);
  for (
    const value of [
      { ...reservation, attemptCount: 2 },
      { ...reservation, flashFallbackUsed: true },
      { ...reservation, model: "gemini-2.5-flash" as const },
      { ...reservation, tier: { effective_tier: "free" as const } },
    ]
  ) {
    assertThrows(() =>
      requirePromptComparisonReservation(comparison, value, now)
    );
  }
  assertThrows(() =>
    requirePromptComparisonReservation(comparison, reservation, now + 1)
  );
});

Deno.test("trusted prompt authority matches the offline native bytes exactly and cannot select another modality or tier", async () => {
  const bytes = encodeWav16(
    Float32Array.from({ length: 44100 }, (_, i) => 0.5 * Math.sin(i * 0.2)),
    44100,
  );
  const offline = await buildOfflineAudioPromptPair(bytes);
  const pair = await prepareAudioPromptPair(bytes);
  const request = buildMultimodalAIRequest({
    observationEvidenceTexts: [],
    visualMediaItems: [],
    imageBase64s: [],
    imageMimeType: "image/webp",
    processedAudios: [encodeBase64(offline.processedWav)],
    audioMediaItems: [{ kind: "audio", sourceIndex: 0 }],
    processedAudioInputIndexes: [0],
    hasVideoAudio: false,
    capture: {
      hasVideo: false,
      videoClipCount: 0,
      declaredVideoFrameCount: 0,
      videoInferenceFrameCount: 0,
    },
    telemetry: AUDIO_PROMPT_CONTEXT,
  });
  for (const [i, arm] of (["A", "B"] as const).entries()) {
    const authority = {
      ...fixtureAuthority("gemini_pro"),
      audioPromptComparison: arm,
    };
    const policy = resolveAIClaim(request, authority);
    assertEquals(
      buildGeminiRequestParameters(request, policy),
      offline.variants[i].native,
    );
    assertEquals(policy, offline.variants[i].policy);
    const comparison = {
      expiresAt: now + 1000,
      assignment: {
        ...AUDIO_PROMPT_COMPARISON_PLAN.assignments[i],
        ...pair.arms[i],
        sourceWavSha256: pair.sourceWavSha256,
        sourceByteLength: pair.sourceByteLength,
        processedWavSha256: pair.processedWavSha256,
      },
    };
    assertEquals(
      await processPromptComparisonAudio(
        comparison,
        new Uint8Array(bytes).buffer,
      ),
      encodeBase64(offline.processedWav),
    );
    await verifyPromptComparisonExecution(comparison, request, policy);
    await assertRejects(() =>
      processPromptComparisonAudio(comparison, new Uint8Array([1, 2, 3]).buffer)
    );
    await assertRejects(() =>
      verifyPromptComparisonExecution(comparison, request, {
        ...policy,
        generation: { ...policy.generation, maxOutputTokens: 4096 },
      })
    );
    assertThrows(() =>
      resolveAIClaim({
        ...request,
        capture: { ...request.capture, hasVideo: true },
      }, authority)
    );
    assertThrows(() =>
      resolveAIClaim({
        ...request,
        evidence: [...request.evidence, request.evidence[0]],
      }, authority)
    );
    assertThrows(() =>
      resolveAIClaim(request, {
        ...fixtureAuthority("gemini_flash_free"),
        audioPromptComparison: arm,
      })
    );
  }
  assertEquals(
    resolveAIClaim(request, fixtureAuthority("gemini_pro")).prompt,
    "identify_audio_v2",
  );
});
