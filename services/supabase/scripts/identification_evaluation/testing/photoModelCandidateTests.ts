/** Invented controller outcomes prove mechanics, never prompt quality. */
import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import { join } from "node:path";
import { OPENAI_LUNA_EVIDENCE_LIMITS_PROFILE } from "../../../functions/_shared/ai/openaiLunaEvidenceLimits.ts";
import { fingerprintBytes, fingerprintJson } from "../evidence.ts";
import { type Ratings } from "../explanationContracts.ts";
import { atomicJson, readJson } from "../files.ts";
import {
  PHOTO_MODEL_REFERENCE_GAP_POLICY,
  validatePhotoModelApproval,
} from "../photoModelAdmission.ts";
import { parsePhotoModelPlan } from "../photoModelContracts.ts";
import { loadPhotoModelPacket } from "../photoModelPreparation.ts";
import { pass, setup, source } from "./photoModelRunnerTests.ts";

async function candidate(scratch: string) {
  const s = await setup(scratch);
  const previous = await loadPhotoModelPacket(s.root, source);
  await atomicJson(join(s.root, "photo-model-plan.json"), {
    ...previous.plan,
    version: "photo_model_plan_v3",
  });
  return { ...s, previous };
}
const gap = (): Ratings => ({
  ...pass(),
  grounding: { status: "not_assessable", reason: "insufficient_reference" },
});

