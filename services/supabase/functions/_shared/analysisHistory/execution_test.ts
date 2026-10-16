import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import { resolveAIClaim } from "../ai/registry.ts";
import { openAITextFixture } from "../ai/testing/openaiFixtures.ts";
import type { AIExecutionOutcome } from "../ai/contracts.ts";
import { identificationProvenance } from "../ai/provenance.ts";
import {
  type AnalysisExecutionDependencies,
  type AnalysisWork,
  captureAnalysisOutcome,
  executeObservationAnalysis,
  type SavedAnalysisOutcome,
} from "./execution.ts";
import { parseExecutableAnalysisInput } from "./analysisInput.ts";
import { identificationUsageFacts } from "../ai/identificationUsage.ts";
import { analysisAuthority } from "./production.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const fixture = JSON.parse(
  await Deno.readTextFile(new URL("./fixtures/page-v1.json", import.meta.url)),
);
const original = JSON.parse(fixture.items[0].snapshot);
const input = {
  schema_version: 1,
  observation_id: original.observation_id,
  analysis_id: original.analysis_id,
  source_analysis_id: null,
  request_digest: "a".repeat(64),
  evidence_manifest: original.evidence_manifest,
  entitlement_protocol: 3,
  identification_protocol: 6,
  history_protocol: 7,
  expected_processor_permission: "google_gemini",
};
function setup() {
  const work: AnalysisWork = {
    state: "admitted",
    claimed: true,
    work_token: id(9),
    input,
    quota: { effective_tier: "free", lease_token: id(10) },
  };
  const snapshot = resolveAIClaim(openAITextFixture(), {
    kind: "user_request",
    userId: id(3),
    permission: "google_gemini",
    operation: "scan_identification",
    reservation: {
      id: id(4),
      requestId: id(5),
      attemptCount: 1,
      policyVersion: 7,
      model: "gemini-2.5-flash",
      tier: { effective_tier: "free" },
      assignment: {
        inputProfile: "multimodal_text_v1",
        provider: "gemini",
        binding: "gemini_baseline_v1",
        permission: "google_gemini",
      },
    },
  });
  const outcome: AIExecutionOutcome = {
    kind: "draft",
    draft: { ...original.result, candidates: [] },
    execution: { ...snapshot, durationMs: 1 },
    providerDurationMs: 1,
    providerCompletedAt: 1,
    returnedModel: snapshot.model,
    usage: null,
    finishReason: "STOP",
    responseCharacters: 10,
  };
  const calls: string[] = [];
  let saved: SavedAnalysisOutcome | undefined;
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
      if (op === "outcome") saved = payload.value as SavedAnalysisOutcome;
      return Promise.resolve(op === "dispatch" ? { may_dispatch: true } : {});
    },
    resolveSpecies: () => {
      calls.push("taxonomy");
      return Promise.resolve({
        id: id(4),
        scientific_name: original.result.scientific_name,
      });
    },
  };
  return { work, snapshot, outcome, deps, calls, saved: () => saved };
}
Deno.test("history execution durably captures output before taxonomy and completes without selecting", async () => {
  const f = setup();
  assertEquals(await executeObservationAnalysis(f.work, f.deps), "complete");
  assertEquals(f.calls, [
    "prepare",
    "dispatch",
    "invoke",
    "outcome",
    "taxonomy",
    "draft",
    "complete",
    "release",
  ]);
  assertEquals(f.saved()?.outcome.kind, "draft");
  assertEquals(f.saved()?.provenance, identificationProvenance(f.snapshot));
});
Deno.test("history recovery after taxonomy failure uses saved result without preparing or invoking", async () => {
  const f = setup();
  await assertRejects(() =>
    executeObservationAnalysis(f.work, {
      ...f.deps,
      resolveSpecies: () => Promise.reject(new Error("synthetic offline")),
    })
  );
  assert(f.saved());
  f.calls.length = 0;
  assertEquals(
    await executeObservationAnalysis({
      ...f.work,
      state: "dispatched",
      provider_outcome: f.saved(),
    }, f.deps),
    "complete",
  );
  assertEquals(f.calls, ["taxonomy", "draft", "complete", "release"]);
});
Deno.test("history durable draft retry only completes and busy terminal replay does no work", async () => {
  const f = setup();
  assertEquals(
    await executeObservationAnalysis({ ...f.work, state: "draft" }, f.deps),
    "complete",
  );
  assertEquals(f.calls, ["complete", "release"]);
  f.calls.length = 0;
  assertEquals(
    await executeObservationAnalysis(
      { state: "complete", claimed: false },
      f.deps,
    ),
    "complete",
  );
  assertEquals(f.calls, []);
});
Deno.test("history ambiguous dispatch acknowledgement never invokes or terminalizes", async () => {
  for (const lost of [true, false]) {
    const f = setup();
    const deps = {
      ...f.deps,
      advance: (op: string, payload: Record<string, unknown>) =>
        op === "dispatch"
          ? lost
            ? Promise.reject(new Error("lost"))
            : Promise.resolve({ may_dispatch: false })
          : f.deps.advance(op, payload),
    };
    if (lost) {
      await assertRejects(() => executeObservationAnalysis(f.work, deps));
    } else {assertEquals(
        await executeObservationAnalysis(f.work, deps),
        "dispatched",
      );}
    assertEquals(
      f.calls,
      lost
        ? ["prepare", "cancel_uninvoked", "release"]
        : ["prepare", "release"],
    );
  }
});
Deno.test("history unknown provider outcomes preserve hold and never become a retry instruction", () => {
  const f = setup();
  for (const kind of ["unknown_execution", "operational_failure"] as const) {
    assertEquals(captureAnalysisOutcome({ ...f.outcome, kind }, f.work), null);
  }
});
Deno.test("history proven refusal and invalid results are persisted before terminal settlement", async () => {
  for (const kind of ["refusal", "invalid_output"] as const) {
    const f = setup();
    const saved = captureAnalysisOutcome(
      { ...f.outcome, kind, reason: "json" },
      f.work,
    );
    assert(saved);
    assertEquals(
      await executeObservationAnalysis({
        ...f.work,
        state: "dispatched",
        provider_outcome: saved,
      }, f.deps),
      "failed_terminal",
    );
    assertEquals(f.calls, ["fail", "release"]);
  }
});
Deno.test("history deleted parent after provider completion prevents all downstream work", async () => {
  const f = setup();
  await assertRejects(() =>
    executeObservationAnalysis(f.work, {
      ...f.deps,
      advance: (op, payload) =>
        op === "outcome"
          ? Promise.reject(new Error("deleted"))
          : f.deps.advance(op, payload),
    })
  );
  assertEquals(f.calls, ["prepare", "dispatch", "invoke", "release"]);
});
Deno.test("history input rejects provider budget excess and caller owner fields before admission", () => {
  assertEquals(parseExecutableAnalysisInput(input), input);
  assertThrows(() =>
    parseExecutableAnalysisInput({ ...input, owner_id: id(3) })
  );
  const v2 = {
    ...input,
    schema_version: 2,
    history_protocol: 8,
    expected_processor_permission: "openai",
    evidence_manifest: {
      schema_version: 2,
      items: [{
        kind: "image",
        media_id: id(30),
        content_type: "image/jpeg",
        byte_count: 5 * 1024 * 1024 + 1,
        sha256: "a".repeat(64),
      }],
    },
  };
  assertThrows(() => parseExecutableAnalysisInput(v2));
  assertThrows(() => analysisAuthority(id(3), setup().work));
});

