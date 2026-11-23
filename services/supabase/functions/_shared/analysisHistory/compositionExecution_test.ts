import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import { resolveAIClaim } from "../ai/registry.ts";
import type { AIExecutionOutcome } from "../ai/contracts.ts";
import { analysisAuthority } from "./production.ts";
import {
  type AnalysisExecutionDependencies,
  type AnalysisWork,
  captureCompositionOutcome,
} from "./execution.ts";
import {
  executeCompositionAnalysis,
  parseCompositionAnalysisWork,
} from "./compositionExecution.ts";
import { materializeCompositionAnalysis } from "./compositionMaterialization.ts";
import { parseCompositionAdmission } from "./compositionAdmission.ts";
import {
  assertCompositionExecutionSnapshot,
  compositionExecutionProfile,
} from "./compositionExecutionPolicy.ts";
import { compositionByteFixture } from "./compositionByteTestFixtures.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const original = JSON.parse(
  JSON.parse(
    await Deno.readTextFile(
      new URL("./fixtures/page-v1.json", import.meta.url),
    ),
  ).items[0].snapshot,
);
async function setup(audio = true) {
  const f = await compositionByteFixture(audio),
    input = parseCompositionAdmission(f.input),
    owner = f.receipt.owner_id;
  const work: AnalysisWork = {
    state: "admitted",
    claimed: true,
    work_token: id(910),
    input,
    quota: {
      reservation_id: id(911),
      lease_token: id(912),
      request_id: input.analysis_id,
      original_analysis_id: input.analysis_id,
      attempt_count: 1,
      policy_version: 7,
      effective_tier: "free",
      model: "gemini-2.5-flash",
      provider: "gemini",
      binding: "gemini_baseline_v1",
      processor_permission: "google_gemini",
      input_profile: compositionExecutionProfile(input).profile,
    },
  };
  const request = await materializeCompositionAnalysis(
    input,
    owner,
    new TextEncoder().encode(JSON.stringify(f.receipt)),
    {
      read: (item) =>
        Promise.resolve(
          f.bytes.get(item.media_id)!,
        ),
    },
    new AbortController().signal,
  );
  const snapshot = resolveAIClaim(request, analysisAuthority(owner, work));
  const outcome: AIExecutionOutcome = {
    kind: "draft",
    draft: { ...original.result, candidates: [] },
    execution: { ...snapshot, durationMs: 1 },
    providerDurationMs: 1,
    providerCompletedAt: 1,
    returnedModel: snapshot.model,
    usage: null,
    finishReason: "STOP",
    responseCharacters: 100,
  };
  const calls: string[] = [], payloads: Record<string, unknown>[] = [];
  const deps: AnalysisExecutionDependencies = {
    prepare: () => {
      calls.push("prepare");
      return Promise.resolve({
        snapshot,
        invoke: () => {
          calls.push("invoke");
          return Promise.resolve(outcome);
        },
      });
    },
    advance: (op, payload) => {
      calls.push(op);
      payloads.push(payload);
      return Promise.resolve(
        op === "dispatch" ? { invocation_id: id(913), may_dispatch: true } : {},
      );
    },
    resolveSpecies: () => {
      calls.push("resolve_species");
      return Promise.resolve({
        id: id(914),
        scientific_name: original.result.scientific_name,
      });
    },
  };
  return { f, work, request, snapshot, outcome, calls, payloads, deps };
}
Deno.test("composition execution orders retained outcome before taxonomy accounting and completion", async () => {
  for (const audio of [false, true]) {
    const f = await setup(audio);
    assertEquals(
      await executeCompositionAnalysis(f.work, f.deps),
      "complete",
    );
    assertEquals(f.calls, [
      "prepare",
      "dispatch",
      "invoke",
      "outcome",
      "resolve_species",
      "draft",
      "account",
      "complete",
      "release",
    ]);
    assertEquals(f.payloads[1].quota_token, f.work.quota!.lease_token);
  }
});
Deno.test("composition dispatch uncertainty false and malformed receipts never invoke or refund", async () => {
  for (const answer of [false, "throw", "malformed"]) {
    const f = await setup(), advance = f.deps.advance;
    f.deps.advance = (op, payload) =>
      op !== "dispatch"
        ? advance(op, payload)
        : answer === "throw"
        ? Promise.reject(new Error("lost dispatch"))
        : Promise.resolve(
          answer === false
            ? { invocation_id: id(913), may_dispatch: false }
            : { may_dispatch: true },
        );
    if (answer === false) {
      assertEquals(
        await executeCompositionAnalysis(f.work, f.deps),
        "dispatched",
      );
    } else {await assertRejects(() =>
        executeCompositionAnalysis(f.work, f.deps)
      );}
    assertEquals(f.calls, ["prepare", "release"]);
  }
});
Deno.test("composition unknown or thrown invocation stays held with no outcome or settlement", async () => {
  for (
    const failure of [
      "unknown_execution",
      "operational_failure",
      "throw",
    ] as const
  ) {
    const f = await setup();
    f.deps.prepare = () =>
      Promise.resolve({
        snapshot: f.snapshot,
        invoke: () => {
          f.calls.push("invoke");
          return failure === "throw"
            ? Promise.reject(new Error("uncertain"))
            : Promise.resolve({ ...f.outcome, kind: failure });
        },
      });
    if (failure === "throw") {
      await assertRejects(() => executeCompositionAnalysis(f.work, f.deps));
    } else {assertEquals(
        await executeCompositionAnalysis(f.work, f.deps),
        "dispatched",
      );}
    assertEquals(f.calls, ["dispatch", "invoke", "release"]);
  }
});
Deno.test("composition cancellation before dispatch never invokes and after invoke retains received evidence", async () => {
  for (const stage of ["prepare", "dispatch", "invoke"]) {
    const f = await setup(),
      controller = new AbortController(),
      advance = f.deps.advance;
    f.deps.prepare = () => {
      if (stage === "prepare") controller.abort();
      return Promise.resolve({
        snapshot: f.snapshot,
        invoke: () => {
          f.calls.push("invoke");
          controller.abort();
          return Promise.resolve(f.outcome);
        },
      });
    };
    f.deps.advance = (op, payload) => {
      if (op === "dispatch" && stage === "dispatch") controller.abort();
      return advance(op, payload);
    };
    if (stage !== "invoke") {
      await assertRejects(() =>
        executeCompositionAnalysis(f.work, f.deps, controller.signal)
      );
    } else {assertEquals(
        await executeCompositionAnalysis(
          f.work,
          f.deps,
          controller.signal,
        ),
        "complete",
      );}
    assertEquals(f.calls.includes("invoke"), stage === "invoke");
    assertEquals(f.calls.includes("outcome"), stage === "invoke");
    assertEquals(f.calls.at(-1), "release");
  }
});
Deno.test("composition known outcomes recover without preparation invocation or media reads", async () => {
  for (const kind of ["draft", "refusal", "invalid_output"] as const) {
    const f = await setup(),
      saved = captureCompositionOutcome(f.outcome, f.work)!;
    if (kind !== "draft") saved.outcome = { kind };
    const work = {
      ...f.work,
      state: "dispatched" as const,
      provider_outcome: saved,
    };
    assertEquals(
      await executeCompositionAnalysis(work, f.deps),
      kind === "draft" ? "complete" : "failed_terminal",
    );
    assertEquals(
      f.calls,
      kind === "draft"
        ? ["resolve_species", "draft", "account", "complete", "release"]
        : ["fail", "release"],
    );
  }
  const f = await setup();
  assertEquals(
    await executeCompositionAnalysis(
      { ...f.work, state: "draft" },
      f.deps,
    ),
    "complete",
  );
  assertEquals(f.calls, ["complete", "release"]);
});
Deno.test("composition settlement failure keeps recovery durable and always awaits release", async () => {
  for (
    const failed of [
      "outcome",
      "resolve_species",
      "draft",
      "account",
      "complete",
    ]
  ) {
    const f = await setup(),
      advance = f.deps.advance,
      resolve = f.deps.resolveSpecies;
    f.deps.advance = async (op, payload) => {
      if (op === failed) throw new Error("held");
      await advance(op, payload);
      if (op === "dispatch") {
        return { invocation_id: id(913), may_dispatch: true };
      }
      if (op === "release") await new Promise((r) => setTimeout(r, 5));
      return {};
    };
    f.deps.resolveSpecies = (result) =>
      failed === "resolve_species"
        ? Promise.reject(new Error("held"))
        : resolve(result);
    await assertRejects(
      () => executeCompositionAnalysis(f.work, f.deps),
      Error,
      "held",
    );
    assertEquals(f.calls.at(-1), "release");
    assertEquals(f.calls.filter((x) => x === "invoke").length, 1);
  }
});
Deno.test("composition work parser rejects forged claim authority before execution and owns snapshots", async () => {
  const f = await setup(), input = f.f.input;
  const parse = (value: unknown) =>
    parseCompositionAnalysisWork(
      value,
      input.observation_id,
      input.analysis_id,
    );
  const parsed = parse(f.work);
  f.work.quota!.model = "tampered";
  assertEquals(parsed.quota!.model, "gemini-2.5-flash");
  for (
    const change of [
      { claimed: "true" },
      { state: "other" },
      { extra: true },
      { input: { ...input, analysis_id: id(999) } },
      { work_token: null },
      { quota: { ...parsed.quota, attempt_count: 2 } },
      { quota: { ...parsed.quota, request_id: id(998) } },
      { quota: { ...parsed.quota, provider: "openai" } },
      { quota: { ...parsed.quota, input_profile: "multimodal_audio_v1" } },
      { quota: { ...parsed.quota, effective_tier: "pro" } },
      { state: "dispatched" },
      { state: "draft", provider_outcome: null, draft: {} },
      { padding: "x".repeat(3 * 1048576) },
    ]
  ) assertThrows(() => parse({ ...parsed, ...change }));
  for (
    const state of [
      "admitted",
      "dispatched",
      "draft",
      "complete",
      "failed_terminal",
    ] as const
  ) {
    assertEquals(
      await executeCompositionAnalysis(
        parse({ state, claimed: false }),
        f.deps,
      ),
      state,
    );
  }
  assertEquals(f.calls, []);
});

