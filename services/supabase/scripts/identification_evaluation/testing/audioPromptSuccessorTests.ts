/** Synthetic first-attempt receipts only. No media, accounts or hosted access. */
import { assert, assertEquals, assertRejects } from "@std/assert";
import { join } from "node:path";
import { promptContinuationFixture } from "./audioPromptContinuationTests.ts";
import {
  admitPromptContinuationSlot,
  claimPromptContinuationSlot,
  closePromptContinuationBlock,
  preparePromptContinuation,
} from "../audioPromptContinuation.ts";
import {
  admitPromptSuccessorSlot,
  claimPromptSuccessorSlot,
  closePromptSuccessorBlock,
  inspectPromptSuccessor,
  preparePromptSuccessor,
  reportPromptSuccessor,
  writePromptSuccessorReport,
} from "../audioPromptSuccessor.ts";
import { promptSuccessorDirectory } from "../audioPromptSuccessorEvidence.ts";
import {
  promptObservationFile,
  withOriginalPromptLock,
} from "../audioPromptExecutionEvidence.ts";
import { claimJson, exists, readJson } from "../files.ts";
import { manageAudioPromptSuccessor } from "../../manage_audio_prompt_successor.ts";

const iso = (n: number) => new Date(n).toISOString();
export function registerAudioPromptSuccessorTests(scratch: string) {
  async function setup() {
    const s = await promptContinuationFixture(scratch);
    await preparePromptContinuation(s.root, s.review, s.runtime);
    const active = s.amendedControl(2);
    for (const slot of [18, 19]) {
      await claimPromptContinuationSlot(s.root, slot, active, s.runtime);
      await s.observe(slot);
      await admitPromptContinuationSlot(s.root, slot, s.runtime);
      s.state.now += 1000;
    }
    s.state.now = Date.parse(s.review.windows[0].expiresAt) + 1000;
    await closePromptContinuationBlock(
      s.root,
      2,
      s.amendedControl(2, true),
      s.state.now,
    );
    const reports = {
      original: join(s.root, "interruption-report.json"),
      continuation: s.root + ".continuation-report.json",
    };
    await claimJson(reports.original, {
      version: "synthetic_stopped_report_v1",
      completed: 17,
      decision: "inconclusive",
    });
    await claimJson(reports.continuation, {
      version: "synthetic_stopped_report_v1",
      completed: 19,
      decision: "inconclusive",
    });
    const tooling = {
      ...await s.runtime.source(),
      commit: "f".repeat(40),
      digest: "0".repeat(64),
    };
    const runtime = { ...s.runtime, source: () => Promise.resolve(tooling) };
    const inspected = await inspectPromptSuccessor(s.root, reports, runtime);
    const review = {
      version: "audio_prompt_successor_review_v1",
      reviewedAt: iso(s.state.now),
      sourceSha: tooling.commit,
      deployedSha: "1".repeat(40),
      predecessorEvidenceSha256: inspected.predecessor.evidenceSha256,
      firstSlot: 20,
      reports,
      windows: [2, 3].map((block, i) => ({
        block,
        startsAt: iso(s.state.now + i * 1_200_000),
        expiresAt: iso(s.state.now + 7_200_000 + i * 1_200_000),
      })),
      privatePreflight: await runtime.privatePreflight(),
      noUnrecordedAttempts: true,
      remainingNeverSubmitted: true,
      pauseBetweenCompletedSlots: true,
      analysisPolicy: "original_screening_rules_with_disclosed_interruptions",
    };
    const root = promptSuccessorDirectory(s.root);
    const control = (block: number, cleanup = false) => ({
      ...s.amendedControl(block, cleanup),
      sourceSha: tooling.commit,
      deployedSha: cleanup ? null : review.deployedSha,
      window: {
        startsAt: review.windows[block - 2].startsAt,
        expiresAt: review.windows[block - 2].expiresAt,
      },
    });
    const observe = async (slot: number, bad = false) => {
      const rows = s.observation(slot);
      if (bad) rows.at(-1)!.status = "interrupted";
      await Deno.writeFile(
        join(root, promptObservationFile(slot)),
        s.bytes(rows),
        { mode: 0o600, createNew: true },
      );
      s.state.now += 121_000;
    };
    const dispose = async () => {
      if (await exists(root)) await Deno.remove(root, { recursive: true });
      if (await exists(reports.continuation)) {
        await Deno.remove(reports.continuation);
      }
      await s.dispose();
    };
    return {
      ...s,
      successor: root,
      inspected,
      successorReview: review,
      successorRuntime: runtime,
      successorControl: control,
      successorObserve: observe,
      dispose,
    };
  }

  Deno.test("prompt successor preserves both predecessors and completes only original slots 20–36", async () => {
    const s = await setup();
    try {
      const manifest = await preparePromptSuccessor(
        s.root,
        s.successorReview,
        s.successorRuntime,
      );
      assertEquals(manifest.version, "audio_prompt_successor_manifest_v1");
      assertEquals(manifest.firstSlot, 20);
      assertEquals(JSON.stringify(s.inspected).includes(s.root), false);
      assertEquals(
        JSON.stringify(s.inspected).includes(
          s.successorReview.reports.continuation,
        ),
        false,
      );
      assertEquals(manifest.original.completedThrough, 17);
      assertEquals(manifest.predecessor.continuation.completedThrough, 19);
      assertEquals(manifest.furtherSuccessorsAllowed, false);
      await assertRejects(() =>
        preparePromptSuccessor(s.root, s.successorReview, s.successorRuntime)
      );
      await assertRejects(() =>
        preparePromptSuccessor(
          s.continuation,
          s.successorReview,
          s.successorRuntime,
        )
      );
      await assertRejects(() =>
        claimPromptContinuationSlot(s.root, 20, s.amendedControl(2), s.runtime)
      );
      let active = s.successorControl(2);
      for (const slot of [18, 19, 21, 25]) {
        await assertRejects(() =>
          claimPromptSuccessorSlot(s.root, slot, active, s.successorRuntime)
        );
      }
      for (let slot = 20; slot <= 36; slot++) {
        if (slot === 25) {
          await assertRejects(() =>
            claimPromptSuccessorSlot(
              s.root,
              slot,
              s.successorControl(3),
              s.successorRuntime,
            )
          );
          await closePromptSuccessorBlock(
            s.root,
            2,
            s.successorControl(2, true),
            s.state.now,
          );
          s.state.now = Math.max(
            s.state.now,
            Date.parse(s.successorReview.windows[1].startsAt),
          );
          active = s.successorControl(3);
        }
        const claim = await claimPromptSuccessorSlot(
          s.root,
          slot,
          active,
          s.successorRuntime,
        );
        assertEquals(
          claim.predecessorEvidenceSha256,
          manifest.predecessor.evidenceSha256,
        );
        await s.successorObserve(slot);
        await admitPromptSuccessorSlot(s.root, slot, s.successorRuntime);
        await assertRejects(() =>
          admitPromptSuccessorSlot(s.root, slot, s.successorRuntime)
        );
        s.state.now += 1000;
      }
      const beforeCleanup = await reportPromptSuccessor(
        s.root,
        s.successorRuntime,
      );
      assertEquals(beforeCleanup.all36FirstAttemptsAdmitted, false);
      await closePromptSuccessorBlock(
        s.root,
        3,
        s.successorControl(3, true),
        s.state.now,
      );
      const report = await reportPromptSuccessor(s.root, s.successorRuntime);
      assertEquals([
        report.originalCompleted,
        report.continuationCompleted,
        report.successorCompleted,
      ], [17, 2, 17]);
      assertEquals(report.remainingSlots, []);
      assertEquals(JSON.stringify(report).includes(s.root), false);
      assertEquals(
        JSON.stringify(report).includes(s.successorReview.reports.continuation),
        false,
      );
      assertEquals(report.all36FirstAttemptsAdmitted, true);
      // Synthetic fixtures intentionally have unknown cost/timing. Never turn
      // completion alone into a screening result.
      assertEquals(report.requiredMeasurementsKnown, false);
      assertEquals(report.screeningRulesMayBeEvaluated, false);
      assertEquals(report.decision, "inconclusive");
      assertEquals(report.productionPromotionAuthorized, false);
      assertEquals(
        (await inspectPromptSuccessor(
          s.root,
          s.successorReview.reports,
          s.successorRuntime,
        )).predecessor,
        s.inspected.predecessor,
      );
      for (const packet of [s.root, s.continuation, s.successor]) {
        await assertRejects(() =>
          writePromptSuccessorReport(
            s.root,
            join(packet, "report.json"),
            s.successorRuntime,
          )
        );
      }
      const destination = s.root + ".successor-report.json";
      await writePromptSuccessorReport(s.root, destination, s.successorRuntime);
      await assertRejects(() =>
        writePromptSuccessorReport(s.root, destination, s.successorRuntime)
      );
      await Deno.remove(destination);
    } finally {
      await s.dispose();
    }
  });

  Deno.test("prompt successor rejects changed approval, deployment, window, pricing and private witness", async () => {
    const s = await setup();
    try {
      const mutations: ((r: typeof s.successorReview) => void)[] = [
        (r) => {
          r.firstSlot = 21;
        },
        (r) => {
          r.version = "audio_prompt_continuation_review_v2";
        },
        (r) => {
          r.predecessorEvidenceSha256 = "a".repeat(64);
        },
        (r) => {
          r.sourceSha = "b".repeat(40);
        },
        (r) => {
          r.deployedSha = "invalid";
        },
        (r) => {
          r.remainingNeverSubmitted = false;
        },
        (r) => {
          r.noUnrecordedAttempts = false;
        },
        (r) => {
          r.pauseBetweenCompletedSlots = false;
        },
        (r) => {
          r.privatePreflight = {
            ...r.privatePreflight,
            sameReviewedOwner: false,
          };
        },
        (r) => {
          r.windows[0].expiresAt = iso(
            Date.parse(r.windows[0].startsAt) + 7_200_001,
          );
        },
        (r) => {
          r.windows[0].block = 3;
        },
        (r) => {
          r.windows[1].startsAt = "2026-10-10T00:00:00.000Z";
          r.windows[1].expiresAt = "2026-10-10T01:00:00.000Z";
        },
      ];
      for (const mutate of mutations) {
        const review = structuredClone(s.successorReview);
        mutate(review);
        await assertRejects(() =>
          preparePromptSuccessor(s.root, review, s.successorRuntime)
        );
        assertEquals(await exists(s.successor), false);
      }
      await assertRejects(() =>
        preparePromptSuccessor(s.root, {
          ...s.successorReview,
          ownerId: "synthetic-private",
        }, s.successorRuntime)
      );
      await preparePromptSuccessor(
        s.root,
        s.successorReview,
        s.successorRuntime,
      );
      const active = s.successorControl(2);
      for (
        const patch of [
          { deployedSha: s.review.deployedSha },
          { sourceSha: s.review.sourceSha },
          { backendBundleSha256: "f".repeat(64) },
          { window: s.amendedControl(2).window },
        ]
      ) {
        await assertRejects(() =>
          claimPromptSuccessorSlot(
            s.root,
            20,
            { ...active, ...patch },
            s.successorRuntime,
          )
        );
      }
      await assertRejects(() =>
        claimPromptSuccessorSlot(s.root, 20, active, {
          ...s.successorRuntime,
          privatePreflight: async () => ({
            ...await s.runtime.privatePreflight() as object,
            foreground: false,
          }),
        })
      );
      await assertRejects(() =>
        claimPromptSuccessorSlot(s.root, 20, active, {
          ...s.successorRuntime,
          source: async () => ({
            ...await s.successorRuntime.source(),
            dirty: true,
          }),
        })
      );
      s.state.now = Date.parse(s.successorReview.windows[0].expiresAt) -
        151_000;
      await assertRejects(() =>
        claimPromptSuccessorSlot(s.root, 20, active, s.successorRuntime)
      );
    } finally {
      await s.dispose();
    }
  });

  Deno.test("prompt successor rejects incomplete, uncertain, early-cleaned or altered parent records", async () => {
    for (
      const change of [
        "gap",
        "claim",
        "excluded",
        "future",
        "cleanup",
        "early",
        "report",
        "hardlink",
      ]
    ) {
      const s = await setup();
      let alias: string | undefined;
      try {
        if (change === "gap") {
          await Deno.remove(
            join(s.continuation, "slots/slot-18.completed.json"),
          );
        }
        if (change === "claim") {
          await claimJson(join(s.continuation, "slots/slot-20.claim.json"), {});
        }
        if (change === "excluded") {
          await claimJson(
            join(s.continuation, "slots/slot-19.excluded.json"),
            {},
          );
        }
        if (change === "future") {
          await claimJson(
            join(s.continuation, "observations/slot-20.jsonl"),
            {},
          );
        }
        const cleanupPath = join(
          s.continuation,
          "controls/block-2.cleanup.json",
        );
        if (change === "cleanup") await Deno.remove(cleanupPath);
        if (change === "early") {
          const cleanup = await readJson(cleanupPath) as Record<
            string,
            unknown
          >;
          cleanup.observedAt = iso(
            Date.parse(s.review.windows[0].expiresAt) - 1,
          );
          await Deno.writeTextFile(cleanupPath, JSON.stringify(cleanup));
        }
        if (change === "report") {
          await Deno.writeTextFile(
            s.successorReview.reports.continuation,
            '{"changed":true}\n',
          );
        }
        if (change === "hardlink") {
          alias = s.root + ".alias";
          await Deno.link(
            join(s.continuation, "slots/slot-18.completed.json"),
            alias,
          );
        }
        await assertRejects(() =>
          preparePromptSuccessor(s.root, s.successorReview, s.successorRuntime)
        );
        assertEquals(await exists(s.successor), false);
      } finally {
        if (alias) await Deno.remove(alias);
        await s.dispose();
      }
    }
  });

  Deno.test("prompt successor has one prepare and claim winner, with both parent locks read-only", async () => {
    const s = await setup();
    try {
      const locks = [join(s.root, ".lock"), join(s.continuation, ".lock")];
      const before = await Promise.all(locks.map((p) => Deno.stat(p)));
      await withOriginalPromptLock(
        s.root,
        () =>
          assertRejects(() =>
            inspectPromptSuccessor(
              s.root,
              s.successorReview.reports,
              s.successorRuntime,
            )
          ),
      );
      await withOriginalPromptLock(
        s.continuation,
        () =>
          assertRejects(() =>
            preparePromptSuccessor(
              s.root,
              s.successorReview,
              s.successorRuntime,
            )
          ),
      );
      const prepared = await Promise.allSettled(
        [1, 2].map(() =>
          preparePromptSuccessor(s.root, s.successorReview, s.successorRuntime)
        ),
      );
      assertEquals(prepared.filter((v) => v.status === "fulfilled").length, 1);
      const claims = await Promise.allSettled(
        [1, 2].map(() =>
          claimPromptSuccessorSlot(
            s.root,
            20,
            s.successorControl(2),
            s.successorRuntime,
          )
        ),
      );
      assertEquals(claims.filter((v) => v.status === "fulfilled").length, 1);
      for (let i = 0; i < locks.length; i++) {
        const after = await Deno.stat(locks[i]);
        assertEquals([after.ino, after.mtime, after.size], [
          before[i].ino,
          before[i].mtime,
          before[i].size,
        ]);
      }
      const pending = await reportPromptSuccessor(s.root, s.successorRuntime);
      assertEquals(pending.pendingOrExcludedSlot, 20);
      assertEquals(pending.screeningRulesMayBeEvaluated, false);
      await assertRejects(() =>
        claimPromptSuccessorSlot(
          s.root,
          21,
          s.successorControl(2),
          s.successorRuntime,
        )
      );
    } finally {
      await s.dispose();
    }
  });

  Deno.test("prompt successor never retries a rejected attempt and cleanup survives predecessor drift", async () => {
    for (const drift of [false, true]) {
      const s = await setup();
      try {
        await preparePromptSuccessor(
          s.root,
          s.successorReview,
          s.successorRuntime,
        );
        await claimPromptSuccessorSlot(
          s.root,
          20,
          s.successorControl(2),
          s.successorRuntime,
        );
        await s.successorObserve(20, !drift);
        if (drift) await Deno.writeTextFile(join(s.root, "run.json"), "{}\n");
        await assertRejects(() =>
          admitPromptSuccessorSlot(s.root, 20, s.successorRuntime)
        );
        assert(await exists(join(s.successor, "slots/slot-20.excluded.json")));
        await closePromptSuccessorBlock(s.root, 2, {
          ...s.successorControl(2, true),
          sourceSha: "9".repeat(40),
        }, s.state.now);
        await assertRejects(() =>
          admitPromptSuccessorSlot(s.root, 20, s.successorRuntime)
        );
        await assertRejects(() =>
          claimPromptSuccessorSlot(
            s.root,
            21,
            s.successorControl(2),
            s.successorRuntime,
          )
        );
        if (drift) {
          await assertRejects(() =>
            reportPromptSuccessor(s.root, s.successorRuntime)
          );
        } else {
          const report = await reportPromptSuccessor(
            s.root,
            s.successorRuntime,
          );
          assertEquals(report.allActivatedBlocksVerifiedAbsent, true);
          assertEquals(report.pendingOrExcludedSlot, 20);
          assertEquals(report.decision, "inconclusive");
        }
      } finally {
        await s.dispose();
      }
    }
  });

  Deno.test("prompt successor rejects renamed roots, symlink reports and invalid CLI operations", async () => {
    const s = await setup();
    try {
      const link = s.root + ".report-link.json";
      assert(
        (await new Deno.Command("ln", {
          args: ["-s", s.successorReview.reports.continuation, link],
          stdout: "null",
          stderr: "null",
        }).output()).success,
      );
      await assertRejects(() =>
        inspectPromptSuccessor(s.root, {
          ...s.successorReview.reports,
          continuation: link,
        }, s.successorRuntime)
      );
      await Deno.remove(link);
      await preparePromptSuccessor(
        s.root,
        s.successorReview,
        s.successorRuntime,
      );
      const moved = s.root + "-moved";
      await Deno.rename(s.root, moved);
      await assertRejects(() =>
        reportPromptSuccessor(s.root, s.successorRuntime)
      );
      await Deno.rename(moved, s.root);
      for (
        const args of [["reset", s.root], ["inspect", s.root], [
          "claim",
          s.root,
          "020",
          "a",
          "b",
        ]]
      ) {
        await assertRejects(() => manageAudioPromptSuccessor(args));
      }
    } finally {
      await s.dispose();
    }
  });
}
