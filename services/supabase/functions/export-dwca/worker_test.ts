import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { SupabaseClient } from "@supabase/supabase-js";
import { ExportWorkerServices, processExportJob } from "./worker.ts";
import { ClaimedExportJob, ExportWorkerError } from "./types.ts";

const job: ClaimedExportJob = {
  id: "00000000-0000-4000-8000-000000000201",
  userId: "00000000-0000-4000-8000-000000000202",
  exportScope: "global",
  includePreciseCoordinates: false,
  pseudonymKeyVersion: 1,
  archiveObjectKey: null,
  fileUrl: null,
  archiveReadyAt: null,
  attemptCount: 1,
  leaseExpiresAt: "2026-07-24T23:59:00.000Z",
};

const unusedClient = {} as SupabaseClient;

function emptyArchive(): ReadableStream<Uint8Array> {
  return new ReadableStream({
    start(controller) {
      controller.enqueue(new Uint8Array([1, 2, 3]));
      controller.close();
    },
  });
}

function successfulServices(
  events: string[],
  claimedJob: ClaimedExportJob | null = job,
): Partial<ExportWorkerServices> {
  return {
    claim() {
      events.push("claim");
      return Promise.resolve(claimedJob);
    },
    renew() {
      events.push("renew");
      return Promise.resolve();
    },
    fetchEmail() {
      events.push("email_lookup");
      return Promise.resolve("export@example.invalid");
    },
    loadPseudonymizer() {
      events.push("pseudonym_key");
      return Promise.resolve({
        keyVersion: 1,
        pseudonymize(userId: string) {
          return Promise.resolve(`pseudonym-${userId}`);
        },
      });
    },
    createArchive(_job, _pseudonymizer, _onProgress) {
      events.push("archive");
      return emptyArchive();
    },
    uploadArchive(_archive, objectKey) {
      events.push(`upload:${objectKey}`);
      return Promise.resolve({
        objectKey,
        signedUrl: "https://r2.example.invalid/export.zip?signed=1",
        uploadedBytes: 3,
        uploadedParts: 1,
      });
    },
    stageArchive() {
      events.push("stage");
      return Promise.resolve();
    },
    sendEmail() {
      events.push("send");
      return Promise.resolve("email-id");
    },
    complete() {
      events.push("complete");
      return Promise.resolve();
    },
    fail(_jobId, _claimToken, code) {
      events.push(`fail:${code}`);
      return Promise.resolve(true);
    },
    now: () => 1_000,
    sleep: () => Promise.resolve(),
  };
}

Deno.test("duplicate delivery exits when the atomic claim returns no job", async () => {
  const events: string[] = [];
  const result = await processExportJob(
    job.id,
    unusedClient,
    successfulServices(events, null),
  );
  assertEquals(result, { disposition: "not_claimed" });
  assertEquals(events, ["claim"]);
});

Deno.test("claimed job uses canonical state and an attempt-fenced storage key", async () => {
  const events: string[] = [];
  const result = await processExportJob(
    job.id,
    unusedClient,
    successfulServices(events),
  );

  assertEquals(result, {
    disposition: "completed",
    attemptCount: 1,
    reusedArchive: false,
    uploadedBytes: 3,
    uploadedParts: 1,
  });
  assertEquals(events.slice(0, 4), [
    "claim",
    "email_lookup",
    "pseudonym_key",
    "archive",
  ]);
  const uploadEvent = events[4];
  const objectKeyPrefix = `upload:exports/${job.userId}/${job.id}/`;
  assertEquals(uploadEvent.startsWith(objectKeyPrefix), true);
  assertEquals(uploadEvent.endsWith(".zip"), true);
  assertEquals(events.slice(5), [
    "renew",
    "stage",
    "renew",
    "send",
    "complete",
  ]);
});

Deno.test("lease retry reuses the staged URL and idempotent email", async () => {
  const events: string[] = [];
  const stagedJob: ClaimedExportJob = {
    ...job,
    archiveObjectKey:
      `exports/${job.userId}/${job.id}/00000000-0000-4000-8000-000000000203.zip`,
    fileUrl: "https://r2.example.invalid/export.zip?signed=stable",
    archiveReadyAt: "2026-07-24T23:00:00.000Z",
    attemptCount: 2,
  };
  const result = await processExportJob(
    job.id,
    unusedClient,
    successfulServices(events, stagedJob),
  );

  assertEquals(result.reusedArchive, true);
  assertEquals(events, [
    "claim",
    "email_lookup",
    "renew",
    "send",
    "complete",
  ]);
});

Deno.test("terminal generation failures are fenced into failed state", async () => {
  const events: string[] = [];
  const services = successfulServices(events);
  services.createArchive = () => {
    throw new ExportWorkerError(
      "pseudonym_key_unavailable",
      "missing key",
    );
  };

  const error = await assertRejects(
    () => processExportJob(job.id, unusedClient, services),
    ExportWorkerError,
  );
  assertEquals(error.code, "pseudonym_key_unavailable");
  assertEquals(events.at(-1), "fail:pseudonym_key_unavailable");
});

Deno.test("retryable delivery failures leave the lease recoverable", async () => {
  const events: string[] = [];
  const services = successfulServices(events, {
    ...job,
    archiveObjectKey:
      `exports/${job.userId}/${job.id}/00000000-0000-4000-8000-000000000203.zip`,
    fileUrl: "https://r2.example.invalid/export.zip?signed=stable",
    archiveReadyAt: "2026-07-24T23:00:00.000Z",
  });
  services.sendEmail = () => {
    events.push("send");
    return Promise.reject(
      new ExportWorkerError(
        "delivery_failed",
        "temporary upstream failure",
        false,
      ),
    );
  };

  const error = await assertRejects(
    () => processExportJob(job.id, unusedClient, services),
    ExportWorkerError,
  );
  assertEquals(error.code, "delivery_failed");
  assertEquals(events.some((event) => event.startsWith("fail:")), false);
});

Deno.test("accepted delivery is never rolled back by completion failure", async () => {
  const events: string[] = [];
  const services = successfulServices(events, {
    ...job,
    archiveObjectKey:
      `exports/${job.userId}/${job.id}/00000000-0000-4000-8000-000000000203.zip`,
    fileUrl: "https://r2.example.invalid/export.zip?signed=stable",
    archiveReadyAt: "2026-07-24T23:00:00.000Z",
  });
  services.complete = () => {
    events.push("complete");
    return Promise.reject(
      new ExportWorkerError(
        "database_unavailable",
        "database unavailable",
      ),
    );
  };

  const error = await assertRejects(
    () => processExportJob(job.id, unusedClient, services),
    ExportWorkerError,
  );
  assertEquals(error.code, "database_unavailable");
  assertEquals(events.filter((event) => event === "complete").length, 3);
  assertEquals(events.some((event) => event.startsWith("fail:")), false);
});
