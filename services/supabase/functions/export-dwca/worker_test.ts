import { assert, assertEquals, assertRejects } from "@std/assert";
import { SupabaseClient } from "@supabase/supabase-js";
import { calculateCrc32 } from "./crc32.ts";
import { ExportWorkerServices, processExportJobStep } from "./worker.ts";
import { ClaimedExportJob, ExportWorkerError } from "./types.ts";

const job: ClaimedExportJob = {
  id: "00000000-0000-4000-8000-000000000201",
  userId: "00000000-0000-4000-8000-000000000202",
  exportScope: "personal",
  includePreciseCoordinates: false,
  pseudonymKeyVersion: 1,
  maxExportRows: 5000,
  maxArchiveBytes: 8 * 1024 * 1024,
  archiveObjectKey: null,
  fileUrl: null,
  archiveReadyAt: null,
  attemptCount: 1,
  leaseExpiresAt: "2026-07-25T23:59:00.000Z",
  workPhase: "occurrence",
  occurrenceAfterId: null,
  multimediaAfterId: null,
  occurrenceRows: 0,
  multimediaRows: 0,
  csvBytes: 0,
  chunkSequence: 0,
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
    fetchBatch() {
      events.push("fetch_batch");
      return Promise.resolve({
        scans: [
          {
            id: "00000000-0000-4000-8000-000000000301",
            user_id: job.userId,
          },
        ],
        sourceByteCount: 256,
        pageComplete: true,
      });
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
    encodeBatch() {
      events.push("encode_batch");
      const bytes = new Uint8Array([1, 2, 3]);
      return Promise.resolve({
        bytes,
        crc32: calculateCrc32(bytes),
        rowCount: 1,
      });
    },
    putChunk(_bytes, objectKey) {
      events.push(`put:${objectKey}`);
      return Promise.resolve();
    },
    advance() {
      events.push("advance");
      return Promise.resolve("multimedia");
    },
    fetchManifest() {
      events.push("manifest");
      return Promise.resolve([]);
    },
    checkSource(_jobId, _claimToken, phase) {
      events.push(`source_fence:${phase}`);
      return Promise.resolve();
    },
    createArchive() {
      events.push("archive");
      return emptyArchive();
    },
    uploadArchive(_archive, objectKey, _onProgress, maximumBytes) {
      events.push(`upload:${objectKey}:${maximumBytes}`);
      return Promise.resolve({
        objectKey,
        uploadedBytes: 3,
        uploadedParts: 1,
      });
    },
    createDownloadGrant() {
      events.push("download_grant");
      return {
        token: "a".repeat(43),
        url:
          "https://project-ref.supabase.co/functions/v1/download-dwca?token=opaque",
        expiresAt: "2026-07-26T23:00:00.000Z",
      };
    },
    stageArchive() {
      events.push("stage");
      return Promise.resolve();
    },
    enqueueCleanup(_jobId, objectKey, reasonCode) {
      events.push(`cleanup:${objectKey}:${reasonCode}`);
      return Promise.resolve();
    },
    fetchEmail() {
      events.push("email_lookup");
      return Promise.resolve("export@example.invalid");
    },
    sendEmail() {
      events.push("send");
      return Promise.resolve("email-id");
    },
    complete() {
      events.push("complete");
      return Promise.resolve();
    },
    release(_jobId, _claimToken, code, terminal) {
      events.push(`release:${code}:${terminal}`);
      return Promise.resolve(true);
    },
    sleep() {
      return Promise.resolve();
    },
  };
}

Deno.test("duplicate delivery exits when the atomic step claim returns no job", async () => {
  const events: string[] = [];
  const result = await processExportJobStep(
    job.id,
    unusedClient,
    successfulServices(events, null),
  );
  assertEquals(result, { disposition: "not_claimed" });
  assertEquals(events, ["claim"]);
});

