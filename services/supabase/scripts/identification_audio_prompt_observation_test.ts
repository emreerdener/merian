import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import {
  AUDIO_PROMPT_COMPARISON_MARKER,
  parseAudioPromptComparisonEvent,
} from "./identification_evaluation/audioPromptComparisonObservation.ts";
import { admitAudioPromptComparisonWindow } from "./identification_evaluation/audioPromptComparisonWindow.ts";
import { admitAudioComparisonWindow } from "./identification_evaluation/audioComparisonWindow.ts";
import {
  isProofLogRow,
  projectAppLog,
} from "./identification_evaluation/appObservation.ts";
import { fingerprintBytes } from "./identification_evaluation/evidence.ts";
import { audioPromptComparisonObservationFixture as fixture } from "./identification_evaluation/testing/audioPromptComparisonFixture.ts";
import { audioComparisonObservationFixture as oldFixture } from "./identification_evaluation/testing/audioComparisonFixture.ts";

Deno.test("prompt window preserves conditional confidence and provisional species agreement without names", async () => {
  for (
    const state of [
      "identified_non_human",
      "unidentified_non_human",
      "human",
      "non_biological",
    ]
  ) {
    const f = fixture();
    f.outcome.subjectState = state;
    f.outcome.isBiological = state !== "non_biological";
    if (state === "identified_non_human") {
      f.outcome.scientificNameSha256 = await fingerprintBytes(
        new TextEncoder().encode("ochotona princeps"),
      );
    }
    const result = await admitAudioPromptComparisonWindow(f.rows, f.expected);
    assertEquals(result.assignment.arm, "B");
    assertEquals(result.nativeOutcome.subjectState, state);
    assertEquals(result.nativeOutcome.confidenceScore, 0.95);
    assertEquals(
      result.provisionalSpeciesAgreement,
      state === "identified_non_human" ? "agreement" : "not_applicable",
    );
    assertEquals(result.formalQualificationEligible, false);
    assertEquals(result.accuracyScored, false);
    assertEquals(JSON.stringify(result).includes("Ochotona"), false);
    if (state === "identified_non_human") {
      f.outcome.scientificNameSha256 = "e".repeat(64);
      assertEquals(
        (await admitAudioPromptComparisonWindow(f.rows, f.expected))
          .provisionalSpeciesAgreement,
        "mismatch",
      );
    }
  }
  // Neither a named control result nor an unresolved animal is species agreement.
  const control = fixture(5);
  control.outcome.subjectState = "identified_non_human";
  control.outcome.scientificNameSha256 = "e".repeat(64);
  assertEquals(
    (await admitAudioPromptComparisonWindow(control.rows, control.expected))
      .provisionalSpeciesAgreement,
    "not_applicable",
  );
});

Deno.test("prompt evidence excludes every missing or duplicated lifecycle boundary", async () => {
  for (let index = 1; index < fixture().rows.length; index++) {
    for (const duplicate of [true, false]) {
      const f = fixture();
      f.rows.splice(
        index,
        duplicate ? 0 : 1,
        ...(duplicate ? [structuredClone(f.rows[index])] : []),
      );
      f.rows.at(-1)!.events = f.rows.length - 3;
      await assertRejects(() =>
        admitAudioPromptComparisonWindow(f.rows, f.expected)
      );
    }
  }
});

Deno.test("prompt observation rejects stale identity, interrupted window and inconsistent subject proofs", async () => {
  const mutations: ((f: ReturnType<typeof fixture>) => void)[] = [
    (f) => {
      f.expected.slot = 1;
    },
    (f) => {
      f.expected.app = { ...f.expected.app, sourceFingerprint: "e".repeat(64) };
    },
    (f) => {
      f.expected.backendBundleSha256 = "e".repeat(64);
    },
    (f) => {
      f.measurement.delivery = "replay";
    },
    (f) => {
      f.measurement.diagnostics.returnedModel = "gemini-2.5-flash";
    },
    (f) => {
      f.rows[0].maxSeconds = 119;
    },
    (f) => {
      f.rows.at(-1)!.finishedAt = "2026-09-23T00:00:30.000Z";
    },
    (f) => {
      f.rows.at(-1)!.stopReason = "watchdog";
    },
    (f) => {
      f.rows.at(-1)!.rejectedProofRows = 1;
    },
    (f) => {
      f.rows.at(-1)!.oversizedRows = 1;
    },
    (f) => {
      f.rows.at(-1)!.collectorExitCode = 1;
    },
    (f) => {
      f.outcome.planSha256 = "e".repeat(64);
    },
    (f) => {
      f.outcome.measurementSha256 = "e".repeat(64);
    },
    (f) => {
      f.outcome.confidenceScore = 1.01;
    },
    (f) => {
      f.outcome.confidenceScore = Number.NaN;
    },
    (f) => {
      f.outcome.isBiological = false;
    },
    (f) => {
      f.outcome.subjectState = ["human"];
    },
    (f) => {
      f.outcome.persistence = ["saved"];
    },
    (f) => {
      f.outcome.scientificNameSha256 = "e".repeat(64);
    },
    (f) => {
      f.outcome.subjectState = "identified_non_human";
    },
    (f) => {
      f.outcome.rawName = "Synthetic private label";
    },
    (f) => {
      f.rows.splice(5, 0, structuredClone(oldFixture().rows[4]));
      f.rows.at(-1)!.events = f.rows.length - 3;
    },
  ];
  for (const mutate of mutations) {
    const f = fixture();
    mutate(f);
    await assertRejects(() =>
      admitAudioPromptComparisonWindow(f.rows, f.expected)
    );
  }
  const old = oldFixture();
  await assertRejects(() =>
    admitAudioPromptComparisonWindow(old.rows, old.expected)
  );
  const prompt = fixture();
  assertThrows(() => admitAudioComparisonWindow(prompt.rows, prompt.expected));
});

Deno.test("prompt observer projects only bounded proof and counts malformed proof rows", () => {
  const f = fixture();
  const line = (event: unknown) =>
    JSON.stringify({
      subsystem: "com.merian.app",
      eventMessage: AUDIO_PROMPT_COMPARISON_MARKER + JSON.stringify(event),
      privateText: "synthetic-private",
    });
  assertEquals(
    projectAppLog(line(f.outcome)),
    parseAudioPromptComparisonEvent(f.outcome),
  );
  for (
    const event of [{ ...f.outcome, rawText: "synthetic-private" }, {
      ...f.outcome,
      subjectState: "unknown",
    }]
  ) {
    assertEquals(isProofLogRow(line(event)), true);
    assertEquals(projectAppLog(line(event)), null);
  }
});
