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

async function source(name: string): Promise<string> {
  return await Deno.readTextFile(new URL(name, exportRoot));
}

Deno.test("export webhook performs one synchronous durable step", async () => {
  const index = await source("index.ts");
  const worker = await source("worker.ts");
  const db = await source("db.ts");

  assertStringIncludes(index, "const requestedJobId = payload.job_id");
  assertStringIncludes(index, "await processExportJobStep");
  assertEquals(index.includes("runBackground"), false);
  assertStringIncludes(
    index,
    'disposition: jobIds.length > 0 ? "processed" : "idle"',
  );
  assertEquals(index.includes("payload.user_id"), false);
  assertEquals(index.includes("payload.export_scope"), false);
  assertEquals(index.includes("payload.include_precise_coordinates"), false);
  assertStringIncludes(worker, "const job = await services.claim");
  assertStringIncludes(db, 'supabaseAdmin.rpc("claim_export_job_step"');
});

Deno.test("export pages, durable chunks, and archives are bounded end to end", async () => {
  const db = await source("db.ts");
  const archive = await source("archive.ts");
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
  assertStringIncludes(zip, "createStoredZipStream");
  assertStringIncludes(storage, "fixedSizeParts");
  assertStringIncludes(storage, "MULTIPART_PART_SIZE");
  assertStringIncludes(storage, "readByteStreamWithinLimit");
  assertStringIncludes(storage, "assertMultipartCompletionSucceeded");
  assertStringIncludes(storage, "MAXIMUM_WORK_CHUNK_BYTES");
  assertStringIncludes(
    storage,
    "uploadedBytes + part.byteLength > maximumBytes",
  );
  assertStringIncludes(worker, "manifestBytes !== job.csvBytes");
  assertStringIncludes(worker, "job.maxArchiveBytes");
  assertStringIncludes(worker, '"source_snapshot_changed"');
  assertStringIncludes(db, "sentinel.source_revision_changed");
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
      "db.ts",
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

Deno.test("failed exports do not consume the next request window", async () => {
  const requestDb = await Deno.readTextFile(
    new URL("../request-export-dwca/db.ts", import.meta.url),
  );
  const requestIndex = await Deno.readTextFile(
    new URL("../request-export-dwca/index.ts", import.meta.url),
  );
  assertStringIncludes(requestDb, '.neq("status", "failed")');
  assertStringIncludes(requestIndex, "user.is_anonymous === true");
  assertStringIncludes(requestIndex, '"account_required"');
  assertStringIncludes(requestIndex, 'exportScope !== "personal"');
  assertStringIncludes(requestIndex, '"global_export_forbidden"');
});
