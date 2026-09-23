import { assertEquals, assertThrows } from "@std/assert";
import {
  AUDIO_COMPARISON_MARKER,
} from "./identification_evaluation/audioComparisonObservation.ts";
import { admitAudioComparisonWindow } from "./identification_evaluation/audioComparisonWindow.ts";
import {
  APP_MEASUREMENT_MARKER,
  measurementLogSha256,
  projectAppLog,
} from "./identification_evaluation/appObservation.ts";
import { collectAppLogs } from "./identification_evaluation/appObserver.ts";
import { fingerprintBytes } from "../functions/identify-multimodal/comparison/fingerprint.ts";
import { audioComparisonObservationFixture as fixture } from "./identification_evaluation/testing/audioComparisonFixture.ts";

function line(message: string) {
  return JSON.stringify({
    subsystem: "com.merian.app",
    eventMessage: message,
    unusedPrivateText: "synthetic-private",
  });
}

Deno.test("comparison admission requires fresh metadata, native finalization, exact draw and complete window", () => {
  const f = fixture();
  const result = admitAudioComparisonWindow(f.rows, f.expected);
  assertEquals(result.assignment.caseId, "c0013");
  assertEquals(result.nativeOutcome.persistence, "saved");
  assertEquals(result.tapToFirstRenderedFrameSeconds, 2);
  assertEquals(result.accuracyScored, false);
  assertEquals(result.primaryCost.estimatedPrimaryUpperUsd, null);
  // Queue deletion can finish before or after draw; both proofs are required.
  [f.rows[5], f.rows[7]] = [f.rows[7], f.rows[5]];
  [f.rows[6], f.rows[7]] = [f.rows[7], f.rows[6]];
  assertEquals(
    admitAudioComparisonWindow(f.rows, f.expected).nativeOutcome.persistence,
    "saved",
  );
});

Deno.test("every missing or duplicated comparison boundary is excluded", () => {
  for (let index = 1; index < fixture().rows.length; index++) {
    for (const duplicate of [true, false]) {
      const f = fixture();
      f.rows.splice(
        index,
        duplicate ? 0 : 1,
        ...(duplicate ? [structuredClone(f.rows[index])] : []),
      );
      // Even a forged matching event count cannot rescue missing/duplicate proof.
      f.rows.at(-1)!.events = f.rows.length - 3;
      assertThrows(() => admitAudioComparisonWindow(f.rows, f.expected));
    }
  }
});

Deno.test("retries, old records, replay, wrong identities, slots, joins and malformed outcomes fail closed", () => {
  const mutations: ((f: ReturnType<typeof fixture>) => void)[] = [
    (f) => {
      f.rows[0].version = "identification_app_observation_v1";
    },
    (f) => {
      f.measurement.version = "identification_app_measurement_v1";
    },
    (f) => {
      f.measurement.contextProfile = "unattested";
    },
    (f) => {
      f.measurement.delivery = "replay";
    },
    (f) => {
      f.measurement.diagnostics.returnedModel = "gemini-2.5-flash";
    },
    (f) => {
      f.expected.app = { ...f.expected.app, sourceFingerprint: "e".repeat(64) };
    },
    (f) => {
      f.expected.backendBundleSha256 = "e".repeat(64);
    },
    (f) => {
      f.expected.slot = 2;
    },
    (f) => {
      (f.rows[4].measurement as Record<string, unknown>).measurementSha256 = "e"
        .repeat(64);
    },
    (f) => {
      (f.rows[5].measurement as Record<string, unknown>).slot = 2;
    },
    (f) => {
      (f.rows[7].measurement as Record<string, unknown>).rawContent =
        "synthetic-private";
    },
    (f) => {
      (f.rows[7].measurement as Record<string, unknown>).confidenceScore = 1.01;
    },
    (f) => {
      (f.rows[7].measurement as Record<string, unknown>).isBiological = "true";
    },
    (f) => {
      (f.rows[7].measurement as Record<string, unknown>).persistence = [
        "saved",
      ];
    },
    (f) => {
      (f.rows[4].measurement as Record<string, unknown>).event = ["receipt"];
    },
    (f) => {
      f.rows.at(-1)!.status = "observer_stopped_or_unavailable";
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
      f.rows.at(-1)!.finishedAt = "2026-09-23T00:00:30.000Z";
    },
    (f) => {
      f.rows[3].observedAt = "2026-09-23T00:00:00.000Z";
    },
    (f) => {
      f.rows[3].measurementSha256 = null;
    },
  ];
  for (const mutate of mutations) {
    const f = fixture();
    mutate(f);
    assertThrows(() => admitAudioComparisonWindow(f.rows, f.expected));
  }
});

Deno.test("observer hashes exact native JSON spelling and records rejected proof rows without content", async () => {
  const f = fixture();
  const raw = JSON.stringify(f.measurement).replace(
    '"otherEdgeMs":10',
    '"otherEdgeMs":10.0',
  );
  const hash = await fingerprintBytes(new TextEncoder().encode(raw));
  assertEquals(
    await measurementLogSha256(line(APP_MEASUREMENT_MARKER + raw)),
    hash,
  );
  const records: unknown[] = [], hashes: (string | null)[] = [];
  const input = [
    line(APP_MEASUREMENT_MARKER + raw),
    line(AUDIO_COMPARISON_MARKER + JSON.stringify(f.proof("receipt"))),
    line(AUDIO_COMPARISON_MARKER + '{"private":"synthetic-private"}'),
    line(APP_MEASUREMENT_MARKER + raw.slice(0, -2)),
  ].join("\n") + "\n";
  const result = await collectAppLogs(
    {
      stdout: new ReadableStream({
        start(c) {
          c.enqueue(new TextEncoder().encode(input));
          c.close();
        },
      }),
      status: Promise.resolve({ success: true, code: 0, signal: null }),
      kill() {},
    },
    new AbortController().signal,
    async () => {},
    (record, sha) => {
      records.push(record);
      hashes.push(sha);
      return Promise.resolve();
    },
  );
  assertEquals(result.rejectedProofRows, 2);
  assertEquals(result.events, 2);
  assertEquals(hashes, [hash, null]);
  assertEquals(JSON.stringify(records).includes("synthetic-private"), false);
  assertEquals(
    projectAppLog(
      line(
        AUDIO_COMPARISON_MARKER +
          JSON.stringify({
            ...f.proof("receipt"),
            rawText: "synthetic-private",
          }),
      ),
    ),
    null,
  );
});
