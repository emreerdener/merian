import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

const exportRoot = new URL("../export-dwca/", import.meta.url);
const deploymentWorkflow = new URL(
  "../../../../.github/workflows/deploy.yml",
  import.meta.url,
);
const monitorWorkflow = new URL(
  "../../../../.github/workflows/dwca-export-health-monitor.yml",
  import.meta.url,
);
const monitorScript = new URL(
  "../../scripts/monitor_dwca_export_queue.ts",
  import.meta.url,
);

async function source(name: string): Promise<string> {
  return await Deno.readTextFile(new URL(name, exportRoot));
}

Deno.test("export webhook performs a deadline-bounded fair durable drain", async () => {
  const index = await source("index.ts");
  const drain = await source("drain.ts");
  const worker = await source("worker.ts");
  const db = await source("db.ts");

  assertStringIncludes(index, "const requestedJobId = payload.job_id");
  assertStringIncludes(index, "await drainExportJobs");
  assertEquals(index.includes("runBackground"), false);
  assertStringIncludes(
    index,
    'disposition: result.attemptedSteps > 0 ? "processed" : "idle"',
  );
  assertEquals(index.includes("payload.user_id"), false);
  assertEquals(index.includes("payload.export_scope"), false);
  assertEquals(index.includes("payload.include_precise_coordinates"), false);
  assertStringIncludes(drain, "EXPORT_DRAIN_RUNTIME_BUDGET_MS");
  assertStringIncludes(drain, "EXPORT_DRAIN_MAXIMUM_STEPS");
  assertStringIncludes(drain, "EXPORT_DRAIN_DISCOVERY_BATCH_SIZE");
  assertStringIncludes(drain, "if (targetedWakeup) break");
  assertStringIncludes(drain, "suppressedJobIds");
  assertStringIncludes(drain, "await fetchHealth");
  assertStringIncludes(drain, "exportQueueHealthStatus");
  assertStringIncludes(db, '"get_due_export_job_ids"');
  assertStringIncludes(db, '"get_dwca_export_queue_health"');
  assertStringIncludes(worker, "const job = await services.claim");
  assertStringIncludes(db, 'supabaseAdmin.rpc("claim_export_job_step"');
});

Deno.test("export pages, durable chunks, and archives are bounded end to end", async () => {
  const db = await source("db.ts");
  const archive = await source("archive.ts");
  const crc32 = await source("crc32.ts");
  const limits = await source("limits.ts");
  const mail = await source("mail.ts");
  const storage = await source("storage.ts");
  const zip = await source("zip.ts");

  const worker = await source("worker.ts");
  assertStringIncludes(db, '"get_dwca_export_scan_batch"');
  assertStringIncludes(db, "p_claim_token: claimToken");
  assertStringIncludes(
    db,
    "p_max_source_bytes: MAXIMUM_EXPORT_SOURCE_PAGE_BYTES",
  );
  assertStringIncludes(limits, "export const EXPORT_PAGE_SIZE = 100");
  assertStringIncludes(
    limits,
    "export const MAXIMUM_EXPORT_SOURCE_PAGE_BYTES = 256 * 1024",
  );
  assertEquals(db.includes(".range("), false);
  assertEquals(db.includes('.from("scans")'), false);
  assertStringIncludes(archive, "encodeExportBatch");
  assertStringIncludes(archive, "class BoundedCsvEncoder");
  assertStringIncludes(archive, "encoder.encodeInto");
  assertStringIncludes(archive, "iterateMultimediaRows");
  assertEquals(archive.includes("const lines: string[]"), false);
  assertEquals(archive.includes("Promise.all"), false);
  assertEquals(archive.includes("lines.join"), false);
  assertStringIncludes(archive, "createPreparedDwcaArchiveStream");
  assertStringIncludes(archive, "fetchExportWorkChunk");
  assertStringIncludes(archive, "calculateCrc32(bytes)");
  assertStringIncludes(archive, "combineCrc32Parts");
  assertStringIncludes(crc32, "secondByteCount");
  assertStringIncludes(crc32, "gf2MatrixSquare");
  assertStringIncludes(crc32, "CRC32_BYTE_OPERATORS");
  assertEquals(
    crc32.indexOf("CRC32_BYTE_OPERATORS") <
      crc32.indexOf("export function combineCrc32"),
    true,
  );
  const combineStart = crc32.indexOf("export function combineCrc32");
  const combineEnd = crc32.indexOf("export function combineCrc32Parts");
  assertEquals(
    crc32.slice(combineStart, combineEnd).includes("gf2MatrixSquare"),
    false,
  );
  assertStringIncludes(zip, "createStoredZipStream");
  assertStringIncludes(zip, "file.expected.crc32");
  assertStringIncludes(zip, "file.expected.byteCount");
  assertEquals(zip.includes("for (const byte of"), false);
  assertStringIncludes(db, "p_chunk_crc32: chunkCrc32");
  assertStringIncludes(storage, "fixedSizeParts");
  assertStringIncludes(storage, "MULTIPART_PART_SIZE");
  assertStringIncludes(storage, "readByteStreamWithinLimit");
  assertStringIncludes(storage, "assertMultipartCompletionSucceeded");
  assertStringIncludes(storage, "MAXIMUM_WORK_CHUNK_BYTES");
  assertStringIncludes(
    storage,
    'response.headers.get("Content-Length")',
  );
  assertStringIncludes(storage, "rawDeclaredLength !== null");
  assertStringIncludes(storage, "Number.isSafeInteger(declaredLength)");
  assertStringIncludes(
    storage,
    "uploadedBytes + part.byteLength > maximumBytes",
  );
  assertEquals(
    storage.includes(
      'Number(response.headers.get("Content-Length"))',
    ),
    false,
  );
  assertStringIncludes(worker, "manifestBytes !== job.csvBytes");
  assertStringIncludes(worker, "job.maxArchiveBytes");
  assertStringIncludes(
    worker,
    'services.checkSource(job.id, claimToken, "assembling")',
  );
  assertStringIncludes(
    worker,
    'services.checkSource(job.id, claimToken, "delivering")',
  );
  assertEquals(
    [...worker.matchAll(
      /services\.checkSource\(job\.id, claimToken, "delivering"\)/g,
    )].length,
    2,
  );
  assertStringIncludes(worker, "services.enqueueCleanup");
  assertStringIncludes(worker, '"source_snapshot_changed"');
  assertStringIncludes(db, '"check_dwca_export_source_fence"');
  assertStringIncludes(db, 'error.code === "55001"');
  assertStringIncludes(db, "sentinel.source_revision_changed");
  assertStringIncludes(storage, "deleteDwcaArchiveObject");
  assertStringIncludes(storage, "createDwcaArchiveRedirectUrl");
  assertEquals(storage.includes("SIGNED_URL_LIFETIME_SECONDS"), false);
  assertEquals(storage.includes("JSZip"), false);
  assertEquals(storage.includes("arrayBuffer()"), false);
  assertEquals(storage.includes("response.text()"), false);
  assertEquals(mail.includes("response.text()"), false);
});