Deno.test("composition snapshot rejects wrong profile and substituted provider result", async () => {
  const f = await setup(false);
  assertThrows(() =>
    assertCompositionExecutionSnapshot({
      ...f.work,
      quota: { ...f.work.quota, input_profile: "multimodal_photo_v1" },
    }, f.snapshot)
  );
  for (const key of ["prompt", "model", "binding", "provider"] as const) {
    const changed = { ...f.snapshot, [key]: "substituted" };
    assertThrows(() =>
      assertCompositionExecutionSnapshot(f.work, changed as typeof f.snapshot)
    );
  }
  const captured = captureCompositionOutcome(f.outcome, f.work)!;
  assertEquals(captured.outcome.kind, "draft");
  await executeCompositionAnalysis(f.work, f.deps);
  const draft = f.payloads.find((p) => "draft" in p)!.draft as Record<
    string,
    unknown
  >;
  assertEquals(draft.schema_version, 5);
  assertEquals(draft.evidence_manifest, f.work.input!.evidence_manifest);
  assertEquals(draft.source_analysis_id, f.work.input!.source_analysis_id);
});

Deno.test("composition profile and snapshot agree with provider registry for every saved media shape", async () => {
  const rows: { valid: boolean; input: unknown }[] = JSON.parse(
    await Deno.readTextFile(
      new URL("./fixtures/composition-request-v5.json", import.meta.url),
    ),
  );
  for (const row of rows.filter((row) => row.valid)) {
    const input = parseCompositionAdmission(row.input);
    const evidence: import("../ai/contracts.ts").IdentifyEvidence[] = [];
    let images = 0, audio = 0, videos = 0, frames = 0;
    for (const node of input.evidence_manifest.items) {
      if (node.kind === "description") {
        evidence.push({
          kind: "text",
          source: "observation_context",
          order: evidence.length,
          text: node.text,
        });
      } else if (node.kind === "image") {
        evidence.push({
          kind: "image",
          order: evidence.length,
          inputIndex: images++,
          lineage: null,
          mimeType: node.artifact.content_type,
          data: "AQID",
        });
      } else if (node.kind === "audio") {
        evidence.push({
          kind: "audio",
          order: evidence.length,
          inputIndex: audio++,
          lineage: null,
          mimeType: "audio/wav",
          data: "AQID",
        });
      } else if (node.kind === "video") {
        for (const frame of node.provenance.frames) {
          evidence.push({
            kind: "image",
            order: evidence.length,
            inputIndex: images++,
            lineage: {
              kind: "video_frame",
              clipIndex: videos,
              frameIndex: frame.index,
            },
            mimeType: frame.artifact.content_type,
            data: "AQID",
          });
          frames++;
        }
        if (node.provenance.audio) {
          evidence.push({
            kind: "audio",
            order: evidence.length,
            inputIndex: audio++,
            lineage: { kind: "video_audio", clipIndex: videos },
            mimeType: "audio/wav",
            data: "AQID",
          });
        }
        videos++;
      }
    }
    const request: import("../ai/contracts.ts").MultimodalAIRequest = {
      task: "identify",
      variant: "multimodal",
      evidence,
      capture: {
        hasVideo: videos > 0,
        videoClipCount: videos,
        declaredVideoFrameCount: frames,
        videoInferenceFrameCount: frames,
      },
    };
    const profile = compositionExecutionProfile(input);
    for (const binding of ["gemini_baseline_v1", "gemini_generation3_v1"]) {
      for (const tier of ["free", "pro"]) {
        const f = await setup(false);
        const work = {
          ...f.work,
          input,
          quota: {
            ...f.work.quota,
            request_id: input.analysis_id,
            original_analysis_id: input.analysis_id,
            input_profile: profile.profile,
            binding,
            effective_tier: tier,
            model: binding === "gemini_generation3_v1"
              ? "gemini-3.8-flash"
              : tier === "pro"
              ? "gemini-2.5-pro"
              : "gemini-2.5-flash",
          },
        };
        const snapshot = resolveAIClaim(
          request,
          analysisAuthority(id(900), work),
        );
        assertCompositionExecutionSnapshot(work, snapshot);
        assertEquals(snapshot.prompt, profile.prompt);
        assertEquals(
          parseCompositionAnalysisWork(
            work,
            input.observation_id,
            input.analysis_id,
          ).input,
          input,
        );
      }
    }
  }
});
