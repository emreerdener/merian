import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import { resolveAIClaim } from "../ai/registry.ts";
import type { AIExecutionOutcome } from "../ai/contracts.ts";
import { analysisAuthority } from "./production.ts";
import {
  type AnalysisExecutionDependencies,
  type AnalysisWork,
  capturePreparedVideoOutcome,
} from "./execution.ts";
import {
  executeVideoObservationAnalysis,
  parseVideoAnalysisWork,
} from "./videoExecution.ts";
import { materializeVideoAnalysis } from "./videoProduction.ts";
import { videoByteFixture } from "./videoByteTestFixtures.ts";
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
  const f = await videoByteFixture(audio),
    input = f.input.input,
    owner = id(900);
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
      input_profile: audio
        ? "multimodal_video_audio_v1"
        : "multimodal_video_frames_v1",
    },
  };
  const request = await materializeVideoAnalysis(input, owner, f.receipt, {
    read: (item) =>
      Promise.resolve(
        f.bytes[f.receipt.items.findIndex((x) => x.media_id === item.media_id)],
      ),
  }, new AbortController().signal);
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
Deno.test("video execution orders retained outcome before taxonomy accounting and completion", async () => {
  for (const audio of [false, true]) {
    const f = await setup(audio);
    assertEquals(
      await executeVideoObservationAnalysis(f.work, f.deps),
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
Deno.test("video provider request contains five derived frames optional audio and no retained source", async () => {
  for (const audio of [false, true]) {
    const f = await setup(audio),
      media = f.request.evidence.filter((x) => x.kind !== "text");
    assertEquals(media.length, audio ? 6 : 5);
    assertEquals(
      media.slice(0, 5).map((x) => x.lineage),
      Array.from(
        { length: 5 },
        (_, frameIndex) => ({
          kind: "video_frame" as const,
          clipIndex: 0,
          frameIndex,
        }),
      ),
    );
    assertEquals(f.request.capture, {
      hasVideo: true,
      videoClipCount: 1,
      declaredVideoFrameCount: 5,
      videoInferenceFrameCount: 5,
    });
    const wire = JSON.stringify(f.request);
    for (
      const forbidden of [
        "video/mp4",
        f.f.receipt.items[0].object_id,
        f.f.receipt.items[0].media_id,
        f.f.receipt.items[0].sha256,
      ]
    ) assert(!wire.includes(forbidden));
    if (audio) {
      assertEquals(media[5].lineage, { kind: "video_audio", clipIndex: 0 });
    }
  }
});
Deno.test("video materialization failure cannot prepare a partial provider cohort", async () => {
  const f = await setup();
  for (let failed = 0; failed < f.f.bytes.length; failed++) {
    let reads = 0;
    await assertRejects(() =>
      materializeVideoAnalysis(f.work.input, id(900), f.f.receipt, {
        read: () => {
          const bytes = f.f.bytes[reads++].slice();
          if (reads === failed + 1) bytes[bytes.length - 1] ^= 1;
          return Promise.resolve(bytes);
        },
      }, new AbortController().signal)
    );
    assertEquals(reads, failed + 1);
  }
});
Deno.test("video dispatch uncertainty false and malformed receipts never invoke or refund", async () => {
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
        await executeVideoObservationAnalysis(f.work, f.deps),
        "dispatched",
      );
    } else {await assertRejects(() =>
        executeVideoObservationAnalysis(f.work, f.deps)
      );}
    assertEquals(f.calls, ["prepare", "release"]);
  }
});
Deno.test("video unknown or thrown invocation stays held with no outcome or settlement", async () => {
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
      await assertRejects(() =>
        executeVideoObservationAnalysis(f.work, f.deps)
      );
    } else {assertEquals(
        await executeVideoObservationAnalysis(f.work, f.deps),
        "dispatched",
      );}
    assertEquals(f.calls, ["dispatch", "invoke", "release"]);
  }
});
Deno.test("video cancellation before dispatch never invokes and after invoke retains received evidence", async () => {
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
        executeVideoObservationAnalysis(f.work, f.deps, controller.signal)
      );
    } else {assertEquals(
        await executeVideoObservationAnalysis(
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
Deno.test("video known outcomes recover without preparation invocation or media reads", async () => {
  for (const kind of ["draft", "refusal", "invalid_output"] as const) {
    const f = await setup(),
      saved = capturePreparedVideoOutcome(f.outcome, f.work)!;
    if (kind !== "draft") saved.outcome = { kind };
    const work = {
      ...f.work,
      state: "dispatched" as const,
      provider_outcome: saved,
    };
    assertEquals(
      await executeVideoObservationAnalysis(work, f.deps),
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
    await executeVideoObservationAnalysis(
      { ...f.work, state: "draft" },
      f.deps,
    ),
    "complete",
  );
  assertEquals(f.calls, ["complete", "release"]);
});
Deno.test("video settlement failure keeps recovery durable and always awaits release", async () => {
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
      () => executeVideoObservationAnalysis(f.work, f.deps),
      Error,
      "held",
    );
    assertEquals(f.calls.at(-1), "release");
    assertEquals(f.calls.filter((x) => x === "invoke").length, 1);
  }
});
Deno.test("video work parser rejects forged claim authority before execution and owns snapshots", async () => {
  const f = await setup(), input = f.f.input.input;
  const parse = (value: unknown) =>
    parseVideoAnalysisWork(value, input.observation_id, input.analysis_id);
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
      await executeVideoObservationAnalysis(
        parse({ state, claimed: false }),
        f.deps,
      ),
      state,
    );
  }
  assertEquals(f.calls, []);
});
