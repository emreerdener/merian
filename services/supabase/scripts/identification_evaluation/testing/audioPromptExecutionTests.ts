/** Synthetic metadata only. These fixtures cannot authorize or submit a run. */
import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import { join } from "node:path";
import { IDENTIFICATION_BUNDLE_SHA256 } from "../../../functions/identify-multimodal/deploymentIdentity.ts";
import { PROMPT_COMPARISON_PROJECT } from "../../control_audio_prompt_comparison.ts";
import {
  admitPromptExecutionSlot,
  claimPromptExecutionSlot,
  closePromptExecutionBlock,
  parsePromptExecutionReview,
  promptExecutionManifest,
  verifyPromptExecutionAssets,
} from "../audioPromptExecution.ts";
import { fingerprintBytes, fingerprintJson } from "../evidence.ts";
import { claimJson, exists, readBytes } from "../files.ts";
import { audioPromptComparisonObservationFixture as fixture } from "./audioPromptComparisonFixture.ts";

const NOW = Date.parse("2026-09-24T18:00:00.000Z");
const iso = (time: number) => new Date(time).toISOString();
const source = {
  commit: "a".repeat(40),
  dirty: false,
  digest: "e".repeat(64),
  sdk: "npm:@google/genai@2.23.0",
};
function witness(now: number) {
  return {
    version: "audio_prompt_private_preflight_v1",
    checkedAt: iso(now),
    ownerMatchesReviewedConfiguration: true,
    sameReviewedOwner: true,
    consentCurrent: true,
    appMatchesReview: true,
    foreground: true,
  };
}
function review() {
  return {
    privatePreflight: witness(NOW - 1000),
    version: "audio_prompt_execution_review_v1",
    reviewedAt: iso(NOW - 1000),
    sourceSha: source.commit,
    deployedSha: "b".repeat(40),
    app: fixture().expected.app,
    backendBundleSha256: IDENTIFICATION_BUNDLE_SHA256,
    pricing: {
      version: "evaluation_pricing_v1",
      currency: "USD",
      service: "paid_standard_synchronous",
      retrievedAt: iso(NOW - 2000),
      sourceUrl: "https://ai.google.dev/gemini-api/docs/pricing",
      reviewRef: "synthetic-price",
      includesReasoning: true,
      models: ["gemini-2.5-flash", "gemini-2.5-pro"].map((model) => ({
        model,
        inputPerMillion: { text: 1, image: 1, audio: 1, cached: 1 },
        outputPerMillion: 1,
        maxInputTokens: 100000,
        maxBillableOutputTokens: 8192,
        limitsEvidenceRef: "synthetic-limits",
      })),
    },
    windows: [1, 2, 3].map((block) => ({
      block,
      startsAt: iso(NOW + (block - 1) * 1_200_000),
      expiresAt: iso(NOW + 7_200_000 + (block - 1) * 1_200_000),
    })),
  };
}

