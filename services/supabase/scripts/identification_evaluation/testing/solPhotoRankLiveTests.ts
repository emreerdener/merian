import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import { join } from "node:path";
import type { AIProviderOutcome } from "../../../functions/_shared/ai/contracts.ts";
import { main } from "../../evaluate_identification.ts";
import { fingerprintBytes, fingerprintJson } from "../evidence.ts";
import type { Ratings } from "../explanationContracts.ts";
import { atomicJson, exists, readJson } from "../files.ts";
import { parsePhotoModelPlan } from "../photoModelContracts.ts";
import { parsePhotoModelRecord } from "../photoModelRecords.ts";
import { parseTaxonomy } from "../taxonomy.ts";
import { prepareSolPhotoRankPacket } from "../solPhotoRankPreparation.ts";
import {
  parseSolRankPlan,
  parseSolRankReferenceReview,
  SOL_RANK_SCREEN_POLICY,
} from "../solPhotoRankContracts.ts";
import {
  loadSolRankPacket,
  prepareSolRankComparison,
  solBillingAssignment,
  type SolRankAssignment,
} from "../solPhotoRankLivePreparation.ts";
import { executeSolRankComparison } from "../solPhotoRankRunner.ts";
import { validateSolRankApproval } from "../solPhotoRankAdmission.ts";
import { solRankPreparationFixture } from "./solPhotoRankPreparationTests.ts";
import { pass, source } from "./photoModelRunnerTests.ts";

