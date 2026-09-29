/** Read-only audit. Reads corpus/catalog only; never changes a completed packet. */
import { join } from "node:path";
import { assertOfflinePermissions } from "./identification_evaluation/admission.ts";
import { readJson } from "./identification_evaluation/files.ts";
import { auditPhotoTaxonomy } from "./identification_evaluation/photoTaxonomyAudit.ts";
import { requireCondition as check } from "./identification_evaluation/validation.ts";

export async function auditPhotoTaxonomyFiles(root: string) {
  await assertOfflinePermissions();
  const corpus = await readJson(join(root, "corpus.json"));
  const taxonomy = await readJson(
    join(root, "taxonomy.json"),
    32 * 1024 * 1024,
  );
  return await auditPhotoTaxonomy(corpus, taxonomy);
}

if (import.meta.main) {
  try {
    check(Deno.args.length === 1 && !Deno.args[0].startsWith("-"));
    const report = await auditPhotoTaxonomyFiles(Deno.args[0]);
    console.log(JSON.stringify(report, null, 2));
    Deno.exitCode = report.catalogConsistency === "clear" ? 0 : 2;
  } catch {
    console.error("photo_taxonomy_audit_failed");
    Deno.exitCode = 1;
  }
}
