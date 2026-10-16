import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import type { AIExecutionOutcome, IdentifyEvidence } from "../ai/contracts.ts";
import { resolveAIClaim } from "../ai/registry.ts";
import { identificationProvenance } from "../ai/provenance.ts";
import { identificationUsageFacts } from "../ai/identificationUsage.ts";
import { parseIdentifySuccessEnvelope } from "../identify/contract.ts";
import { diagnosticTriggerForTier } from "../identify/thresholds.ts";
import { parseExecutableAnalysisInput } from "./analysisInput.ts";
import {
  type AnalysisWork,
  captureAnalysisOutcome,
  capturePreparedVideoOutcome,
  executeObservationAnalysis,
} from "./execution.ts";
import {
  buildPreparedVideoDraft,
  parsePreparedVideoAdmission,
} from "./videoAdmission.ts";

const vectors: { name: string; input: Record<string, unknown> }[] = JSON.parse(
  await Deno.readTextFile(
    new URL("./fixtures/video-request-v4.json", import.meta.url),
  ),
);
const draft = {
  is_biological_subject: true,
  is_live_capture: true,
  scientific_name: "Danaus plexippus",
  common_name: "Monarch",
  confidence_score: 0.88,
  ai_reasoning: "Synthetic fixture with contrasting wing pattern.",
  extracted_visual_traits: ["synthetic orange wings"],
  candidates: [{
    scientific_name: "Danaus gilippus",
    confidence_score: 0.6,
    distinguishing_feature: "Synthetic alternative wing pattern.",
  }],
  image_quality: {
    sharpness: 10,
    framing: 10,
    diagnostic_utility: 10,
    overall_score: 100,
  },
};
function setup(index: number, tier: "free" | "pro" = "free") {
  const input = parsePreparedVideoAdmission(
    structuredClone(vectors[index].input),
  );
  const audio = input.evidence_manifest.provenance.audio !== null;
  const assignment = {
    inputProfile: audio
      ? "multimodal_video_audio_v1"
      : "multimodal_video_frames_v1",
    provider: "gemini",
    binding: "gemini_baseline_v1",
    permission: "google_gemini",
  } as const;
  const evidence: IdentifyEvidence[] = Array.from(
    { length: 5 },
    (_, order) => ({
      kind: "image",
      order,
      data: "AQ==",
      mimeType: "image/jpeg",
      inputIndex: order,
      lineage: null,
    }),
  );
  if (audio) {
    evidence.push({
      kind: "audio",
      order: 5,
      data: "Ag==",
      mimeType: "audio/wav",
      inputIndex: 5,
      lineage: null,
    });
  }
  const model = tier === "pro" ? "gemini-2.5-pro" : "gemini-2.5-flash";
  const snapshot = resolveAIClaim({
    task: "identify",
    variant: "multimodal",
    evidence,
    capture: {
      hasVideo: true,
      videoClipCount: 1,
      declaredVideoFrameCount: 5,
      videoInferenceFrameCount: 5,
    },
  }, {
    kind: "user_request",
    userId: input.observation_id,
    permission: "google_gemini",
    operation: "scan_identification",
    reservation: {
      assignment,
      id: input.analysis_id,
      requestId: input.analysis_id,
      attemptCount: 1,
      policyVersion: 7,
      model,
      tier: { effective_tier: tier },
    },
  });
  const work: AnalysisWork = {
    state: "dispatched",
    claimed: true,
    input,
    quota: {
      input_profile: assignment.inputProfile,
      provider: assignment.provider,
      binding: assignment.binding,
      processor_permission: assignment.permission,
      attempt_count: 1,
      policy_version: 7,
      model,
      effective_tier: tier,
    },
  };
  const outcome: AIExecutionOutcome = {
    kind: "draft",
    draft: structuredClone(draft),
    execution: { ...snapshot, durationMs: 1 },
    providerDurationMs: 1,
    providerCompletedAt: 1,
    returnedModel: model,
    usage: null,
    finishReason: "STOP",
    responseCharacters: 100,
  };
  return { work, outcome, audio };
}
function result(outcome: AIExecutionOutcome, work: AnalysisWork) {
  const saved = capturePreparedVideoOutcome(outcome, work);
  assert(saved?.outcome.kind === "draft");
  return {
    saved,
    data: parseIdentifySuccessEnvelope({
      success: true,
      data: saved.outcome.result,
    }).data,
  };
}
Deno.test("prepared video outcomes preserve both graph modes and funding tiers without mutating saved input", () => {
  for (let i = 0; i < vectors.length; i++) {
    for (const tier of ["free", "pro"] as const) {
      const f = setup(i, tier), before = JSON.stringify(f);
      const { saved, data } = result(f.outcome, f.work);
      assertEquals(data.scan_id, f.work.input!.observation_id);
      assertEquals(data.inference_tier, tier === "pro" ? "pro" : "flash");
      assertEquals(data.scientific_name, draft.scientific_name);
      assertEquals(data.extracted_visual_traits, draft.extracted_visual_traits);
      assertEquals(
        saved.provenance,
        identificationProvenance(f.outcome.execution),
      );
      assertEquals(saved.usage, identificationUsageFacts(f.outcome));
      const prepared = buildPreparedVideoDraft(
        JSON.stringify(f.work.input),
        data,
        {
          id: f.work.input!.source_analysis_id as string,
          scientific_name: draft.scientific_name,
        },
      );
      assertEquals(prepared.evidence_manifest, f.work.input!.evidence_manifest);
      assertEquals(JSON.stringify(f), before);
      assertThrows(() => parseExecutableAnalysisInput(f.work.input));
    }
  }
});
Deno.test("prepared video normalization uses visual schema even with an audio companion", () => {
  for (let i = 0; i < vectors.length; i++) {
    const f = setup(i);
    // No audio-only discriminator exists, yet visual evidence remains valid.
    assertEquals(
      result(f.outcome, f.work).data.scientific_name,
      draft.scientific_name,
    );
  }
});
Deno.test("prepared video audio branch alone applies blended human canonicalization", () => {
  for (let i = 0; i < vectors.length; i++) {
    const f = setup(i);
    const { data } = result({
      ...f.outcome,
      kind: "draft",
      draft: { ...draft, scientific_name: "homo sapien", life_stage: "adult" },
    }, f.work);
    if (f.audio) {
      assertEquals(data.scientific_name, "Homo sapiens");
      assertEquals(data.candidates, []);
      assertEquals(data.life_stage, undefined);
    } else {
      assertEquals(data.life_stage, "adult");
      assertEquals(data.candidates?.length, 1);
    }
  }
});
Deno.test("prepared video confidence follows the admitted tier and keeps alternatives below its threshold", () => {
  for (const tier of ["free", "pro"] as const) {
    for (let i = 0; i < vectors.length; i++) {
      const f = setup(i, tier),
        threshold = diagnosticTriggerForTier(tier === "pro" ? "pro" : "flash");
      for (const score of [threshold - 0.001, threshold]) {
        const { data } = result({
          ...f.outcome,
          kind: "draft",
          draft: { ...draft, confidence_score: score },
        }, f.work);
        assertEquals(data.candidates?.length ?? 0, score < threshold ? 1 : 0);
      }
    }
  }
});
Deno.test("prepared video refuses unsafe output and records malformed received output as invalid", () => {
  const f = setup(0);
  for (
    const outcome of [{ ...f.outcome, finishReason: "SAFETY" }, {
      ...f.outcome,
      kind: "refusal" as const,
    }]
  ) {
    assertEquals(capturePreparedVideoOutcome(outcome, f.work)?.outcome, {
      kind: "refusal",
    });
  }
  for (
    const value of [null, {}, { ...draft, confidence_score: 2 }, {
      ...draft,
      ai_reasoning: "x".repeat(1048577),
    }]
  ) {
    assertEquals(
      capturePreparedVideoOutcome(
        { ...f.outcome, kind: "draft", draft: value },
        f.work,
      )?.outcome,
      { kind: "invalid_output" },
    );
  }
  assertEquals(
    capturePreparedVideoOutcome({
      ...f.outcome,
      kind: "invalid_output",
      reason: "json",
    }, f.work)?.outcome,
    { kind: "invalid_output" },
  );
});
Deno.test("prepared video unknown execution and operational failure never fabricate a saved outcome", () => {
  const f = setup(0);
  for (const kind of ["unknown_execution", "operational_failure"] as const) {
    assertEquals(
      capturePreparedVideoOutcome({ ...f.outcome, kind }, {
        ...f.work,
        input: undefined,
        quota: undefined,
      }),
      null,
    );
  }
});
Deno.test("prepared video rejects changed graph, assignment and immutable provider binding", () => {
  for (let i = 0; i < vectors.length; i++) {
    const f = setup(i);
    for (
      const change of [
        { input_profile: "multimodal_audio_v1" },
        {
          input_profile: f.audio
            ? "multimodal_video_frames_v1"
            : "multimodal_video_audio_v1",
        },
        { provider: "openai" },
        { binding: "openai_photo_v1" },
        { processor_permission: "openai" },
        { attempt_count: 2 },
        { policy_version: 8 },
        { policy_version: 0 },
        { model: "other" },
        { effective_tier: "other" },
      ]
    ) {
      assertThrows(() =>
        capturePreparedVideoOutcome(f.outcome, {
          ...f.work,
          quota: { ...f.work.quota, ...change },
        })
      );
    }
    for (
      const input of [undefined, {}, { ...f.work.input, schema_version: 3 }, {
        ...f.work.input,
        evidence_manifest: {},
      }]
    ) {
      assertThrows(() =>
        capturePreparedVideoOutcome(f.outcome, { ...f.work, input })
      );
    }
    const other = setup((i + 1) % vectors.length);
    assertThrows(() =>
      capturePreparedVideoOutcome({
        ...f.outcome,
        execution: other.outcome.execution,
      }, f.work)
    );
  }
});

