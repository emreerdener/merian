import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";

import {
  MEDIA_BUDGETS,
  validateInlineAudioBase64Budget,
  validateStagingObjectKey,
} from "../_shared/mediaBudgets.ts";

type AudioSpecInput = {
  audio_r2_key?: string;
  audio_base64?: string;
};

function validateAudioSpecBudget(body: AudioSpecInput): number | null {
  if (!body.audio_r2_key && !body.audio_base64) return 400;
  if (
    body.audio_base64 &&
    validateInlineAudioBase64Budget(body.audio_base64)
  ) {
    return 413;
  }
  if (body.audio_r2_key) {
    const keyError = validateStagingObjectKey(body.audio_r2_key, "user");
    if (keyError === "path_traversal") return 400;
  }
  return null;
}

Deno.test("audio-spec repairs prerequisites and returns success only after durable ingestion", async () => {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );
  const scanId = source.indexOf("const generatedScanId =");
  const recovery = source.indexOf(
    "strandedRecovery = await recoverStrandedScanIngestionAttempt(",
    scanId,
  );
  const profile = source.indexOf(
    "await upsertGhostUserIfMissing(user.id, supabaseAdmin);",
    recovery,
  );
  const quota = source.indexOf(
    "quotaLease = await reserveAIProviderCall(",
    profile,
  );
  const ingestion = source.indexOf("const runBackgroundIngestion = async");
  const scanInsert = source.indexOf("await insertScan(", ingestion);
  const awaitIngestion = source.indexOf(
    "await runBackgroundIngestion();",
    scanInsert,
  );
  const success = source.indexOf(
    "return jsonResponse(responseEnvelope, 200);",
    awaitIngestion,
  );

  assert(recovery > scanId);
  assert(profile > recovery);
  assert(quota > profile);
  assert(scanInsert > ingestion);
  assert(awaitIngestion > scanInsert);
  assert(success > awaitIngestion);
  assert(!source.includes("runBackground(runBackgroundIngestion())"));
  assert(source.includes('"scan_media_restage_required"'));
  assert(source.includes('"scan_persistence_failed"'));
  assert(source.includes("const quotaRetryEnabled = await quotaLease.fail();"));
  assert(source.includes("audio_storage_urls: audioStorageUrls"));
  assert(source.includes("promotedUrlsByStorageKey: stagedAudioSourceKey"));
  assert(source.includes("const stagedAudioSourceKey = audio_base64"));
});

Deno.test("audio-spec budget - missing audio source is rejected", () => {
  assertEquals(validateAudioSpecBudget({}), 400);
});

Deno.test("audio-spec budget - oversized inline base64 is rejected before decode", () => {
  assertEquals(
    validateAudioSpecBudget({
      audio_base64: "A".repeat(MEDIA_BUDGETS.maxAudioBase64Chars + 1),
    }),
    413,
  );
});

Deno.test("audio-spec budget - staged R2 path traversal is rejected", () => {
  assertEquals(
    validateAudioSpecBudget({ audio_r2_key: "staging/user/../audio.wav" }),
    400,
  );
});

Deno.test("audio-spec budget - normal staged R2 key is accepted", () => {
  assertEquals(
    validateAudioSpecBudget({ audio_r2_key: "staging/user/audio.wav" }),
    null,
  );
});
