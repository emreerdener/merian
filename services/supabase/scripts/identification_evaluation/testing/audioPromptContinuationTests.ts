/** Synthetic receipts only. No recorded audio, account, or provider access. */
import { assert, assertEquals, assertRejects } from "@std/assert";
import { join } from "node:path";
import {
  admitPromptExecutionSlot,
  claimPromptExecutionSlot,
  closePromptExecutionBlock,
} from "../audioPromptExecution.ts";
import {
  admitPromptContinuationSlot,
  claimPromptContinuationSlot,
  closePromptContinuationBlock,
  inspectPromptContinuationOriginal,
  preparePromptContinuation,
  promptContinuationDirectory,
  reportPromptContinuation,
  writePromptContinuationReport,
} from "../audioPromptContinuation.ts";
import {
  auditOriginalPromptExecution,
  promptObservationFile,
  withOriginalPromptLock,
} from "../audioPromptExecutionEvidence.ts";
import { claimJson, exists } from "../files.ts";
import { promptExecutionFixture } from "./audioPromptExecutionTests.ts";

const iso = (n: number) => new Date(n).toISOString();
export async function promptContinuationFixture(scratch: string, prefix = 17) {
  const s = await promptExecutionFixture(scratch);
  await Deno.mkdir(join(s.root, "observations"), { mode: 0o700 });
  let active = s.control(1);
  for (let slot = 1; slot <= prefix; slot++) {
    if (slot === 13 || slot === 25) {
      await closePromptExecutionBlock(
        s.root,
        Math.ceil((slot - 1) / 12),
        s.control(Math.ceil((slot - 1) / 12), true),
        s.state.now,
      );
      active = s.control(Math.ceil(slot / 12));
    }
    await claimPromptExecutionSlot(s.root, slot, active, s.runtime);
    const bytes = s.bytes(s.observation(slot));
    await Deno.writeFile(join(s.root, promptObservationFile(slot)), bytes, {
      mode: 0o600,
    });
    s.state.now += 121_000;
    await admitPromptExecutionSlot(s.root, slot, bytes, s.state.now);
    s.state.now += 1000;
  }
  const lastBlock = Math.ceil(prefix / 12);
  s.state.now = Date.parse(s.manifest.review.windows[lastBlock - 1].expiresAt) +
    1000;
  await closePromptExecutionBlock(
    s.root,
    lastBlock,
    s.control(lastBlock, true),
    s.state.now,
  );
  s.state.now = Date.parse(s.manifest.review.windows[lastBlock - 1].expiresAt) +
    1000;
  const tooling = {
    ...await s.runtime.source(),
    commit: "c".repeat(40),
    digest: "d".repeat(64),
  };
  const runtime = {
    ...s.runtime,
    source: () => Promise.resolve(tooling),
    bundle: () => Promise.resolve(s.manifest.review.backendBundleSha256),
    verifyTables: () => Promise.resolve(),
  };
  const original =
    (await inspectPromptContinuationOriginal(s.root, runtime)).original;
  const review = {
    version: "audio_prompt_continuation_review_v2",
    reviewedAt: iso(s.state.now),
    sourceSha: tooling.commit,
    deployedSha: "e".repeat(40),
    originalEvidenceSha256: original.evidenceSha256,
    firstSlot: prefix + 1,
    windows: Array.from(
      { length: 4 - lastBlock },
      (_, i) => ({
        block: lastBlock + i,
        startsAt: iso(s.state.now + i * 1_200_000),
        expiresAt: iso(s.state.now + 7_200_000 + i * 1_200_000),
      }),
    ),
    privatePreflight: await runtime.privatePreflight(),
    noUnrecordedAttempts: true,
    remainingNeverSubmitted: true,
    pauseBetweenCompletedSlots: true,
    analysisPolicy: "original_screening_rules_with_disclosed_interruption",
  };
  const continuation = promptContinuationDirectory(s.root);
  const control = (block: number, cleanup = false) => ({
    ...s.control(block, cleanup),
    sourceSha: tooling.commit,
    deployedSha: cleanup ? null : review.deployedSha,
    window: {
      startsAt: review.windows.find((w) => w.block === block)!.startsAt,
      expiresAt: review.windows.find((w) => w.block === block)!.expiresAt,
    },
  });
  const observe = async (
    slot: number,
    mutate?: (rows: Record<string, unknown>[]) => void,
  ) => {
    const rows = s.observation(slot);
    mutate?.(rows);
    await Deno.writeFile(
      join(continuation, promptObservationFile(slot)),
      s.bytes(rows),
      { mode: 0o600, createNew: true },
    );
    s.state.now += 121_000;
  };
  const dispose = async () => {
    await Deno.remove(s.root, { recursive: true });
    if (await exists(continuation)) {
      await Deno.remove(continuation, { recursive: true });
    }
  };
  return {
    ...s,
    original,
    review,
    continuation,
    runtime,
    amendedControl: control,
    observe,
    dispose,
  };
}

