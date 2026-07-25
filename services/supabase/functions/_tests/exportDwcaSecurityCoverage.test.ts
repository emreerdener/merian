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

Deno.test("export webhook treats its payload as a job-id wake-up only", async () => {
  const index = await source("index.ts");
  const worker = await source("worker.ts");
  const db = await source("db.ts");

  assertStringIncludes(index, "const jobId = payload.job_id");
  assertStringIncludes(index, "runBackground(worker)");
  assertStringIncludes(index, 'disposition: "accepted"');
  assertEquals(index.includes("payload.user_id"), false);
  assertEquals(index.includes("payload.export_scope"), false);
  assertEquals(index.includes("payload.include_precise_coordinates"), false);
  assertStringIncludes(worker, "const job = await services.claim");
  assertStringIncludes(db, 'supabaseAdmin.rpc("claim_export_job"');
});

Deno.test("export pages and archives remain bounded end to end", async () => {
  const db = await source("db.ts");
  const archive = await source("archive.ts");
  const mail = await source("mail.ts");
  const storage = await source("storage.ts");
  const zip = await source("zip.ts");

  assertStringIncludes(db, "export const EXPORT_PAGE_SIZE = 200");
  assertStringIncludes(db, '.gt("id", afterId)');
  assertEquals(db.includes(".range("), false);
  assertEquals(db.includes("offset"), false);
  assertStringIncludes(archive, "AsyncGenerator<Uint8Array>");
  assertStringIncludes(zip, "createStoredZipStream");
  assertStringIncludes(storage, "fixedSizeParts");
  assertStringIncludes(storage, "MULTIPART_PART_SIZE");
  assertStringIncludes(storage, "readByteStreamWithinLimit");
  assertStringIncludes(storage, "assertMultipartCompletionSucceeded");
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
  assertStringIncludes(dwca, "pseudonymizer.pseudonymize(scan.user_id)");
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
});