export async function promptExecutionFixture(scratch: string) {
  const root = await Deno.makeTempDir({
    dir: scratch,
    prefix: "prompt-ledger-",
  });
  await Deno.chmod(root, 0o700);
  for (const name of ["slots", "controls"]) {
    await Deno.mkdir(join(root, name), { mode: 0o700 });
  }
  const manifest = promptExecutionManifest(review(), source, NOW);
  await claimJson(join(root, "run.json"), manifest);
  await claimJson(join(root, "freeze.json"), {
    version: "audio_prompt_execution_freeze_v1",
    manifestSha256: await fingerprintJson(manifest),
    manifestFileSha256: await fingerprintBytes(
      await readBytes(join(root, "run.json"), 262_144),
    ),
  });
  const state = { now: NOW + 1000 };
  const runtime = {
    now: () => state.now,
    source: () => Promise.resolve(source),
    privatePreflight: () => Promise.resolve(witness(state.now)),
    verifyAssets: () => Promise.resolve(), // Ledger metadata fixtures contain no recorded media.
  };
  const control = (block: number, cleanup = false) => ({
    version: "audio_prompt_comparison_control_v1",
    operation: cleanup ? "deactivate" : "activate",
    target: PROMPT_COMPARISON_PROJECT,
    sourceSha: manifest.review.sourceSha,
    deployedSha: cleanup ? null : manifest.review.deployedSha,
    observedAt: iso(state.now),
    status: cleanup ? "disabled" : "active",
    mutationAttempted: true,
    cleanup: cleanup ? "verified_absent" : "not_needed",
    configurationPresent: !cleanup,
    block,
    window: {
      startsAt: manifest.review.windows[block - 1].startsAt,
      expiresAt: manifest.review.windows[block - 1].expiresAt,
    },
    planSha256: manifest.planSha256,
    backendBundleSha256: manifest.review.backendBundleSha256,
    automaticIdentificationRequests: 0,
    failure: null,
  });
  const observation = (slot: number) => {
    const f = fixture(slot);
    f.measurement.diagnostics.backendBundleSha256 =
      IDENTIFICATION_BUNDLE_SHA256;
    f.rows[0].pricing = manifest.review.pricing;
    f.rows[0].startedAt = iso(state.now);
    f.rows[1].readyAt = iso(state.now + 1000);
    for (const r of f.rows.slice(2, -1)) r.observedAt = iso(state.now + 3000);
    f.rows.at(-1)!.finishedAt = iso(state.now + 120_000);
    return f.rows;
  };
  const bytes = (rows: unknown[]) =>
    new TextEncoder().encode(
      rows.map((r) => JSON.stringify(r)).join("\n") + "\n",
    );
  return { root, manifest, state, runtime, control, observation, bytes };
}

