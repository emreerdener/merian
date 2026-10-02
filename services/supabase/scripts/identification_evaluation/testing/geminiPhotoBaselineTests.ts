import { assert, assertEquals, assertRejects } from "@std/assert";
import { join } from "node:path";
import { buildGeminiRequestParameters } from "../../../functions/_shared/ai/geminiRequest.ts";
import { resolveAIClaim } from "../../../functions/_shared/ai/registry.ts";
import { prepareEvidence } from "../assets.ts";
import { fingerprintJson } from "../evidence.ts";
import { atomicJson, claimJson, exists, readJson } from "../files.ts";
import {
  executeGeminiBaseline,
  GEMINI_BASELINE,
  prepareGeminiBaseline,
  readGeminiBaseline,
} from "../geminiPhotoBaselinePilot.ts";
import { fixtureAuthority } from "../profiles.ts";
import {
  executeReasoningPilot,
  type ReasoningPlan,
} from "../reasoningPilot.ts";
import type { Pricing } from "../runContracts.ts";
import {
  confidenceOutcome,
  confidenceSource as source,
  writeConfidenceFixture,
} from "./confidenceFixtures.ts";

export function registerGeminiPhotoBaselineTests(scratch: string) {
  async function setup(priorNanoUsd?: number) {
    const root = await Deno.makeTempDir({
      dir: scratch,
      prefix: "gemini-baseline-",
    });
    const fixture = await writeConfidenceFixture(root);
    const cases = fixture.corpus.cases.filter((c) =>
      c.input.split === "development"
    ).slice(0, 4);
    const original: ReasoningPlan = {
      version: "openai_photo_reasoning_pilot_v1",
      mode: "offline",
      authorizationRef: "synthetic",
      packetRootDigest: await fingerprintJson(root),
      cases: cases.map((c, i) => ({
        input: c.input,
        reference: i === 0 ? null : c.reference,
        facts: ["Invented reference fact; never provider input."],
        evidenceRef: "synthetic",
        rightsApproved: true,
        personalDataExcluded: true,
      })),
    };
    await atomicJson(join(root, "reasoning-plan.json"), original);
    await executeReasoningPilot(
      root,
      source,
      "offline",
      {
        provider: "openai",
        prepare: () => () => Promise.resolve(confidenceOutcome(cases[0])),
      },
      () =>
        Promise.resolve({
          grounding: { status: "pass", reason: "supported" },
          requiredInformation: { status: "pass", reason: "supported" },
          uncertainty: { status: "pass", reason: "supported" },
        }),
    );
    const baseline = await readJson(
      join(root, "reasoning-report.json"),
    ) as Record<string, unknown>;
    if (priorNanoUsd !== undefined) baseline.settledNanoUsd = priorNanoUsd;
    for (const suffix of ["plan", "manifest"]) {
      await Deno.copyFile(
        join(root, `reasoning-${suffix}.json`),
        join(root, `baseline-${suffix}.json`),
      );
    }
    await atomicJson(join(root, "baseline-report.json"), baseline);
    const plan = {
      version: GEMINI_BASELINE.version,
      mode: "offline",
      authorizationRef: "synthetic-gemini",
      packetRootDigest: await fingerprintJson(root),
      baselineReportDigest: await fingerprintJson(baseline),
      retainUntil: "2026-10-22T00:00:00.000Z",
      paidServiceApproved: true,
      inputPermission: "gemini",
    };
    await atomicJson(join(root, "gemini-plan.json"), plan);
    const pricing: Pricing = {
      version: "evaluation_pricing_v1",
      currency: "USD",
      service: "paid_standard_synchronous",
      retrievedAt: "2026-10-01T00:00:00.000Z",
      sourceUrl: "https://ai.google.dev/gemini-api/docs/pricing",
      reviewRef: "synthetic",
      includesReasoning: true,
      models: ["gemini-2.5-flash", "gemini-2.5-pro"].map((model) => ({
        model: model as Pricing["models"][number]["model"],
        inputPerMillion: { text: 2.5, image: 2.5, audio: 2.5, cached: .25 },
        outputPerMillion: 15,
        maxInputTokens: 1_048_576,
        maxBillableOutputTokens: 65_536,
        limitsEvidenceRef: "synthetic",
      })),
    };
    await atomicJson(join(root, "pricing.json"), pricing);
    const pilot = await prepareGeminiBaseline(root, source);
    const outcome = () => ({
      ...confidenceOutcome(cases[0]),
      returnedModel: "gemini-2.5-pro",
    });
    return { root, pilot, outcome, plan };
  }
  Deno.test("Gemini baseline makes six preclaimed calls with native request parity, private projections and no replay", async () => {
    const { root, pilot, outcome } = await setup();
    try {
      assertEquals(
        pilot.manifest.assignments.map((a) => a.assignment.caseId),
        [0, 0, 0, 1, 2, 3].map((i) => pilot.cases[i].input.caseId),
      );
      for (const a of pilot.manifest.assignments) {
        const c = pilot.cases.find((c) =>
          c.input.caseId === a.assignment.caseId
        )!;
        const request = await prepareEvidence(root, c.input);
        const snapshot = resolveAIClaim(
          request,
          fixtureAuthority("gemini_pro", request),
        );
        const native = buildGeminiRequestParameters(request, snapshot);
        assertEquals(await fingerprintJson(native), a.assignment.requestDigest);
        assertEquals(native.config!.thinkingConfig!.thinkingBudget, 5000);
        assertEquals(native.config!.temperature, .1);
        assertEquals(native.config!.maxOutputTokens, 8192);
        assert(!JSON.stringify(native).includes("Invented reference fact"));
      }
      let calls = 0;
      const invoke = async (ordinal: number) => {
        calls++;
        assert(
          await exists(
            join(
              root,
              "gemini-attempts",
              String(ordinal).padStart(2, "0") + ".claim.json",
            ),
          ),
        );
        return outcome();
      };
      const report = await executeGeminiBaseline(
        root,
        source,
        "offline",
        invoke,
      );
      assertEquals(report.complete, true);
      assertEquals(report.attempted, 6);
      assertEquals(
        report.records.filter((r) => r.assessment === null).length,
        3,
      );
      assertEquals(report.outstandingNanoUsd, 0);
      assert(report.cumulativeNanoUsd > report.settledNanoUsd);
      const saved = JSON.stringify(report);
      for (
        const forbidden of [
          "Syntheticus",
          "ai_reasoning",
          "data:image",
          "Invented reference fact",
        ]
      ) {
        assert(!saved.includes(forbidden));
      }
      await executeGeminiBaseline(root, source, "offline", invoke);
      assertEquals(calls, 6);
      await assertRejects(() =>
        executeGeminiBaseline(root, source, "live", invoke)
      );
      await assertRejects(() =>
        prepareGeminiBaseline(root, { ...source, digest: "f".repeat(64) })
      );
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });
  Deno.test("Gemini baseline retains failed, uncertain, mismatched and missing-usage reservations without retry", async () => {
    for (
      const failure of [
        "throw",
        "missing_usage",
        "contradictory_usage",
        "wrong_model",
      ] as const
    ) {
      const { root, pilot, outcome } = await setup();
      try {
        let calls = 0;
        const invoke = () => {
          calls++;
          if (failure === "throw") throw new Error("synthetic");
          const result = outcome();
          if (failure === "missing_usage") result.usage = null;
          if (failure === "contradictory_usage") {
            result.usage = { ...result.usage!, totalTokens: 1 };
          }
          if (failure === "wrong_model") {
            result.returnedModel = "gemini-2.5-flash";
          }
          return Promise.resolve(result);
        };
        const report = await executeGeminiBaseline(
          root,
          source,
          "offline",
          invoke,
        );
        assertEquals(report.complete, false);
        assertEquals(
          report.outstandingNanoUsd,
          pilot.manifest.assignments[0].reservedNanoUsd,
        );
        await executeGeminiBaseline(root, source, "offline", invoke);
        assertEquals(calls, 1);
      } finally {
        await Deno.remove(root, { recursive: true });
      }
    }
  });
  Deno.test("Gemini baseline accounts for prior OpenAI cost before dispatch and preserves an interrupted claim", async () => {
    const setupBudget = await setup(9_000_000_000);
    try {
      let calls = 0;
      const report = await executeGeminiBaseline(
        setupBudget.root,
        source,
        "offline",
        () => {
          calls++;
          return Promise.resolve(setupBudget.outcome());
        },
      );
      assertEquals(calls, 0);
      assertEquals(report.stop, "budget_exhausted");
    } finally {
      await Deno.remove(setupBudget.root, { recursive: true });
    }
    const { root, pilot, outcome } = await setup();
    try {
      await readGeminiBaseline(root, pilot);
      await claimJson(join(root, "gemini-attempts", "01.claim.json"), {
        version: "gemini_photo_baseline_claim_v1",
        manifestDigest: pilot.digest,
        assignment: pilot.manifest.assignments[0],
      });
      let calls = 0;
      const report = await executeGeminiBaseline(
        root,
        source,
        "offline",
        () => {
          calls++;
          return Promise.resolve(outcome());
        },
      );
      assertEquals(calls, 0);
      assertEquals(report.stop, "interrupted_attempt");
      assertEquals(report.attempted, 1);
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });
  Deno.test("Gemini baseline rejects changed parent evidence and packet relocation", async () => {
    const { root, plan } = await setup();
    try {
      await atomicJson(join(root, "gemini-plan.json"), {
        ...plan,
        packetRootDigest: "a".repeat(64),
      });
      await assertRejects(() => prepareGeminiBaseline(root, source));
      await atomicJson(join(root, "gemini-plan.json"), plan);
      const baseline = await readJson(
        join(root, "baseline-report.json"),
      ) as Record<string, unknown>;
      await atomicJson(join(root, "baseline-report.json"), {
        ...baseline,
        settledNanoUsd: 0,
      });
      await assertRejects(() => prepareGeminiBaseline(root, source));
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });
}
