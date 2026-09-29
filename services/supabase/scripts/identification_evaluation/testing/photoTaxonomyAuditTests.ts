import { assertEquals } from "@std/assert";
import { join } from "node:path";
import { atomicJson, readJson } from "../files.ts";
import { photoModelFixture } from "./photoModelPreparationTests.ts";
import { parseTaxonomy } from "../taxonomy.ts";
import { fingerprintBytes } from "../evidence.ts";

export function registerPhotoTaxonomyAuditTests(scratch: string) {
  Deno.test("photo catalog CLI is read-only and distinguishes clear, blocked, invalid and permission-denied audits", async () => {
    const root = await Deno.makeTempDir({
      dir: scratch,
      prefix: "photo-audit-",
    });
    try {
      await photoModelFixture(root, Date.now());
      const old = parseTaxonomy(await readJson(join(root, "taxonomy.json")));
      const taxonomy = {
        version: "evaluation_taxonomy_v2",
        taxonomyVersion: old.taxonomyVersion,
        catalogRef: "synthetic-audit",
        reviewRef: "synthetic-review",
        taxa: old.taxa.map((t) => ({
          taxon: t.taxon,
          canonicalName: "names" in t ? t.names[0] : t.canonicalName,
          synonyms: "names" in t ? t.names.slice(1) : t.synonyms,
        })),
      };
      const run = (options: string[] = [], args = [root]) =>
        new Deno.Command("deno", {
          args: [
            "run",
            "--frozen",
            "--no-prompt",
            "--deny-net",
            "--deny-env",
            "--deny-write",
            `--allow-read=${root}`,
            "--config",
            "services/supabase/functions/deno.json",
            ...options,
            "services/supabase/scripts/audit_photo_taxonomy.ts",
            ...args,
          ],
          stdout: "piped",
          stderr: "piped",
        }).output();
      for (const collision of [false, true]) {
        const t = structuredClone(taxonomy);
        if (collision) {
          t.taxa.push({
            ...t.taxa[0],
            taxon: { ...t.taxa[0].taxon, id: "synthetic:duplicate" },
          });
        }
        await atomicJson(join(root, "taxonomy.json"), t);
        const digest = async () =>
          await Promise.all(
            ["corpus.json", "taxonomy.json"].map(async (f) =>
              fingerprintBytes(await Deno.readFile(join(root, f)))
            ),
          );
        const before = await digest();
        const result = await run();
        assertEquals(result.code, collision ? 2 : 0);
        const report = JSON.parse(new TextDecoder().decode(result.stdout));
        assertEquals(
          report.catalogConsistency,
          collision ? "blocked" : "clear",
        );
        assertEquals(report.dispatchAuthorized, false);
        assertEquals(await digest(), before);
      }
      const flags = await run([], ["--live", root]);
      assertEquals(flags.code, 1);
      assertEquals(
        new TextDecoder().decode(flags.stderr).trim(),
        "photo_taxonomy_audit_failed",
      );
      const denied = await run([`--deny-read=${root}`]);
      assertEquals(denied.code, 1);
      assertEquals(
        new TextDecoder().decode(denied.stderr).trim(),
        "photo_taxonomy_audit_failed",
      );
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });
}
