import { assert, assertEquals, assertRejects } from "@std/assert";
import { join } from "node:path";
import { prepareEvidence } from "../assets.ts";
import { fingerprintJson } from "../evidence.ts";
import { atomicJson, claimJson, readJson } from "../files.ts";
import {
  preparePrimaryScreen,
  PRIMARY_SCREEN,
  screenRequest,
} from "../photoPrimaryScreenPreparation.ts";
import {
  dispatchPrimaryScreen,
  primaryScreenReport,
} from "../photoPrimaryScreenRunner.ts";
import {
  confidenceOutcome,
  confidenceSource,
  writeConfidenceFixture,
} from "./confidenceFixtures.ts";
import { solPrimaryDraftFixture } from "../../../functions/_shared/ai/testing/openaiSolPrimaryFixtures.ts";
import type { AIProviderOutcome } from "../../../functions/_shared/ai/contracts.ts";

export function registerPhotoPrimaryScreenTests(scratch: string) {
  async function setup() {
    const root = await Deno.makeTempDir({
      dir: scratch,
      prefix: "primary-screen-",
    });
    const fixture = await writeConfidenceFixture(root);
    const cases = [
      ...fixture.corpus.cases.slice(0, 14),
      ...fixture.corpus.cases.filter((c) =>
        c.reference.subject === "biological" &&
        c.reference.resolution === "unresolved"
      ).slice(0, 6),
    ];
    const assignments = [];
    for (const c of cases) {
      const native = screenRequest(
        await prepareEvidence(root, c.input),
        "released",
      );
      assignments.push({
        key: `development-${c.input.caseId}-released`,
        phase: "development",
        caseId: c.input.caseId,
        arm: "released",
        requestDigest: await fingerprintJson(native.parameters),
        settingsDigest: await fingerprintJson(native.snapshot),
        reservedNanoUsd: 1,
        gemini: null,
      });
    }
    const parentManifest = {
      version: "photo_decision_manifest_v1",
      protocol: {},
      source: confidenceSource,
      planDigest: "1".repeat(64),
      corpusDigest: await fingerprintJson(fixture.corpus),
      taxonomyDigest: await fingerprintJson(fixture.taxonomy),
      evidenceDigest: null,
      openaiPricingDigest: "2".repeat(64),
      geminiPricingDigest: "3".repeat(64),
      assignments: [...assignments, ...assignments],
    };
    const exposure = {
      parentManifest,
      claims: assignments.map((assignment) => ({
        version: "photo_decision_claim_v1",
        manifestDigest: "",
        assignment,
      })),
      clusters: cases.map((c) => ({
        caseId: c.input.caseId,
        clusterRef: `subject-${c.input.caseId}`,
      })),
    };
    const parentDigest = await fingerprintJson(parentManifest);
    exposure.claims.forEach((c) => c.manifestDigest = parentDigest);
    const plan = {
      version: PRIMARY_SCREEN.version,
      mode: "offline",
      paidServiceApproved: false,
      authorizationRef: "synthetic-primary-screen",
      packetRootDigest: await fingerprintJson(await Deno.realPath(root)),
      retainUntil: "2026-10-22T00:00:00.000Z",
      inputPermission: "openai",
      caseIds: cases.map((c) => c.input.caseId),
      exposureDigest: await fingerprintJson(exposure),
      reviewRef: "synthetic-review",
      budgetNanoUsd: PRIMARY_SCREEN.budgetNanoUsd,
      maxCalls: 40,
    };
    await atomicJson(join(root, "screen-exposure.json"), exposure);
    await atomicJson(join(root, "screen-plan.json"), plan);
    // The fixture uses the confidence runner's pricing filename.
    await atomicJson(join(root, "openai-pricing.json"), fixture.pricing);
    const study = await preparePrimaryScreen(root, confidenceSource);
    return { root, study, plan };
  }
  Deno.test("primary screen freezes 40 paired attempts, records safe diagnostics and never replays", async () => {
    const { root, study } = await setup();
    try {
      let calls = 0;
      let callbackError: unknown;
      while (true) {
        const { next } = await primaryScreenReport(root, study);
        if (!next) break;
        await dispatchPrimaryScreen(
          root,
          study,
          next.arm,
          async (a) => {
            try {
              calls++;
              const before = await primaryScreenReport(root, study);
              assertEquals(before.report.attempted, calls);
              assertEquals(before.report.stop, "interrupted_attempt");
              const c = study.cases.find((c) => c.input.caseId === a.caseId)!;
              const result = confidenceOutcome(c);
              if (result.kind !== "draft") throw new Error("fixture_invalid");
              return {
                ...result,
                mediaSafety: {
                  provider: "openai",
                  policy: "openai_photo_moderation_v1",
                  disposition: "allowed",
                },
                draft: a.arm === "primary"
                  ? solPrimaryDraftFixture(
                    c.reference.resolution === "unresolved"
                      ? "unresolved_biological"
                      : "species",
                  )
                  : result.draft,
              };
            } catch (error) {
              callbackError = error;
              throw error;
            }
          },
        );
        if (callbackError) throw callbackError;
      }
      const report = (await primaryScreenReport(root, study)).report;
      assertEquals(calls, 40);
      assertEquals(report.complete, true);
      assertEquals(report.outstandingNanoUsd, 0);
      assertEquals(report.superiorityEstablished, false);
      assertEquals(report.confidenceQualification, false);
      assertEquals(report.screen.passed, false);
      assertEquals(report.screen.unresolvedGains, 0);
      const text = JSON.stringify(report);
      for (
        const v of [
          "Syntheticus",
          "Invented explanation",
          "data:image",
          "ai_reasoning",
        ]
      ) assert(!text.includes(v));
      await assertRejects(() =>
        dispatchPrimaryScreen(root, study, "primary", () => {
          throw new Error("must_not_dispatch");
        })
      );
      assertEquals(calls, 40);
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });
  Deno.test("primary screen retains an interrupted claim and rejects out-of-order or changed source", async () => {
    const { root, study } = await setup();
    try {
      for (const paidServiceApproved of [false, undefined]) {
        await assertRejects(() =>
          dispatchPrimaryScreen(
            root,
            {
              ...study,
              plan: { ...study.plan, mode: "live", paidServiceApproved },
            },
            study.manifest.assignments[0].arm,
          )
        );
      }
      assertEquals(
        (await primaryScreenReport(root, study)).report.attempted,
        0,
      );
      const first = study.manifest.assignments[0];
      await primaryScreenReport(root, study);
      await claimJson(join(root, "screen-attempts", "01.claim.json"), {
        version: "photo_primary_screen_claim_v1",
        manifestDigest: study.digest,
        assignment: first,
      });
      const r = (await primaryScreenReport(root, study)).report;
      assertEquals(r.attempted, 1);
      assertEquals(r.stop, "interrupted_attempt");
      assertEquals(r.outstandingNanoUsd, first.reservedNanoUsd);
      await assertRejects(() =>
        dispatchPrimaryScreen(root, study, first.arm, () => {
          throw new Error("no_retry");
        })
      );
      await assertRejects(() =>
        preparePrimaryScreen(root, {
          ...confidenceSource,
          digest: "f".repeat(64),
        })
      );
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });
  Deno.test("primary screen stops on uncertain billing and rejects saved prose or accounting edits", async () => {
    const { root, study } = await setup();
    try {
      const a = study.manifest.assignments[0],
        c = study.cases.find((c) => c.input.caseId === a.caseId)!;
      const r = await dispatchPrimaryScreen(
        root,
        study,
        a.arm,
        () =>
          Promise.resolve(
            { ...confidenceOutcome(c), usage: null } as AIProviderOutcome,
          ),
      );
      assertEquals(r.report.attempted, 1);
      assertEquals(r.report.stop, "accounting_incomplete");
      assertEquals(r.report.outstandingNanoUsd, a.reservedNanoUsd);
      const path = join(root, "screen-attempts", "01.result.json"),
        raw = await readJson(path) as Record<string, unknown>;
      await atomicJson(path, {
        ...raw,
        diagnostics: { provider_text: "must not escape" },
      });
      await assertRejects(() => primaryScreenReport(root, study));
      await atomicJson(path, { ...raw, settledNanoUsd: 0 });
      await assertRejects(() => primaryScreenReport(root, study));
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });
  Deno.test("primary screen freezes scope and exposure instead of reusing budget or duplicate clusters", async () => {
    const { root, study, plan } = await setup();
    try {
      for (
        const change of [{ budgetNanoUsd: 20_000_000_000 }, { maxCalls: 42 }, {
          caseIds: [...plan.caseIds.slice(1), plan.caseIds[1]],
        }, { packetRootDigest: "f".repeat(64) }]
      ) {
        await atomicJson(join(root, "screen-plan.json"), {
          ...plan,
          ...change,
        });
        await assertRejects(() => preparePrimaryScreen(root, confidenceSource));
      }
      await atomicJson(join(root, "screen-plan.json"), plan);
      assertEquals(
        (await preparePrimaryScreen(root, confidenceSource)).digest,
        study.digest,
      );
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });
}
