import { assert, assertEquals, assertRejects } from "@std/assert";
import { join } from "node:path";
import { fingerprintBytes, fingerprintJson } from "../evidence.ts";
import { type Ratings } from "../explanationContracts.ts";
import { atomicJson, exists, readJson } from "../files.ts";
import {
  PHOTO_MODEL_REFERENCE_GAP_POLICY,
  validatePhotoModelApproval,
} from "../photoModelAdmission.ts";
import {
  loadPhotoModelParent,
  preparePhotoModelContinuation,
} from "../photoModelContinuation.ts";
import { loadPhotoModelPacket } from "../photoModelPreparation.ts";
import { executePhotoModelContinuation } from "../photoModelRunner.ts";
import { pass, setup, source } from "./photoModelRunnerTests.ts";

const nextSource = {
  ...source,
  commit: "2".repeat(40),
  digest: "3".repeat(64),
};
const gap = (): Ratings => ({
  ...pass(),
  grounding: { status: "not_assessable", reason: "insufficient_reference" },
});
async function stopped(scratch: string) {
  const s = await setup(scratch);
  s.dependencies.review = () => Promise.resolve(gap());
  assertEquals((await s.run()).stop, "screen_failed");
  assertEquals(s.calls, [1]);
  s.dependencies.review = () => Promise.resolve(pass());
  const resume = () =>
    executePhotoModelContinuation(
      s.root,
      nextSource,
      "offline",
      s.dependencies,
    );
  return { ...s, resume };
}
async function originalBytes(root: string) {
  const result: Record<string, string> = {};
  for (
    const name of [
      "manifest.json",
      "stop.json",
      "state.json",
      "claims/01.json",
      "results/01.json",
      "reviews/01.json",
    ]
  ) {
    result[name] = await Deno.readTextFile(join(root, "photo-model-run", name));
  }
  return result;
}
export function registerPhotoModelContinuationTests(scratch: string) {
  Deno.test("photo-model continuation verifies an expired original approval at claim time and retains its credential binding", async () => {
    const s = await stopped(scratch);
    try {
      // Invented provenance only. This exercises admission with no live dispatch or real media.
      const packet = await loadPhotoModelPacket(s.root, nextSource);
      packet.report.source.dirty = false;
      packet.corpus.evidenceOrigin = "real";
      packet.plan.inputApproval = {
        provider: "openai",
        corpusDigest: packet.plan.corpusDigest,
        caseIds: [
          ...packet.plan.screenCaseIds,
          ...packet.plan.challengeCaseIds,
        ],
        recordRef: "synthetic-input",
      };
      packet.report.planDigest = await fingerprintJson(packet.plan);
      const oldSource = { ...source, dirty: false },
        now = Date.now(),
        historical = now - 2 * 86400000,
        key = "synthetic-key";
      const approval = {
        version: "photo_model_approval_v1",
        project: "naturebook",
        operation: "18_call_luna_sol_photo_comparison",
        planDigest: packet.report.planDigest,
        sourceCommit: source.commit,
        sourceDigest: source.digest,
        credentialSha256: await fingerprintBytes(new TextEncoder().encode(key)),
        budgetUsd: 40,
        approvedAt: new Date(historical).toISOString(),
        expiresAt: new Date(historical + 3600000).toISOString(),
        recordRef: "synthetic-parent-approval",
        reviewerRef: "synthetic-reviewer",
        delegationRef: "synthetic-delegation",
      };
      const dir = join(s.root, "photo-model-run");
      const manifest = await readJson(join(dir, "manifest.json")) as {
        createdAt: string;
        binding: Record<string, unknown>;
      };
      manifest.createdAt = new Date(historical).toISOString();
      Object.assign(manifest.binding, {
        mode: "live",
        source: oldSource,
        planDigest: packet.report.planDigest,
        approvalDigest: await fingerprintJson(approval),
      });
      const runDigest = await fingerprintJson(manifest);
      await atomicJson(join(dir, "manifest.json"), manifest);
      await atomicJson(join(s.root, "photo-model-approval.json"), approval);
      for (
        const relative of [
          "claims/01.json",
          "results/01.json",
          "reviews/01.json",
          "stop.json",
        ]
      ) {
        const path = join(dir, relative),
          value = await readJson(path) as Record<string, unknown>;
        value.runDigest = runDigest;
        if (relative.startsWith("claims")) {
          value.startedAt = new Date(historical + 60000).toISOString();
        }
        if (relative.startsWith("reviews")) {
          value.resultDigest = await fingerprintJson(
            await readJson(join(dir, "results", "01.json")),
          );
        }
        await atomicJson(path, value);
      }
      const parent = await loadPhotoModelParent(s.root, packet, "live", key);
      assertEquals(parent.parentRunDigest, runDigest);
      await assertRejects(() =>
        loadPhotoModelParent(s.root, packet, "live", "different-synthetic-key")
      );
      await assertRejects(() =>
        validatePhotoModelApproval(
          approval,
          { ...packet, report: { ...packet.report, source: oldSource } },
          key,
          now,
        )
      );
      assertEquals(s.calls, [1]);
    } finally {
      await Deno.remove(s.root, { recursive: true });
    }
  });
  Deno.test("photo-model continuation inherits the exact first attempt, permits only reference gaps, and dispatches the 17 untouched ordinals once", async () => {
    const s = await stopped(scratch);
    try {
      const before = await originalBytes(s.root);
      const preflight = await preparePhotoModelContinuation(s.root, nextSource);
      assertEquals(preflight.dispatchAuthorized, false);
      assertEquals(preflight.inheritedCalls, 1);
      assertEquals(preflight.maxAdditionalCalls, 17);
      assertEquals(preflight.fullScheduleReservationWithPremiumUsd, 39.0071088);
      s.dependencies.review = () =>
        Promise.resolve([4, 7].includes(s.calls.at(-1)!) ? gap() : pass());
      const state = await s.resume();
      assertEquals(state.version, "photo_model_state_v2");
      assertEquals(state.complete, true);
      assertEquals(state.claimedCalls, 18);
      assertEquals(state.completedCalls, 18);
      assertEquals(state.heldReservationUsd, 39.0071088);
      assert("referenceGapOrdinals" in state);
      assertEquals(state.referenceGapOrdinals, [1, 4, 7]);
      assertEquals(state.explanationEvidenceComplete, false);
      assertEquals(state.newlyClaimedCalls, 17);
      assertEquals(state.productionActivationAuthorized, false);
      assertEquals(s.calls, Array.from({ length: 18 }, (_, i) => i + 1));
      assertEquals(await s.resume(), state);
      assertEquals(s.calls.length, 18);
      for (const name of ["claims", "results", "reviews"]) {
        const paths = Array.from(
          await Array.fromAsync(
            Deno.readDir(join(s.root, "photo-model-continuation", name)),
          ),
        ).map((e) => e.name);
        assertEquals(paths.length, 17);
        assert(!paths.includes("01.json"));
      }
      assertEquals(await originalBytes(s.root), before);
    } finally {
      await Deno.remove(s.root, { recursive: true });
    }
  });
  Deno.test("photo-model continuation preserves hard screening, review, model, safety and billing stops", async (t) => {
    for (
      const failure of [
        "wrong_match",
        "fail",
        "reviewer_unsure",
        "review_unavailable",
        "missing_usage",
        "model",
        "safety",
      ]
    ) {
      await t.step(failure, async () => {
        const s = await stopped(scratch);
        try {
          const before = await originalBytes(s.root), outcome = s.outcome;
          s.dependencies.outcome = async (a) => {
            const r = await outcome(a);
            if (failure === "missing_usage") return { ...r, usage: null };
            if (failure === "model") {
              return { ...r, returnedModel: "unknown-model" };
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
            return failure === "wrong_match" && r.kind === "draft"
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
              failure === "fail"
                ? {
                  ...pass(),
                  grounding: { status: "fail", reason: "invented_evidence" },
                }
                : ["reviewer_unsure", "review_unavailable"].includes(failure)
                ? {
                  ...pass(),
                  grounding: { status: "not_assessable", reason: failure },
                }
                : pass(),
            );
          const state = await s.resume();
          assert(state.stop !== null);
          assertEquals(state.complete, false);
          assertEquals(s.calls, [1, 2]);
          assertEquals(await s.resume(), state);
          assertEquals(s.calls, [1, 2]);
          assertEquals(await originalBytes(s.root), before);
        } finally {
          await Deno.remove(s.root, { recursive: true });
        }
      });
    }
  });
  Deno.test("photo-model continuation rejects a different parent, schedule or reservation before creating a new journal", async (t) => {
    for (
      const mutation of [
        "extra_claim",
        "unknown_file",
        "wrong_stop",
        "missing_review",
        "result_drift",
        "order_drift",
        "budget_drift",
      ]
    ) {
      await t.step(mutation, async () => {
        const s = await stopped(scratch);
        try {
          const parent = join(s.root, "photo-model-run");
          if (mutation === "extra_claim") {
            await atomicJson(join(parent, "claims", "02.json"), {});
          }
          if (mutation === "unknown_file") {
            await atomicJson(join(parent, "unknown.json"), {});
          }
          if (mutation === "missing_review") {
            await Deno.remove(join(parent, "reviews", "01.json"));
          }
          if (mutation === "wrong_stop") {
            const path = join(parent, "stop.json");
            await atomicJson(path, {
              ...(await readJson(path) as object),
              reason: "provider_failure",
            });
          }
          if (mutation === "result_drift") {
            const path = join(parent, "results", "01.json");
            await atomicJson(path, {
              ...(await readJson(path) as object),
              estimatedUpperNanoUsd: 0,
            });
          }
          if (mutation === "order_drift" || mutation === "budget_drift") {
            const path = join(s.root, "photo-model-plan.json");
            const plan = await readJson(path) as {
              budgetUsd: number;
              screenCaseIds: string[];
            };
            if (mutation === "budget_drift") plan.budgetUsd = 39.5;
            else plan.screenCaseIds.reverse();
            await atomicJson(path, plan);
          }
          await assertRejects(s.resume);
          assertEquals(s.calls, [1]);
          assertEquals(
            await exists(join(s.root, "photo-model-continuation")),
            false,
          );
        } finally {
          await Deno.remove(s.root, { recursive: true });
        }
      });
    }
  });
  Deno.test("photo-model continuation detects parent drift before the next dispatch and never clears its terminal stop", async () => {
    const s = await stopped(scratch);
    try {
      const path = join(s.root, "photo-model-run", "reviews", "01.json"),
        review = await readJson(path);
      s.dependencies.review = async () => {
        await atomicJson(path, {});
        return pass();
      };
      const state = await s.resume();
      assertEquals(state.stop, "configuration_invalid");
      assertEquals(s.calls, [1, 2]);
      await atomicJson(path, review);
      assertEquals((await s.resume()).stop, "configuration_invalid");
      assertEquals(s.calls, [1, 2]);
    } finally {
      await Deno.remove(s.root, { recursive: true });
    }
  });
  Deno.test("photo-model continuation locks both journals and never retries an interrupted claim", async () => {
    const s = await stopped(scratch);
    let release!: () => void, entered!: () => void;
    const hold = new Promise<void>((r) => release = r),
      started = new Promise<void>((r) => entered = r);
    try {
      const before = await originalBytes(s.root), outcome = s.outcome;
      s.dependencies.outcome = async (a) => {
        if (a.ordinal === 2) {
          entered();
          await hold;
        }
        return await outcome(a);
      };
      const first = s.resume();
      await started;
      await assertRejects(s.resume);
      await assertRejects(s.run);
      release();
      await first;
      assertEquals(s.calls.length, 18);
      assertEquals(await originalBytes(s.root), before);
      await Deno.remove(
        join(s.root, "photo-model-continuation", "results", "18.json"),
      );
      await Deno.remove(
        join(s.root, "photo-model-continuation", "reviews", "18.json"),
      );
      assertEquals((await s.resume()).stop, "interrupted_attempt");
      assertEquals(s.calls.length, 18);
    } finally {
      release();
      await Deno.remove(s.root, { recursive: true });
    }
  });
  Deno.test("photo-model continuation approval is separate authority bound to the prior record and combined cap", async () => {
    const s = await stopped(scratch);
    try {
      const packet = await loadPhotoModelPacket(s.root, nextSource);
      const parent = await loadPhotoModelParent(s.root, packet, "offline");
      packet.report.source.dirty = false;
      packet.corpus.evidenceOrigin = "real";
      packet.plan.inputApproval = {
        provider: "openai",
        corpusDigest: packet.plan.corpusDigest,
        caseIds: [
          ...packet.plan.screenCaseIds,
          ...packet.plan.challengeCaseIds,
        ],
        recordRef: "synthetic-approval",
      };
      const now = Date.now(), key = "synthetic-key";
      const approval = {
        version: "photo_model_continuation_approval_v1",
        project: "naturebook",
        operation: "remaining_17_luna_sol_photo_comparison",
        planDigest: await fingerprintJson(packet.plan),
        sourceCommit: nextSource.commit,
        sourceDigest: nextSource.digest,
        credentialSha256: await fingerprintBytes(new TextEncoder().encode(key)),
        budgetUsd: 40,
        approvedAt: new Date(now).toISOString(),
        expiresAt: new Date(now + 3600000).toISOString(),
        recordRef: "synthetic-continuation",
        reviewerRef: "assistant",
        delegationRef: "synthetic-delegation",
        parentRunDigest: parent.parentRunDigest,
        parentArtifactsDigest: parent.parentArtifactsDigest,
        screeningPolicy: PHOTO_MODEL_REFERENCE_GAP_POLICY,
        maxAdditionalCalls: 17,
      };
      await validatePhotoModelApproval(approval, packet, key, now, parent);
      await assertRejects(() =>
        validatePhotoModelApproval(approval, packet, key, now)
      );
      for (
        const delta of [
          { parentRunDigest: "0".repeat(64) },
          { parentArtifactsDigest: "0".repeat(64) },
          { maxAdditionalCalls: 18 },
          { budgetUsd: 40.01 },
          { screeningPolicy: "ignore_failures" },
          { version: "photo_model_approval_v1" },
          { operation: "18_call_luna_sol_photo_comparison" },
          { expiresAt: new Date(now).toISOString() },
          { credentialSha256: "0".repeat(64) },
        ]
      ) {
        await assertRejects(() =>
          validatePhotoModelApproval(
            { ...approval, ...delta },
            packet,
            key,
            now,
            parent,
          )
        );
      }
      assertEquals(s.calls, [1]);
    } finally {
      await Deno.remove(s.root, { recursive: true });
    }
  });
}