Deno.test("prepared video rejects invalid provider policy even for terminal received outcomes", () => {
  const f = setup(0);
  for (
    const change of [
      { provider: "openai" },
      { binding: "other" },
      { task: "species_overview" },
      { model: "other" },
      { policyVersion: 8 },
      { prompt: "identify_audio_v2" },
      { schema: "merian_audio_v2" },
      { confidence: "gemini_audio_v2" },
      { permission: "openai" },
      { operation: "scan_audio_identification" },
      { contextKind: "service_job" },
      { diagnosticTrigger: 0.5 },
    ]
  ) {
    const execution = Object.assign(
      structuredClone(f.outcome.execution),
      change,
    );
    for (const kind of ["draft", "refusal"] as const) {
      assertThrows(() =>
        capturePreparedVideoOutcome(
          { ...f.outcome, kind, draft, execution },
          f.work,
        )
      );
    }
  }
  assertThrows(() =>
    capturePreparedVideoOutcome(f.outcome, { ...f.work, quota: undefined })
  );
  assertThrows(() =>
    capturePreparedVideoOutcome(f.outcome, {
      ...f.work,
      quota: { ...f.work.quota, effective_tier: "pro" },
    })
  );
  for (
    const change of [{ history_protocol: 12 }, {
      source_analysis_id: f.work.input!.analysis_id,
    }]
  ) {
    assertThrows(() =>
      capturePreparedVideoOutcome(f.outcome, {
        ...f.work,
        input: { ...f.work.input, ...change },
      })
    );
  }
});
Deno.test("generic capture and claimed executor deny V4 before any dependency call", async () => {
  const f = setup(0);
  assertThrows(() => captureAnalysisOutcome(f.outcome, f.work));
  let calls = 0;
  const denied = () => {
    calls++;
    throw new Error("unexpected dependency");
  };
  await assertRejects(() =>
    executeObservationAnalysis(f.work, {
      prepare: denied,
      advance: denied,
      resolveSpecies: denied,
    })
  );
  assertEquals(calls, 0);
});

Deno.test("prepared video binds both tier/model pairs even when quota and snapshot agree", () => {
  for (const tier of ["free", "pro"] as const) {
    const f = setup(0, tier),
      other = tier === "free" ? "gemini-2.5-pro" : "gemini-2.5-flash";
    const execution = f.outcome.execution;
    assert(execution.provider === "gemini");
    assertThrows(() =>
      capturePreparedVideoOutcome({
        ...f.outcome,
        execution: { ...execution, model: other },
      }, { ...f.work, quota: { ...f.work.quota, model: other } })
    );
  }
});
Deno.test("unclaimed V4 cannot pass through the generic executor", async () => {
  const f = setup(0);
  const denied = () => {
    throw new Error("unexpected dependency");
  };
  await assertRejects(() =>
    executeObservationAnalysis({ ...f.work, claimed: false }, {
      prepare: denied,
      advance: denied,
      resolveSpecies: denied,
    })
  );
});
