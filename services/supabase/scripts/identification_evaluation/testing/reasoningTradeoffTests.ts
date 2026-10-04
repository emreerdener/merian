import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import { join } from "node:path";
import { atomicJson, claimJson, exists, withRunLock } from "../files.ts";
import { fingerprintJson } from "../evidence.ts";
import {
  confidenceFixture,
  confidenceOutcome,
  confidenceSource as source,
  writeConfidenceFixture,
} from "./confidenceFixtures.ts";
import {
  prepareReasoningTradeoff,
  TRADEOFF,
  TRADEOFF_ARMS,
  type TradeoffCase,
  tradeoffOrder,
} from "../reasoningTradeoffPreparation.ts";
import {
  bindTradeoffAuthorization,
  dispatchReasoningTradeoff,
  readReasoningTradeoff,
  reasoningTradeoffReport,
} from "../reasoningTradeoffRunner.ts";
import { tradeoffStatistics } from "../reasoningTradeoffStatistics.ts";
import type { ConfidenceObservation } from "../confidenceScoring.ts";

export function registerReasoningTradeoffTests(scratch: string) {
  async function setup() {
    const root = await Deno.makeTempDir({ dir: scratch, prefix: "tradeoff-" });
    const f = await writeConfidenceFixture(root);
    const cases = f.corpus.cases.filter((c) => c.input.split === "development")
      .slice(0, 20).map((c, i) => ({
        ...c,
        stratum: i < 2 ? "library" as const : "control" as const,
      }));
    const corpus = {
      version: "photo_reasoning_tradeoff_corpus_v1",
      cases: cases.map(({ curation: _c, ...c }) => c),
    };
    const review = {
      version: "photo_reasoning_tradeoff_review_v1",
      reviewerKind: "synthetic",
      independentHumanValidation: false,
      cases: await Promise.all(
        cases.map(async (c) => ({
          caseId: c.input.caseId,
          assetDigest: c.input.assets[0].sha256,
          inputPermissions: ["openai", "gemini_paid"],
          referenceDigest: await fingerprintJson(c.reference),
          status: "accepted",
          rightsApproved: true,
          personalDataExcluded: true,
          nearDuplicatesReviewed: true,
          exposure: "synthetic",
          reportedFailure: "not_applicable",
          visible: "Synthetic pixels.",
          limitation: "No biological evidence.",
          sources: [],
        })),
      ),
    };
    const gp = {
      version: "evaluation_pricing_v1",
      currency: "USD",
      service: "paid_standard_synchronous",
      retrievedAt: new Date().toISOString(),
      sourceUrl: "https://ai.google.dev/gemini-api/docs/pricing",
      reviewRef: "synthetic",
      includesReasoning: true,
      models: ["gemini-2.5-flash", "gemini-2.5-pro"].map((model) => ({
        model,
        inputPerMillion: { text: 1, image: 1, audio: 1, cached: 1 },
        outputPerMillion: 2,
        maxInputTokens: 1048576,
        maxBillableOutputTokens: 65536,
        limitsEvidenceRef: "synthetic",
      })),
    };
    const plan = {
      version: TRADEOFF.version,
      mode: "offline",
      authorizationRef: root.split("/").at(-1),
      paidServiceApproved: false,
      inputPermissions: ["openai", "gemini_paid"],
      budgetNanoUsd: TRADEOFF.budgetNanoUsd,
      packetRootDigest: await fingerprintJson(await Deno.realPath(root)),
      retainUntil: new Date(Date.now() + 86400000).toISOString(),
      sourceDigest: source.digest,
      corpusDigest: await fingerprintJson(corpus),
      reviewDigest: await fingerprintJson(review),
      taxonomyDigest: await fingerprintJson(f.taxonomy),
      openaiPricingDigest: await fingerprintJson(f.pricing),
      geminiPricingDigest: await fingerprintJson(gp),
      credentialDigests: { openai: null, gemini: null },
    };
    for (
      const [name, value] of Object.entries({
        "tradeoff-plan": plan,
        "tradeoff-corpus": corpus,
        "tradeoff-review": review,
        "openai-pricing": f.pricing,
        "gemini-pricing": gp,
      })
    ) await atomicJson(join(root, name + ".json"), value);
    return {
      root,
      cases,
      plan,
      corpus,
      review,
      study: await prepareReasoningTradeoff(root, source),
    };
  }
  Deno.test("tradeoff freezes 60 parity-checked requests with balanced orders and rejects drift/holds", async () => {
    const { root, study, plan, review } = await setup();
    try {
      assertEquals(study.manifest.assignments.length, 60);
      const orders = tradeoffOrder(study.cases);
      for (const arm of TRADEOFF_ARMS) {
        for (let pos = 0; pos < 3; pos++) {
          assert(
            [6, 7].includes(
              orders.filter((r, i) => r.arm === arm && i % 3 === pos).length,
            ),
          );
        }
      }
      assertEquals(
        (await prepareReasoningTradeoff(root, source)).digest,
        study.digest,
      );
      await assertRejects(() =>
        prepareReasoningTradeoff(root, { ...source, digest: "f".repeat(64) })
      );
      for (
        const field of [
          "budgetNanoUsd",
          "reviewDigest",
          "taxonomyDigest",
          "openaiPricingDigest",
          "geminiPricingDigest",
          "packetRootDigest",
        ] as const
      ) {
        await atomicJson(join(root, "tradeoff-plan.json"), {
          ...plan,
          [field]: field === "budgetNanoUsd" ? 20_000_000_000 : "f".repeat(64),
        });
        await assertRejects(() => prepareReasoningTradeoff(root, source));
      }
      await atomicJson(join(root, "tradeoff-plan.json"), plan);
      review.cases[0].status = "hold";
      await atomicJson(join(root, "tradeoff-review.json"), review);
      await atomicJson(join(root, "tradeoff-plan.json"), {
        ...plan,
        reviewDigest: await fingerprintJson(review),
      });
      await assertRejects(() => prepareReasoningTradeoff(root, source));
      await atomicJson(join(root, "tradeoff-review.json"), {
        ...review,
        cases: review.cases.map((r) => ({ ...r, status: "accepted" })),
      });
      await atomicJson(join(root, "tradeoff-plan.json"), plan);
      await Deno.writeFile(
        join(root, study.cases[0].input.assets[0].path),
        new Uint8Array([1, 2, 3]),
      );
      await assertRejects(() => prepareReasoningTradeoff(root, source));
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });
  Deno.test("tradeoff completes all synthetic claims before invoke, accounts both providers, leaks no prose and never replays", async () => {
    const { root, study } = await setup();
    try {
      let calls = 0;
      for (const a of study.manifest.assignments) {
        const result = await withRunLock(
          root,
          () =>
            dispatchReasoningTradeoff(root, study, a.arm, async () => {
              assert(
                await exists(
                  join(root, "tradeoff-attempts", a.key + ".claim.json"),
                ),
              );
              calls++;
              const outcome = confidenceOutcome(
                {
                  ...study.cases.find((c) => c.input.caseId === a.caseId)!,
                  curation: { kind: "synthetic" },
                },
              );
              return a.arm === "gemini"
                ? {
                  ...outcome,
                  returnedModel: "gemini-2.5-pro",
                  finishReason: "STOP",
                }
                : outcome;
            }),
        );
        assertEquals(result.report.stop, null);
      }
      const { report } = await reasoningTradeoffReport(root, study);
      assertEquals(calls, 60);
      assertEquals(report.complete, true);
      assertEquals(report.outstandingNanoUsd, 0);
      assertEquals(report.advancesToFreshValidation, false);
      for (
        const secret of [
          "Syntheticus",
          "ai_reasoning",
          "base64",
          "Synthetic pixels",
        ]
      ) assert(!JSON.stringify(report).includes(secret));
      await assertRejects(() =>
        dispatchReasoningTradeoff(
          root,
          study,
          "low",
          () =>
            Promise.resolve(
              confidenceOutcome({
                ...study.cases[0],
                curation: { kind: "synthetic" },
              }),
            ),
        )
      );
      assertEquals(calls, 60);
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });
  Deno.test("tradeoff uncertain calls consume one slot and retain the reservation, including torn writes", async () => {
    for (const kind of ["throw", "usage", "model", "torn"] as const) {
      const { root, study } = await setup();
      try {
        const a = study.manifest.assignments[0];
        if (kind === "torn") {
          await readReasoningTradeoff(root, study);
          await claimJson(
            join(root, "tradeoff-attempts", a.key + ".claim.json"),
            {
              version: "photo_reasoning_tradeoff_claim_v1",
              manifestDigest: study.digest,
              assignment: a,
            },
          );
        } else {await dispatchReasoningTradeoff(root, study, a.arm, () => {
            if (kind === "throw") throw new Error("private error");
            const o = confidenceOutcome(
              {
                ...study.cases.find((c) => c.input.caseId === a.caseId)!,
                curation: { kind: "synthetic" },
              },
            );
            return Promise.resolve({
              ...o,
              returnedModel: kind === "model"
                ? "wrong-model"
                : a.arm === "gemini"
                ? "gemini-2.5-pro"
                : "gpt-6-sol",
              usage: kind === "usage" ? null : o.usage,
            });
          });}
        const ledger = await readReasoningTradeoff(root, study);
        assertEquals(ledger.attempted, 1);
        assertEquals(ledger.outstandingNanoUsd, a.reservedNanoUsd);
        assert(ledger.stop);
        await assertRejects(() =>
          dispatchReasoningTradeoff(
            root,
            study,
            a.arm,
            () =>
              Promise.resolve(
                confidenceOutcome({
                  ...study.cases[0],
                  curation: { kind: "synthetic" },
                }),
              ),
          )
        );
      } finally {
        await Deno.remove(root, { recursive: true });
      }
    }
  });
  Deno.test("tradeoff rejects altered requests and dual-provider rights before claiming", async () => {
    const { root, study, plan, review } = await setup();
    try {
      const a = study.manifest.assignments[0];
      const original = a.requestDigest;
      a.requestDigest = "f".repeat(64);
      await assertRejects(() =>
        dispatchReasoningTradeoff(
          root,
          study,
          a.arm,
          () =>
            Promise.resolve(
              confidenceOutcome({
                ...study.cases[0],
                curation: { kind: "synthetic" },
              }),
            ),
        )
      );
      assertEquals((await readReasoningTradeoff(root, study)).attempted, 0);
      a.requestDigest = original;
      for (const change of ["permission", "url"] as const) {
        const changed = structuredClone(review);
        if (change === "permission") {
          changed.cases[0].inputPermissions = ["openai"];
        } else {changed.cases[0].sources = [
            "https://example.org/reference?token=private",
          ] as never[];}
        await atomicJson(join(root, "tradeoff-review.json"), changed);
        await atomicJson(join(root, "tradeoff-plan.json"), {
          ...plan,
          reviewDigest: await fingerprintJson(changed),
        });
        await assertRejects(() => prepareReasoningTradeoff(root, source));
      }
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });
  Deno.test("real inspection mode refuses both live and synthetic dispatch before claim", async () => {
    const { root, study } = await setup();
    try {
      study.plan.mode = "inspection";
      const a = study.manifest.assignments[0];
      await assertRejects(() => dispatchReasoningTradeoff(root, study, a.arm));
      let invoked = false;
      await assertRejects(() =>
        dispatchReasoningTradeoff(root, study, a.arm, () => {
          invoked = true;
          return Promise.resolve(
            confidenceOutcome({
              ...study.cases[0],
              curation: { kind: "synthetic" },
            }),
          );
        })
      );
      assertEquals(invoked, false);
      assertEquals((await readReasoningTradeoff(root, study)).attempted, 0);
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });
  Deno.test("tradeoff cumulative spend plus next reservation stops before the cap", async () => {
    const { root, study } = await setup();
    try {
      let calls = 0;
      for (const a of study.manifest.assignments) {
        if ((await readReasoningTradeoff(root, study)).stop) break;
        await dispatchReasoningTradeoff(root, study, a.arm, () => {
          calls++;
          const out = confidenceOutcome(
            {
              ...study.cases.find((c) => c.input.caseId === a.caseId)!,
              curation: { kind: "synthetic" },
            },
          );
          return Promise.resolve({
            ...out,
            returnedModel: a.arm === "gemini" ? "gemini-2.5-pro" : "gpt-6-sol",
            finishReason: a.arm === "gemini" ? "STOP" : "completed",
            usage: {
              ...out.usage!,
              promptTokens: 1000000,
              totalTokens: 1000040,
              cachedTokens: 0,
            },
          });
        });
      }
      const ledger = await readReasoningTradeoff(root, study);
      assertEquals(ledger.stop, "budget_exhausted");
      assert(calls > 0 && calls < 60);
      assert(ledger.settledNanoUsd <= TRADEOFF.budgetNanoUsd);
      assertEquals(ledger.outstandingNanoUsd, 0);
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });
  Deno.test("tradeoff rejects copied authorization, wrong arm, out-of-order claims and concurrent locks", async () => {
    const { root, study } = await setup();
    try {
      await bindTradeoffAuthorization(root, study);
      await assertRejects(() =>
        bindTradeoffAuthorization(root, { ...study, digest: "f".repeat(64) })
      );
      await assertRejects(() =>
        dispatchReasoningTradeoff(
          root,
          study,
          study.manifest.assignments[0].arm === "low" ? "medium" : "low",
          () =>
            Promise.resolve(
              confidenceOutcome({
                ...study.cases[0],
                curation: { kind: "synthetic" },
              }),
            ),
        )
      );
      await withRunLock(root, async () => {
        await assertRejects(() => withRunLock(root, () => Promise.resolve()));
      });
      const a = study.manifest.assignments[1];
      await claimJson(join(root, "tradeoff-attempts", a.key + ".claim.json"), {
        version: "photo_reasoning_tradeoff_claim_v1",
        manifestDigest: study.digest,
        assignment: a,
      });
      await assertRejects(() => readReasoningTradeoff(root, study));
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });
}

// Pure scoring assertions: a speed win, mapping repair or missing case cannot pass alone.
Deno.test("tradeoff selection requires paired biological gains, no regressions and every latency/stratum gate", () => {
  const f = confidenceFixture();
  const cases: TradeoffCase[] = f.corpus.cases.filter((c) =>
    c.input.split === "development" && c.reference.supportedRank === "species"
  ).slice(0, 20).map((c, i) => ({
    ...c,
    stratum: i < 2 ? "library" : "control",
  }));
  const correct = cases.map((c) =>
    f.observations.find((o) => o.prediction.caseId === c.input.caseId)!
  );
  const wrong = (o: ConfidenceObservation): ConfidenceObservation =>
    o.prediction.outcome === "normalized"
      ? {
        ...o,
        prediction: {
          ...o.prediction,
          taxon: { id: "synthetic:other", rank: "species" },
        },
      }
      : o;
  const results = TRADEOFF_ARMS.flatMap((arm) =>
    correct.map((o, i) => ({
      arm,
      observation: arm === "low" && (i === 0 || i === 2) ? wrong(o) : o,
      providerDurationMs: arm === "gemini" ? 2000 : 1000,
    }))
  );
  assertEquals(
    tradeoffStatistics(cases, results).advancesToFreshValidation,
    true,
  );
  assertEquals(
    tradeoffStatistics(cases, results.slice(1)).advancesToFreshValidation,
    false,
  );
  assertEquals(
    tradeoffStatistics(
      cases,
      results.map((r) =>
        r.arm === "medium" ? { ...r, providerDurationMs: 1900 } : r
      ),
    ).gates.latency,
    false,
  );
  assertEquals(
    tradeoffStatistics(
      cases,
      results.map((r, i) =>
        r.arm === "medium" && i === 23
          ? { ...r, observation: wrong(r.observation) }
          : r
      ),
    ).gates.noLowRegressions,
    false,
  );
  const unmapped = results.map((r) =>
    r.arm === "low" && r.observation.prediction.outcome === "normalized"
      ? {
        ...r,
        observation: {
          prediction: { ...r.observation.prediction, taxon: null },
          mapping: { status: "unmapped" as const, match: null },
        },
      }
      : r
  );
  assertEquals(tradeoffStatistics(cases, unmapped).gates.biologicalGain, false);
  for (const arm of TRADEOFF_ARMS) {
    const failed = results.map((r) =>
      r.arm === arm && r.observation.prediction.caseId === cases[0].input.caseId
        ? {
          ...r,
          observation: {
            prediction: {
              caseId: cases[0].input.caseId,
              outcome: "invalid_output" as const,
            },
            mapping: null,
          },
        }
        : r
    );
    assertEquals(
      tradeoffStatistics(cases, failed).advancesToFreshValidation,
      false,
    );
  }
  assertThrows(() => tradeoffStatistics(cases, [...results, results[0]]));
});