export function registerAudioPromptExecutionTests(scratch: string) {
  const setup = () => promptExecutionFixture(scratch);

  Deno.test("prompt execution freeze rejects dirty builds, stale pricing, changed plans and private fields", () => {
    assertEquals(
      promptExecutionManifest(review(), source, NOW).plannedSubmissions,
      36,
    );
    const mutations = [
      (v: ReturnType<typeof review>) => {
        v.app.sourceState = "dirty";
      },
      (v: ReturnType<typeof review>) => {
        v.app.sourceRevision = "f".repeat(40);
      },
      (v: ReturnType<typeof review>) => {
        v.backendBundleSha256 = "f".repeat(64);
      },
      (v: ReturnType<typeof review>) => {
        v.pricing.retrievedAt = "2026-09-01T00:00:00.000Z";
      },
      (v: ReturnType<typeof review>) => {
        v.windows[1].block = 1;
      },
      (v: ReturnType<typeof review>) => {
        v.windows[2].expiresAt = "2026-10-25T00:00:00.000Z";
      },
      (v: ReturnType<typeof review>) => {
        v.windows[0].expiresAt = iso(NOW + 7_200_001);
      },
      (v: ReturnType<typeof review>) => {
        v.windows[0].startsAt = "2026-09-32T18:00:00.000Z";
      },
    ];
    for (const mutate of mutations) {
      const v = review();
      mutate(v);
      assertThrows(() => parsePromptExecutionReview(v));
    }
    assertThrows(() =>
      parsePromptExecutionReview({
        ...review(),
        ownerId: "synthetic-private-value",
      })
    );
    assertThrows(() =>
      promptExecutionManifest(review(), { ...source, dirty: true }, NOW)
    );
    assertThrows(() => promptExecutionManifest(review(), source, NOW - 2000));
    assertThrows(() =>
      promptExecutionManifest(review(), source, NOW + 7_200_000)
    );
  });

  Deno.test("prompt execution admits all 36 ordered attempts only across verified block cleanup", async () => {
    const s = await setup();
    try {
      for (let block = 1; block <= 3; block++) {
        const activation = s.control(block);
        if (block > 1) {
          await assertRejects(() =>
            claimPromptExecutionSlot(
              s.root,
              (block - 1) * 12 + 1,
              activation,
              s.runtime,
            )
          );
          await closePromptExecutionBlock(
            s.root,
            block - 1,
            s.control(block - 1, true),
            s.state.now,
          );
        }
        for (let slot = (block - 1) * 12 + 1; slot <= block * 12; slot++) {
          await claimPromptExecutionSlot(s.root, slot, activation, s.runtime);
          const rows = s.observation(slot);
          s.state.now += 121_000;
          const done = await admitPromptExecutionSlot(
            s.root,
            slot,
            s.bytes(rows),
            s.state.now,
          );
          assertEquals(done.admitted.assignment.slot, slot);
          assertEquals(
            done.admitted.nativeOutcome.subjectState,
            "unidentified_non_human",
          );
          assertEquals(done.admitted.primaryCost.reason, "usage_incomplete");
          assertEquals(done.admitted.formalQualificationEligible, false);
          await assertRejects(() =>
            admitPromptExecutionSlot(s.root, slot, s.bytes(rows), s.state.now)
          );
          s.state.now += 1000;
        }
      }
      await closePromptExecutionBlock(
        s.root,
        3,
        s.control(3, true),
        s.state.now,
      );
      assertEquals([...Deno.readDirSync(join(s.root, "slots"))].length, 72);
      assertEquals([...Deno.readDirSync(join(s.root, "controls"))].length, 6);
    } finally {
      await Deno.remove(s.root, { recursive: true });
    }
  });

  Deno.test("prompt execution unknown claim blocks retry, skipping, and changed source or activation", async () => {
    const s = await setup();
    try {
      const active = s.control(1);
      await assertRejects(() =>
        claimPromptExecutionSlot(s.root, 1, active, {
          ...s.runtime,
          source: () => Promise.resolve({ ...source, dirty: true }),
        })
      );
      await assertRejects(() =>
        claimPromptExecutionSlot(s.root, 1, { ...active, block: 2 }, s.runtime)
      );
      await assertRejects(() =>
        claimPromptExecutionSlot(s.root, 1, active, {
          ...s.runtime,
          privatePreflight: () => Promise.resolve(witness(NOW - 600_000)),
        })
      );
      await assertRejects(() =>
        claimPromptExecutionSlot(s.root, 1, active, {
          ...s.runtime,
          privatePreflight: () =>
            Promise.resolve({
              ...witness(s.state.now),
              sameReviewedOwner: false,
            }),
        })
      );
      const racing = await Promise.allSettled(
        [1, 2].map(() =>
          claimPromptExecutionSlot(s.root, 1, active, s.runtime)
        ),
      );
      assertEquals(racing.filter((r) => r.status === "fulfilled").length, 1);
      await assertRejects(() =>
        claimPromptExecutionSlot(s.root, 1, active, s.runtime)
      );
      await assertRejects(() =>
        claimPromptExecutionSlot(s.root, 2, active, s.runtime)
      );
      await assertRejects(() =>
        claimPromptExecutionSlot(s.root, 13, s.control(2), s.runtime)
      );
      // Cleanup remains recordable after an uncertain attempt, including an
      // already-absent controller result without the private configuration.
      const cleanup = {
        ...s.control(1, true),
        sourceSha: "f".repeat(40),
        block: null,
        window: null,
        planSha256: null,
        backendBundleSha256: null,
        mutationAttempted: false,
      };
      await closePromptExecutionBlock(s.root, 1, cleanup, s.state.now);
      await assertRejects(() =>
        claimPromptExecutionSlot(s.root, 1, active, s.runtime)
      );
      assert(await exists(join(s.root, "slots/slot-01.claim.json")));
    } finally {
      await Deno.remove(s.root, { recursive: true });
    }
  });

  Deno.test("prompt execution rejected observation is terminal and cannot be replaced by a later good window", async () => {
    const mutations = [
      (rows: Record<string, unknown>[]) => {
        rows[0].pricing = null;
      },
      (rows: Record<string, unknown>[]) => {
        rows.at(-1)!.status = "interrupted";
      },
      (rows: Record<string, unknown>[]) => {
        rows[0].startedAt = iso(NOW);
      },
      (rows: Record<string, unknown>[]) => {
        (rows[4].measurement as Record<string, unknown>).slot = 2;
      },
    ];
    for (const mutate of mutations) {
      const s = await setup();
      try {
        const active = s.control(1);
        await claimPromptExecutionSlot(s.root, 1, active, s.runtime);
        const earlyCleanup = s.control(1, true);
        const valid = s.observation(1), invalid = structuredClone(valid);
        mutate(invalid);
        s.state.now += 121_000;
        await assertRejects(() =>
          admitPromptExecutionSlot(s.root, 1, s.bytes(invalid), s.state.now)
        );
        assert(await exists(join(s.root, "slots/slot-01.excluded.json")));
        await assertRejects(() =>
          admitPromptExecutionSlot(s.root, 1, s.bytes(valid), s.state.now)
        );
        await assertRejects(() =>
          claimPromptExecutionSlot(s.root, 2, active, s.runtime)
        );
        await assertRejects(() =>
          closePromptExecutionBlock(s.root, 1, earlyCleanup, s.state.now)
        );
        await closePromptExecutionBlock(
          s.root,
          1,
          s.control(1, true),
          s.state.now,
        );
        assertEquals(
          await exists(join(s.root, "slots/slot-01.completed.json")),
          false,
        );
      } finally {
        await Deno.remove(s.root, { recursive: true });
      }
    }
  });

  Deno.test("prompt execution rechecks every asset and rejects additions, tampering and links", async () => {
    const root = await Deno.makeTempDir({
      dir: scratch,
      prefix: "prompt-assets-",
    });
    await Deno.mkdir(join(root, "assets"), { mode: 0o700 });
    try {
      const bytes = new Uint8Array([1, 2, 3]);
      const assignments = await Promise.all(
        [1, 2, 3, 4, 5, 6].map(async (id) => {
          const caseId = "c" + String(id).padStart(4, "0");
          await Deno.writeFile(join(root, "assets", caseId + ".wav"), bytes, {
            mode: 0o600,
          });
          return {
            caseId,
            sourceWavSha256: await fingerprintBytes(bytes),
            sourceByteLength: bytes.length,
          };
        }),
      );
      await verifyPromptExecutionAssets(root, assignments);
      const path = join(root, "assets/c0001.wav");
      await Deno.writeFile(path, new Uint8Array([1, 2, 4]));
      await assertRejects(() => verifyPromptExecutionAssets(root, assignments));
      await Deno.writeFile(path, bytes);
      await Deno.writeFile(join(root, "assets/extra.wav"), bytes);
      await assertRejects(() => verifyPromptExecutionAssets(root, assignments));
      await Deno.remove(join(root, "assets/extra.wav"));
      await Deno.remove(path);
      assert(
        (await new Deno.Command("ln", { args: ["-s", "c0002.wav", path] })
          .output()).success,
      );
      await assertRejects(() => verifyPromptExecutionAssets(root, assignments));
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });

  Deno.test("prompt execution rejects torn freezes, linked packets and claims too near expiry", async () => {
    const s = await setup();
    try {
      s.state.now = NOW + 7_200_000 - 151_000;
      await assertRejects(() =>
        claimPromptExecutionSlot(s.root, 1, s.control(1), s.runtime)
      );
      s.state.now = NOW + 1000;
      const original = await Deno.readTextFile(join(s.root, "run.json"));
      await Deno.writeTextFile(join(s.root, "run.json"), original.slice(0, -3));
      await assertRejects(() =>
        claimPromptExecutionSlot(s.root, 1, s.control(1), s.runtime)
      );
      await Deno.writeTextFile(join(s.root, "run.json"), original);
      await Deno.rename(join(s.root, "run.json"), join(s.root, "other.json"));
      assert(
        (await new Deno.Command("ln", {
          args: ["-s", "other.json", join(s.root, "run.json")],
        }).output()).success,
      );
      await assertRejects(() =>
        claimPromptExecutionSlot(s.root, 1, s.control(1), s.runtime)
      );
      assertEquals(
        await exists(join(s.root, "slots/slot-01.claim.json")),
        false,
      );
    } finally {
      await Deno.remove(s.root, { recursive: true });
    }
  });
}
