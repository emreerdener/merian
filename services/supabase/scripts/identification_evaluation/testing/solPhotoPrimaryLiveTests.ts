import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import { join } from "node:path";
import type { AIProviderOutcome } from "../../../functions/_shared/ai/contracts.ts";
import { SOL_PRIMARY_PROFILE } from "../../../functions/_shared/ai/openaiSolPrimary.ts";
import { solPrimaryDraftFixture } from "../../../functions/_shared/ai/testing/openaiSolPrimaryFixtures.ts";
import { prepareEvidence } from "../assets.ts";
import { fingerprintBytes, fingerprintJson } from "../evidence.ts";
import type { Ratings } from "../explanationContracts.ts";
import { atomicJson, exists, readJson } from "../files.ts";
import {
  parsePhotoModelPlan,
  parsePhotoModelPricing,
} from "../photoModelContracts.ts";
import { parsePhotoModelMeasurementRecord } from "../photoModelRecords.ts";
import { validateSolPrimaryApproval } from "../solPhotoPrimaryAdmission.ts";
import {
  parseSolPrimaryPlan,
  SOL_PRIMARY_SCREEN_POLICY,
} from "../solPhotoPrimaryContracts.ts";
import {
  loadSolPrimaryPacket,
  primaryBillingAssignment,
  type SolPrimaryAssignment,
} from "../solPhotoPrimaryLivePreparation.ts";
import { prepareSolPhotoPrimaryPacket } from "../solPhotoPrimaryPreparation.ts";
import {
  parseSolPrimaryRecord,
  projectSolPrimaryOutcome,
} from "../solPhotoPrimaryRecords.ts";
import { executeSolPrimaryComparison } from "../solPhotoPrimaryRunner.ts";
import {
  solPrimaryAssessment,
  solPrimaryIdentityInterpretation,
  solPrimaryScreenDecision,
  solPrimarySummary,
} from "../solPhotoPrimaryScoring.ts";
import { parseSolRankPlan } from "../solPhotoRankContracts.ts";
import { solPrimaryPreparationFixture } from "./solPhotoPrimaryPreparationTests.ts";
import { pass, source } from "./photoModelRunnerTests.ts";

async function setup(scratch: string) {
  const parent = await Deno.makeTempDir({
    dir: scratch,
    prefix: "primary-live-",
  });
  const f = await solPrimaryPreparationFixture(parent);
  const receipt = await prepareSolPhotoPrimaryPacket(f.source, f.target);
  const pricing = parsePhotoModelPricing(
    await readJson(join(f.source, "photo-model-pricing.json")),
  );
  const plan = parseSolPrimaryPlan({
    ...f.plan,
    version: "sol_photo_primary_plan_v1",
    id: "synthetic-primary-live",
    preparationDigest: await fingerprintJson(receipt),
    pricingDigest: await fingerprintJson(pricing),
    maxCalls: 18,
    attemptsPerAssignment: 1,
    budgetUsd: 110,
    screeningPolicy: SOL_PRIMARY_SCREEN_POLICY,
    inputApproval: null,
  });
  await atomicJson(join(f.target, "sol-primary-plan.json"), plan);
  await atomicJson(join(f.target, "sol-primary-pricing.json"), pricing);
  const packet = await loadSolPrimaryPacket(f.target, source);
  const calls: number[] = [];
  const outcome = (a: SolPrimaryAssignment): Promise<AIProviderOutcome> => {
    calls.push(a.ordinal);
    const ref = f.corpus.cases.find((c) => c.input.caseId === a.caseId)!
      .provisionalReference!;
    const taxon = f.taxonomy.taxa.find((t) =>
      t.taxon.id === ref.acceptableTaxa[0]?.id
    );
    const resolution = ref.subject === "non_biological"
      ? "non_biological"
      : ref.resolution === "unresolved"
      ? "unresolved_biological"
      : taxon!.taxon.rank;
    const draft = solPrimaryDraftFixture(resolution);
    draft.scientific_name = taxon?.canonicalName ??
      (resolution === "non_biological" ? "Quartz" : null);
    draft.common_name = taxon?.canonicalName ??
      (resolution === "non_biological" ? "Quartz" : "Unresolved organism");
    draft.ai_reasoning = "Private synthetic prose sentinel.";
    if (a.profile !== SOL_PRIMARY_PROFILE) {
      delete draft.resolution;
      draft.candidates = [];
    }
    return Promise.resolve({
      kind: "draft",
      draft,
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
    });
  };
  const dependencies = {
    outcome,
    review: (): Promise<Ratings | null> => Promise.resolve(pass()),
  };
  const project = async (
    ordinal: number,
    draftChange: Record<string, unknown> = {},
    baseline = false,
  ) => {
    const a = {
      ...packet.report.order[ordinal - 1],
      ...(baseline ? { profile: "openai_photo_sol_low_v1" as const } : {}),
    };
    const c = f.corpus.cases.find((c) => c.input.caseId === a.caseId)!;
    const result = await outcome(a);
    checkDraft(result);
    Object.assign(result.draft as Record<string, unknown>, draftChange);
    return {
      a,
      ...projectSolPrimaryOutcome(
        result,
        c.input,
        await prepareEvidence(f.target, c.input),
        f.facts.cards.find((c) => c.caseId === a.caseId)!,
        a,
        "1".repeat(64),
        "2".repeat(64),
        packet.taxonomy,
        pricing,
      ),
    };
  };
  return {
    ...f,
    parent,
    root: f.target,
    packet,
    plan,
    receipt,
    pricing,
    calls,
    dependencies,
    project,
    run: () =>
      executeSolPrimaryComparison(f.target, source, "offline", dependencies),
  };
}
function checkDraft(
  outcome: AIProviderOutcome,
): asserts outcome is Extract<AIProviderOutcome, { kind: "draft" }> {
  assertEquals(outcome.kind, "draft");
}