export function registerAudioPromptContinuationTests(scratch: string) {
  const setup = (prefix = 17) => promptContinuationFixture(scratch, prefix);

  Deno.test("prompt continuation completes only untouched 18–36 and preserves the closed original", async () => {
    const s = await setup();
    try {
      const before = await auditOriginalPromptExecution(
        s.root,
        s.state.now,
        s.runtime,
      );
      await preparePromptContinuation(s.root, s.review, s.runtime);
      await assertRejects(() =>
        preparePromptContinuation(s.root, s.review, s.runtime)
      );
      let active = s.amendedControl(2);
      for (let slot = 18; slot <= 36; slot++) {
        if (slot === 25) {
          await assertRejects(() =>
            claimPromptContinuationSlot(
              s.root,
              slot,
              s.amendedControl(3),
              s.runtime,
            )
          );
          await closePromptContinuationBlock(
            s.root,
            2,
            s.amendedControl(2, true),
            s.state.now,
          );
          s.state.now = Math.max(
            s.state.now,
            Date.parse(s.review.windows[1].startsAt),
          );
          active = s.amendedControl(3);
        }
        const claim = await claimPromptContinuationSlot(
          s.root,
          slot,
          active,
          s.runtime,
        );
        assertEquals(claim.expected.app, s.manifest.review.app);
        assertEquals(claim.originalEvidenceSha256, s.original.evidenceSha256);
        await s.observe(slot);
        const done = await admitPromptContinuationSlot(s.root, slot, s.runtime);
        assertEquals(done.admitted.assignment.slot, slot);
        await assertRejects(() =>
          admitPromptContinuationSlot(s.root, slot, s.runtime)
        );
        s.state.now += 1000;
      }
      await closePromptContinuationBlock(
        s.root,
        3,
        s.amendedControl(3, true),
        s.state.now,
      );
      const report = await reportPromptContinuation(s.root, s.runtime);
      assertEquals(report.originalCompleted, 17);
      assertEquals(report.continuationCompleted, 19);
      assertEquals(report.remainingSlots, []);
      assertEquals(report.execution, "amended_after_disclosed_interruption");
      assertEquals(report.allActivatedBlocksVerifiedAbsent, true);
      assertEquals(report.all36FirstAttemptsAdmitted, true);
      assertEquals(report.requiredMeasurementsKnown, false);
      assertEquals(report.screeningRulesMayBeEvaluated, false);
      assertEquals(report.decision, "inconclusive");
      assertEquals(report.productionPromotionAuthorized, false);
      assertEquals(report.original.deployedSha, s.original.deployedSha);
      assert(s.review.deployedSha !== report.original.deployedSha);
      assertEquals(
        report.continuationControls.map((c) => c.activation.deployedSha),
        [s.review.deployedSha, s.review.deployedSha],
      );
      assertEquals(
        (await auditOriginalPromptExecution(s.root, s.state.now, s.runtime))
          .files,
        before.files,
      );
      assertEquals([...Deno.readDirSync(join(s.root, "slots"))].length, 34);
      assertEquals(
        [...Deno.readDirSync(join(s.continuation, "slots"))].length,
        38,
      );
    } finally {
      await s.dispose();
    }
  });

  Deno.test("prompt continuation rejects changed review, runtime, owner witness, windows and original evidence", async () => {
    const mutations:
      ((v: Awaited<ReturnType<typeof setup>>["review"]) => void)[] = [
        (v) => {
          v.firstSlot = 19;
        },
        (v) => {
          v.originalEvidenceSha256 = "f".repeat(64);
        },
        (v) => {
          v.sourceSha = "a".repeat(40);
        },
        (v) => {
          v.deployedSha = "invalid";
        },
        (v) => {
          v.version = "audio_prompt_continuation_review_v3";
        },
        (v) => {
          v.remainingNeverSubmitted = false;
        },
        (v) => {
          v.noUnrecordedAttempts = false;
        },
        (v) => {
          v.pauseBetweenCompletedSlots = false;
        },
        (v) => {
          v.windows[0].expiresAt = iso(
            Date.parse(v.windows[0].startsAt) + 7_200_001,
          );
        },
        (v) => {
          v.windows[0].block = 3;
        },
        (v) => {
          v.windows[1].expiresAt = "2026-10-25T00:00:00.000Z";
        },
        (v) => {
          v.windows[1].expiresAt = "2026-10-02T00:00:00.000Z";
          v.windows[1].startsAt = "2026-10-01T23:00:00.000Z";
        },
        (v) => {
          v.privatePreflight = {
            ...v.privatePreflight,
            sameReviewedOwner: false,
          };
        },
      ];
    const s = await setup();
    try {
      for (const mutate of mutations) {
        const review = structuredClone(s.review);
        mutate(review);
        await assertRejects(() =>
          preparePromptContinuation(s.root, review, s.runtime)
        );
        assertEquals(await exists(s.continuation), false);
      }
      await assertRejects(() =>
        preparePromptContinuation(s.root, {
          ...s.review,
          ownerId: "synthetic-private",
        }, s.runtime)
      );
      await assertRejects(() =>
        preparePromptContinuation(s.root, s.review, {
          ...s.runtime,
          bundle: () => Promise.resolve("f".repeat(64)),
        })
      );
      await preparePromptContinuation(s.root, s.review, s.runtime);
      const active = s.amendedControl(2);
      await assertRejects(() =>
        claimPromptContinuationSlot(s.root, 17, active, s.runtime)
      );
      await assertRejects(() =>
        claimPromptContinuationSlot(s.root, 19, active, s.runtime)
      );
      await assertRejects(() =>
        claimPromptContinuationSlot(s.root, 25, s.amendedControl(3), s.runtime)
      );
      await assertRejects(() =>
        claimPromptContinuationSlot(s.root, 18, {
          ...active,
          sourceSha: s.manifest.review.sourceSha,
        }, s.runtime)
      );
      await assertRejects(() =>
        claimPromptContinuationSlot(s.root, 18, {
          ...active,
          deployedSha: "f".repeat(40),
        }, s.runtime)
      );
      await assertRejects(() =>
        claimPromptContinuationSlot(s.root, 18, {
          ...active,
          deployedSha: s.original.deployedSha,
        }, s.runtime)
      );
      await assertRejects(() =>
        claimPromptContinuationSlot(s.root, 18, {
          ...active,
          backendBundleSha256: "f".repeat(64),
        }, s.runtime)
      );
      await assertRejects(() =>
        claimPromptContinuationSlot(s.root, 18, {
          ...active,
          window: s.control(2).window,
        }, s.runtime)
      );
      await assertRejects(() =>
        claimPromptContinuationSlot(s.root, 18, active, {
          ...s.runtime,
          source: async () => ({ ...await s.runtime.source(), dirty: true }),
        })
      );
      await assertRejects(() =>
        claimPromptContinuationSlot(s.root, 18, active, {
          ...s.runtime,
          privatePreflight: async () => ({
            ...await s.runtime.privatePreflight() as object,
            foreground: false,
          }),
        })
      );
      const path = join(s.root, "observations/slot-01.jsonl"),
        bytes = await Deno.readFile(path);
      await Deno.writeTextFile(path, new TextDecoder().decode(bytes) + "\n");
      await assertRejects(() =>
        claimPromptContinuationSlot(s.root, 18, active, s.runtime)
      );
      await Deno.writeFile(path, bytes);
      await Deno.writeTextFile(
        join(s.root, "observations/slot-18.jsonl"),
        "{}\n",
        { mode: 0o600 },
      );
      await assertRejects(() =>
        claimPromptContinuationSlot(s.root, 18, active, s.runtime)
      );
      await Deno.remove(join(s.root, "observations/slot-18.jsonl"));
      s.state.now = Date.parse(s.review.windows[0].expiresAt) - 151_000;
      await assertRejects(() =>
        claimPromptContinuationSlot(s.root, 18, active, s.runtime)
      );
      assertEquals(
        [...Deno.readDirSync(join(s.continuation, "slots"))].length,
        0,
      );
    } finally {
      await s.dispose();
    }
  });

  Deno.test("prompt continuation refuses gaps, uncertain prior claims and missing cleanup before preparing", async () => {
    for (const change of ["gap", "claim", "excluded", "cleanup", "operator"]) {
      const s = await setup();
      try {
        if (change === "gap") {
          await Deno.remove(join(s.root, "slots/slot-16.completed.json"));
        }
        if (change === "claim") {
          await claimJson(join(s.root, "slots/slot-18.claim.json"), {});
        }
        if (change === "excluded") {
          await claimJson(join(s.root, "slots/slot-17.excluded.json"), {});
        }
        if (change === "cleanup") {
          await Deno.remove(join(s.root, "controls/block-2.cleanup.json"));
        }
        if (change === "operator") {
          await Deno.mkdir(join(s.root, "operator"), { mode: 0o700 });
          await claimJson(join(s.root, "operator/slot-18.json"), {});
        }
        await assertRejects(() =>
          preparePromptContinuation(s.root, s.review, s.runtime)
        );
        assertEquals(await exists(s.continuation), false);
      } finally {
        await s.dispose();
      }
    }
  });

  Deno.test("prompt continuation has one claim winner and never retries an uncertain or rejected attempt", async () => {
    for (const failedObservation of [false, true]) {
      const s = await setup();
      try {
        await preparePromptContinuation(s.root, s.review, s.runtime);
        const active = s.amendedControl(2);
        const attempts = await Promise.allSettled(
          [1, 2].map(() =>
            claimPromptContinuationSlot(s.root, 18, active, s.runtime)
          ),
        );
        assertEquals(
          attempts.filter((a) => a.status === "fulfilled").length,
          1,
        );
        if (failedObservation) {
          await s.observe(18, (rows) => {
            rows.at(-1)!.status = "interrupted";
          });
          await assertRejects(() =>
            admitPromptContinuationSlot(s.root, 18, s.runtime)
          );
          assert(
            await exists(join(s.continuation, "slots/slot-18.excluded.json")),
          );
          await assertRejects(() =>
            admitPromptContinuationSlot(s.root, 18, s.runtime)
          );
        }
        await assertRejects(() =>
          claimPromptContinuationSlot(s.root, 18, active, s.runtime)
        );
        await assertRejects(() =>
          claimPromptContinuationSlot(s.root, 19, active, s.runtime)
        );
        await assertRejects(() =>
          closePromptContinuationBlock(s.root, 2, {
            ...s.amendedControl(2, true),
            observedAt: iso(Date.parse(active.observedAt) - 1),
          }, s.state.now)
        );
        await closePromptContinuationBlock(
          s.root,
          2,
          s.amendedControl(2, true),
          s.state.now,
        );
        assertEquals(
          (await reportPromptContinuation(s.root, s.runtime)).decision,
          "inconclusive",
        );
        await assertRejects(() =>
          claimPromptContinuationSlot(s.root, 18, active, s.runtime)
        );
        await assertRejects(() =>
          preparePromptContinuation(s.root, s.review, s.runtime)
        );
      } finally {
        await s.dispose();
      }
    }
  });

  Deno.test("prompt continuation cleanup remains available if original evidence changes after a claim", async () => {
    const s = await setup();
    try {
      await preparePromptContinuation(s.root, s.review, s.runtime);
      await claimPromptContinuationSlot(
        s.root,
        18,
        s.amendedControl(2),
        s.runtime,
      );
      await Deno.writeTextFile(join(s.root, "run.json"), "{}\n");
      await closePromptContinuationBlock(s.root, 2, {
        ...s.amendedControl(2, true),
        sourceSha: "f".repeat(40),
      }, s.state.now);
      await assertRejects(() => reportPromptContinuation(s.root, s.runtime));
      assert(
        await exists(join(s.continuation, "controls/block-2.cleanup.json")),
      );
    } finally {
      await s.dispose();
    }
  });

  Deno.test("prompt continuation keeps v1 deployment semantics and requires a v2 deployment binding", async () => {
    const s = await setup();
    try {
      const legacyReview: Record<string, unknown> = { ...s.review };
      delete legacyReview.deployedSha;
      await assertRejects(() =>
        preparePromptContinuation(s.root, legacyReview, s.runtime)
      );
      assertEquals(await exists(s.continuation), false);
      legacyReview.version = "audio_prompt_continuation_review_v1";
      await assertRejects(() =>
        preparePromptContinuation(s.root, {
          ...legacyReview,
          deployedSha: s.review.deployedSha,
        }, s.runtime)
      );
      await preparePromptContinuation(s.root, legacyReview, s.runtime);
      const frozen = JSON.parse(
        await Deno.readTextFile(join(s.continuation, "run.json")),
      );
      assertEquals(frozen.review, legacyReview);
      assertEquals(frozen.original.deployedSha, s.original.deployedSha);
      await assertRejects(() =>
        claimPromptContinuationSlot(
          s.root,
          18,
          s.amendedControl(2),
          s.runtime,
        )
      );
      await claimPromptContinuationSlot(s.root, 18, {
        ...s.amendedControl(2),
        deployedSha: s.original.deployedSha,
      }, s.runtime);
      await s.observe(18);
      await admitPromptContinuationSlot(s.root, 18, s.runtime);
      await closePromptContinuationBlock(
        s.root,
        2,
        s.amendedControl(2, true),
        s.state.now,
      );
      const report = await reportPromptContinuation(s.root, s.runtime);
      assertEquals(report.continuationCompleted, 1);
      assertEquals(
        report.continuationControls[0].activation.deployedSha,
        s.original.deployedSha,
      );
    } finally {
      await s.dispose();
    }
  });

  Deno.test("prompt continuation takes the original lock without altering or recreating it", async () => {
    const s = await setup();
    try {
      const before = await Deno.stat(join(s.root, ".lock"));
      await withOriginalPromptLock(s.root, async () => {
        await assertRejects(() =>
          inspectPromptContinuationOriginal(s.root, s.runtime)
        );
      });
      const after = await Deno.stat(join(s.root, ".lock"));
      assertEquals(after.ino, before.ino);
      assertEquals(after.mtime, before.mtime);
      await Deno.remove(join(s.root, ".lock"));
      await assertRejects(() =>
        preparePromptContinuation(s.root, s.review, s.runtime)
      );
      assertEquals(await exists(join(s.root, ".lock")), false);
    } finally {
      await s.dispose();
    }
  });

  Deno.test("prompt continuation rejects voluntary early closure and report destination or tooling drift", async () => {
    const s = await setup();
    try {
      const cleanupPath = join(s.root, "controls/block-2.cleanup.json");
      const originalCleanup = await Deno.readTextFile(cleanupPath);
      const early = JSON.parse(originalCleanup);
      early.observedAt = iso(Date.parse(s.original.lastCompletedAt) + 1);
      await Deno.writeTextFile(cleanupPath, JSON.stringify(early));
      await assertRejects(() =>
        inspectPromptContinuationOriginal(s.root, s.runtime)
      );
      await assertRejects(() =>
        preparePromptContinuation(s.root, s.review, s.runtime)
      );
      await Deno.writeTextFile(cleanupPath, originalCleanup);
      await preparePromptContinuation(s.root, s.review, s.runtime);
      const before = [...Deno.readDirSync(s.root)].map((e) => e.name).sort();
      for (
        const output of [
          join(s.root, "new-report.json"),
          join(s.root, "observations/new-report.json"),
          join(s.continuation, "new-report.json"),
        ]
      ) {
        await assertRejects(() =>
          writePromptContinuationReport(s.root, output, s.runtime)
        );
        assertEquals(await exists(output), false);
      }
      assertEquals(
        [...Deno.readDirSync(s.root)].map((e) => e.name).sort(),
        before,
      );
      await assertRejects(() =>
        reportPromptContinuation(s.root, {
          ...s.runtime,
          source: async () => ({ ...await s.runtime.source(), dirty: true }),
        })
      );
      await assertRejects(() =>
        reportPromptContinuation(s.root, {
          ...s.runtime,
          bundle: () => Promise.resolve("f".repeat(64)),
        })
      );
      const output = s.root + ".diagnostic.json";
      await writePromptContinuationReport(s.root, output, s.runtime);
      await assertRejects(() =>
        writePromptContinuationReport(s.root, output, s.runtime)
      );
      await Deno.remove(output);
    } finally {
      await s.dispose();
    }
  });
}