async function setup(scratch: string) {
  const parent = await Deno.makeTempDir({ dir: scratch, prefix: "sol-live-" });
  const f = await solRankPreparationFixture(parent);
  const receipt = await prepareSolPhotoRankPacket(f.source, f.target, f.remap);
  const corpus = await readJson(
    join(f.target, "corpus.json"),
  ) as typeof f.corpus;
  const taxonomy = parseTaxonomy(
    await readJson(join(f.target, "taxonomy.json")),
  );
  const referenceReview = parseSolRankReferenceReview({
    version: "sol_photo_rank_reference_review_v1",
    corpusDigest: await fingerprintJson(corpus),
    taxonomyDigest: await fingerprintJson(taxonomy),
    factsDigest: await fingerprintJson(f.facts),
    method: "assistant_input_review_v1",
    reviewerRef: "synthetic-reviewer",
    reviewedAt: new Date().toISOString(),
    referenceStatus: "synthetic_mechanics_only",
    catalogCoverage: "finite_not_exhaustive",
    independentTruthVerified: false,
    cases: [...new Map(receipt.order.map((a) => [a.caseId, {
      caseId: a.caseId,
      inputDigest: a.inputDigest,
      referenceDigest: a.referenceDigest,
      factsDigest: a.factsDigest,
      identitySupport: "usable_provisional",
      missingEvidenceRecorded: true,
    }])).values()],
  });
  const plan = parseSolRankPlan({
    ...f.plan,
    version: "sol_photo_rank_plan_v1",
    id: "synthetic-sol-plan",
    corpusDigest: referenceReview.corpusDigest,
    taxonomyDigest: referenceReview.taxonomyDigest,
    preparationDigest: await fingerprintJson(receipt),
    referenceReviewDigest: await fingerprintJson(referenceReview),
    screeningPolicy: SOL_RANK_SCREEN_POLICY,
    budgetUsd: 110,
  });
  for (
    const [name, value] of [
      ["sol-rank-plan.json", plan],
      ["sol-rank-pricing.json", f.pricing],
      ["sol-rank-reference-review.json", referenceReview],
    ] as const
  ) await atomicJson(join(f.target, name), value);
  const calls: number[] = [];
  const outcome = (a: SolRankAssignment): Promise<AIProviderOutcome> => {
    calls.push(a.ordinal);
    const r = corpus.cases.find((c) => c.input.caseId === a.caseId)!
      .provisionalReference!;
    const t = taxonomy.taxa.find((t) => t.taxon.id === r.acceptableTaxa[0]?.id);
    const name = t ? "canonicalName" in t ? t.canonicalName : t.names[0] : null;
    return Promise.resolve({
      kind: "draft",
      returnedModel: "gpt-6-sol",
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
        common_name: name ?? "Invented control",
        confidence_score: name ? .8 : 0,
        ai_reasoning: "Private synthetic prose sentinel.",
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
  const dependencies = {
    outcome,
    review: (): Promise<Ratings | null> => Promise.resolve(pass()),
  };
  return {
    parent,
    root: f.target,
    receipt,
    corpus,
    plan,
    referenceReview,
    calls,
    dependencies,
    run: () =>
      executeSolRankComparison(f.target, source, "offline", dependencies),
  };
}
export function registerSolRankLiveTests(scratch: string) {
  Deno.test("Sol live packet freezes 18 same-model requests, reviewed limits and a separate full reservation", async () => {
    const s = await setup(scratch);
    try {
      const report = await prepareSolRankComparison(s.root, source);
      assertEquals(report.regionalReservationUsd, 106.383024);
      assertEquals(report.budgetFitsRegionalReservation, true);
      assertEquals(report.order.length, 18);
      assertEquals(report.recordVersion, "photo_model_attempt_v2");
      assert(report.order.every((a) => a.model === "gpt-6-sol"));
      assertEquals(
        report.order.map(({ reservedNanoUsd: _, ...a }) => a),
        s.receipt.order,
      );
      assertEquals(await exists(join(s.root, "sol-photo-rank-run")), false);
      assertThrows(() => parsePhotoModelPlan(s.plan));
      for (
        const change of [
          { maxCalls: 19 },
          { attemptsPerAssignment: 2 },
          { budgetUsd: 111 },
          { screeningPolicy: "reference_gaps_recorded_v1" },
          { version: "photo_model_plan_v3" },
        ]
      ) {
        assertThrows(() => parseSolRankPlan({ ...s.plan, ...change }));
      }
      await main(["preflight-sol-rank-photo", s.root]);
      await assertRejects(() => main(["preflight-free-pro-photo", s.root]));
    } finally {
      await Deno.remove(s.parent, { recursive: true });
    }
  });
  Deno.test("Sol packet rejects changed media, stale references, preparation/order drift and unreviewed pricing", async () => {
    for (
      const kind of [
        "media",
        "reference",
        "preparation",
        "facts",
        "pricing",
      ] as const
    ) {
      const s = await setup(scratch);
      try {
        if (kind === "media") {
          await Deno.writeFile(
            join(s.root, s.corpus.cases[0].input.assets[0].path),
            new Uint8Array([0]),
          );
        }
        if (kind === "reference") {
          s.referenceReview.cases[0].inputDigest = "f".repeat(64);
          s.plan.referenceReviewDigest = await fingerprintJson(
            s.referenceReview,
          );
          await atomicJson(
            join(s.root, "sol-rank-reference-review.json"),
            s.referenceReview,
          );
          await atomicJson(join(s.root, "sol-rank-plan.json"), s.plan);
        }
        if (kind === "preparation") {
          s.receipt.order[0].requestDigest = "f".repeat(64);
          s.plan.preparationDigest = await fingerprintJson(s.receipt);
          await atomicJson(
            join(s.root, "sol-rank-preparation.json"),
            s.receipt,
          );
          await atomicJson(join(s.root, "sol-rank-plan.json"), s.plan);
        }
        if (kind === "facts") {
          await atomicJson(join(s.root, "photo-model-facts.json"), {});
        }
        if (kind === "pricing") {
          const p = await readJson(
            join(s.root, "sol-rank-pricing.json"),
          ) as Record<string, unknown>;
          p.retrievedAt = new Date(Date.now() - 8 * 86400000).toISOString();
          s.plan.pricingDigest = await fingerprintJson(p);
          await atomicJson(join(s.root, "sol-rank-pricing.json"), p);
          await atomicJson(join(s.root, "sol-rank-plan.json"), s.plan);
        }
        await assertRejects(() => s.run());
        assertEquals(s.calls.length, 0);
        assertEquals(await exists(join(s.root, "sol-photo-rank-run")), false);
      } finally {
        await Deno.remove(s.parent, { recursive: true });
      }
    }
  });
  Deno.test("Sol controller journals v2 mapping with assistant ratings, preserves prose privacy and never redispatches completed claims", async () => {
    const s = await setup(scratch);
    try {
      assertEquals((await s.run()).complete, true);
      assertEquals(s.calls.length, 18);
      const run = join(s.root, "sol-photo-rank-run");
      const manifest = await readJson(join(run, "manifest.json")) as Record<
        string,
        unknown
      >;
      assertEquals(manifest.version, "sol_photo_rank_run_v1");
      const record = await readJson(join(run, "results", "01.json")) as Record<
        string,
        unknown
      >;
      assertEquals(record.version, "photo_model_attempt_v2");
      assertEquals(
        (record.mapping as Record<string, unknown>).status,
        "matched",
      );
      const packet = await loadSolRankPacket(s.root, source);
      assertThrows(() =>
        parsePhotoModelRecord(
          record,
          solBillingAssignment(packet.report.order[0]),
          record.runDigest as string,
          record.assignmentDigest as string,
        )
      );
      const summary = await readJson(join(run, "summary.json")) as Record<
        string,
        unknown
      >;
      assertEquals(summary.pairedChallengeCases, 6);
      assertEquals(summary.productionActivationAuthorized, false);
      const walk = async (dir: string): Promise<string> => {
        let text = "";
        for await (const e of Deno.readDir(dir)) {
          text += e.isDirectory
            ? await walk(join(dir, e.name))
            : await Deno.readTextFile(join(dir, e.name));
        }
        return text;
      };
      const stored = await walk(run);
      assert(!stored.includes("Private synthetic"));
      assert(!stored.includes("data:image"));
      assertEquals((await s.run()).complete, true);
      assertEquals(s.calls.length, 18);
      assertEquals(await exists(join(s.root, "photo-model-run")), false);
    } finally {
      await Deno.remove(s.parent, { recursive: true });
    }
  });
  Deno.test("Sol screen stops separately on unsupported identity, missing mapping, wrong explanation and unavailable review", async () => {
    for (
      const kind of ["mapping", "identity", "explanation", "review"] as const
    ) {
      const s = await setup(scratch);
      try {
        const original = s.dependencies.outcome;
        if (kind === "mapping" || kind === "identity") {
          s.dependencies.outcome = async (a) => {
            const v = await original(a);
            assert(v.kind === "draft");
            return {
              ...v,
              draft: {
                ...(v.draft as Record<string, unknown>),
                scientific_name: kind === "mapping"
                  ? "Inventedus missing"
                  : null,
              },
            };
          };
        }
        if (kind === "explanation") {
          s.dependencies.review = () => {
            const r = pass();
            r.grounding = { status: "fail", reason: "invented_evidence" };
            return Promise.resolve(r);
          };
        }
        if (kind === "review") {
          s.dependencies.review = () => Promise.resolve(null);
        }
        const state = await s.run();
        assertEquals(
          state.stop,
          kind === "mapping"
            ? "screen_unassessable"
            : kind === "review"
            ? "review_missing"
            : "screen_failed",
        );
        assertEquals(s.calls.length, 1);
        assertEquals((await s.run()).stop, state.stop);
        assertEquals(s.calls.length, 1);
      } finally {
        await Deno.remove(s.parent, { recursive: true });
      }
    }
  });
  Deno.test("Sol provider and usage failures preserve one claim and never trigger retries", async () => {
    for (const kind of ["throw", "usage", "model", "safety"] as const) {
      const s = await setup(scratch);
      try {
        const original = s.dependencies.outcome;
        s.dependencies.outcome = async (a) => {
          const v = await original(a);
          if (kind === "throw") throw new Error("Private error sentinel");
          if (kind === "usage") return { ...v, usage: null };
          if (kind === "model") return { ...v, returnedModel: "gpt-6-luna" };
          if (kind === "safety") return { ...v, mediaSafety: undefined };
          return v;
        };
        const state = await s.run();
        assertEquals(state.stop, "provider_failure");
        assertEquals(state.claimedCalls, 1);
        assertEquals(state.completedCalls, 0);
        assertEquals((await s.run()).stop, "provider_failure");
        assertEquals(s.calls.length, 1);
      } finally {
        await Deno.remove(s.parent, { recursive: true });
      }
    }
  });
  Deno.test("Sol interrupted claims, lost reviews, rejected old records and changed packets cannot resume dispatch", async () => {
    for (
      const kind of ["claim", "review", "record", "source", "packet"] as const
    ) {
      const s = await setup(scratch);
      try {
        const original = s.dependencies.review;
        s.dependencies.review = () => {
          throw new Error("Synthetic review interruption");
        };
        await assertRejects(() => s.run());
        const run = join(s.root, "sol-photo-rank-run");
        s.dependencies.review = original;
        if (kind === "claim") {
          await Deno.remove(join(run, "results", "01.json"));
        }
        if (kind === "record") {
          const r = await readJson(join(run, "results", "01.json")) as Record<
            string,
            unknown
          >;
          delete r.mapping;
          r.version = "photo_model_attempt_v1";
          await atomicJson(join(run, "results", "01.json"), r);
          await assertRejects(() => s.run());
        } else {
          if (kind === "packet") {
            await atomicJson(join(s.root, "sol-rank-plan.json"), {});
          }
          const result = kind === "source"
            ? await executeSolRankComparison(
              s.root,
              { ...source, digest: "f".repeat(64) },
              "offline",
              s.dependencies,
            )
            : await s.run();
          assertEquals(
            result.stop,
            kind === "claim"
              ? "interrupted_attempt"
              : kind === "review"
              ? "review_missing"
              : "configuration_invalid",
          );
        }
        assertEquals(s.calls.length, 1);
      } finally {
        await Deno.remove(s.parent, { recursive: true });
      }
    }
  });
  Deno.test("Sol admission needs a fresh versioned source/key/budget-bound approval and rejects old or expired authority", async () => {
    const s = await setup(scratch);
    try {
      const packet = await loadSolRankPacket(s.root, source);
      // Pure validator fixture only; no real evidence or network admission is granted.
      packet.corpus.evidenceOrigin = "real";
      packet.report.source = { ...packet.report.source, dirty: false };
      packet.plan.inputApproval = {
        provider: "openai",
        corpusDigest: packet.plan.corpusDigest,
        caseIds: [
          ...packet.plan.screenCaseIds,
          ...packet.plan.challengeCaseIds,
        ],
        recordRef: "synthetic-owner",
      };
      const credential = "invented-test-credential", now = Date.now();
      const approval = {
        version: "sol_photo_rank_approval_v1",
        project: "naturebook",
        operation: "18_call_sol_rank_photo_comparison",
        screeningPolicy: SOL_RANK_SCREEN_POLICY,
        planDigest: await fingerprintJson(packet.plan),
        sourceCommit: source.commit,
        sourceDigest: source.digest,
        credentialSha256: await fingerprintBytes(
          new TextEncoder().encode(credential),
        ),
        budgetUsd: 110,
        approvedAt: new Date(now - 1000).toISOString(),
        expiresAt: new Date(now + 3600000).toISOString(),
        recordRef: "synthetic-owner",
        reviewerRef: "synthetic-reviewer",
        delegationRef: "synthetic-delegation",
      };
      assertEquals(
        (await validateSolRankApproval(approval, packet, credential, now))
          .budgetUsd,
        110,
      );
      for (
        const change of [
          { version: "photo_model_candidate_approval_v1" },
          { operation: "other" },
          { sourceDigest: "a".repeat(64) },
          { credentialSha256: "a".repeat(64) },
          { planDigest: "a".repeat(64) },
          { budgetUsd: 40 },
          { expiresAt: new Date(now - 1).toISOString() },
        ]
      ) {
        await assertRejects(() =>
          validateSolRankApproval(
            { ...approval, ...change },
            packet,
            credential,
            now,
          )
        );
      }
      await atomicJson(join(s.root, "sol-rank-plan.json"), {
        ...s.plan,
        budgetUsd: 40,
      });
      await assertRejects(() => s.run());
      assertEquals(s.calls.length, 0);
    } finally {
      await Deno.remove(s.parent, { recursive: true });
    }
  });
}