export function registerSolPrimaryLiveTests(scratch: string) {
  Deno.test("primary runner binds 18 calls, retains all five states, excludes limited references from quality and resumes without replay", async () => {
    const s = await setup(scratch);
    try {
      assertEquals(
        s.packet.report.recordVersion,
        "sol_primary_photo_attempt_v1",
      );
      assertEquals(s.packet.report.dispatchAuthorized, false);
      assertEquals(s.packet.report.regionalReservationUsd, 106.383024);
      assertThrows(() => parseSolRankPlan(s.plan));
      assertThrows(() => parsePhotoModelPlan(s.plan));
      assertThrows(() => parseSolPrimaryPlan({ ...s.plan, maxCalls: 19 }));
      const result = await s.run();
      assertEquals(result.stop, null);
      assertEquals(result.complete, true);
      assertEquals(s.calls, Array.from({ length: 18 }, (_, i) => i + 1));
      await s.run();
      assertEquals(s.calls.length, 18);
      const dir = join(s.root, "sol-photo-primary-run");
      const summary = await readJson(join(dir, "summary.json")) as ReturnType<
        typeof solPrimarySummary
      >;
      assertEquals(summary.confidenceCalibrationQualified, false);
      assertEquals(summary.qualityQualified, false);
      assertEquals(summary.profiles[1].profile, "openai_photo_sol_low_v1");
      const screens = summary.profiles.find((p) =>
        p.profile === SOL_PRIMARY_PROFILE && p.phase === "screen"
      )!;
      assertEquals(screens.qualityPasses, 4);
      assertEquals(screens.referenceLimitedContinuations, 2);
      assertEquals(screens.explanationPasses, 4);
      assertEquals(
        new Set(summary.attempts.slice(0, 6).map((a) => a.primaryResolution)),
        new Set(
          [
            "species",
            "genus",
            "family",
            "unresolved_biological",
            "non_biological",
          ] as const,
        ),
      );
      assert(
        summary.attempts.slice(0, 6).every((a) =>
          a.resolutionOrigin === "explicit"
        ),
      );
      assert(
        summary.attempts.filter((a) => a.profile !== SOL_PRIMARY_PROFILE).every(
          (a) => a.resolutionOrigin === "catalog",
        ),
      );
      const checkPrivate = async (root: string) => {
        for await (const item of Deno.readDir(root)) {
          const path = join(root, item.name);
          if (item.isDirectory) await checkPrivate(path);
          else {
            assertEquals((await Deno.stat(path)).mode! & 0o077, 0);
            const text = await Deno.readTextFile(path);
            for (
              const forbidden of [
                "Private synthetic prose",
                "Invented",
                "Canis lupus",
                "Felis catus",
                "data:image",
                "Authorization",
                "synthetic-key",
              ]
            ) assert(!text.includes(forbidden));
          }
        }
      };
      await checkPrivate(dir);
      const record = await readJson(join(dir, "results/01.json"));

      assertThrows(() =>
        parsePhotoModelMeasurementRecord(
          record,
          primaryBillingAssignment(s.packet.report.order[0]),
          "1".repeat(64),
          "2".repeat(64),
        )
      );
    } finally {
      await Deno.remove(s.parent, { recursive: true });
    }
  });

  Deno.test("primary records reject cross-rank mapping, retain unresolved mappings and distinguish baseline catalog rank", async () => {
    const s = await setup(scratch);
    try {
      const valid = await s.project(3);
      assertEquals(valid.record.primaryResolution, "genus");
      assertEquals(valid.record.mapping.status, "matched");
      const legacy = await s.project(3, {}, true);
      assertEquals(legacy.record.primaryResolution, "genus");
      assertEquals(legacy.record.resolutionOrigin, "catalog");
      const conflicting = await s.project(3, {
        scientific_name: "Invented example",
      });
      assertEquals(conflicting.record.reason, "normalization_failed");
      assertEquals(conflicting.record.primaryResolution, null);
      assertEquals(conflicting.display, null);
      assertThrows(() =>
        parseSolPrimaryRecord(
          { ...valid.record, primaryResolution: "species" },
          valid.a,
          "1".repeat(64),
          "2".repeat(64),
        )
      );
      assertThrows(() =>
        parseSolPrimaryRecord(
          { ...valid.record, prose: "must not persist" },
          valid.a,
          "1".repeat(64),
          "2".repeat(64),
        )
      );
      for (const baseline of [false, true]) {
        const unmapped = await s.project(
          3,
          { scientific_name: "Unmappedname" },
          baseline,
        );
        assertEquals(unmapped.record.mapping.status, "unmapped");
        assertEquals(
          unmapped.record.primaryResolution,
          baseline ? null : "genus",
        );
        assertEquals(
          solPrimaryScreenDecision(s.packet, unmapped.a, {
            record: unmapped.record,
            ratings: pass(),
          }),
          "unassessable",
        );
      }
      // A finite catalog can map a name ambiguously; neither profile may gain rank credit.
      s.packet.taxonomy.taxa[0].synonyms.push("Sharedname");
      s.packet.taxonomy.taxa[1].synonyms.push("Sharedname");
      for (const baseline of [false, true]) {
        const ambiguous = await s.project(
          3,
          { scientific_name: "Sharedname" },
          baseline,
        );
        assertEquals(ambiguous.record.mapping.status, "ambiguous");
        assertEquals(
          ambiguous.record.primaryResolution,
          baseline ? null : "genus",
        );
        assertEquals(
          solPrimaryScreenDecision(s.packet, ambiguous.a, {
            record: ambiguous.record,
            ratings: pass(),
          }),
          "unassessable",
        );
      }
      const unknown = await s.project(5);
      assertEquals(unknown.record.primaryResolution, "unresolved_biological");
      assertEquals(unknown.record.mapping.status, "not_applicable");
      assert(
        unknown.display?.decision.includes(
          "Primary resolution: unresolved_biological",
        ),
      );
    } finally {
      await Deno.remove(s.parent, { recursive: true });
    }
  });

  Deno.test("primary limited-reference subject disagreement may continue but never gains a quality pass or conceals review failures", async () => {
    const s = await setup(scratch);
    try {
      const x = await s.project(5, {
        ...solPrimaryDraftFixture("non_biological"),
      });
      const e = { record: x.record, ratings: pass() };
      const assessment = solPrimaryAssessment(s.packet, x.a, e);
      assertEquals(assessment.subject, "disagreement");
      assertEquals(
        solPrimaryIdentityInterpretation(assessment),
        "unassessable_limited_reference",
      );
      assertEquals(
        solPrimaryScreenDecision(s.packet, x.a, e),
        "reference_limited",
      );
      e.ratings.uncertainty = {
        status: "not_assessable",
        reason: "insufficient_reference",
      };
      assertEquals(
        solPrimaryScreenDecision(s.packet, x.a, e),
        "reference_limited",
      );
      const summary = solPrimarySummary(
        s.packet,
        new Map([[x.a.ordinal, e]]),
        new Map([[x.a.ordinal, x.record]]),
      );
      assertEquals(summary.attempts[0].explanationPassed, false);
      assertEquals(
        summary.profiles.find((p) =>
          p.profile === SOL_PRIMARY_PROFILE && p.phase === "screen"
        )!.qualityPasses,
        0,
      );
      for (const reason of ["reviewer_unsure", "review_unavailable"] as const) {
        e.ratings.uncertainty = { status: "not_assessable", reason };
        assertEquals(
          solPrimaryScreenDecision(s.packet, x.a, e),
          "unassessable",
        );
      }
      e.ratings.uncertainty = {
        status: "fail",
        reason: "unsupported_specificity",
      };
      assertEquals(solPrimaryScreenDecision(s.packet, x.a, e), "failed");
      const supported = await s.project(1, {
        ...solPrimaryDraftFixture("non_biological"),
      });
      assertEquals(
        solPrimaryScreenDecision(s.packet, supported.a, {
          record: supported.record,
          ratings: pass(),
        }),
        "failed",
      );
      const realOutcome = s.dependencies.outcome;
      s.dependencies.outcome = async (a) => {
        const o = await realOutcome(a);
        if (a.ordinal === 5) {
          checkDraft(o);
          return { ...o, draft: solPrimaryDraftFixture("non_biological") };
        }
        return o;
      };
      s.calls.length = 0;
      assertEquals((await s.run()).complete, true);
      assertEquals(s.calls.length, 18);
    } finally {
      await Deno.remove(s.parent, { recursive: true });
    }
  });

  Deno.test("primary run stops on unsupported evidence and never reuses the stopped call", async () => {
    const s = await setup(scratch);
    try {
      s.dependencies.review = () => {
        const ratings = pass();
        ratings.grounding = { status: "fail", reason: "invented_evidence" };
        return Promise.resolve(ratings);
      };
      assertEquals((await s.run()).stop, "screen_failed");
      assertEquals(s.calls, [1]);
      s.dependencies.review = () => Promise.resolve(pass());
      assertEquals((await s.run()).stop, "screen_failed");
      assertEquals(s.calls, [1]);
    } finally {
      await Deno.remove(s.parent, { recursive: true });
    }
  });

  Deno.test("primary interrupted claims and missing reviews hold reservation without redispatch", async () => {
    for (const missing of ["result", "review"] as const) {
      const s = await setup(scratch);
      try {
        s.dependencies.review = () => Promise.resolve(null);
        assertEquals((await s.run()).stop, "review_missing");
        const dir = join(s.root, "sol-photo-primary-run");
        await Deno.remove(join(dir, "reviews/01.json"));
        if (missing === "result") {
          await Deno.remove(join(dir, "results/01.json"));
        }
        await Deno.remove(join(dir, "stop.json"));
        s.dependencies.review = () => Promise.resolve(pass());
        const result = await s.run();
        assertEquals(
          result.stop,
          missing === "result" ? "interrupted_attempt" : "review_missing",
        );
        assertEquals(result.claimedCalls, 1);
        assertEquals(result.heldReservationUsd, 5.910168);
        assertEquals(s.calls, [1]);
        await s.run();
        assertEquals(s.calls, [1]);
      } finally {
        await Deno.remove(s.parent, { recursive: true });
      }
    }
  });

  Deno.test("primary admission rejects stale or retagged reference inputs and changed configuration before another call", async () => {
    const s = await setup(scratch);
    try {
      const before = s.dependencies.outcome;
      s.dependencies.outcome = async (a) => {
        const result = await before(a);
        const changed = structuredClone(s.review);
        changed.cases[4].identitySupport = "usable_provisional";
        await atomicJson(
          join(s.root, "primary-reference-review.json"),
          changed,
        );
        return result;
      };
      const stopped = await s.run();
      assertEquals(stopped.stop, "configuration_invalid");
      assertEquals(s.calls, [1]);
      await assertRejects(() => loadSolPrimaryPacket(s.root, source));
      await atomicJson(join(s.root, "primary-reference-review.json"), s.review);
      assertEquals((await s.run()).stop, "configuration_invalid");
      assertEquals(s.calls, [1]);
      await atomicJson(join(s.root, "sol-primary-pricing.json"), {
        ...s.pricing,
        retrievedAt: "2020-01-01T00:00:00Z",
      });
      await assertRejects(() => loadSolPrimaryPacket(s.root, source));
    } finally {
      await Deno.remove(s.parent, { recursive: true });
    }
  });

  Deno.test("primary fresh budget failure creates no manifest and historical bindings are refused without modifying journals", async () => {
    const s = await setup(scratch);
    try {
      await atomicJson(join(s.root, "sol-primary-plan.json"), {
        ...s.plan,
        budgetUsd: 1,
      });
      await assertRejects(s.run);
      assertEquals(s.calls, []);
      assertEquals(
        await exists(join(s.root, "sol-photo-primary-run/manifest.json")),
        false,
      );
      await atomicJson(join(s.root, "sol-primary-plan.json"), s.plan);
      s.dependencies.review = () => Promise.resolve(null);
      await s.run();
      const path = join(s.root, "sol-photo-primary-run/manifest.json");
      const manifest = await readJson(path) as { binding: { version: string } };
      manifest.binding.version = "sol_photo_rank_run_binding_v2";
      await atomicJson(path, manifest);
      const paths = [
        path,
        join(s.root, "sol-photo-primary-run/stop.json"),
        join(s.root, "sol-photo-primary-run/state.json"),
      ];
      const hashes = await Promise.all(
        paths.map(async (p) => fingerprintBytes(await Deno.readFile(p))),
      );
      await assertRejects(s.run, Error, "unsupported_version");
      assertEquals(
        await Promise.all(
          paths.map(async (p) => fingerprintBytes(await Deno.readFile(p))),
        ),
        hashes,
      );
      assertEquals(s.calls, [1]);
    } finally {
      await Deno.remove(s.parent, { recursive: true });
    }
  });

  Deno.test("primary execution approval is new, exact-source, exact-budget, credential-bound and time-limited", async () => {
    const s = await setup(scratch);
    try {
      const packet = structuredClone(s.packet);
      packet.corpus.evidenceOrigin = "real";
      packet.plan.inputApproval = {
        provider: "openai",
        corpusDigest: packet.plan.corpusDigest,
        caseIds: [
          ...packet.plan.screenCaseIds,
          ...packet.plan.challengeCaseIds,
        ],
        recordRef: "synthetic-permission-test",
      };
      packet.report.source.dirty = false;
      const now = Date.now();
      const approval = {
        version: "sol_photo_primary_approval_v1",
        project: "naturebook",
        operation: "18_call_sol_primary_photo_comparison",
        screeningPolicy: SOL_PRIMARY_SCREEN_POLICY,
        planDigest: await fingerprintJson(packet.plan),
        sourceCommit: packet.report.source.commit,
        sourceDigest: packet.report.source.digest,
        credentialSha256: await fingerprintBytes(
          new TextEncoder().encode("synthetic-key"),
        ),
        budgetUsd: 110,
        approvedAt: new Date(now - 1000).toISOString(),
        expiresAt: new Date(now + 60000).toISOString(),
        recordRef: "synthetic-approval",
        reviewerRef: "synthetic-reviewer",
        delegationRef: "synthetic-delegation",
      };
      assertEquals(
        await validateSolPrimaryApproval(
          approval,
          packet,
          "synthetic-key",
          now,
        ),
        approval,
      );
      for (
        const change of [
          { version: "sol_photo_rank_approval_v1" },
          { operation: "18_call_sol_rank_photo_comparison" },
          { sourceCommit: "a".repeat(40) },
          { planDigest: "f".repeat(64) },
          { budgetUsd: 109 },
          { expiresAt: new Date(now - 1).toISOString() },
          { screeningPolicy: "sol_rank_mapping_and_reference_gaps_v1" },
        ]
      ) {
        await assertRejects(() =>
          validateSolPrimaryApproval(
            { ...approval, ...change },
            packet,
            "synthetic-key",
            now,
          )
        );
      }
      await assertRejects(() =>
        validateSolPrimaryApproval(approval, packet, "other-key", now)
      );
      await assertRejects(() =>
        executeSolPrimaryComparison(s.root, source, "live", s.dependencies)
      );
      assertEquals(s.calls, []);
    } finally {
      await Deno.remove(s.parent, { recursive: true });
    }
  });
}
