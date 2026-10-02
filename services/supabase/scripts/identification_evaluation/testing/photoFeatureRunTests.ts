import { assert, assertEquals, assertRejects } from "@std/assert";
import { join } from "node:path";
import { prepareEvidence } from "../assets.ts";
import { atomicJson, claimJson, readJson } from "../files.ts";
import { fingerprintJson } from "../evidence.ts";
import {
  collectPhotoFeatures,
  type FeatureRunInput,
  featureRunReport,
  freezeFeatureRun,
  verifyFeatureApproval,
} from "../photoFeatureRun.ts";
import type { FeatureReviewer } from "../photoFeatureInstrument.ts";
import {
  confidenceOutcome,
  writeConfidenceFixture,
} from "./confidenceFixtures.ts";
import { solPrimaryDraftFixture } from "../../../functions/_shared/ai/testing/openaiSolPrimaryFixtures.ts";
export function registerPhotoFeatureRunTests(scratch: string) {
  const reviewers = (): FeatureReviewer[] =>
    ["slot-01", "slot-02"].map((id) => ({
      id,
      method: "synthetic",
      review: (view) => {
        assert(!("caseId" in view) && !("prediction" in view));
        assert(Object.isFrozen(view.features));
        return Promise.resolve(
          view.features.map(() => ({
            support: "supported",
            visibilityAccurate: true,
            diagnosticValue: "shared",
          })),
        );
      },
    }));
  async function setup() {
    const root = await Deno.makeTempDir({
      dir: scratch,
      prefix: "feature-run-",
    });
    const f = await writeConfidenceFixture(root);
    const cases = [];
    for (const c of f.corpus.cases.slice(0, 18)) {
      cases.push({
        caseId: c.input.caseId,
        reference: c.reference,
        mechanisms: [1, 2],
        imageDigest: c.input.assets[0].sha256,
        reviewCard: ["Synthetic shape fixture; no scientific claim."],
        request: await prepareEvidence(root, c.input),
      });
    }
    const run = join(root, "run");
    await Deno.mkdir(run, { mode: 0o700 });
    const input: FeatureRunInput = {
      plan: {
        mode: "offline",
        paidServiceApproved: false,
        authorizationRef: "synthetic-feature-run",
        budgetNanoUsd: 10_000_000_000,
        retainUntil: "2026-10-22T00:00:00.000Z",
        sourceDigest: "1".repeat(64),
        packetDigest: "2".repeat(64),
        pricingDigest: await fingerprintJson(f.pricing),
        reviewSeed: 17,
        reviewerAssignments: reviewers().map(({ id, method }) => ({
          id,
          method,
        })),
      },
      cases,
      taxonomy: f.taxonomy,
      pricing: f.pricing,
    };
    const provider = {
      mode: "offline" as const,
      preflight: () => Promise.resolve(),
      invoke: (arm: "primary" | "features") => {
        const out = confidenceOutcome(f.corpus.cases[0]);
        if (out.kind !== "draft") throw Error("fixture_invalid");
        return Promise.resolve({
          ...out,
          mediaSafety: {
            provider: "openai" as const,
            policy: "openai_photo_moderation_v1" as const,
            disposition: "allowed" as const,
          },
          draft: {
            ...solPrimaryDraftFixture(),
            ...(arm === "features"
              ? {
                diagnostic_features: [{
                  kind: "shape",
                  visibility: "visible",
                  observation: "PRIVATE FEATURE SENTINEL",
                }],
              }
              : {}),
          },
        });
      },
    };
    return { root, run, input, provider };
  }
  Deno.test("feature collector settles 36 slots and reviews blinded transient features without replay", async () => {
    const s = await setup();
    try {
      let calls = 0, reviews = 0;
      const judges = reviewers().map((r) => ({
        ...r,
        review: async (view: Parameters<FeatureReviewer["review"]>[0]) => {
          reviews++;
          assertEquals(calls, 36);
          return await r.review(view);
        },
      }));
      const report = await collectPhotoFeatures(s.run, s.input, {
        ...s.provider,
        invoke: async (arm) => {
          calls++;
          return await s.provider.invoke(arm);
        },
      }, judges);
      assertEquals(calls, 36);
      assertEquals(reviews, 36);
      assertEquals(report.complete, true);
      assertEquals(report.outstandingNanoUsd, 0);
      const state = await freezeFeatureRun(s.run, s.input);
      assertEquals(await featureRunReport(state), report);
      await assertRejects(() =>
        collectPhotoFeatures(s.run, s.input, s.provider, reviewers())
      );
      for await (const file of Deno.readDir(s.run)) {
        if (file.name === ".lock") continue;
        const bytes = await Deno.readTextFile(join(s.run, file.name));
        for (
          const privateText of [
            "PRIVATE FEATURE",
            "Syntheticus",
            "ai_reasoning",
            "data:image",
          ]
        ) assert(!bytes.includes(privateText));
      }
      const assignment = state.manifest.assignments.find((a) =>
        a.arm === "features"
      )!;
      const path = join(
        s.run,
        String(assignment.ordinal).padStart(2, "0") + ".review.json",
      );
      const saved = await readJson(path) as {
        receipt: {
          eligible: boolean;
          imageDigest: string;
          traits: { kind: string; visibility: string }[];
        };
      };
      for (const field of ["imageDigest", "cardDigest", "featureDigest"]) {
        await atomicJson(path, {
          ...saved,
          receipt: { ...saved.receipt, [field]: "f".repeat(64) },
        });
        await assertRejects(() => featureRunReport(state));
      }
      await atomicJson(path, {
        ...saved,
        receipt: {
          ...saved.receipt,
          traits: saved.receipt.traits.map((t) => ({
            ...t,
            visibility: "unclear",
          })),
        },
      });
      await assertRejects(() => featureRunReport(state));
      await atomicJson(path, saved);
      const altered = structuredClone(s.input);
      altered.cases[0].reviewCard = ["Changed facts"];
      await assertRejects(() => freezeFeatureRun(s.run, altered));
      const manifestPath = join(s.run, "feature-run.json");
      const manifest = await readJson(manifestPath) as {
        stable: { assignments: { snapshotDigest: string }[] };
      };
      manifest.stable.assignments[0].snapshotDigest = "f".repeat(64);
      await atomicJson(manifestPath, manifest);
      await assertRejects(() => freezeFeatureRun(s.run, s.input));
    } finally {
      await Deno.remove(s.root, { recursive: true });
    }
  });
  Deno.test("feature interruption consumes claim; uncertain billing stops with reservation", async () => {
    const s = await setup();
    try {
      const report = await collectPhotoFeatures(s.run, s.input, {
        ...s.provider,
        invoke: () => {
          throw Error("PRIVATE ERROR");
        },
      }, reviewers());
      assertEquals(report.attempted, 1);
      assertEquals(report.stop, "accounting_incomplete");
      assert(report.outstandingNanoUsd > 0);
      assert(!JSON.stringify(report).includes("PRIVATE"));
      await assertRejects(() =>
        collectPhotoFeatures(s.run, s.input, s.provider, reviewers())
      );
      const other = join(s.root, "interrupted");
      await Deno.mkdir(other, { mode: 0o700 });
      const study = await freezeFeatureRun(other, s.input);
      await claimJson(join(other, "01.claim.json"), {
        version: "photo_feature_claim_v1",
        runDigest: study.digest,
        assignment: study.manifest.assignments[0],
      });
      const stopped = await featureRunReport(study);
      assertEquals(stopped.stop, "interrupted_attempt");
      assert(stopped.outstandingNanoUsd > 0);
      await assertRejects(() =>
        collectPhotoFeatures(other, s.input, s.provider, reviewers())
      );
    } finally {
      await Deno.remove(s.root, { recursive: true });
    }
  });
  Deno.test("lost feature review blocks advancement after settled collection; no regeneration", async () => {
    const s = await setup();
    try {
      const judges = reviewers();
      judges[1].review = () => Promise.reject(Error("PRIVATE ERROR"));
      const report = await collectPhotoFeatures(
        s.run,
        s.input,
        s.provider,
        judges,
      );
      assertEquals(report.attempted, 36);
      assertEquals(report.outstandingNanoUsd, 0);
      assertEquals(report.complete, false);
      assertEquals(report.screenPassed, false);
      await assertRejects(() =>
        collectPhotoFeatures(s.run, s.input, s.provider, reviewers())
      );
      await assertRejects(() =>
        freezeFeatureRun(s.run, {
          ...s.input,
          plan: { ...s.input.plan, budgetNanoUsd: 20_000_000_000 },
        })
      );
      await assertRejects(() =>
        freezeFeatureRun(s.run, {
          ...s.input,
          plan: { ...s.input.plan, paidServiceApproved: true },
        })
      );
    } finally {
      await Deno.remove(s.root, { recursive: true });
    }
  });
  Deno.test("feature preflight binds image bytes, pricing, reviewer slots and budget", async () => {
    const s = await setup();
    try {
      for (
        const input of [
          { ...s.input, plan: { ...s.input.plan, budgetNanoUsd: 1 } },
          {
            ...s.input,
            plan: { ...s.input.plan, pricingDigest: "f".repeat(64) },
          },
          {
            ...s.input,
            plan: {
              ...s.input.plan,
              reviewerAssignments: s.input.plan.reviewerAssignments.map(
                (r) => ({ ...r, id: "personal-name" }),
              ),
            },
          },
          {
            ...s.input,
            plan: {
              ...s.input.plan,
              reviewerAssignments: [
                s.input.plan.reviewerAssignments[0],
                s.input.plan.reviewerAssignments[0],
              ],
            },
          },
          {
            ...s.input,
            cases: s.input.cases.map((c, i) =>
              i ? c : { ...c, imageDigest: "f".repeat(64) }
            ),
          },
        ]
      ) await assertRejects(() => freezeFeatureRun(s.run, input));
      assertEquals([...Deno.readDirSync(s.run)].length, 0);
      const study = await freezeFeatureRun(s.run, s.input);
      const extra = join(s.run, "unexpected.json");
      await atomicJson(extra, { private: "sentinel" });
      await assertRejects(() => featureRunReport(study));
      assertEquals(study.manifest.assignments.length, 36);
      assertEquals(new Set(study.manifest.tokens.map((t) => t.token)).size, 18);
      assert(
        await fingerprintJson(study.manifest.reviewOrder) !==
          await fingerprintJson(s.input.cases.map((c) => c.caseId)),
      );
    } finally {
      await Deno.remove(s.root, { recursive: true });
    }
  });
  Deno.test("feature live approval is separately bound and checked before credentials or dispatch", async () => {
    const s = await setup();
    try {
      const input = structuredClone(s.input);
      input.plan.mode = "live";
      input.plan.paidServiceApproved = true;
      input.plan.retainUntil = new Date(Date.now() + 86400000).toISOString();
      input.plan.reviewerAssignments.forEach((r) =>
        r.method = "local_interactive"
      );
      const judges = reviewers().map((r) => ({
        ...r,
        method: "local_interactive" as const,
      }));
      let preflights = 0;
      await assertRejects(() =>
        collectPhotoFeatures(s.run, input, {
          ...s.provider,
          mode: "live",
          preflight: () => {
            preflights++;
            return Promise.resolve();
          },
        }, judges)
      );
      assertEquals(preflights, 0);
      const study = await freezeFeatureRun(s.run, input);
      assertEquals((await featureRunReport(study)).attempted, 0);
      const approvals = join(s.root, ".photo-feature-approvals");
      await Deno.mkdir(approvals, { mode: 0o700 });
      const path = join(
        approvals,
        await fingerprintJson(input.plan.authorizationRef) + ".json",
      );
      const approval = {
        version: "photo_feature_user_approval_v1",
        authorizationRef: input.plan.authorizationRef,
        runDigest: study.digest,
        rootDigest: study.manifest.rootDigest,
        pricingDigest: input.plan.pricingDigest,
        budgetNanoUsd: input.plan.budgetNanoUsd,
        maxCalls: 36,
        expiresAt: input.plan.retainUntil,
      };
      for (
        const mutation of [
          { maxCalls: 37 },
          { budgetNanoUsd: 1 },
          { pricingDigest: "f".repeat(64) },
          { runDigest: "f".repeat(64) },
          { rootDigest: "f".repeat(64) },
        ]
      ) {
        await atomicJson(path, { ...approval, ...mutation });
        await assertRejects(() => verifyFeatureApproval(study));
      }
      await atomicJson(path, approval);
      await verifyFeatureApproval(study);
      await Deno.chmod(approvals, 0o755);
      await assertRejects(() => verifyFeatureApproval(study));
    } finally {
      await Deno.remove(s.root, { recursive: true });
    }
  });
}