export function registerPhotoModelCandidateTests(scratch: string) {
  Deno.test("photo-model candidate cannot restart or overwrite a stopped original journal", async () => {
    const s = await setup(scratch);
    try {
      s.dependencies.review = () => Promise.resolve(gap());
      assertEquals((await s.run()).stop, "screen_failed");
      const manifestPath = join(s.root, "photo-model-run", "manifest.json");
      const stopPath = join(s.root, "photo-model-run", "stop.json");
      const manifest = await Deno.readTextFile(manifestPath),
        stop = await Deno.readTextFile(stopPath);
      const old = await loadPhotoModelPacket(s.root, source);
      await atomicJson(join(s.root, "photo-model-plan.json"), {
        ...old.plan,
        version: "photo_model_plan_v3",
      });
      assertEquals((await s.run()).stop, "screen_failed");
      assertEquals(s.calls, [1]);
      assertEquals(await Deno.readTextFile(manifestPath), manifest);
      assertEquals(await Deno.readTextFile(stopPath), stop);
    } finally {
      await Deno.remove(s.root, { recursive: true });
    }
  });
  Deno.test("photo-model candidate plan changes Luna request identity but preserves Sol, evidence, pricing and the 18-call bound", async () => {
    const s = await candidate(scratch);
    try {
      const packet = await loadPhotoModelPacket(s.root, source);
      assertEquals(packet.report.plannedCalls, 18);
      assertEquals(packet.report.dispatchAuthorized, false);
      assertEquals(
        packet.report.screeningPolicy,
        PHOTO_MODEL_REFERENCE_GAP_POLICY,
      );
      assertEquals(
        packet.report.fullScheduleReservationWithPremiumUsd,
        39.0071088,
      );
      assertEquals(packet.pricing, s.previous.pricing);
      assertEquals(packet.facts, s.previous.facts);
      assertEquals(packet.corpus, s.previous.corpus);
      for (const [i, row] of packet.report.order.entries()) {
        const old = s.previous.report.order[i];
        if (row.model === "gpt-6-sol") assertEquals(row, old);
        else {
          assertEquals(row.profile, OPENAI_LUNA_EVIDENCE_LIMITS_PROFILE);
          assert(
            row.snapshotDigest !== old.snapshotDigest &&
              row.requestDigest !== old.requestDigest,
          );
          assertEquals({
            ...row,
            profile: old.profile,
            snapshotDigest: old.snapshotDigest,
            requestDigest: old.requestDigest,
          }, old);
        }
      }
      for (
        const delta of [{ maxCalls: 19 }, { attemptsPerAssignment: 2 }, {
          budgetUsd: 41,
        }, { profile: "unreviewed" }]
      ) {
        assertThrows(() => parsePhotoModelPlan({ ...packet.plan, ...delta }));
      }
      assertEquals(s.calls.length, 0);
    } finally {
      await Deno.remove(s.root, { recursive: true });
    }
  });

  Deno.test("photo-model candidate records reference gaps without counting them as passes and still stops on mineral specificity", async () => {
    for (const failure of [false, true]) {
      const s = await candidate(scratch);
      try {
        s.dependencies.review = () =>
          Promise.resolve(
            failure && s.calls.length === 6
              ? {
                ...gap(),
                uncertainty: {
                  status: "fail",
                  reason: "unsupported_specificity",
                },
              }
              : gap(),
          );
        const state = await s.run();
        assertEquals(state.complete, !failure);
        assertEquals(state.stop, failure ? "screen_failed" : null);
        assertEquals(state.claimedCalls, failure ? 6 : 18);
        assert("referenceGapOrdinals" in state);
        assertEquals(state.referenceGapOrdinals, s.calls);
        assertEquals(state.explanationEvidenceComplete, false);
        assertEquals(state.productionActivationAuthorized, false);
        assertEquals(await s.run(), state);
        assertEquals(s.calls.length, failure ? 6 : 18);
        const manifest = await readJson(
          join(s.root, "photo-model-run", "manifest.json"),
        ) as { binding: { screeningPolicy: string } };
        assertEquals(
          manifest.binding.screeningPolicy,
          PHOTO_MODEL_REFERENCE_GAP_POLICY,
        );
      } finally {
        await Deno.remove(s.root, { recursive: true });
      }
    }
  });

  Deno.test("photo-model candidate requires its own explicit approval and cannot borrow original or continuation authority", async () => {
    const s = await candidate(scratch);
    try {
      const packet = await loadPhotoModelPacket(s.root, source);
      // Synthetic admission exercise only. No real evidence, credential or dispatch.
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
      const now = Date.now(), key = "synthetic-key";
      const approval = {
        version: "photo_model_candidate_approval_v1",
        project: "naturebook",
        operation: "18_call_luna_evidence_limits_sol_photo_comparison",
        screeningPolicy: PHOTO_MODEL_REFERENCE_GAP_POLICY,
        planDigest: await fingerprintJson(packet.plan),
        sourceCommit: source.commit,
        sourceDigest: source.digest,
        credentialSha256: await fingerprintBytes(new TextEncoder().encode(key)),
        budgetUsd: 40,
        approvedAt: new Date(now).toISOString(),
        expiresAt: new Date(now + 3600000).toISOString(),
        recordRef: "synthetic-candidate-approval",
        reviewerRef: "synthetic-reviewer",
        delegationRef: "synthetic-delegation",
      };
      await validatePhotoModelApproval(approval, packet, key, now);
      for (
        const delta of [
          {
            version: "photo_model_approval_v1",
            operation: "18_call_luna_sol_photo_comparison",
          },
          {
            version: "photo_model_continuation_approval_v1",
            operation: "remaining_17_luna_sol_photo_comparison",
          },
          { screeningPolicy: undefined },
          { screeningPolicy: "ignore_failures" },
          { sourceDigest: "2".repeat(64) },
          { budgetUsd: 41 },
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
      await assertRejects(() =>
        validatePhotoModelApproval(approval, packet, key, now, {
          parentRunDigest: "2".repeat(64),
          parentArtifactsDigest: "3".repeat(64),
        })
      );
      packet.plan.version = "photo_model_plan_v2";
      const oldPlanDigest = await fingerprintJson(packet.plan);
      await assertRejects(() =>
        validatePhotoModelApproval(
          { ...approval, planDigest: oldPlanDigest },
          packet,
          key,
          now,
        )
      );
      assertEquals(s.calls.length, 0);
    } finally {
      await Deno.remove(s.root, { recursive: true });
    }
  });
}
