import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import { join } from "node:path";
import { main } from "../../evaluate_identification.ts";
import { type EvaluationCorpus } from "../contracts.ts";
import { fingerprintEvidence, fingerprintJson } from "../evidence.ts";
import { parseExploratoryCorpus } from "../exploratory.ts";
import { atomicJson, exists, readJson } from "../files.ts";
import { createDemo } from "../offline.ts";
import {
  parsePhotoModelFacts,
  parsePhotoModelPlan,
  parsePhotoModelPricing,
  type PhotoModelPricing,
} from "../photoModelContracts.ts";
import { preparePhotoModelComparison } from "../photoModelPreparation.ts";
import { parseRunSpec, type SourceIdentity } from "../runContracts.ts";

const source: SourceIdentity = {
  commit: "0".repeat(40),
  dirty: true,
  digest: "1".repeat(64),
  sdk: "npm:@google/genai@2.23.0",
};
export async function photoModelFixture(root: string, now: number) {
  await createDemo(root);
  const original = await readJson(
    join(root, "corpus.json"),
  ) as EvaluationCorpus;
  const images = original.cases.flatMap((c) => c.input.assets).filter((a) =>
    a.kind === "image" || a.kind === "video_frame"
  ).slice(0, 12);
  const corpus = parseExploratoryCorpus({
    version: "identification_exploratory_corpus_v1",
    id: "synthetic-photo-models-v1",
    kind: "exploratory",
    evidenceOrigin: "synthetic",
    eligibility: null,
    taxonomyVersion: original.taxonomyVersion,
    preparationVersion: original.preparationVersion,
    splitSeed: original.splitSeed,
    cases: original.cases.map((c, i) => ({
      input: {
        ...c.input,
        inputGroup: "photos",
        observationTexts: [],
        clips: [],
        assets: [{
          id: images[i].id,
          path: images[i].path,
          sha256: images[i].sha256,
          byteLength: images[i].byteLength,
          mimeType: images[i].mimeType,
          kind: "image",
          sourceIndex: 0,
        }],
      },
      provisionalReference: c.reference,
      curation: { kind: "synthetic" },
    })),
  });
  const facts = parsePhotoModelFacts({
    version: "photo_model_facts_v1",
    cards: await Promise.all(corpus.cases.map(async (c) => ({
      caseId: c.input.caseId,
      inputDigest: await fingerprintEvidence(c.input),
      observed: ["Invented image for software tests only."],
      missing: [],
      acceptableReasons: ["Synthetic fixture is not biological evidence."],
      rankLimit: "Mechanics only.",
      requirements: [
        "decision_evidence",
        "rank_limit",
        "abstention_reason",
        "non_biological_reason",
      ],
    }))),
  });
  const pricing: PhotoModelPricing = parsePhotoModelPricing({
    version: "photo_model_pricing_v1",
    retrievedAt: new Date(now).toISOString(),
    reviewRef: "synthetic-pricing-test",
    currency: "USD",
    billing: "paid_standard_synchronous",
    profiles: {
      openai_photo_luna_low_v1: {
        model: "gpt-6-luna",
        source: "https://developers.openai.com/api/docs/models/gpt-6-luna",
        inputCeilingUsdPerMillion: 0.25,
        outputCeilingUsdPerMillion: 0.75,
      },
      openai_photo_sol_low_v1: {
        model: "gpt-6-sol",
        source: "https://developers.openai.com/api/docs/models/gpt-6-sol",
        inputCeilingUsdPerMillion: 5,
        outputCeilingUsdPerMillion: 15,
      },
    },
  });
  const plan = parsePhotoModelPlan({
    version: "photo_model_plan_v1",
    id: "synthetic-photo-model-plan",
    corpusDigest: await fingerprintJson(corpus),
    taxonomyDigest: await fingerprintJson(
      await readJson(join(root, "taxonomy.json")),
    ),
    factsDigest: await fingerprintJson(facts),
    pricingDigest: await fingerprintJson(pricing),
    screenCaseIds: corpus.cases.slice(0, 6).map((c) => c.input.caseId),
    challengeCaseIds: corpus.cases.slice(6).map((c) => c.input.caseId),
    maxCalls: 18,
    attemptsPerAssignment: 1,
    budgetUsd: 5,
    inputApproval: null,
  });
  for (
    const [file, value] of [
      ["corpus.json", corpus],
      ["photo-model-facts.json", facts],
      ["photo-model-pricing.json", pricing],
      ["photo-model-plan.json", plan],
    ] as const
  ) await atomicJson(join(root, file), value);
  return { plan, corpus, facts, pricing };
}
export function registerPhotoModelPreparationTests(scratch: string) {
  Deno.test("photo-model preflight binds identical paired evidence, caps 18 calls and reports the unaffordable full-context reservation without dispatch", async () => {
    const root = await Deno.makeTempDir({
      dir: scratch,
      prefix: "photo-models-",
    });
    try {
      const { plan } = await photoModelFixture(root, Date.now());
      await main(["preflight-free-pro-photo", root]);
      const report = await preparePhotoModelComparison(root, source);
      assertEquals(report.plannedCalls, 18);
      assertEquals(report.dispatchAuthorized, false);
      assertEquals(report.liveControllerAvailable, true);
      assertEquals(report.evidenceStatus, "synthetic_mechanics_only");
      assertEquals(report.fullScheduleReservationUsd, 35.461008);
      assertEquals(report.budgetFitsConservativeReservation, false);
      assertEquals(
        report.order.filter((a) => a.model === "gpt-6-luna").length,
        12,
      );
      assertEquals(
        report.order.filter((a) => a.model === "gpt-6-sol").length,
        6,
      );
      assertEquals(
        report.order.slice(0, 6).map((a) => a.caseId),
        plan.screenCaseIds,
      );
      for (let i = 6; i < 18; i += 2) {
        const left = report.order[i], right = report.order[i + 1];
        assertEquals(left.caseId, right.caseId);
        assertEquals(left.inputDigest, right.inputDigest);
        assertEquals(left.referenceDigest, right.referenceDigest);
        assertEquals(left.factsDigest, right.factsDigest);
        assert(
          left.profile !== right.profile &&
            left.requestDigest !== right.requestDigest,
        );
        assertEquals(left.attempt, 1);
      }
      assertEquals(report.order.slice(6, 10).map((a) => a.model), [
        "gpt-6-luna",
        "gpt-6-sol",
        "gpt-6-sol",
        "gpt-6-luna",
      ]);
      assertEquals(await exists(join(root, "runs")), false);
      const serialized = JSON.stringify(report);
      for (
        const forbidden of [
          "Invented image",
          "data:image",
          "assets/",
          "acceptableTaxa",
          "Authorization",
        ]
      ) assert(!serialized.includes(forbidden));
      const old = await readJson(join(root, "spec.json")) as Record<
        string,
        unknown
      >;
      for (
        const profile of ["openai_photo_luna_low_v1", "openai_photo_sol_low_v1"]
      ) assertThrows(() => parseRunSpec({ ...old, profiles: [profile] }));
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });
  Deno.test("photo-model packet rejects changed references, missing evidence, wrong media, stale prices and expanded scope", async () => {
    const root = await Deno.makeTempDir({
      dir: scratch,
      prefix: "photo-models-invalid-",
    });
    const now = Date.now();
    try {
      const { plan, corpus, facts, pricing } = await photoModelFixture(
        root,
        now,
      );
      for (
        const change of [
          { maxCalls: 19 },
          { attemptsPerAssignment: 2 },
          { budgetUsd: 6 },
          { challengeCaseIds: plan.screenCaseIds },
          { model: "gpt-6-sol" },
          {
            inputApproval: {
              provider: "gemini",
              corpusDigest: plan.corpusDigest,
              caseIds: [...plan.screenCaseIds, ...plan.challengeCaseIds],
              recordRef: "synthetic-approval",
            },
          },
        ]
      ) assertThrows(() => parsePhotoModelPlan({ ...plan, ...change }));
      assertThrows(() =>
        parsePhotoModelFacts({ ...facts, cards: facts.cards.slice(1) })
      );
      assertThrows(() =>
        parsePhotoModelPricing({
          ...pricing,
          profiles: {
            ...pricing.profiles,
            openai_photo_sol_low_v1: {
              ...pricing.profiles.openai_photo_sol_low_v1,
              inputCeilingUsdPerMillion: 2,
            },
          },
        })
      );
      await assertRejects(() =>
        preparePhotoModelComparison(root, source, now + 8 * 86400000)
      );
      for (
        const change of [
          (c: typeof corpus) => {
            c.cases[0].provisionalReference = null;
          },
          (c: typeof corpus) => {
            c.cases[0].input = {
              ...c.cases[0].input,
              observationTexts: ["Unreviewed description."],
            };
          },
          (c: typeof corpus) => {
            c.cases[0].input = {
              ...c.cases[0].input,
              assets: [{
                ...c.cases[0].input.assets[0],
                sha256: "f".repeat(64),
              }],
            };
          },
          (c: typeof corpus) => {
            c.cases[0].input = {
              ...c.cases[0].input,
              inputGroup: "description",
              assets: [],
              observationTexts: ["Synthetic description."],
            };
          },
        ]
      ) {
        const changed = structuredClone(corpus);
        change(changed);
        await atomicJson(join(root, "corpus.json"), changed);
        await atomicJson(join(root, "photo-model-plan.json"), {
          ...plan,
          corpusDigest: await fingerprintJson(changed),
        });
        await assertRejects(() =>
          preparePhotoModelComparison(root, source, now)
        );
      }
      await atomicJson(join(root, "corpus.json"), corpus);
      await atomicJson(join(root, "photo-model-plan.json"), plan);
      const changedFacts = structuredClone(facts);
      changedFacts.cards[0].observed = ["Changed after freezing."];
      await atomicJson(join(root, "photo-model-facts.json"), changedFacts);
      await assertRejects(() => preparePhotoModelComparison(root, source, now));
      await atomicJson(join(root, "photo-model-facts.json"), facts);
      await Deno.remove(join(root, corpus.cases[0].input.assets[0].path));
      await assertRejects(() => preparePhotoModelComparison(root, source, now));
      assertEquals(
        await exists(join(root, "photo-model-preflight.json")),
        false,
      );
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });
  Deno.test("real photo-model preparation requires existing owner approval for OpenAI and unexpired evidence", async () => {
    const root = await Deno.makeTempDir({
      dir: scratch,
      prefix: "photo-models-scope-",
    });
    const now = Date.now();
    try {
      const { plan, corpus } = await photoModelFixture(root, now);
      const real = parseExploratoryCorpus({
        ...corpus,
        evidenceOrigin: "real",
        eligibility: {
          recordRef: "synthetic-review-record",
          reviewerRef: "r0001",
          reviewerKind: "automated",
          retainUntil: new Date(now + 86400000 * 3).toISOString().slice(0, 10),
        },
        cases: corpus.cases.map((c) => ({
          ...c,
          curation: {
            kind: "eligibility_reviewed",
            source: "purpose_collected",
            sourceRecordRef: "synthetic-source",
            referenceRecordRef: "synthetic-reference",
            permission: "gemini_evaluation",
            rightsApproved: true,
            personalDataExcluded: true,
            nearDuplicatesReviewed: true,
          },
        })),
      });
      const corpusDigest = await fingerprintJson(real);
      const changedPlan = { ...plan, corpusDigest };
      await atomicJson(join(root, "corpus.json"), real);
      await atomicJson(join(root, "photo-model-plan.json"), changedPlan);
      await assertRejects(() => preparePhotoModelComparison(root, source, now));
      await atomicJson(join(root, "photo-model-plan.json"), {
        ...changedPlan,
        inputApproval: {
          provider: "openai",
          corpusDigest,
          caseIds: [...plan.screenCaseIds, ...plan.challengeCaseIds],
          recordRef: "synthetic-owner-authorization",
        },
      });
      assertEquals(
        (await preparePhotoModelComparison(root, source, now)).evidenceStatus,
        "provisional_reference_pilot",
      );
      await assertRejects(() =>
        preparePhotoModelComparison(root, source, now + 86400000 * 4)
      );
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });
}