Deno.test("history execution rejects HEIC and excessive photo context before reserving quota", () => {
  const base = {
    ...input,
    schema_version: 2,
    history_protocol: 8,
    expected_processor_permission: "openai",
  };
  const photo = {
    kind: "image",
    media_id: id(30),
    content_type: "image/jpeg",
    byte_count: 10,
    sha256: "a".repeat(64),
  };
  assertThrows(() =>
    parseExecutableAnalysisInput({
      ...base,
      evidence_manifest: {
        schema_version: 2,
        items: [{ ...photo, content_type: "image/heic" }],
      },
    })
  );
  assertThrows(() =>
    parseExecutableAnalysisInput({
      ...base,
      evidence_manifest: {
        schema_version: 2,
        items: [
          photo,
          ...Array.from(
            { length: 5 },
            () => ({ kind: "description", text: "x".repeat(8192) }),
          ),
        ],
      },
    })
  );
});

Deno.test("saved photo and audio outcomes recover exact persisted evidence without another provider call", async () => {
  for (const version of [2, 3]) {
    const f = setup();
    const manifest = {
      schema_version: version,
      items: [{
        kind: version === 2 ? "image" : "audio",
        media_id: id(30),
        content_type: version === 2 ? "image/jpeg" : "audio/wav",
        byte_count: 46,
        sha256: "b".repeat(64),
      }],
    };
    const persisted = JSON.stringify({
      ...input,
      schema_version: version,
      history_protocol: version === 2 ? 8 : 9,
      evidence_manifest: manifest,
    });
    f.work.input = JSON.parse(persisted);
    f.work.state = "dispatched";
    f.work.provider_outcome = {
      schema_version: 1,
      provenance: identificationProvenance(f.snapshot),
      outcome: { kind: "draft", result: original.result },
      usage: identificationUsageFacts(f.outcome),
    };
    const advance = f.deps.advance;
    f.deps.advance = (op, payload) => {
      if (op === "draft") {
        const draft = payload.draft as Record<string, unknown>;
        assertEquals(draft.schema_version, version);
        assertEquals(draft.evidence_manifest, manifest);
        assertEquals(draft.request_digest, input.request_digest);
      }
      return advance(op, payload);
    };
    assertEquals(await executeObservationAnalysis(f.work, f.deps), "complete");
    assertEquals(f.calls, ["taxonomy", "draft", "complete", "release"]);
    assertEquals(JSON.stringify(f.work.input), persisted);
  }
});
