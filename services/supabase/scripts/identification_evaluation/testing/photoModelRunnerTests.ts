import { createOpenAIPhotoModelEvaluationAdapter } from "../../../functions/_shared/ai/openai.ts";
import { openAIPhotoModelSnapshot } from "../../../functions/_shared/ai/openaiPhotoModels.ts";
import {
  openAIPhotoModerationFixture,
  openAIResponseFixture,
} from "../../../functions/_shared/ai/testing/openaiFixtures.ts";
import { assert, assertEquals, assertRejects } from "@std/assert";
import { join } from "node:path";
import type { AIProviderOutcome } from "../../../functions/_shared/ai/contracts.ts";
import { fingerprintBytes, fingerprintJson } from "../evidence.ts";
import { CRITERIA, type Ratings } from "../explanationContracts.ts";
import { atomicJson, exists, readJson } from "../files.ts";
import { validatePhotoModelApproval } from "../photoModelAdmission.ts";
import {
  loadPhotoModelPacket,
  type PhotoModelAssignment,
} from "../photoModelPreparation.ts";
import { executePhotoModelComparison } from "../photoModelRunner.ts";
import { parsePhotoModelPlan } from "../photoModelContracts.ts";
import { parseTaxonomy, type SourceIdentity } from "../runContracts.ts";
import { photoModelFixture } from "./photoModelPreparationTests.ts";

const source: SourceIdentity = {
  commit: "0".repeat(40),
  dirty: true,
  digest: "1".repeat(64),
  sdk: "npm:@google/genai@2.23.0",
};
const pass = (): Ratings =>
  Object.fromEntries(
    CRITERIA.map((k) => [k, { status: "pass", reason: "supported" }]),
  ) as Ratings;