Deno.test("export identity and delivery use dedicated idempotent secrets", async () => {
  const pseudonym = await source("pseudonym.ts");
  const dwca = await source("dwca.ts");
  const mail = await source("mail.ts");
  const productionSources = await Promise.all(
    [
      "archive.ts",
      "crc32.ts",
      "db.ts",
      "drain.ts",
      "dwca.ts",
      "index.ts",
      "limits.ts",
      "mail.ts",
      "pseudonym.ts",
      "storage.ts",
      "types.ts",
      "worker.ts",
      "zip.ts",
    ].map(source),
  );

  assertStringIncludes(
    pseudonym,
    "DWCA_PSEUDONYM_HMAC_KEY_V${keyVersion}",
  );
  assertStringIncludes(pseudonym, '{ name: "HMAC", hash: "SHA-256" }');
  assertStringIncludes(dwca, "ownerUserId === null");
  assertStringIncludes(dwca, "pseudonymizer.pseudonymize(ownerUserId)");
  assertStringIncludes(mail, '"Idempotency-Key": `dwca-export/${jobId}`');
  assert(
    productionSources.every((value) =>
      !value.includes("SUPABASE_JWT_SECRET") &&
      !value.includes('|| "salt"') &&
      !value.includes('?? "salt"')
    ),
  );
});

Deno.test("deployment validates and synchronizes the pinned pseudonym key", async () => {
  const workflow = await Deno.readTextFile(deploymentWorkflow);
  assertStringIncludes(
    workflow,
    "DWCA_PSEUDONYM_HMAC_KEY_V1: ${{ secrets.DWCA_PSEUDONYM_HMAC_KEY_V1 }}",
  );
  assertStringIncludes(
    workflow,
    '"DWCA_PSEUDONYM_HMAC_KEY_V1=$DWCA_PSEUDONYM_HMAC_KEY_V1"',
  );
  assertStringIncludes(workflow, "base64 --decode");
  assertStringIncludes(workflow, 'if [ "$dwca_key_bytes" -lt 32 ]');
});

Deno.test("DwC-A backlog monitor shares route defaults and emits bounded artifacts", async () => {
  const workflow = await Deno.readTextFile(monitorWorkflow);
  const script = await Deno.readTextFile(monitorScript);

  for (
    const expected of [
      "EXPORT_BACKLOG_WARNING_AGE_SECONDS",
      "EXPORT_BACKLOG_CRITICAL_AGE_SECONDS",
      "EXPORT_BACKLOG_WARNING_COUNT",
      "EXPORT_BACKLOG_CRITICAL_COUNT",
      "get_dwca_export_queue_health",
      "get_dwca_archive_cleanup_health",
    ]
  ) {
    assertStringIncludes(script, expected);
  }
  assertStringIncludes(workflow, "monitor_dwca_export_queue.ts");
  assertStringIncludes(workflow, "INPUT_WARNING_AFTER_MINUTES");
  assertStringIncludes(workflow, "INPUT_CRITICAL_AFTER_MINUTES");
  assertStringIncludes(workflow, "INPUT_WARNING_BACKLOG");
  assertStringIncludes(workflow, "INPUT_CRITICAL_BACKLOG");
  assertStringIncludes(workflow, "retention-days: 30");
});

Deno.test("export intake is atomic and fails closed behind the release gate", async () => {
  const requestDb = await Deno.readTextFile(
    new URL("../request-export-dwca/db.ts", import.meta.url),
  );
  const requestIndex = await Deno.readTextFile(
    new URL("../request-export-dwca/index.ts", import.meta.url),
  );
  assertStringIncludes(requestDb, '"request_dwca_export_job"');
  assertEquals(requestDb.includes('.from("export_jobs")'), false);
  assertStringIncludes(requestDb, 'case "disabled"');
  assertStringIncludes(requestIndex, "user.is_anonymous === true");
  assertStringIncludes(requestIndex, '"account_required"');
  assertStringIncludes(requestIndex, 'exportScope !== "personal"');
  assertStringIncludes(requestIndex, '"global_export_forbidden"');
  assertStringIncludes(requestIndex, 'disposition === "disabled"');
  assertStringIncludes(requestIndex, '"feature_unavailable"');
});