Deno.test("preparation performs one fixed keyset page and durably advances", async () => {
  const events: string[] = [];
  const result = await processExportJobStep(
    job.id,
    unusedClient,
    successfulServices(events),
  );

  assertEquals(result, {
    disposition: "advanced",
    phase: "multimedia",
    rowCount: 1,
  });
  assertEquals(events.slice(0, 3), ["claim", "fetch_batch", "encode_batch"]);
  assert(events[3].startsWith(
    `put:exports/${job.userId}/${job.id}/work/occurrence/00000000-`,
  ));
  assert(
    /^put:.*\/00000000-[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.csv$/i
      .test(events[3]),
  );
  assertEquals(events[4], "advance");
  assertEquals(events.includes("archive"), false);
  assertEquals(events.includes("send"), false);
});

Deno.test("assembly consumes only the durable bounded manifest", async () => {
  const events: string[] = [];
  const assembling: ClaimedExportJob = {
    ...job,
    workPhase: "assembling",
    occurrenceRows: 1,
    csvBytes: 3,
  };
  const services = successfulServices(events, assembling);
  services.fetchManifest = () => {
    events.push("manifest");
    return Promise.resolve([{
      phase: "occurrence",
      sequence: 0,
      objectKey: `exports/${job.userId}/${job.id}/work/occurrence/00000000.csv`,
      byteCount: 3,
      crc32: calculateCrc32(new Uint8Array([1, 2, 3])),
    }]);
  };

  const result = await processExportJobStep(
    job.id,
    unusedClient,
    services,
  );

  assertEquals(result, {
    disposition: "advanced",
    phase: "delivering",
    uploadedBytes: 3,
    uploadedParts: 1,
  });
  assertEquals(events.slice(0, 4), [
    "claim",
    "source_fence:assembling",
    "manifest",
    "archive",
  ]);
  assert(events[4].startsWith(
    `upload:exports/${job.userId}/${job.id}/`,
  ));
  assert(events[4].endsWith(`.zip:${job.maxArchiveBytes}`));
  assertEquals(events.at(-1), "stage");
});

Deno.test("delivery retries only the fenced idempotent completion write", async () => {
  const events: string[] = [];
  const delivering: ClaimedExportJob = {
    ...job,
    workPhase: "delivering",
    archiveObjectKey: `exports/${job.userId}/${job.id}/archive.zip`,
    fileUrl: "https://r2.example.invalid/export.zip?signed=stable",
    archiveReadyAt: "2026-07-25T23:00:00.000Z",
  };
  const services = successfulServices(events, delivering);
  let completions = 0;
  services.complete = () => {
    events.push("complete");
    completions += 1;
    return completions < 3
      ? Promise.reject(new Error("database unavailable"))
      : Promise.resolve();
  };

  const result = await processExportJobStep(
    job.id,
    unusedClient,
    services,
  );
  assertEquals(result, {
    disposition: "completed",
    phase: "completed",
  });
  assertEquals(events.filter((event) => event === "send").length, 1);
  assertEquals(events.filter((event) => event === "complete").length, 3);
  assertEquals(
    events.filter((event) => event === "source_fence:delivering").length,
    2,
  );
  assertEquals(events[1], "source_fence:delivering");
});

Deno.test("assembly rejects a changed earlier source before reading its manifest", async () => {
  const events: string[] = [];
  const assembling: ClaimedExportJob = {
    ...job,
    workPhase: "assembling",
  };
  const services = successfulServices(events, assembling);
  services.checkSource = (_jobId, _claimToken, phase) => {
    events.push(`source_fence:${phase}`);
    return Promise.reject(
      new ExportWorkerError(
        "source_snapshot_changed",
        "an earlier source row changed",
      ),
    );
  };

  const error = await assertRejects(
    () => processExportJobStep(job.id, unusedClient, services),
    ExportWorkerError,
  );
  assertEquals(error.code, "source_snapshot_changed");
  assertEquals(events.includes("manifest"), false);
  assertEquals(
    events.some((event) => event.startsWith("upload:")),
    false,
  );
  assertEquals(events.at(-1), "release:source_snapshot_changed:true");
});

Deno.test("a source change at archive staging durably enqueues the unstaged object", async () => {
  const events: string[] = [];
  const assembling: ClaimedExportJob = {
    ...job,
    workPhase: "assembling",
    occurrenceRows: 1,
    csvBytes: 3,
  };
  const services = successfulServices(events, assembling);
  services.fetchManifest = () =>
    Promise.resolve([{
      phase: "occurrence",
      sequence: 0,
      objectKey: "exports/test/work/occurrence/00000000.csv",
      byteCount: 3,
      crc32: calculateCrc32(new Uint8Array([1, 2, 3])),
    }]);
  services.stageArchive = () =>
    Promise.reject(
      new ExportWorkerError(
        "source_snapshot_changed",
        "source changed during upload",
      ),
    );

  const error = await assertRejects(
    () => processExportJobStep(job.id, unusedClient, services),
    ExportWorkerError,
  );
  assertEquals(error.code, "source_snapshot_changed");
  assertEquals(
    events.some((event) =>
      event.startsWith("cleanup:exports/") &&
      event.endsWith(":archive_staging_failed")
    ),
    true,
  );
  assertEquals(events.at(-1), "release:source_snapshot_changed:true");
});

Deno.test("delivery enqueues a staged archive and sends no email after revocation", async () => {
  const events: string[] = [];
  const archiveObjectKey = `exports/${job.userId}/${job.id}/staged.zip`;
  const delivering: ClaimedExportJob = {
    ...job,
    workPhase: "delivering",
    archiveObjectKey,
    fileUrl: "https://r2.example.invalid/export.zip?signed=stable",
    archiveReadyAt: "2026-07-25T23:00:00.000Z",
  };
  const services = successfulServices(events, delivering);
  services.checkSource = (_jobId, _claimToken, phase) => {
    events.push(`source_fence:${phase}`);
    return Promise.reject(
      new ExportWorkerError(
        "source_snapshot_changed",
        "source was tombstoned",
      ),
    );
  };

  const error = await assertRejects(
    () => processExportJobStep(job.id, unusedClient, services),
    ExportWorkerError,
  );
  assertEquals(error.code, "source_snapshot_changed");
  assertEquals(
    events.includes(
      `cleanup:${archiveObjectKey}:privacy_boundary_changed`,
    ),
    true,
  );
  assertEquals(events.includes("send"), false);
  assertEquals(events.at(-1), "release:source_snapshot_changed:true");
});

Deno.test("delivery revalidates after email lookup before calling the provider", async () => {
  const events: string[] = [];
  const archiveObjectKey = `exports/${job.userId}/${job.id}/staged.zip`;
  const delivering: ClaimedExportJob = {
    ...job,
    workPhase: "delivering",
    archiveObjectKey,
    fileUrl: "https://r2.example.invalid/export.zip?signed=private",
    archiveReadyAt: "2026-07-25T23:00:00.000Z",
  };
  const services = successfulServices(events, delivering);
  let fenceChecks = 0;
  services.checkSource = (_jobId, _claimToken, phase) => {
    events.push(`source_fence:${phase}`);
    fenceChecks += 1;
    return fenceChecks === 1 ? Promise.resolve() : Promise.reject(
      new ExportWorkerError(
        "source_snapshot_changed",
        "source changed while resolving the recipient",
      ),
    );
  };

  const error = await assertRejects(
    () => processExportJobStep(job.id, unusedClient, services),
    ExportWorkerError,
  );
  assertEquals(error.code, "source_snapshot_changed");
  assertEquals(events.includes("email_lookup"), true);
  assertEquals(events.includes("send"), false);
  assertEquals(
    events.includes(
      `cleanup:${archiveObjectKey}:privacy_boundary_changed`,
    ),
    true,
  );
  assertEquals(events.at(-1), "release:source_snapshot_changed:true");
});

Deno.test("delivery deletes the archive when completion detects an in-flight privacy change", async () => {
  const events: string[] = [];
  const archiveObjectKey = `exports/${job.userId}/${job.id}/staged.zip`;
  const delivering: ClaimedExportJob = {
    ...job,
    workPhase: "delivering",
    archiveObjectKey,
    fileUrl: "https://r2.example.invalid/export.zip?signed=private",
    archiveReadyAt: "2026-07-25T23:00:00.000Z",
  };
  const services = successfulServices(events, delivering);
  services.complete = () => {
    events.push("complete");
    return Promise.reject(
      new ExportWorkerError(
        "source_snapshot_changed",
        "source changed while the provider accepted delivery",
      ),
    );
  };

  const error = await assertRejects(
    () => processExportJobStep(job.id, unusedClient, services),
    ExportWorkerError,
  );
  assertEquals(error.code, "source_snapshot_changed");
  assertEquals(events.filter((event) => event === "send").length, 1);
  assertEquals(events.filter((event) => event === "complete").length, 1);
  assertEquals(
    events.includes(
      `cleanup:${archiveObjectKey}:privacy_boundary_changed`,
    ),
    true,
  );
  assertEquals(events.at(-1), "release:source_snapshot_changed:true");
});

Deno.test("canonical budget failures become terminal under the active fence", async () => {
  const events: string[] = [];
  const budgetExhausted: ClaimedExportJob = {
    ...job,
    occurrenceRows: job.maxExportRows,
  };
  const services = successfulServices(events, budgetExhausted);

  const error = await assertRejects(
    () => processExportJobStep(job.id, unusedClient, services),
    ExportWorkerError,
  );
  assertEquals(error.code, "export_too_large");
  assertEquals(events.some((event) => event.startsWith("put:")), false);
  assertEquals(events.includes("advance"), false);
  assertEquals(events.at(-1), "release:export_too_large:true");
});

Deno.test("changed source snapshots become terminal under the active fence", async () => {
  const events: string[] = [];
  const services = successfulServices(events);
  services.fetchBatch = () =>
    Promise.reject(
      new ExportWorkerError(
        "source_snapshot_changed",
        "source revision changed",
      ),
    );

  const error = await assertRejects(
    () => processExportJobStep(job.id, unusedClient, services),
    ExportWorkerError,
  );
  assertEquals(error.code, "source_snapshot_changed");
  assertEquals(events.includes("encode_batch"), false);
  assertEquals(events.some((event) => event.startsWith("put:")), false);
  assertEquals(events.at(-1), "release:source_snapshot_changed:true");
});

Deno.test("canonical CSV byte failures are rejected before R2 upload", async () => {
  const events: string[] = [];
  const budgetExhausted: ClaimedExportJob = {
    ...job,
    csvBytes: job.maxArchiveBytes - 65_536,
  };
  const services = successfulServices(events, budgetExhausted);

  const error = await assertRejects(
    () => processExportJobStep(job.id, unusedClient, services),
    ExportWorkerError,
  );
  assertEquals(error.code, "export_too_large");
  assertEquals(events.some((event) => event.startsWith("put:")), false);
  assertEquals(events.includes("advance"), false);
  assertEquals(events.at(-1), "release:export_too_large:true");
});

Deno.test("impossible empty-batch CRC metadata is rejected before R2 upload", async () => {
  const events: string[] = [];
  const services = successfulServices(events);
  services.encodeBatch = () =>
    Promise.resolve({
      bytes: new Uint8Array(),
      crc32: 1,
      rowCount: 0,
    });

  const error = await assertRejects(
    () => processExportJobStep(job.id, unusedClient, services),
    ExportWorkerError,
  );
  assertEquals(error.code, "archive_generation_failed");
  assertEquals(events.some((event) => event.startsWith("put:")), false);
  assertEquals(events.includes("advance"), false);
  assertEquals(events.at(-1), "release:archive_generation_failed:false");
});

Deno.test("invalid source byte pages are rejected before encoding", async () => {
  const events: string[] = [];
  const services = successfulServices(events);
  services.fetchBatch = () =>
    Promise.resolve({
      scans: [],
      sourceByteCount: 1,
      pageComplete: false,
    });

  const error = await assertRejects(
    () => processExportJobStep(job.id, unusedClient, services),
    ExportWorkerError,
  );
  assertEquals(error.code, "database_unavailable");
  assertEquals(events.includes("encode_batch"), false);
  assertEquals(events.some((event) => event.startsWith("put:")), false);
  assertEquals(events.at(-1), "release:database_unavailable:false");
});

Deno.test("transient provider or storage failures release for durable retry", async () => {
  const events: string[] = [];
  const services = successfulServices(events);
  services.putChunk = () =>
    Promise.reject(
      new ExportWorkerError(
        "storage_unavailable",
        "temporary R2 failure",
        false,
      ),
    );

  const error = await assertRejects(
    () => processExportJobStep(job.id, unusedClient, services),
    ExportWorkerError,
  );
  assertEquals(error.code, "storage_unavailable");
  assertEquals(events.at(-1), "release:storage_unavailable:false");
});

Deno.test("permanent delivery rejection becomes terminal and cannot retry forever", async () => {
  const events: string[] = [];
  const delivering: ClaimedExportJob = {
    ...job,
    workPhase: "delivering",
    archiveObjectKey: `exports/${job.userId}/${job.id}/archive.zip`,
    fileUrl:
      "https://project-ref.supabase.co/functions/v1/download-dwca?token=opaque",
    archiveReadyAt: "2026-07-25T23:00:00.000Z",
  };
  const services = successfulServices(events, delivering);
  services.sendEmail = () =>
    Promise.reject(
      new ExportWorkerError(
        "delivery_failed",
        "the recipient was permanently rejected",
        true,
      ),
    );

  const error = await assertRejects(
    () => processExportJobStep(job.id, unusedClient, services),
    ExportWorkerError,
  );
  assertEquals(error.code, "delivery_failed");
  assertEquals(events.at(-1), "release:delivery_failed:true");
});