async function setup(scratch: string, budget = 40) {
  const root = await Deno.makeTempDir({
    dir: scratch,
    prefix: "photo-runner-",
  });
  const f = await photoModelFixture(root, Date.now());
  await atomicJson(
    join(root, "photo-model-plan.json"),
    parsePhotoModelPlan({
      ...f.plan,
      version: "photo_model_plan_v2",
      budgetUsd: budget,
    }),
  );
  const taxonomy = parseTaxonomy(await readJson(join(root, "taxonomy.json")));
  const calls: number[] = [];
  const outcome = (
    a: PhotoModelAssignment,
  ): Promise<AIProviderOutcome> => {
    calls.push(a.ordinal);
    const r = f.corpus.cases.find((c) => c.input.caseId === a.caseId)!
      .provisionalReference!;
    const taxon = taxonomy.taxa.find((t) =>
      t.taxon.id === r.acceptableTaxa[0]?.id
    );
    const name = taxon
      ? "names" in taxon ? taxon.names[0] : taxon.canonicalName
      : null;
    return Promise.resolve({
      kind: "draft",
      returnedModel: a.model,
      serviceTier: "default",
      providerDurationMs: 123,
      providerCompletedAt: Date.now(),
      finishReason: "completed",
      responseCharacters: 10,
      mediaSafety: {
        provider: "openai",
        policy: "openai_photo_moderation_v1",
        disposition: "allowed",
      },
      usage: {
        promptTokens: 1000,
        outputTokens: 200,
        candidateTokens: 100,
        thinkingTokens: 100,
        totalTokens: 1200,
        cachedTokens: 0,
        cacheWriteTokens: 0,
        toolTokens: 0,
        modalityBreakdown: {},
      },
      draft: {
        is_biological_subject: r.subject === "biological",
        is_live_capture: true,
        scientific_name: name,
        common_name: name ?? "Unresolved synthetic fixture",
        confidence_score: name ? .8 : 0,
        ai_reasoning: "Private synthetic explanation sentinel.",
        extracted_visual_traits: ["Private synthetic trait sentinel."],
        candidates: [],
        image_quality: {
          sharpness: 1,
          framing: 1,
          diagnostic_utility: 1,
          overall_score: 0,
        },
      },
    });
  };
  const dependencies = { outcome, review: () => Promise.resolve(pass()) };
  const run = () =>
    executePhotoModelComparison(root, source, "offline", dependencies);
  return { root, f, calls, outcome, dependencies, run };
}
export function registerPhotoModelRunnerTests(scratch: string) {
  Deno.test("photo-model controller freezes 18 calls, paired order and ratings without model prose; completed resume sends nothing", async () => {
    const s = await setup(scratch);
    try {
      const state = await s.run();
      assertEquals(state.complete, true);
      assertEquals(state.claimedCalls, 18);
      assertEquals(state.completedCalls, 18);
      assertEquals(state.heldReservationUsd, 39.0071088);
      assertEquals(s.calls, Array.from({ length: 18 }, (_, i) => i + 1));
      assertEquals(await s.run(), state);
      assertEquals(s.calls.length, 18);
      for (const dir of ["claims", "results", "reviews"]) {
        for await (
          const entry of Deno.readDir(join(s.root, "photo-model-run", dir))
        ) {
          const path = join(s.root, "photo-model-run", dir, entry.name);
          assertEquals((await Deno.stat(path)).mode! & 0o077, 0);
          const value = JSON.stringify(await readJson(path));
          for (
            const sentinel of [
              "Private synthetic",
              "data:image",
              "Authorization",
              "ai_reasoning",
              "synthetic-key",
            ]
          ) assert(!value.includes(sentinel));
        }
      }
    } finally {
      await Deno.remove(s.root, { recursive: true });
    }
  });
  Deno.test("photo-model controller denies insufficient total budget and injected live execution before any claim", async () => {
    const s = await setup(scratch, 5);
    try {
      await assertRejects(s.run);
      assertEquals(s.calls.length, 0);
      assertEquals(await exists(join(s.root, "photo-model-run")), false);
      await assertRejects(() =>
        executePhotoModelComparison(s.root, source, "live", s.dependencies)
      );
      assertEquals(s.calls.length, 0);
    } finally {
      await Deno.remove(s.root, { recursive: true });
    }
  });
  Deno.test("photo-model screening blocks challenges after a wrong match or failed explanation and survives restart", async () => {
    for (const kind of ["wrong_match", "bad_review"] as const) {
      const s = await setup(scratch);
      try {
        const outcome = s.outcome;
        s.dependencies.outcome = async (a) => {
          const r = await outcome(a);
          return kind === "wrong_match" && a.ordinal === 3 && r.kind === "draft"
            ? {
              ...r,
              draft: {
                ...(r.draft as Record<string, unknown>),
                scientific_name: "Syntheticus unknown",
              },
            }
            : r;
        };
        s.dependencies.review = () =>
          Promise.resolve(
            kind === "bad_review" && s.calls.length === 6
              ? {
                ...pass(),
                grounding: { status: "fail", reason: "invented_evidence" },
              }
              : pass(),
          );
        const state = await s.run();
        assertEquals(state.stop, "screen_failed");
        assertEquals(s.calls.length, kind === "wrong_match" ? 3 : 6);
        assertEquals(await s.run(), state);
      } finally {
        await Deno.remove(s.root, { recursive: true });
      }
    }
  });
  Deno.test("photo-model failures and missing billing retain reservations and are never replaced by successful retries", async () => {
    for (
      const failure of [
        "exception",
        "missing_usage",
        "wrong_model",
        "refusal",
        "safety",
      ] as const
    ) {
      const s = await setup(scratch);
      try {
        const outcome = s.outcome;
        s.dependencies.outcome = async (a) => {
          const r = await outcome(a);
          if (a.ordinal !== 8) return r;
          if (failure === "exception") {
            throw new Error("private provider diagnostics");
          }
          if (failure === "missing_usage") return { ...r, usage: null };
          if (failure === "wrong_model") {
            return { ...r, returnedModel: "unknown-private-model" };
          }
          if (failure === "safety") {
            return {
              ...r,
              mediaSafety: {
                provider: "openai",
                policy: "openai_photo_moderation_v1",
                disposition: "unavailable",
              },
            };
          }
          const { draft: _draft, ...facts } = r as Extract<
            AIProviderOutcome,
            { kind: "draft" }
          >;
          return { ...facts, kind: "refusal" };
        };
        const state = await s.run();
        assertEquals(state.stop, "provider_failure");
        assertEquals(s.calls.length, 8);
        assert(
          state.heldReservationUsd !== null && state.heldReservationUsd > 0,
        );
        assertEquals(await s.run(), state);
        assertEquals(s.calls.length, 8);
        assert(
          !JSON.stringify(
            await readJson(
              join(s.root, "photo-model-run", "results", "08.json"),
            ),
          ).includes("private"),
        );
      } finally {
        await Deno.remove(s.root, { recursive: true });
      }
    }
  });
  Deno.test("photo-model crash reconciliation ignores cached success and never repeats a claim or a lost review", async () => {
    for (const lost of ["result", "review"] as const) {
      const s = await setup(scratch);
      try {
        await s.run();
        for (const dir of ["claims", "results", "reviews"]) {
          for (let n = 2; n <= 18; n++) {
            await Deno.remove(
              join(
                s.root,
                "photo-model-run",
                dir,
                String(n).padStart(2, "0") + ".json",
              ),
            );
          }
        }
        await Deno.remove(
          join(s.root, "photo-model-run", "reviews", "01.json"),
        );
        if (lost === "result") {
          await Deno.remove(
            join(s.root, "photo-model-run", "results", "01.json"),
          );
        }
        const state = await s.run();
        assertEquals(
          state.stop,
          lost === "result" ? "interrupted_attempt" : "review_missing",
        );
        assertEquals(state.claimedCalls, 1);
        assertEquals(s.calls.length, 18);
        assertEquals(await s.run(), state);
        assertEquals(s.calls.length, 18);
      } finally {
        await Deno.remove(s.root, { recursive: true });
      }
    }
  });
  Deno.test("photo-model controller refuses concurrent execution, changed source and rebound result reviews", async () => {
    const s = await setup(scratch);
    let release!: () => void;
    const hold = new Promise<void>((r) => release = r);
    let entered!: () => void;
    const started = new Promise<void>((r) => entered = r);
    try {
      const outcome = s.outcome;
      s.dependencies.outcome = async (a) => {
        const r = await outcome(a);
        if (a.ordinal === 1) {
          entered();
          await hold;
        }
        return r;
      };
      const first = s.run();
      await started;
      await assertRejects(s.run);
      assertEquals(s.calls.length, 1);
      release();
      await first;
      const changed = await executePhotoModelComparison(
        s.root,
        { ...source, digest: "2".repeat(64) },
        "offline",
        s.dependencies,
      );
      assertEquals(changed.stop, "configuration_invalid");
      assertEquals((await s.run()).stop, "configuration_invalid");
      const path = join(s.root, "photo-model-run", "reviews", "01.json");
      const review = await readJson(path) as Record<string, unknown>;
      await atomicJson(path, { ...review, resultDigest: "0".repeat(64) });
      await assertRejects(s.run);
      assertEquals(s.calls.length, 18);
    } finally {
      release();
      await Deno.remove(s.root, { recursive: true });
    }
  });
  Deno.test("photo-model input drift stops durably before the next call and cannot be cleared by restoring the packet", async () => {
    for (const moment of ["during", "resume"] as const) {
      const s = await setup(scratch);
      const pricePath = join(s.root, "photo-model-pricing.json"),
        price = await readJson(pricePath);
      try {
        if (moment === "during") {
          s.dependencies.review = async () => {
            await atomicJson(pricePath, {});
            return pass();
          };
        } else await s.run();
        if (moment === "resume") await atomicJson(pricePath, {});
        const stopped = await s.run();
        assertEquals(stopped.stop, "configuration_invalid");
        const calls = s.calls.length;
        assertEquals(calls, moment === "during" ? 1 : 18);
        await atomicJson(pricePath, price);
        assertEquals((await s.run()).stop, "configuration_invalid");
        assertEquals(s.calls.length, calls);
      } finally {
        await Deno.remove(s.root, { recursive: true });
      }
    }
  });
  Deno.test("photo-model native decoder failures retain a specific bounded audit reason", async () => {
    for (const failure of ["model_mismatch", "safety_unavailable"] as const) {
      const s = await setup(scratch);
      try {
        s.dependencies.outcome = async (a) => {
          s.calls.push(a.ordinal);
          const packet = await loadPhotoModelPacket(s.root, source);
          const { prepareEvidence } = await import("../assets.ts");
          const request = await prepareEvidence(
            s.root,
            packet.corpus.cases.find((c) => c.input.caseId === a.caseId)!.input,
          );
          const snapshot = openAIPhotoModelSnapshot(request, a.profile);
          const adapter = createOpenAIPhotoModelEvaluationAdapter(
            "synthetic-key",
            () =>
              Promise.resolve(Response.json({
                ...openAIResponseFixture(),
                model: failure === "model_mismatch" ? "gpt-6-sol" : a.model,
                ...(failure === "model_mismatch"
                  ? { moderation: openAIPhotoModerationFixture() }
                  : {}),
              })),
          );
          return await adapter.prepare(request, snapshot)();
        };
        assertEquals((await s.run()).stop, "provider_failure");
        const record = await readJson(
          join(s.root, "photo-model-run", "results", "01.json"),
        ) as { reason: string };
        assertEquals(record.reason, failure);
        assertEquals(s.calls.length, 1);
      } finally {
        await Deno.remove(s.root, { recursive: true });
      }
    }
  });
  Deno.test("photo-model unavailable challenge review remains terminal even without a cached stop summary", async () => {
    const s = await setup(scratch);
    try {
      s.dependencies.review = () =>
        Promise.resolve(
          s.calls.length === 7
            ? {
              ...pass(),
              grounding: {
                status: "not_assessable",
                reason: "review_unavailable",
              },
            }
            : pass(),
        );
      assertEquals((await s.run()).stop, "review_missing");
      assertEquals(s.calls.length, 7);
      await Deno.remove(join(s.root, "photo-model-run", "stop.json"));
      assertEquals((await s.run()).stop, "review_missing");
      assertEquals(s.calls.length, 7);
    } finally {
      await Deno.remove(s.root, { recursive: true });
    }
  });
  Deno.test("photo-model live approval binds exact revision, scope, key, budget, timing and assistant delegation", async () => {
    const s = await setup(scratch);
    try {
      const packet = await loadPhotoModelPacket(s.root, source);
      // Synthetic object exercise of approval parsing only; no live dispatch or corpus admission.
      packet.report.source.dirty = false;
      packet.corpus.evidenceOrigin = "real";
      packet.plan.inputApproval = {
        provider: "openai",
        corpusDigest: packet.plan.corpusDigest,
        caseIds: [
          ...packet.plan.screenCaseIds,
          ...packet.plan.challengeCaseIds,
        ],
        recordRef: "synthetic-input-approval",
      };
      const now = Date.now(), key = "synthetic-key";
      const approval = {
        version: "photo_model_approval_v1",
        project: "naturebook",
        operation: "18_call_luna_sol_photo_comparison",
        planDigest: await fingerprintJson(packet.plan),
        sourceCommit: source.commit,
        sourceDigest: source.digest,
        credentialSha256: await fingerprintBytes(new TextEncoder().encode(key)),
        budgetUsd: 40,
        approvedAt: new Date(now).toISOString(),
        expiresAt: new Date(now + 3600000).toISOString(),
        recordRef: "synthetic-budget-approval",
        reviewerRef: "codex",
        delegationRef: "synthetic-owner-delegation",
      };
      await validatePhotoModelApproval(approval, packet, key, now);
      for (
        const delta of [
          { project: "other" },
          { operation: "deploy" },
          { planDigest: "0".repeat(64) },
          { sourceDigest: "2".repeat(64) },
          { credentialSha256: "3".repeat(64) },
          { budgetUsd: 5 },
          { expiresAt: new Date(now).toISOString() },
          { expiresAt: new Date(now + 25 * 3600000).toISOString() },
          { provider: "gemini" },
        ]
      ) {
        await assertRejects(() =>
          validatePhotoModelApproval(
            { ...approval, ...delta },
            packet,
            key,
            now,
          )
        );
      }
      packet.report.source.dirty = true;
      await assertRejects(() =>
        validatePhotoModelApproval(approval, packet, key, now)
      );
      assertEquals(s.calls.length, 0);
    } finally {
      await Deno.remove(s.root, { recursive: true });
    }
  });
}
