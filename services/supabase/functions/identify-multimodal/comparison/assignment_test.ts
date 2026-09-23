import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import { IDENTIFICATION_BUNDLE_SHA256 } from "../deploymentIdentity.ts";
import { AUDIO_COMPARISON_PLAN, AUDIO_COMPARISON_PLAN_SHA256 } from "./plan.ts";
import {
  AudioComparisonError,
  audioComparisonReceipt,
  audioComparisonScanId,
  comparisonRequested,
  processComparisonAudio,
  requireComparisonReservation,
  resolveAudioComparison,
  verifyComparisonExecution,
} from "./assignment.ts";
import { fingerprintJson } from "./fingerprint.ts";
import { prepareAudioComparisonPair } from "../../../scripts/identification_evaluation/audioComparison.ts";
import { fixtureAuthority } from "../../../scripts/identification_evaluation/profiles.ts";
import { encodeWav16 } from "../../audio-spec/wav.ts";
import { resolveAIClaim } from "../../_shared/ai/registry.ts";
import { buildMultimodalAIRequest } from "../provider.ts";
import { comparisonAudio } from "./audio.ts";
import { encodeBase64 } from "../../_shared/encoding.ts";

const userId = "00000000-0000-4000-8000-000000000201";
const now = Date.parse("2026-09-23T12:30:00.000Z");
const configuration = {
  version: 1,
  ownerId: userId,
  startsAt: "2026-09-23T12:00:00.000Z",
  expiresAt: "2026-09-23T13:00:00.000Z",
  planSha256: AUDIO_COMPARISON_PLAN_SHA256,
  backendBundleSha256: IDENTIFICATION_BUNDLE_SHA256,
};

Deno.test("comparison reservation independently guards tier, fallback, reopening and expiry", () => {
  const comparison = {
    assignment: AUDIO_COMPARISON_PLAN.assignments[0],
    expiresAt: now + 1000,
  };
  const reservation = {
    attemptCount: 1,
    model: "gemini-2.5-pro" as const,
    flashFallbackUsed: false,
    tier: { effective_tier: "pro" as const },
  };
  requireComparisonReservation(comparison, reservation, now);
  for (
    const invalid of [
      { ...reservation, attemptCount: 2 },
      { ...reservation, attemptCount: 3 },
      { ...reservation, model: "gemini-2.5-flash" as const },
      { ...reservation, tier: { effective_tier: "free" as const } },
      { ...reservation, flashFallbackUsed: true },
    ]
  ) {
    assertThrows(
      () => requireComparisonReservation(comparison, invalid, now),
      AudioComparisonError,
    );
  }
  assertThrows(
    () => requireComparisonReservation(comparison, reservation, now + 1000),
    AudioComparisonError,
    "unavailable",
  );
});
async function input(slot = 1) {
  const scanId = await audioComparisonScanId(slot);
  return {
    body: {
      user_id: userId,
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
      audio_comparison: { planSha256: AUDIO_COMPARISON_PLAN_SHA256, slot },
    },
    userId,
    scanId,
    now,
    configuration: JSON.stringify(configuration),
  };
}

Deno.test("comparison table binds twelve unique stable slots to one immutable plan", async () => {
  assertEquals(
    await fingerprintJson(AUDIO_COMPARISON_PLAN),
    AUDIO_COMPARISON_PLAN_SHA256,
  );
  const ids = [];
  for (const a of AUDIO_COMPARISON_PLAN.assignments) {
    ids.push(await audioComparisonScanId(a.slot));
    assertEquals(
      (await resolveAudioComparison(await input(a.slot)))?.assignment,
      a,
    );
  }
  assertEquals(new Set(ids).size, 12);
  assertEquals(
    comparisonRequested({}, "ac0a0001-0000-4000-8000-000000000001"),
    false,
  );
  assertEquals(comparisonRequested({}, ids[0]), true);
  assertEquals(
    ids,
    await Promise.all(
      AUDIO_COMPARISON_PLAN.assignments.map((a) =>
        audioComparisonScanId(a.slot)
      ),
    ),
  );
  await assertRejects(() => audioComparisonScanId(13));
});

Deno.test("comparison config fails closed without affecting ordinary requests", async () => {
  const original = await input();
  for (
    const config of [
      undefined,
      "",
      "{",
      "x".repeat(1025),
      "null",
      "[]",
      ...[
        { version: 2 },
        { ownerId: "00000000-0000-4000-8000-000000000999" },
        { planSha256: "0".repeat(64) },
        { backendBundleSha256: "0".repeat(64) },
        { startsAt: "2026-09-23" },
        { startsAt: "2026-02-30T12:00:00.000Z" },
        { startsAt: "2026-09-24T12:00:00.000Z" },
        { expiresAt: "2026-09-23T12:30:00.000Z" },
        { expiresAt: "2026-09-24T12:00:00.001Z" },
        { expiresAt: "2026-10-23T00:00:00.000Z" },
        { startsAt: "2026-09-22T12:00:00.000Z" },
        { provider: "arbitrary" },
      ].map((change) => JSON.stringify({ ...configuration, ...change })),
    ]
  ) {
    await assertRejects(
      () => resolveAudioComparison({ ...original, configuration: config }),
      AudioComparisonError,
      "unavailable",
    );
    assertEquals(
      await resolveAudioComparison({
        ...original,
        body: {},
        scanId: userId,
        configuration: config,
      }),
      null,
    );
  }
});

Deno.test("comparison rejects removed markers, replay, extra evidence and changed identity/context", async () => {
  const original = await input();
  for (
    const body of [
      { ...original.body, audio_comparison: undefined },
      {
        ...original.body,
        audio_comparison: { ...original.body.audio_comparison, slot: 13 },
      },
      {
        ...original.body,
        audio_comparison: { ...original.body.audio_comparison, slot: 2 },
      },
      {
        ...original.body,
        audio_comparison: {
          ...original.body.audio_comparison,
          arm: "arbitrary",
        },
      },
      {
        ...original.body,
        audio_comparison: {
          ...original.body.audio_comparison,
          planSha256: "0".repeat(64),
        },
      },
      { ...original.body, client_scan_id: userId },
      { ...original.body, user_id: "wrong-owner" },
      { ...original.body, gpsLatitude: 0 },
      { ...original.body, currentMonth: 2 },
      { ...original.body, audioBase64s: ["a", "b"] },
      { ...original.body, r2ObjectKeys: [] },
      {
        ...original.body,
        audioMediaItems: [{ kind: "video_audio", clipIndex: 0 }],
      },
      { ...original.body, ownerMediaTimeline: [] },
    ]
  ) {
    await assertRejects(
      () => resolveAudioComparison({ ...original, body }),
      AudioComparisonError,
    );
  }
  await assertRejects(
    () => resolveAudioComparison({ ...original, internalReplayAttempt: 1 }),
    AudioComparisonError,
    "excluded",
  );
  await assertRejects(
    () =>
      resolveAudioComparison({
        ...original,
        body: {},
        internalReplayAttempt: 1,
        configuration: undefined,
      }),
    AudioComparisonError,
    "excluded",
  );
  await assertRejects(
    () => resolveAudioComparison({ ...original, scanId: userId }),
    AudioComparisonError,
  );
});

Deno.test("both processors attest actual bytes and reject media/request/policy drift", async () => {
  const source = encodeWav16(
    Float32Array.from({ length: 44928 }, (_, i) => 0.3 * Math.sin(i / 11)),
    44100,
  );
  const pair = await prepareAudioComparisonPair(source);
  for (const arm of pair.arms) {
    const comparison = {
      assignment: { ...AUDIO_COMPARISON_PLAN.assignments[0], ...pair, ...arm },
      expiresAt: now + 1000,
    };
    const audio = await processComparisonAudio(
      comparison,
      new Uint8Array(source).buffer,
    );
    assertEquals(audio, encodeBase64(comparisonAudio(source, arm.arm)));
    const request = buildMultimodalAIRequest({
      observationEvidenceTexts: [],
      visualMediaItems: [],
      imageBase64s: [],
      imageMimeType: "image/webp",
      processedAudios: [audio],
      audioMediaItems: [{ kind: "audio", sourceIndex: 0 }],
      processedAudioInputIndexes: [0],
      hasVideoAudio: false,
      capture: {
        hasVideo: false,
        videoClipCount: 0,
        declaredVideoFrameCount: 0,
        videoInferenceFrameCount: 0,
      },
      telemetry: {
        safeGpsLat: null,
        safeGpsLon: null,
        deviceLocale: "en",
        deviceTimeZone: "UTC",
        deviceRegion: null,
        currentMonth: 1,
        timeOfDay: "12:00 PM",
      },
    });
    const snapshot = resolveAIClaim(request, fixtureAuthority("gemini_pro"));
    await verifyComparisonExecution(comparison, request, snapshot);
    const changed = new Uint8Array(source);
    changed[44] ^= 1;
    await assertRejects(
      () => processComparisonAudio(comparison, changed.buffer),
      AudioComparisonError,
    );
    await assertRejects(
      () =>
        processComparisonAudio({
          ...comparison,
          assignment: {
            ...comparison.assignment,
            processedWavSha256: "0".repeat(64),
          },
        }, new Uint8Array(source).buffer),
      AudioComparisonError,
    );
    for (
      const field of [
        "providerRequestSha256",
        "policySha256",
        "confidenceSha256",
      ]
    ) {
      await assertRejects(
        () =>
          verifyComparisonExecution(
            {
              ...comparison,
              assignment: { ...comparison.assignment, [field]: "0".repeat(64) },
            },
            request,
            snapshot,
          ),
        AudioComparisonError,
      );
    }
    await assertRejects(
      () =>
        verifyComparisonExecution(
          comparison,
          { ...request, evidence: [] },
          snapshot,
        ),
      AudioComparisonError,
    );
    const receipt = audioComparisonReceipt(comparison);
    assertEquals(receipt.length < 1024, true);
    assertEquals(receipt.includes(userId), false);
    assertEquals(receipt.includes(audio), false);
  }
  const malformed = new Uint8Array(source);
  malformed[32] = 4;
  assertThrows(() =>
    comparisonAudio(malformed, "audio-linear-full-windows-v1")
  );
});
